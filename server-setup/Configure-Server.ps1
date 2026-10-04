[CmdletBinding()]
param([string]$BayshoreRoot, [string]$ServerIp, [string]$MaxiTerminalPath)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot -Parent
if (-not $BayshoreRoot) {
    $bundledRoot = Join-Path $packageRoot 'server'
    if (Test-Path -LiteralPath (Join-Path $bundledRoot 'package.json') -PathType Leaf) { $BayshoreRoot = $bundledRoot }
    elseif (Test-Path -LiteralPath (Join-Path $packageRoot 'package.json') -PathType Leaf) { $BayshoreRoot = $packageRoot }
    else { throw 'Use the complete server setup ZIP from releases; its server folder is missing.' }
}
$BayshoreRoot = [IO.Path]::GetFullPath($BayshoreRoot)
foreach ($required in 'package.json', 'scripts\Setup.ps1', 'src\index.ts') {
    if (-not (Test-Path -LiteralPath (Join-Path $BayshoreRoot $required) -PathType Leaf)) { throw "Missing server file: $required" }
}
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Install Node.js 22 or newer LTS from https://nodejs.org, reopen setup, and try again.'
}
if (-not $ServerIp) {
    $existingConfig = Join-Path $BayshoreRoot 'config.json'
    $defaultIp = if (Test-Path -LiteralPath $existingConfig -PathType Leaf) {
        [string](Get-Content -LiteralPath $existingConfig -Raw | ConvertFrom-Json).serverIp
    } else {
        [string](Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway -and $_.IPv4Address } |
            Sort-Object { $_.NetIPv4Interface.InterfaceMetric } | Select-Object -First 1).IPv4Address.IPAddress
    }
    $typedIp = (Read-Host "Server LAN IPv4 address [Enter uses $defaultIp]").Trim()
    $ServerIp = if ($typedIp) { $typedIp } else { $defaultIp }
}
$parsed = $null
if (-not [Net.IPAddress]::TryParse($ServerIp, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    -not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $ServerIp -ErrorAction SilentlyContinue)) {
    throw "Server address $ServerIp is not an active IPv4 address on this PC."
}
$terminalSetup = Join-Path $packageRoot 'server-terminal-setup\scripts\Configure-Server-Terminal.ps1'
if (-not (Test-Path -LiteralPath $terminalSetup -PathType Leaf)) { throw 'The server-terminal-setup folder is missing.' }
Write-Host 'Setting up PostgreSQL, the player database, and Bayshore. First setup downloads PostgreSQL and Node dependencies.'
& (Join-Path $BayshoreRoot 'scripts\Setup.ps1') -ServerIp $ServerIp
& $terminalSetup -BayshoreRoot $BayshoreRoot -MaxiTerminalPath $MaxiTerminalPath
& (Join-Path $BayshoreRoot 'scripts\Configure-Firewall.ps1')
Write-Host ''
Write-Host 'Server setup completed.' -ForegroundColor Green
Write-Host "Give the player PCs this server IP: $ServerIp"
Write-Host 'Start: server-terminal-setup\Start-Bayshore-And-Terminal.bat'
Write-Host 'Stop: server-terminal-setup\Stop-Bayshore-And-Terminal.bat'
Write-Host 'Keep this entire folder for future use: it contains your player saves and configuration.'
