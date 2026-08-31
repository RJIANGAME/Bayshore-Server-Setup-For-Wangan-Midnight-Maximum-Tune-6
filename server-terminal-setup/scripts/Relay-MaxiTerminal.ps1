[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$setupRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $setupRoot 'server-terminal.json'
$pidPath = Join-Path $setupRoot 'terminal-relay.pid'
$logPath = Join-Path $setupRoot 'terminal-relay.log'
$mutex = [Threading.Mutex]::new($false, 'Local\Bayshore-MaxiTerminal-Unicast-Relay')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Write-RelayLog([string]$Message) {
    Add-Content -LiteralPath $logPath -Value ("{0:u} {1}" -f (Get-Date), $Message) -Encoding UTF8
}
$udp = $null
try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Server terminal is not configured.' }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $serverIp = [string]$config.ServerIp
    $enabled = $config.PSObject.Properties.Name -contains 'TerminalRelayEnabled' -and [bool]$config.TerminalRelayEnabled
    $clientIps = @($config.TerminalRelayClientIps) | ForEach-Object { [string]$_ } | Where-Object { $_ }
    if (-not $enabled -or $clientIps.Count -eq 0) { exit 0 }

    $serverAddress = $null
    if (-not [Net.IPAddress]::TryParse($serverIp, [ref]$serverAddress) -or
        $serverAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid relay ServerIp: $serverIp"
    }
    $targets = foreach ($clientIp in $clientIps | Sort-Object -Unique) {
        $address = $null
        if (-not [Net.IPAddress]::TryParse($clientIp, [ref]$address) -or
            $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $clientIp -eq $serverIp) {
            throw "Invalid terminal relay client IPv4 address: $clientIp"
        }
        [Net.IPEndPoint]::new($address, 50765)
    }

    [IO.File]::WriteAllText($pidPath, [string]$PID, [Text.Encoding]::ASCII)
    $udp = [Net.Sockets.UdpClient]::new()
    $udp.ExclusiveAddressUse = $false
    $udp.Client.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $udp.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Any, 50765))
    $udp.JoinMulticastGroup([Net.IPAddress]::Parse('225.0.0.1'), $serverAddress)
    $udp.Client.ReceiveTimeout = 1000
    Write-RelayLog "Started (PID $PID); source $serverIp, clients $($clientIps -join ', ')."

    $forwarded = 0
    $lastStatus = Get-Date
    while ($true) {
        $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        try { $data = $udp.Receive([ref]$remote) }
        catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut) { continue }
            throw
        }
        if ([string]$remote.Address -ne $serverIp) { continue }
        $ascii = [Text.Encoding]::ASCII.GetString($data)
        if ($ascii -notmatch '280811990003') { continue }
        foreach ($target in $targets) {
            [void]$udp.Send($data, $data.Length, $target)
            $forwarded++
        }
        if (((Get-Date) - $lastStatus).TotalSeconds -ge 60) {
            Write-RelayLog "Healthy; forwarded $forwarded terminal packets since the previous status."
            $forwarded = 0
            $lastStatus = Get-Date
        }
    }
}
catch {
    Write-RelayLog "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    if ($udp) { $udp.Dispose() }
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        $recordedPid = (Get-Content -LiteralPath $pidPath -Raw).Trim()
        if ($recordedPid -eq [string]$PID) { Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue }
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Write-RelayLog "Stopped (PID $PID)."
}
