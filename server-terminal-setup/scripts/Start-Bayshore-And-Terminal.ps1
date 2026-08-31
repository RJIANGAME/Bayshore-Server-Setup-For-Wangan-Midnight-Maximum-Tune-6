[CmdletBinding()]
param()

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

if ((Get-FileHash -LiteralPath $terminalExe -Algorithm SHA256).Hash -ne [string]$config.MaxiTerminalSha256) {
    throw 'Installed MaxiTerminal.exe no longer matches the approved SHA-256. Run configuration again.'
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

Write-Host 'Bayshore and WMMT6 terminal are ready.' -ForegroundColor Green
Write-Host "Server: https://${serverIp}:$servicePort"
Write-Host "Terminal PID: $($existing.Id), UDP 50765"
