[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Client setup must run as administrator. Right-click Configure-Client.bat and select Run as administrator.'
}
$clientRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $clientRoot 'client-config.json'
$assetRoot = Join-Path $clientRoot 'assets'

if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

function Require-IPv4([string]$Name, [string]$Value) {
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "$Name must be a valid IPv4 address in client-config.json."
    }
}

$autoNetwork = $null
if ($config.AdapterIp -eq 'AUTO' -or $config.RouterIp -eq 'AUTO') {
    $autoNetwork = Get-NetIPConfiguration |
        Where-Object {
            $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address -and $_.IPv4DefaultGateway
        } |
        Sort-Object { $_.NetIPv4Interface.InterfaceMetric } |
        Select-Object -First 1
    if (-not $autoNetwork) {
        throw 'AUTO network detection failed. Set ServerIp, AdapterIp, and RouterIp manually in client-config.json.'
    }
}

$adapterIp = if ($config.AdapterIp -eq 'AUTO') { [string]$autoNetwork.IPv4Address.IPAddress } else { [string]$config.AdapterIp }
$routerIp = if ($config.RouterIp -eq 'AUTO') { [string]$autoNetwork.IPv4DefaultGateway.NextHop } else { [string]$config.RouterIp }
$configuredServerIp = [string]$config.ServerIp
if ([string]::IsNullOrWhiteSpace($configuredServerIp) -or $configuredServerIp -in @('PROMPT', 'SELECT', 'AUTO')) {
    do {
        $serverIp = (Read-Host 'Enter the Bayshore server IPv4 address (example: 192.168.0.25)').Trim()
        $parsedServerIp = $null
        $validServerIp = [Net.IPAddress]::TryParse($serverIp, [ref]$parsedServerIp) -and
            $parsedServerIp.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
        if (-not $validServerIp) {
            Write-Warning 'Enter a valid IPv4 address, such as 192.168.0.25.'
        }
    } while (-not $validServerIp)
} else {
    $serverIp = $configuredServerIp
}

Require-IPv4 'ServerIp' $serverIp
Require-IPv4 'AdapterIp' $adapterIp
Require-IPv4 'RouterIp' $routerIp
$config.ServerIp = $serverIp
$config.AdapterIp = $adapterIp
$config.RouterIp = $routerIp

$configuredCabinetId = if ($config.PSObject.Properties.Name -contains 'CabinetId') { [string]$config.CabinetId } else { 'PROMPT' }
if ($configuredCabinetId -notmatch '^[1-4]$') {
    do {
        $configuredCabinetId = (Read-Host 'Enter this drive cabinet number (1-4; every active cabinet must be different)').Trim()
        if ($configuredCabinetId -notmatch '^[1-4]$') {
            Write-Warning 'Cabinet number must be 1, 2, 3, or 4.'
        }
    } while ($configuredCabinetId -notmatch '^[1-4]$')
}
$cabinetId = [int]$configuredCabinetId
if ($config.PSObject.Properties.Name -contains 'CabinetId') {
    $config.CabinetId = $cabinetId
} else {
    $config | Add-Member -NotePropertyName CabinetId -NotePropertyValue $cabinetId
}

function Resolve-ExecutablePath(
    [string]$ConfiguredPath,
    [string]$Label,
    [string]$FileName,
    [string[]]$RelativeCandidates
) {
    $forceSelection = $ConfiguredPath -eq 'SELECT'
    if ($ConfiguredPath -and $ConfiguredPath -ne 'AUTO' -and -not $forceSelection) {
        $expanded = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ConfiguredPath))
        $explicitFile = if ([IO.Path]::GetExtension($expanded)) { $expanded } else { Join-Path $expanded $FileName }
        if (Test-Path -LiteralPath $explicitFile -PathType Leaf) { return $explicitFile }
        Write-Warning "$Label was not found at the configured path: $explicitFile"
    }

    $detected = @()
    if (-not $forceSelection) {
        foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
            foreach ($relative in $RelativeCandidates) {
                $candidate = Join-Path $drive.Root $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $detected += [IO.Path]::GetFullPath($candidate)
                }
            }
        }
    }
    $detected = @($detected | Sort-Object -Unique)
    if ($detected.Count -eq 1 -and -not $forceSelection) {
        Write-Host "Auto-detected ${Label}: $($detected[0])"
        return $detected[0]
    }
    if ($detected.Count -gt 1) {
        Write-Warning "Multiple $Label installations were found. Select the correct one:"
        $detected | ForEach-Object { Write-Host "  $_" }
    } elseif ($forceSelection) {
        Write-Host "Manual $Label selection is enabled to prevent choosing an old or unintended installation."
    }

    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Select $Label ($FileName)"
    $picker.Filter = "$FileName|$FileName|Executable files (*.exe)|*.exe"
    $picker.FileName = $FileName
    $picker.CheckFileExists = $true
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw "$Label was not selected. Set its path in client-config.json and run setup again."
    }
    if ([IO.Path]::GetFileName($picker.FileName) -ine $FileName) {
        throw "Expected $FileName for $Label, but $([IO.Path]::GetFileName($picker.FileName)) was selected."
    }
    return [IO.Path]::GetFullPath($picker.FileName)
}

$gameExe = Resolve-ExecutablePath ([string]$config.GamePath) 'WMMT6 game' 'wmn6r.exe' @(
    'WMMT6\wmn6r.exe',
    'Games\WMMT6\wmn6r.exe',
    'Arcade\Games\WMMT6\wmn6r.exe',
    'WMMT6\WMMT6\Wangan Midnight Maximum Tune 6 (Namco ES3)\wmn6r.exe',
    'Games\Wangan Midnight Maximum Tune 6 (Namco ES3)\wmn6r.exe'
)
$tpExe = Resolve-ExecutablePath ([string]$config.TeknoParrotPath) 'TeknoParrot' 'TeknoParrotUi.exe' @(
    'TeknoParrot\TeknoParrotUi.exe',
    'Games\TeknoParrot\TeknoParrotUi.exe',
    'Arcade\TeknoParrot\TeknoParrotUi.exe'
)
$maxiExe = $null
if ([string]$config.MaxiTerminalPath -ne 'DISABLED') {
    $maxiExe = Resolve-ExecutablePath ([string]$config.MaxiTerminalPath) 'MaxiTerminal' 'MaxiTerminal.exe' @(
        'MaxiTerminal\MaxiTerminal.exe',
        'Tools\MaxiTerminal\MaxiTerminal.exe',
        'Games\MaxiTerminal\MaxiTerminal.exe',
        'Arcade\Bayshore\bin\MaxiTerminal\MaxiTerminal.exe',
        'Bayshore\bin\MaxiTerminal\MaxiTerminal.exe'
    )
}
$gameRoot = Split-Path $gameExe -Parent
$tpRoot = Split-Path $tpExe -Parent
$amcus = Join-Path $gameRoot 'AMCUS'
$launcherSourceRoot = Join-Path $clientRoot 'launcher'

foreach ($required in $gameExe, $tpExe, (Join-Path $amcus 'AMAuthd.exe'), (Join-Path $amcus 'AMConfig.ini'), (Join-Path $amcus 'iauthdll.dll'), (Join-Path $amcus 'MuchaBin\muchacd.exe')) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required client file is missing: $required" }
}
$expectedGameHashes = @('92F02199A44FA65A35AF3ED162B5CE5477CFC8B2E3A13CCC95936356680F1479')
$gameHash = (Get-FileHash -LiteralPath $gameExe -Algorithm SHA256).Hash
if ($gameHash -notin $expectedGameHashes) {
    throw "Unsupported wmn6r.exe SHA-256: $gameHash. This package supports WMMT6 1.03.04 only."
}

$installedOpenParrotPath = Join-Path $tpRoot 'OpenParrotx64\OpenParrot64.dll'
if (-not (Test-Path -LiteralPath $installedOpenParrotPath -PathType Leaf)) {
    throw "TeknoParrot's OpenParrot64.dll is missing: $installedOpenParrotPath"
}
$installedOpenParrotHash = (Get-FileHash -LiteralPath $installedOpenParrotPath -Algorithm SHA256).Hash
$knownCrashingOpenParrotHashes = @(
    'C91922AFAEEBFA9EF81BE2FA532DBCF0E6F4A2DF6EA3C91C5F84AD86D7790952',
    'BF36B6971738F8B43C400BF07CB422729A8B1065CB429A1978E89782FD09A5E9'
)
if ($installedOpenParrotHash -in $knownCrashingOpenParrotHashes) {
    throw "The installed OpenParrot64.dll is a known crashing build from an older Bayshore client package ($installedOpenParrotHash). Restore OpenParrot64.dll using TeknoParrot's updater or a clean TeknoParrot backup, then rerun setup. No client files were changed."
}
Write-Host "Preserving TeknoParrot-supplied OpenParrot64.dll: $installedOpenParrotPath (SHA-256 $installedOpenParrotHash)"

# AMAuth's serialID uses the 280811... identity exposed by OpenParrot's WMMT6
# terminal/auth path. Do not use the separate 280813... drive-dongle identity.
$openParrotAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($installedOpenParrotPath))
$embeddedAuthSerials = @([regex]::Matches($openParrotAscii, '2808119900\d{2}') | ForEach-Object Value | Sort-Object -Unique)
if ($embeddedAuthSerials.Count -ne 1) {
    throw "Could not identify exactly one WMMT6 AMAuth serial in OpenParrot64.dll. Found: $($embeddedAuthSerials -join ', '). Restore or rebuild a compatible Project Asakura OpenParrot DLL."
}
foreach ($required in 'WMMT6-Launch.bat', 'WMMT6-Launch.ps1') {
    $requiredPath = Join-Path $launcherSourceRoot $required
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required safe launcher file is missing: $requiredPath" }
}
$embeddedAuthSerial = [string]$embeddedAuthSerials[0]
$configuredDriveSerial = if ($config.PSObject.Properties.Name -contains 'DriveSerial') { [string]$config.DriveSerial } else { 'AUTO' }
$driveSerial = if ([string]::IsNullOrWhiteSpace($configuredDriveSerial) -or $configuredDriveSerial -eq 'AUTO') { $embeddedAuthSerial } else { $configuredDriveSerial }
if ($driveSerial -notmatch '^\d{12}$') { throw 'DriveSerial must be AUTO or exactly 12 decimal digits.' }
if ($driveSerial -ne $embeddedAuthSerial) {
    throw "DriveSerial $driveSerial does not match OpenParrot's embedded AMAuth serial $embeddedAuthSerial. Use AUTO or make both values identical."
}
Write-Host "Matched OpenParrot/AMAuth serial: $driveSerial"

$requiredClientAssets = @(
    @{ Name = 'bngrw.dll'; Hash = '1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74'; Candidates = @((Join-Path $gameRoot 'bngrw.dll')) },
    @{ Name = 'setting.lua.gz'; Hash = '298852A70485DBBAA889739A8A360923DFE7262231AE15CCE758F56ABF8093DD'; Candidates = @((Join-Path $gameRoot 'TP\setting.lua.gz')) },
    @{ Name = 'server_wangan.crt'; Hash = 'D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377'; Candidates = @(
        (Join-Path $gameRoot 'data_jp\network\certs\terminal-cert_v388.pem'),
        (Join-Path $gameRoot 'data_jp\network\certs\v388-ca-cert.pem')
    ) },
    @{ Name = 'server_wangan.key'; Hash = '56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B'; Candidates = @((Join-Path $gameRoot 'data_jp\network\private\terminal-key_v388.pem')) }
)
$resolvedClientAssets = @{}
foreach ($asset in $requiredClientAssets) {
    $assetPath = $null
    $candidatePaths = @((Join-Path $assetRoot $asset.Name)) + @($asset.Candidates)
    $seenCandidatePaths = @{}
    foreach ($candidatePath in $candidatePaths) {
        $candidatePath = [IO.Path]::GetFullPath($candidatePath)
        if ($seenCandidatePaths.ContainsKey($candidatePath)) { continue }
        $seenCandidatePaths[$candidatePath] = $true
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
        $candidateHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
        if ($candidateHash -eq $asset.Hash) {
            $assetPath = [IO.Path]::GetFullPath($candidatePath)
            Write-Host "Using verified $($asset.Name): $assetPath"
            break
        }
        Write-Warning "Ignoring incompatible $($asset.Name) at $candidatePath (SHA-256 $candidateHash)."
    }

    if (-not $assetPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title = "Select compatible $($asset.Name)"
        $picker.Filter = 'Compatible client files (*.dll;*.gz;*.crt;*.key;*.pem)|*.dll;*.gz;*.crt;*.key;*.pem|All files (*.*)|*.*'
        $picker.FileName = $asset.Name
        $picker.CheckFileExists = $true
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw "Compatible $($asset.Name) was not selected. Required SHA-256: $($asset.Hash)"
        }
        $selectedHash = (Get-FileHash -LiteralPath $picker.FileName -Algorithm SHA256).Hash
        if ($selectedHash -ne $asset.Hash) {
            throw "Selected $($asset.Name) is incompatible. Expected SHA-256 $($asset.Hash), received $selectedHash."
        }
        $assetPath = [IO.Path]::GetFullPath($picker.FileName)
        Write-Host "Using selected verified $($asset.Name): $assetPath"
    }
    $resolvedClientAssets[$asset.Name] = $assetPath
}

# Complete read-only preflight. Nothing below this block has modified the game,
# TeknoParrot, hosts file, firewall, routes, or client identity.
$preflightEncoding = [Text.Encoding]::GetEncoding(932)
$preflightAmConfigPath = Join-Path $amcus 'AMConfig.ini'
$preflightAmConfig = [IO.File]::ReadAllText($preflightAmConfigPath, $preflightEncoding)
foreach ($key in @('cacfg-auth_server_url', 'cacfg-auth_server_sslverify', 'amdcfg-writableConfig', 'dtcfg-dl_image_path')) {
    if (-not [regex]::IsMatch($preflightAmConfig, ('(?m)^' + [regex]::Escape($key) + '=.*$'))) {
        throw "AMConfig.ini lacks $key. No client files were changed."
    }
}

$preflightProfilesRoot = Join-Path $tpRoot 'GameProfiles'
$preflightRequestedProfile = if ($config.PSObject.Properties.Name -contains 'ProfileName') { [string]$config.ProfileName } else { 'AUTO' }
$preflightBaseProfile = $null
if ($preflightRequestedProfile -and $preflightRequestedProfile -ne 'AUTO') {
    $preflightRequestedFile = if ($preflightRequestedProfile.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) { $preflightRequestedProfile } else { "$preflightRequestedProfile.xml" }
    $preflightCandidate = Join-Path $preflightProfilesRoot $preflightRequestedFile
    if (Test-Path -LiteralPath $preflightCandidate -PathType Leaf) { $preflightBaseProfile = Get-Item -LiteralPath $preflightCandidate }
    else { throw "Requested TeknoParrot profile is missing: $preflightCandidate. No client files were changed." }
} else {
    $preflightBaseProfile = Get-ChildItem -LiteralPath $preflightProfilesRoot -Filter '*.xml' -File |
        Where-Object { $_.BaseName -match '(?i)(WMMT.?6|Wangan.*Maximum.*Tune.*6)' -and $_.BaseName -notmatch '(?i)(6R|6RR|Bayshore)' } |
        Sort-Object @{ Expression = { if ($_.BaseName -ieq 'WMMT6') { 0 } else { 1 } } }, Name |
        Select-Object -First 1
    if (-not $preflightBaseProfile) {
        $preflightBaseProfile = Get-ChildItem -LiteralPath $preflightProfilesRoot -Filter '*.xml' -File |
            Where-Object {
                $text = Get-Content -LiteralPath $_.FullName -Raw
                $text -match '(?i)(WMMT.?6|Wangan Midnight Maximum Tune 6)' -and $text -notmatch '(?i)(WMMT.?6R|Maximum Tune 6R)'
            } |
            Select-Object -First 1
    }
    if (-not $preflightBaseProfile) { throw 'Could not find a WMMT6 TeknoParrot profile. No client files were changed.' }
}

$preflightUserProfile = Join-Path (Join-Path $tpRoot 'UserProfiles') $preflightBaseProfile.Name
if (-not (Test-Path -LiteralPath $preflightUserProfile -PathType Leaf)) {
    throw "TeknoParrot user profile is missing: $preflightUserProfile. Configure WMMT6 once in TeknoParrot, then run setup again. No client files were changed."
}
$preflightProfileXml = [xml](Get-Content -LiteralPath $preflightUserProfile -Raw)
$preflightProfileTexts = @(
    [IO.File]::ReadAllText($preflightBaseProfile.FullName),
    [IO.File]::ReadAllText($preflightUserProfile)
)
foreach ($profileText in $preflightProfileTexts) {
    foreach ($fieldName in @('HasTwoExecutables', 'LaunchSecondExecutableFirst')) {
        if (-not [regex]::IsMatch($profileText, "(?is)<$fieldName>\s*(true|false)\s*</$fieldName>")) {
            throw "TeknoParrot profile lacks required launch field '$fieldName'. No client files were changed."
        }
    }
}

$preflightIdentityPath = Join-Path $clientRoot 'generated-client-identity.json'
if (Test-Path -LiteralPath $preflightIdentityPath -PathType Leaf) {
    $preflightIdentity = Get-Content -LiteralPath $preflightIdentityPath -Raw | ConvertFrom-Json
    if ([string]$preflightIdentity.AccessCode -notmatch '^\d{20}$' -or
        [string]$preflightIdentity.CardId -notmatch '^[0-9A-Fa-f]{32}$' -or
        [string]$preflightIdentity.DriveSerial -notmatch '^\d{12}$') {
        throw "Existing client identity is invalid: $preflightIdentityPath. No client files were changed."
    }
}
$iauthDll = Join-Path $amcus 'iauthdll.dll'
$msvcr100Candidates = @(
    (Join-Path $env:WINDIR 'System32\msvcr100.dll'),
    (Join-Path $amcus 'msvcr100.dll')
)
if (-not ($msvcr100Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)) {
    throw 'iauthdll.dll requires the Microsoft Visual C++ 2010 SP1 x64 Redistributable (MSVCR100.dll). Install vcredist_x64.exe from https://www.microsoft.com/en-us/download/details.aspx?id=26999, restart Windows, and rerun setup. No client files were changed.'
}
if (-not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $config.AdapterIp -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw "The selected client IPv4 address is not assigned to this computer: $($config.AdapterIp). No client files were changed."
}
Write-Host 'Complete client preflight passed. Applying configuration...' -ForegroundColor Green

$backupRoot = Join-Path $clientRoot ("backups\{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backupNumber = 0

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $script:backupNumber++
    $safeName = ($Path -replace '^[A-Za-z]:', '') -replace '[\\/:*?"<>|]', '_'
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot ("{0:D3}_{1}" -f $script:backupNumber, $safeName)) -Force
}

function New-RandomDigits([int]$Count) {
    $bytes = [byte[]]::new($Count)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return -join ($bytes | ForEach-Object { ($_ % 10).ToString() })
}

function New-RandomHex([int]$ByteCount) {
    $bytes = [byte[]]::new($ByteCount)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return -join ($bytes | ForEach-Object { $_.ToString('X2') })
}

function Install-VerifiedAsset([string]$Name, [string]$Destination, [string]$ExpectedHash) {
    $source = [string]$resolvedClientAssets[$Name]
    if (-not $source -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Resolved client asset is missing: $Name" }
    $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash) { throw "Resolved client asset hash mismatch: $Name" }
    if ([IO.Path]::GetFullPath($source) -eq [IO.Path]::GetFullPath($Destination)) {
        Write-Host "Existing destination is already verified: $Destination"
        return
    }
    Backup-File $Destination
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $Destination -Force
}

Install-VerifiedAsset 'bngrw.dll' (Join-Path $gameRoot 'bngrw.dll') '1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74'
Install-VerifiedAsset 'setting.lua.gz' (Join-Path $gameRoot 'TP\setting.lua.gz') '298852A70485DBBAA889739A8A360923DFE7262231AE15CCE758F56ABF8093DD'

foreach ($target in @(
    (Join-Path $gameRoot 'data_jp\network\certs\terminal-cert_v388.pem'),
    (Join-Path $gameRoot 'data_jp\network\certs\v388-ca-cert.pem')
)) {
    Install-VerifiedAsset 'server_wangan.crt' $target 'D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377'
}
$keyTarget = Join-Path $gameRoot 'data_jp\network\private\terminal-key_v388.pem'
Install-VerifiedAsset 'server_wangan.key' $keyTarget '56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B'

$encoding = [Text.Encoding]::GetEncoding(932)
$amConfigPath = Join-Path $amcus 'AMConfig.ini'
Backup-File $amConfigPath
$amConfig = [IO.File]::ReadAllText($amConfigPath, $encoding)
$replacements = @{
    'cacfg-auth_server_url' = "https://$($config.ServerIp):10082/"
    'cacfg-auth_server_sslverify' = '0'
    'amdcfg-writableConfig' = (Join-Path $amcus 'WritableConfig.ini')
    'dtcfg-dl_image_path' = (Join-Path $amcus 'dl_image')
}
foreach ($item in $replacements.GetEnumerator()) {
    $pattern = '(?m)^' + [regex]::Escape($item.Key) + '=.*$'
    if (-not [regex]::IsMatch($amConfig, $pattern)) { throw "AMConfig.ini lacks $($item.Key)." }
    $amConfig = [regex]::Replace($amConfig, $pattern, ($item.Key + '=' + $item.Value))
}
[IO.File]::WriteAllText($amConfigPath, $amConfig, $encoding)

$gameProfilesRoot = Join-Path $tpRoot 'GameProfiles'
$requestedProfile = if ($config.PSObject.Properties.Name -contains 'ProfileName') { [string]$config.ProfileName } else { 'AUTO' }
$baseProfile = $null
if ($requestedProfile -and $requestedProfile -ne 'AUTO') {
    $requestedFile = if ($requestedProfile.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) { $requestedProfile } else { "$requestedProfile.xml" }
    $candidate = Join-Path $gameProfilesRoot $requestedFile
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $baseProfile = Get-Item -LiteralPath $candidate }
    else { throw "Requested TeknoParrot profile is missing: $candidate" }
} else {
    $baseProfile = Get-ChildItem -LiteralPath $gameProfilesRoot -Filter '*.xml' -File |
        Where-Object { $_.BaseName -match '(?i)(WMMT.?6|Wangan.*Maximum.*Tune.*6)' -and $_.BaseName -notmatch '(?i)(6R|6RR|Bayshore)' } |
        Sort-Object @{ Expression = { if ($_.BaseName -ieq 'WMMT6') { 0 } else { 1 } } }, Name |
        Select-Object -First 1
    if (-not $baseProfile) {
        $baseProfile = Get-ChildItem -LiteralPath $gameProfilesRoot -Filter '*.xml' -File |
            Where-Object {
                $text = Get-Content -LiteralPath $_.FullName -Raw
                $text -match '(?i)(WMMT.?6|Wangan Midnight Maximum Tune 6)' -and $text -notmatch '(?i)(WMMT.?6R|Maximum Tune 6R)'
            } |
            Select-Object -First 1
    }
    if (-not $baseProfile) { throw 'Could not auto-detect a WMMT6 TeknoParrot profile. Set ProfileName in client-config.json.' }
}

$profilePath = Join-Path (Join-Path $tpRoot 'UserProfiles') $baseProfile.Name
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "TeknoParrot user profile disappeared during setup: $profilePath" }

$identityPath = Join-Path $clientRoot 'generated-client-identity.json'
$cardPath = Join-Path $gameRoot 'card.ini'
$identity = $null
if (Test-Path -LiteralPath $identityPath -PathType Leaf) {
    $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
} else {
    $accessCode = $null
    $cardId = $null
    if (Test-Path -LiteralPath $cardPath -PathType Leaf) {
        $existingCard = Get-Content -LiteralPath $cardPath -Raw
        $accessMatch = [regex]::Match($existingCard, '(?im)^\s*accessCode\s*=\s*(\d{20})\s*$')
        $cardMatch = [regex]::Match($existingCard, '(?im)^\s*chipId\s*=\s*([0-9A-F]{32})\s*$')
        if ($accessMatch.Success -and $cardMatch.Success) {
            $accessCode = $accessMatch.Groups[1].Value
            $cardId = $cardMatch.Groups[1].Value.ToUpperInvariant()
        }
    }
    if (-not $accessCode -or -not $cardId) {
        $accessCode = New-RandomDigits 20
        $cardId = New-RandomHex 16
    }
    $identity = [pscustomobject][ordered]@{
        AccessCode = $accessCode
        CardId = $cardId
        DriveSerial = $driveSerial
        CabinetId = $cabinetId
        ProfileFile = $baseProfile.Name
    }
    [IO.File]::WriteAllText($identityPath, ($identity | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

if ([string]$identity.AccessCode -notmatch '^\d{20}$') { throw "Invalid AccessCode in $identityPath" }
if ([string]$identity.CardId -notmatch '^[0-9A-Fa-f]{32}$') { throw "Invalid CardId in $identityPath" }
if ($identity.PSObject.Properties.Name -contains 'DriveSerial') {
    $identity.DriveSerial = $driveSerial
} else {
    $identity | Add-Member -NotePropertyName DriveSerial -NotePropertyValue $driveSerial
}
if ($identity.PSObject.Properties.Name -contains 'CabinetId') {
    $identity.CabinetId = $cabinetId
} else {
    $identity | Add-Member -NotePropertyName CabinetId -NotePropertyValue $cabinetId
}

Backup-File $cardPath
[IO.File]::WriteAllText($cardPath, "[card]`r`naccessCode=$($identity.AccessCode)`r`nchipId=$($identity.CardId.ToUpperInvariant())`r`n", [Text.UTF8Encoding]::new($false))

$writablePath = Join-Path $amcus 'WritableConfig.ini'
Backup-File $writablePath
[IO.File]::WriteAllText($writablePath, "[RuntimeConfig]`r`nmode=`r`nnetID=$cabinetId`r`nserialID=$($identity.DriveSerial)`r`n", [Text.UTF8Encoding]::new($false))

# Configure only the existing WMMT6 user profile. A renamed GameProfile copy
# appears as a second "Metadata Missing" game in TeknoParrot, so v1.3.1 no
# longer creates WMMT6-Bayshore.xml. AMAuth is started by the external launcher
# and the normal profile launches only wmn6r.exe.
Backup-File $profilePath
[xml]$profileXml = Get-Content -LiteralPath $profilePath -Raw

$gamePathNode = $profileXml.SelectSingleNode('/GameProfile/GamePath')
if (-not $gamePathNode) { throw "Profile lacks GamePath: $profilePath" }
$gamePathNode.InnerText = $gameExe

foreach ($fieldName in @('HasTwoExecutables', 'LaunchSecondExecutableFirst')) {
    $node = $profileXml.SelectSingleNode("/GameProfile/$fieldName")
    if (-not $node) { throw "Profile lacks required launch field '$fieldName': $profilePath" }
    $node.InnerText = 'false'
}

function Set-TeknoParrotField([string]$Name, [string]$Value, [string]$Category = 'General') {
    $node = @($profileXml.GameProfile.ConfigValues.FieldInformation) |
        Where-Object { [string]$_.FieldName -eq $Name } |
        Select-Object -First 1
    if ($node) {
        $node.FieldValue = $Value
        return
    }

    $node = $profileXml.CreateElement('FieldInformation')
    $properties = [ordered]@{
        CategoryName = $Category
        FieldName = $Name
        FieldValue = $Value
        FieldType = 'Text'
        FieldMin = '0'
        FieldMax = '0'
        FieldStep = '0'
    }
    foreach ($item in $properties.GetEnumerator()) {
        $element = $profileXml.CreateElement($item.Key)
        $element.InnerText = [string]$item.Value
        [void]$node.AppendChild($element)
    }
    [void]$profileXml.GameProfile.ConfigValues.AppendChild($node)
}

Set-TeknoParrotField 'TerminalMode' '0'
Set-TeknoParrotField 'TerminalEmulator' '1'
Set-TeknoParrotField 'Banapass Connection' '1'
Set-TeknoParrotField 'WhiteScreenFix' '1'
Set-TeknoParrotField 'Windowed' '0'
Set-TeknoParrotField 'NetworkAdapterIP' ([string]$config.AdapterIp)
Set-TeknoParrotField 'RouterIP' ([string]$config.RouterIp) 'Network'
Set-TeknoParrotField 'AccessCode' ([string]$identity.AccessCode) 'Banapass'
Set-TeknoParrotField 'Card ID' ([string]$identity.CardId.ToUpperInvariant()) 'Banapass'

$xmlSettings = [Xml.XmlWriterSettings]::new()
$xmlSettings.Encoding = [Text.UTF8Encoding]::new($false)
$xmlSettings.Indent = $true
$xmlWriter = [Xml.XmlWriter]::Create($profilePath, $xmlSettings)
try { $profileXml.Save($xmlWriter) } finally { $xmlWriter.Dispose() }

# Remove only the obsolete filenames generated by client setup v1.2/v1.3.
# Each file is copied into this run's timestamped backup before removal.
foreach ($obsoleteProfile in @(
    (Join-Path $gameProfilesRoot "$($baseProfile.BaseName)-Bayshore.xml"),
    (Join-Path (Join-Path $tpRoot 'UserProfiles') "$($baseProfile.BaseName)-Bayshore.xml")
)) {
    if (Test-Path -LiteralPath $obsoleteProfile -PathType Leaf) {
        Backup-File $obsoleteProfile
        Remove-Item -LiteralPath $obsoleteProfile -Force
    }
}

$identity.ProfileFile = $baseProfile.Name
[IO.File]::WriteAllText($identityPath, ($identity | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

# Install the coordinated launcher. It starts AMAuth directly, lets TeknoParrot
# launch/inject only wmn6r.exe, then applies a centered 16:9 borderless window
# with black bars when the monitor is not 16:9. It never changes display mode.
$safeLauncherBat = Join-Path $tpRoot 'WMMT6-Launch.bat'
$safeLauncherScript = Join-Path $tpRoot 'WMMT6-Launch.ps1'
$safeLauncherConfig = Join-Path $tpRoot 'WMMT6-Launch.json'
foreach ($target in $safeLauncherBat, $safeLauncherScript, $safeLauncherConfig) { Backup-File $target }
Copy-Item -LiteralPath (Join-Path $launcherSourceRoot 'WMMT6-Launch.bat') -Destination $safeLauncherBat -Force
Copy-Item -LiteralPath (Join-Path $launcherSourceRoot 'WMMT6-Launch.ps1') -Destination $safeLauncherScript -Force
$safeLauncherSettings = [ordered]@{
    GameExecutable = $gameExe
    AuthExecutable = (Join-Path $amcus 'AMAuthd.exe')
    MuchaExecutable = (Join-Path $amcus 'MuchaBin\muchacd.exe')
    ProfileFile = $baseProfile.Name
    AdapterIp = $config.AdapterIp
    ServerUri = "https://$($config.ServerIp):9002"
    OpenParrotPath = $installedOpenParrotPath
    OpenParrotSha256 = $installedOpenParrotHash
    AspectWidth = 16
    AspectHeight = 9
}
[IO.File]::WriteAllText($safeLauncherConfig, ($safeLauncherSettings | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

# Retire the old independent window/resolution helper. Borderless mode is now
# integrated into WMMT6-Launch.bat so only one launcher owns AMAuth and the game.
foreach ($obsoleteLauncher in 'WMMT6-Borderless.bat', 'WMMT6-Borderless.ps1', 'WMMT6-Borderless.json') {
    $obsoletePath = Join-Path $tpRoot $obsoleteLauncher
    if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) {
        Backup-File $obsoletePath
        Remove-Item -LiteralPath $obsoletePath -Force
    }
}

if ($maxiExe) {
    $maxiConfigPath = Join-Path (Split-Path $maxiExe -Parent) 'config.json'
    Backup-File $maxiConfigPath
    $maxiConfig = [ordered]@{
        adapter = $config.AdapterIp; online_mode = '1'; server_uri = "https://$($config.ServerIp):9002"
        software_revision = '10304'; event_mode = '0'; event_mode_count = '4'; event_double = '0'
        event_2on2 = '0'; event_serial = '0000000000'; freeplay = '0'; version = '100'
        feature_year = '2018'; feature_month = '12'; feature_pluses = '0'; feature_release_at = '0'
        packet_interval = '120'; adapter_ip = $config.AdapterIp; coin_chute = 1; buycard_cost = 8
        game_cost = 1; continue_cost = 1; fullcourse_cost = 4
    }
    [IO.File]::WriteAllText($maxiConfigPath, ($maxiConfig | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
Backup-File $hostsPath
$hosts = [IO.File]::ReadAllLines($hostsPath) |
    Where-Object { $_ -notmatch '(?i)\b(tenporouter\.loc|bbrouter\.loc|naominet\.jp)\b' -and $_ -notmatch '^# Bayshore portable client' }
$hosts += '# Bayshore portable client'
$hosts += "$($config.ServerIp) tenporouter.loc"
$hosts += "$($config.ServerIp) bbrouter.loc"
$hosts += "$($config.ServerIp) naominet.jp"
[IO.File]::WriteAllLines($hostsPath, $hosts, [Text.UTF8Encoding]::new($false))

$adapter = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $config.AdapterIp -ErrorAction Stop | Select-Object -First 1
$route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '225.0.0.1/32' -ErrorAction SilentlyContinue |
    Where-Object InterfaceIndex -eq $adapter.InterfaceIndex
if (-not $route) {
    try {
        # 0.0.0.0 declares an on-link IPv4 route. Omitting PolicyStore writes
        # both ActiveStore and PersistentStore; New-NetRoute rejects an
        # explicitly supplied PersistentStore on some supported Windows builds.
        New-NetRoute -DestinationPrefix '225.0.0.1/32' -InterfaceIndex $adapter.InterfaceIndex `
            -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "New-NetRoute could not create the multicast route; trying the Windows netsh fallback. $($_.Exception.Message)"
        $netsh = Join-Path $env:WINDIR 'System32\netsh.exe'
        & $netsh interface ipv4 add route prefix=225.0.0.1/32 interface=$($adapter.InterfaceIndex) `
            nexthop=0.0.0.0 metric=1 store=persistent | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "netsh could not create the multicast route; trying the legacy route.exe fallback (exit code $LASTEXITCODE)."
            $routeExe = Join-Path $env:WINDIR 'System32\route.exe'
            & $routeExe -p add 225.0.0.1 mask 255.255.255.255 $config.AdapterIp metric 1 if $adapter.InterfaceIndex | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Unable to create the persistent 225.0.0.1/32 multicast route (route.exe exit code $LASTEXITCODE)." }
        }
    }
}
$route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '225.0.0.1/32' -ErrorAction SilentlyContinue |
    Where-Object InterfaceIndex -eq $adapter.InterfaceIndex |
    Select-Object -First 1
if (-not $route) { throw 'The 225.0.0.1/32 multicast route was not present after configuration.' }

$firewallEntries = @(@{ Name = 'WMMT6 Cabinet'; Program = $gameExe })
if ($maxiExe) { $firewallEntries += @{ Name = 'WMMT6 MaxiTerminal'; Program = $maxiExe } }
foreach ($entry in $firewallEntries) {
    if (-not (Get-NetFirewallRule -DisplayName $entry.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $entry.Name -Direction Inbound -Action Allow -Program $entry.Program | Out-Null
    }
}

$regsvr32 = Join-Path $env:WINDIR 'System32\regsvr32.exe'
$regArguments = '/s "' + $iauthDll.Replace('"', '""') + '"'
$regProcess = Start-Process -FilePath $regsvr32 -ArgumentList $regArguments -WorkingDirectory $amcus `
    -WindowStyle Hidden -Wait -PassThru
if ($regProcess.ExitCode -ne 0) {
    $registeredIauthPath = $null
    $iauthClsidPath = 'Registry::HKEY_CLASSES_ROOT\CLSID\{045A5150-D2B3-4590-A38B-C1158678E1AC}\InProcServer32'
    try { $registeredIauthPath = [string](Get-Item -LiteralPath $iauthClsidPath -ErrorAction Stop).GetValue('') }
    catch { }
    $compatibleRegistration = $false
    if ($registeredIauthPath -and (Test-Path -LiteralPath $registeredIauthPath -PathType Leaf)) {
        $selectedIauthHash = (Get-FileHash -LiteralPath $iauthDll -Algorithm SHA256).Hash
        $registeredIauthHash = (Get-FileHash -LiteralPath $registeredIauthPath -Algorithm SHA256).Hash
        $compatibleRegistration = $selectedIauthHash -eq $registeredIauthHash
    }
    if ($compatibleRegistration) {
        Write-Warning "iauthdll.dll re-registration returned exit code $($regProcess.ExitCode), but an identical compatible DLL is already registered at $registeredIauthPath. Continuing."
    } else {
        throw "iauthdll.dll registration failed with exit code $($regProcess.ExitCode). Install the Microsoft Visual C++ 2010 SP1 x64 Redistributable and check Windows registry permissions."
    }
}

Write-Host ''
Write-Host 'WMMT6 client configuration completed successfully.' -ForegroundColor Green
Write-Host "Backups: $backupRoot"
Write-Host "Server: https://$($config.ServerIp):9002"
Write-Host "TeknoParrot profile (configured in place): $profilePath"
Write-Host "Aspect-preserving borderless launcher: $safeLauncherBat"
Write-Host 'White Screen Fix: enabled; Windowed mode: disabled'
Write-Host 'Borderless mode: centered 16:9 with black bars; display resolution is unchanged'
Write-Host "Client identity: $identityPath"
Write-Host "Cabinet number (AMAuth netID): $cabinetId"
Write-Host "Matched AMAuth serial: $driveSerial"
if (-not $maxiExe) { Write-Host 'MaxiTerminal: server-side venue service; nothing is installed on this client' }
