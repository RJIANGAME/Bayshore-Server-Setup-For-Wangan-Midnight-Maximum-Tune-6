[CmdletBinding()]
param(
    [string]$BayshoreRoot,
    [string]$MaxiTerminalPath,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
$setupRoot = Split-Path $PSScriptRoot -Parent
$expectedMaxiHash = 'DF792DE6500F1A9836439535846B12E2391024E98097DE4E7145F29027F262AF'

function Select-Folder([string]$Title) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = [System.Windows.Forms.FolderBrowserDialog]::new()
    $picker.Description = $Title
    $picker.ShowNewFolderButton = $false
    try {
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No Bayshore server folder was selected.' }
        return [IO.Path]::GetFullPath($picker.SelectedPath)
    }
    finally { $picker.Dispose() }
}

function Select-MaxiTerminal {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = [System.Windows.Forms.OpenFileDialog]::new()
    $picker.Title = 'Select your legally obtained WMMT6 MaxiTerminal.exe'
    $picker.Filter = 'MaxiTerminal.exe|MaxiTerminal.exe'
    $picker.FileName = 'MaxiTerminal.exe'
    $picker.CheckFileExists = $true
    try {
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'MaxiTerminal.exe was not selected.' }
        return [IO.Path]::GetFullPath($picker.FileName)
    }
    finally { $picker.Dispose() }
}

if (-not $BayshoreRoot) { $BayshoreRoot = Select-Folder 'Select the Bayshore server root folder' }
$BayshoreRoot = [IO.Path]::GetFullPath($BayshoreRoot)

$applicationRoot = $null
if (Test-Path -LiteralPath (Join-Path $BayshoreRoot 'config.json') -PathType Leaf) {
    $applicationRoot = $BayshoreRoot
} elseif (Test-Path -LiteralPath (Join-Path $BayshoreRoot 'server\config.json') -PathType Leaf) {
    $applicationRoot = Join-Path $BayshoreRoot 'server'
} else {
    throw "The selected folder is not a configured Bayshore server: $BayshoreRoot"
}

if (-not $MaxiTerminalPath) { $MaxiTerminalPath = Select-MaxiTerminal }
$MaxiTerminalPath = [IO.Path]::GetFullPath($MaxiTerminalPath)
if ([IO.Path]::GetFileName($MaxiTerminalPath) -ine 'MaxiTerminal.exe') { throw 'The selected file must be named MaxiTerminal.exe.' }
$actualHash = (Get-FileHash -LiteralPath $MaxiTerminalPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedMaxiHash) {
    throw "Unsupported MaxiTerminal.exe SHA-256: $actualHash. Expected the approved WMMT6 build $expectedMaxiHash."
}

$bayshoreConfigPath = Join-Path $applicationRoot 'config.json'
$bayshoreConfig = Get-Content -LiteralPath $bayshoreConfigPath -Raw | ConvertFrom-Json
$serverIp = [string]$bayshoreConfig.serverIp
$parsedIp = $null
if (-not [Net.IPAddress]::TryParse($serverIp, [ref]$parsedIp) -or
    $parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    -not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $serverIp -ErrorAction SilentlyContinue)) {
    throw "Bayshore config.json serverIp is not assigned to this computer: $serverIp"
}

$servicePort = 9002
$envPath = Join-Path $applicationRoot '.env'
if (Test-Path -LiteralPath $envPath -PathType Leaf) {
    $envText = [IO.File]::ReadAllText($envPath)
    $portMatch = [regex]::Match($envText, '(?m)^SERVICE_PORT=(\d+)$')
    if ($portMatch.Success) { $servicePort = [int]$portMatch.Groups[1].Value }
}

$terminalRoot = Join-Path $applicationRoot 'bin\MaxiTerminal'
$terminalExe = Join-Path $terminalRoot 'MaxiTerminal.exe'
New-Item -ItemType Directory -Force -Path $terminalRoot | Out-Null
if ([IO.Path]::GetFullPath($MaxiTerminalPath) -ine [IO.Path]::GetFullPath($terminalExe)) {
    Copy-Item -LiteralPath $MaxiTerminalPath -Destination $terminalExe -Force
}

$terminalConfig = [ordered]@{
    adapter = $serverIp
    online_mode = '1'
    server_uri = "https://${serverIp}:$servicePort"
    software_revision = '10304'
    event_mode = '0'
    event_mode_count = '4'
    event_double = '0'
    event_2on2 = '0'
    event_serial = '0000000000'
    freeplay = '0'
    version = '100'
    feature_year = '2018'
    feature_month = '12'
    feature_pluses = '0'
    feature_release_at = '0'
    packet_interval = '120'
    adapter_ip = $serverIp
    coin_chute = 1
    buycard_cost = 8
    game_cost = 1
    continue_cost = 1
    fullcourse_cost = 4
}
[IO.File]::WriteAllText((Join-Path $terminalRoot 'config.json'), ($terminalConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

$installedConfig = [ordered]@{
    BayshoreRoot = $BayshoreRoot
    ApplicationRoot = $applicationRoot
    ServerIp = $serverIp
    ServicePort = $servicePort
    MaxiTerminalPath = $terminalExe
    MaxiTerminalSha256 = $expectedMaxiHash
    WatchdogEnabled = $true
    IdleRestartMinutes = 60
    HealthCheckSeconds = 10
    HealthFailureThreshold = 3
}
[IO.File]::WriteAllText((Join-Path $setupRoot 'server-terminal.json'), ($installedConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

if (-not $SkipFirewall) {
    $ruleName = 'Bayshore WMMT6 MaxiTerminal UDP 50765'
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol UDP -LocalPort 50765 -Program $terminalExe | Out-Null
}

Write-Host 'Verified and installed the user-supplied MaxiTerminal.' -ForegroundColor Green
Write-Host "Server IP: $serverIp"
Write-Host "Game service: https://${serverIp}:$servicePort"
Write-Host "Terminal: $terminalExe"
Write-Host 'Run Start-Bayshore-And-Terminal.bat for daily startup.'
