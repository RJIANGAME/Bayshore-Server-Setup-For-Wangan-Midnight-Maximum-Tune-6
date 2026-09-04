[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$SkipWatchdog
)

$ErrorActionPreference = 'Stop'
$setupRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $setupRoot 'server-terminal.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Server terminal is not configured. Run Configure-Server-Terminal.bat first.'
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$applicationRoot = [IO.Path]::GetFullPath([string]$config.ApplicationRoot)
$terminalExe = [IO.Path]::GetFullPath([string]$config.MaxiTerminalPath)
$serverIp = [string]$config.ServerIp
$servicePort = [int]$config.ServicePort

# IIS registers a wildcard HTTP.sys listener on TCP 80, which conflicts with
# Bayshore's ALL.NET listener. Only stop IIS when that exact conflict exists.
$port80 = Get-NetTCPConnection -LocalPort 80 -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' -and $_.OwningProcess -eq 4 } |
    Select-Object -First 1
if ($port80) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $elevatedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Restart) { $elevatedArgs += '-Restart' }
        if ($SkipWatchdog) { $elevatedArgs += '-SkipWatchdog' }
        $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList $elevatedArgs -WorkingDirectory (Get-Location).Path -Wait -PassThru
        exit $elevated.ExitCode
    }
    $w3svc = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
    if ($w3svc -and $w3svc.Status -eq 'Running') {
        Stop-Service -Name W3SVC -Force
        Set-Service -Name W3SVC -StartupType Manual
    }
    $was = Get-Service -Name WAS -ErrorAction SilentlyContinue
    if ($was -and $was.Status -eq 'Running') {
        Stop-Service -Name WAS -Force
        Set-Service -Name WAS -StartupType Manual
    }
    Start-Sleep -Seconds 2
}

if ($Restart) {
    $stopScript = Join-Path $PSScriptRoot 'Stop-Bayshore-And-Terminal.ps1'
    & $stopScript
}

if ((Get-FileHash -LiteralPath $terminalExe -Algorithm SHA256).Hash -ne [string]$config.MaxiTerminalSha256) {
    throw 'Installed MaxiTerminal.exe no longer matches the approved SHA-256. Run configuration again.'
}

# Start the bundled PostgreSQL before Bayshore. Bayshore's own launcher still
# handles external/service-based PostgreSQL installations.
$pgRoot = @(
    (Join-Path $applicationRoot '.runtime\pgsql'),
    (Join-Path $applicationRoot '.runtime\postgresql')
) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bin\pg_ctl.exe') } | Select-Object -First 1
$pgData = Join-Path $applicationRoot '.data\postgres'
if ($pgRoot -and (Test-Path -LiteralPath $pgData -PathType Container)) {
    $pgReady = Join-Path $pgRoot 'bin\pg_isready.exe'
    & $pgReady -h 127.0.0.1 -p 5432 -q
    if ($LASTEXITCODE -ne 0) {
        $dataRoot = Join-Path $applicationRoot '.data'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        $pgCtl = Join-Path $pgRoot 'bin\pg_ctl.exe'
        $pgLog = Join-Path $dataRoot 'postgres.log'
        $quotedData = '"' + $pgData.Replace('"', '\"') + '"'
        $quotedLog = '"' + $pgLog.Replace('"', '\"') + '"'
        $pgOptions = '"-h 127.0.0.1 -p 5432"'
        $pgArguments = "start -D $quotedData -l $quotedLog -w -o $pgOptions"
        # Keep PostgreSQL out of the interactive launcher's console process
        # group. Closing the BAT window must not send Ctrl+C to postgres.
        $pgStart = Start-Process -FilePath $pgCtl -ArgumentList $pgArguments `
            -WindowStyle Hidden -PassThru
        if (-not $pgStart.WaitForExit(30000)) {
            try { $pgStart.Kill() } catch { }
            throw 'PostgreSQL startup timed out.'
        }
        $pgStart.Refresh()
        if ($pgStart.ExitCode -ne 0) { throw "PostgreSQL failed to start (pg_ctl exit $($pgStart.ExitCode))." }
    }
}

$sourceStart = Join-Path $applicationRoot 'scripts\Start.ps1'
$portableStart = Join-Path $applicationRoot 'scripts\Start-PublishedServer.ps1'
if (Test-Path -LiteralPath $portableStart -PathType Leaf) {
    & $portableStart
} elseif (Test-Path -LiteralPath $sourceStart -PathType Leaf) {
    & $sourceStart -Background
} else {
    throw "Could not find a supported Bayshore start script under $applicationRoot"
}

$deadline = (Get-Date).AddSeconds(45)
do {
    & curl.exe --insecure --silent --fail --connect-timeout 1 "https://127.0.0.1:$servicePort/readyz" *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
if ($LASTEXITCODE -ne 0) { throw "Bayshore did not become ready on TCP $servicePort." }

$existing = Get-Process -Name 'MaxiTerminal' -ErrorAction SilentlyContinue |
    Where-Object { try { [IO.Path]::GetFullPath($_.Path) -ieq $terminalExe } catch { $false } } |
    Select-Object -First 1
if (-not $existing) {
    $existing = Start-Process -FilePath $terminalExe -WorkingDirectory (Split-Path $terminalExe -Parent) -WindowStyle Hidden -PassThru
}
$terminalDeadline = (Get-Date).AddSeconds(15)
do {
    if ($existing.HasExited) { throw "MaxiTerminal exited with code $($existing.ExitCode)." }
    $udp = Get-NetUDPEndpoint -LocalPort 50765 -ErrorAction SilentlyContinue |
        Where-Object OwningProcess -eq $existing.Id |
        Select-Object -First 1
    if ($udp) { break }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $terminalDeadline)
if (-not $udp) { throw 'MaxiTerminal is running but did not bind UDP 50765.' }

$relayEnabled = $config.PSObject.Properties.Name -contains 'TerminalRelayEnabled' -and [bool]$config.TerminalRelayEnabled
$relayClients = @($config.TerminalRelayClientIps) | ForEach-Object { [string]$_ } | Where-Object { $_ }
$relay = $null
if ($relayEnabled -and $relayClients.Count -gt 0) {
    $relayScript = Join-Path $PSScriptRoot 'Relay-MaxiTerminal.ps1'
    if (-not (Test-Path -LiteralPath $relayScript -PathType Leaf)) { throw "Terminal relay script is missing: $relayScript" }
    $relayPidPath = Join-Path $setupRoot 'terminal-relay.pid'
    if (Test-Path -LiteralPath $relayPidPath -PathType Leaf) {
        $relayPid = 0
        if ([int]::TryParse((Get-Content -LiteralPath $relayPidPath -Raw).Trim(), [ref]$relayPid)) {
            $relayProcess = Get-Process -Id $relayPid -ErrorAction SilentlyContinue
            $relayCommand = Get-CimInstance Win32_Process -Filter "ProcessId=$relayPid" -ErrorAction SilentlyContinue
            if ($relayProcess -and
                ($relayCommand.CommandLine -match 'Relay-MaxiTerminal\.ps1' -or
                 [string]::IsNullOrWhiteSpace([string]$relayCommand.CommandLine))) {
                $relay = $relayProcess
            }
        }
    }
    if (-not $relay) {
        $relayArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$relayScript`""
        $relay = Start-Process -FilePath 'powershell.exe' -ArgumentList $relayArgs -WorkingDirectory $setupRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 2
        $relay.Refresh()
        if ($relay.HasExited) {
            if ($relay.ExitCode -eq 0) {
                Write-Host 'Terminal unicast relay is already running.'
                $relay = $null
            } else {
                throw "Terminal unicast relay exited during startup with code $($relay.ExitCode)."
            }
        }
    }
}

if (-not $SkipWatchdog) {
    $watchdogScript = Join-Path $PSScriptRoot 'Watch-Bayshore-And-Terminal.ps1'
    $watchdogPidPath = Join-Path $setupRoot 'watchdog.pid'
    $watchdogRunning = $false
    if (Test-Path -LiteralPath $watchdogPidPath -PathType Leaf) {
        $watchdogPid = 0
        if ([int]::TryParse((Get-Content -LiteralPath $watchdogPidPath -Raw).Trim(), [ref]$watchdogPid)) {
            $watchdogRunning = [bool](Get-Process -Id $watchdogPid -ErrorAction SilentlyContinue)
        }
    }
    if (-not $watchdogRunning) {
        $watchdogArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$watchdogScript`""
        $watchdog = Start-Process -FilePath 'powershell.exe' -ArgumentList $watchdogArgs -WorkingDirectory $setupRoot -WindowStyle Hidden -PassThru
        [IO.File]::WriteAllText($watchdogPidPath, [string]$watchdog.Id, [Text.Encoding]::ASCII)
    }
}

Write-Host 'PostgreSQL, Bayshore, and WMMT6 terminal are ready.' -ForegroundColor Green
Write-Host "Server: https://${serverIp}:$servicePort"
Write-Host "Terminal PID: $($existing.Id), UDP 50765"
if ($relay) { Write-Host "Terminal unicast relay PID: $($relay.Id); clients: $($relayClients -join ', ')" }
if (-not $SkipWatchdog) { Write-Host 'Recovery watchdog: running' }
