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

Get-Process -Name 'MaxiTerminal' -ErrorAction SilentlyContinue |
    Where-Object { try { [IO.Path]::GetFullPath($_.Path) -ieq $terminalExe } catch { $false } } |
    Stop-Process -Force -ErrorAction Stop

$portableStop = Join-Path $applicationRoot 'scripts\Stop-PublishedServer.ps1'
$sourceStop = Join-Path $applicationRoot 'scripts\Stop.ps1'
if (Test-Path -LiteralPath $portableStop -PathType Leaf) {
    & $portableStop
} elseif (Test-Path -LiteralPath $sourceStop -PathType Leaf) {
    & $sourceStop
} else {
    Write-Warning "No supported Bayshore stop script was found under $applicationRoot; MaxiTerminal was stopped."
}

Write-Host 'Bayshore and WMMT6 terminal stop completed.' -ForegroundColor Green
