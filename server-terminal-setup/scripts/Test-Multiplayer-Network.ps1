[CmdletBinding()]
param([string[]]$ClientIp, [ValidateRange(1, 120)][int]$Samples = 20)
$ErrorActionPreference = 'Stop'
if (-not $ClientIp) {
    $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'server-terminal.json'
    $defaults = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        @((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).TerminalRelayClientIps)
    } else { @() }
    $inputIps = (Read-Host "PC IPv4 addresses, comma separated [Enter uses: $($defaults -join ', ')]").Trim()
    $ClientIp = if ($inputIps) { $inputIps -split '[,;\s]+' } else { $defaults }
}
$targets = @($ClientIp | Where-Object { $_ } | Sort-Object -Unique)
if ($targets.Count -eq 0) { throw 'Enter at least one player PC IPv4 address.' }
foreach ($target in $targets) {
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($target, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid player PC IPv4 address: $target"
    }
}
$pinger = [Net.NetworkInformation.Ping]::new()
try {
    foreach ($target in $targets) {
        $times = @()
        Write-Host "Testing $target ($Samples samples)..."
        for ($i = 0; $i -lt $Samples; $i++) {
            try {
                $reply = $pinger.Send($target, 750)
                if ($reply.Status -eq [Net.NetworkInformation.IPStatus]::Success) { $times += $reply.RoundtripTime }
            } catch { Write-Verbose $_.Exception.Message }
            Start-Sleep -Milliseconds 250
        }
        $lost = $Samples - $times.Count
        $stats = $times | Measure-Object -Minimum -Maximum -Average
        Write-Host "$target : $($times.Count)/$Samples replies, $lost lost."
        if ($times.Count -gt 0) { Write-Host "Round trip: min $($stats.Minimum) ms, max $($stats.Maximum) ms, average $([Math]::Round($stats.Average, 1)) ms." }
    }
} finally { $pinger.Dispose() }
Write-Host 'Run this check on each player PC against the other PC to test the versus path.'
Write-Host 'Loss or large latency spikes can disrupt versus. No replies can also mean ICMP is blocked or the PC is off.'
Write-Host 'Use different cabinet numbers, the same LAN, and Ethernet for the most reliable test. Terminal relay does not relay race traffic.'
