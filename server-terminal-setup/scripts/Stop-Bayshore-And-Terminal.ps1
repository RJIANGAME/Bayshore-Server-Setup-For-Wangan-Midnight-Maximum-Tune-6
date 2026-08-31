[CmdletBinding()]
param([switch]$KeepWatchdog)

$ErrorActionPreference = 'Stop'
$setupRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $setupRoot 'server-terminal.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Server terminal is not configured. Run Configure-Server-Terminal.bat first.'
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$applicationRoot = [IO.Path]::GetFullPath([string]$config.ApplicationRoot)
$terminalExe = [IO.Path]::GetFullPath([string]$config.MaxiTerminalPath)

if (-not $KeepWatchdog) {
    $watchdogPidPath = Join-Path $setupRoot 'watchdog.pid'
    if (Test-Path -LiteralPath $watchdogPidPath -PathType Leaf) {
        $watchdogPid = 0
        if ([int]::TryParse((Get-Content -LiteralPath $watchdogPidPath -Raw).Trim(), [ref]$watchdogPid) -and $watchdogPid -ne $PID) {
            Stop-Process -Id $watchdogPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $watchdogPidPath -Force -ErrorAction SilentlyContinue
    }
}

Get-Process -Name 'MaxiTerminal' -ErrorAction SilentlyContinue |
    Where-Object { try { [IO.Path]::GetFullPath($_.Path) -ieq $terminalExe } catch { $false } } |
    Stop-Process -Force -ErrorAction Stop

$portableStop = Join-Path $applicationRoot 'scripts\Stop-PublishedServer.ps1'
$sourceStop = Join-Path $applicationRoot 'scripts\Stop.ps1'
if (Test-Path -LiteralPath $portableStop -PathType Leaf) {
    & $portableStop
} elseif (Test-Path -LiteralPath $sourceStop -PathType Leaf) {
    # Stop the application first. PostgreSQL is handled idempotently below;
    # older source stop scripts fail when -IncludeDatabase is used while the
    # database is already stopped.
    & $sourceStop
} else {
    Write-Warning "No supported Bayshore stop script was found under $applicationRoot; MaxiTerminal was stopped."
}

# Also stop a bundled database when the application stop script does not.
$pgRoot = @(
    (Join-Path $applicationRoot '.runtime\pgsql'),
    (Join-Path $applicationRoot '.runtime\postgresql')
) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bin\pg_ctl.exe') } | Select-Object -First 1
$pgData = Join-Path $applicationRoot '.data\postgres'
if ($pgRoot -and (Test-Path -LiteralPath $pgData -PathType Container)) {
    & (Join-Path $pgRoot 'bin\pg_ctl.exe') -D $pgData status *> $null
    if ($LASTEXITCODE -eq 0) {
        & (Join-Path $pgRoot 'bin\pg_ctl.exe') -D $pgData stop -m fast
        if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL failed to stop.' }
    }
}

Write-Host 'PostgreSQL, Bayshore, and WMMT6 terminal stop completed.' -ForegroundColor Green
