[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$setupRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $setupRoot 'server-terminal.json'
$pidPath = Join-Path $setupRoot 'watchdog.pid'
$logPath = Join-Path $setupRoot 'watchdog.log'

function Write-WatchdogLog([string]$Message) {
    Add-Content -LiteralPath $logPath -Value ("{0:u} {1}" -f (Get-Date), $Message) -Encoding UTF8
}

function Get-PortablePostgresRoot([string]$ApplicationRoot) {
    return @(
        (Join-Path $ApplicationRoot '.runtime\pgsql'),
        (Join-Path $ApplicationRoot '.runtime\postgresql')
    ) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bin\pg_isready.exe') } | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Server terminal is not configured.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$applicationRoot = [IO.Path]::GetFullPath([string]$config.ApplicationRoot)
$terminalExe = [IO.Path]::GetFullPath([string]$config.MaxiTerminalPath)
$servicePort = [int]$config.ServicePort
$idleMinutes = if ($null -ne $config.IdleRestartMinutes) { [Math]::Max(5, [int]$config.IdleRestartMinutes) } else { 60 }
$checkSeconds = if ($null -ne $config.HealthCheckSeconds) { [Math]::Max(10, [int]$config.HealthCheckSeconds) } else { 30 }
$failureThreshold = if ($null -ne $config.HealthFailureThreshold) { [Math]::Max(2, [int]$config.HealthFailureThreshold) } else { 3 }
$enabled = if ($null -ne $config.WatchdogEnabled) { [bool]$config.WatchdogEnabled } else { $true }

if (-not $enabled) { exit 0 }
[IO.File]::WriteAllText($pidPath, [string]$PID, [Text.Encoding]::ASCII)
$lastClientActivity = Get-Date
$failureCount = 0
$outLog = Join-Path $applicationRoot '.data\bayshore.out.log'
$lastOutLogWrite = if (Test-Path -LiteralPath $outLog) { (Get-Item -LiteralPath $outLog).LastWriteTimeUtc } else { [datetime]::MinValue }
Write-WatchdogLog "Started (PID $PID); idle recovery ${idleMinutes}m, health check ${checkSeconds}s."

try {
    while ($true) {
        Start-Sleep -Seconds $checkSeconds

        $terminal = Get-Process -Name 'MaxiTerminal' -ErrorAction SilentlyContinue |
            Where-Object { try { [IO.Path]::GetFullPath($_.Path) -ieq $terminalExe } catch { $false } } |
            Select-Object -First 1
        $terminalUdp = if ($terminal) {
            Get-NetUDPEndpoint -LocalPort 50765 -ErrorAction SilentlyContinue |
                Where-Object OwningProcess -eq $terminal.Id | Select-Object -First 1
        }

        & curl.exe --insecure --silent --fail --max-time 5 "https://127.0.0.1:$servicePort/readyz" *> $null
        $serviceOk = $LASTEXITCODE -eq 0
        $pgRoot = Get-PortablePostgresRoot $applicationRoot
        $databaseOk = $true
        if ($pgRoot) {
            & (Join-Path $pgRoot 'bin\pg_isready.exe') -h 127.0.0.1 -p 5432 -q
            $databaseOk = $LASTEXITCODE -eq 0
        }

        if ($serviceOk -and $databaseOk -and $terminal -and $terminalUdp) { $failureCount = 0 } else { $failureCount++ }

        $clientConnection = Get-NetTCPConnection -LocalPort 80, 10082, $servicePort -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -in 'Established', 'TimeWait', 'CloseWait', 'FinWait1', 'FinWait2', 'SynReceived' -and
                $_.RemoteAddress -notin '127.0.0.1', '::1', '0.0.0.0', '::'
            } | Select-Object -First 1
        $outLogWrite = if (Test-Path -LiteralPath $outLog) { (Get-Item -LiteralPath $outLog).LastWriteTimeUtc } else { [datetime]::MinValue }
        if ($clientConnection -or $outLogWrite -gt $lastOutLogWrite) { $lastClientActivity = Get-Date }
        $lastOutLogWrite = $outLogWrite

        $reason = $null
        if ($failureCount -ge $failureThreshold) {
            $reason = "health failed $failureCount consecutive times"
        } elseif (((Get-Date) - $lastClientActivity).TotalMinutes -ge $idleMinutes -and -not $clientConnection) {
            $reason = "no LAN client activity for at least $idleMinutes minutes"
        }

        if ($reason) {
            Write-WatchdogLog "Recovery started: $reason."
            try {
                & (Join-Path $PSScriptRoot 'Stop-Bayshore-And-Terminal.ps1') -KeepWatchdog
                Start-Sleep -Seconds 2
                & (Join-Path $PSScriptRoot 'Start-Bayshore-And-Terminal.ps1') -SkipWatchdog
                Write-WatchdogLog 'Recovery completed successfully.'
                $failureCount = 0
                $lastClientActivity = Get-Date
                $lastOutLogWrite = if (Test-Path -LiteralPath $outLog) { (Get-Item -LiteralPath $outLog).LastWriteTimeUtc } else { [datetime]::MinValue }
            } catch {
                Write-WatchdogLog "Recovery failed: $($_.Exception.Message)"
                $failureCount = 0
                $lastClientActivity = Get-Date
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $pidPath) {
        $recordedPid = (Get-Content -LiteralPath $pidPath -Raw).Trim()
        if ($recordedPid -eq [string]$PID) { Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue }
    }
    Write-WatchdogLog "Stopped (PID $PID)."
}
