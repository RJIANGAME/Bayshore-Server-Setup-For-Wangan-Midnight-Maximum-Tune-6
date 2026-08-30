[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
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
$borderlessSourceRoot = Join-Path $clientRoot 'borderless'

foreach ($required in $gameExe, $tpExe, (Join-Path $amcus 'AMAuthd.exe'), (Join-Path $amcus 'AMConfig.ini'), (Join-Path $amcus 'iauthdll.dll')) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required client file is missing: $required" }
}
foreach ($required in 'WMMT6-Borderless.bat', 'WMMT6-Borderless.ps1') {
    $requiredPath = Join-Path $borderlessSourceRoot $required
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required borderless launcher file is missing: $requiredPath" }
}

$expectedGameHashes = @('92F02199A44FA65A35AF3ED162B5CE5477CFC8B2E3A13CCC95936356680F1479')
$gameHash = (Get-FileHash -LiteralPath $gameExe -Algorithm SHA256).Hash
if ($gameHash -notin $expectedGameHashes) {
    throw "Unsupported wmn6r.exe SHA-256: $gameHash. This package supports WMMT6 1.03.04 only."
}

$requiredClientAssets = @(
    @{ Name = 'OpenParrot64.dll'; Hash = 'C91922AFAEEBFA9EF81BE2FA532DBCF0E6F4A2DF6EA3C91C5F84AD86D7790952'; Candidates = @((Join-Path $tpRoot 'OpenParrotx64\OpenParrot64.dll')) },
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

Install-VerifiedAsset 'OpenParrot64.dll' (Join-Path $tpRoot 'OpenParrotx64\OpenParrot64.dll') 'C91922AFAEEBFA9EF81BE2FA532DBCF0E6F4A2DF6EA3C91C5F84AD86D7790952'
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
        Where-Object { $_.BaseName -match '(?i)(WMMT.?6|Wangan.*Maximum.*Tune.*6)' -and $_.BaseName -notmatch '(?i)(6R|6RR)' } |
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
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $profilePath -Parent) | Out-Null
    Copy-Item -LiteralPath $baseProfile.FullName -Destination $profilePath
}
Backup-File $profilePath
[xml]$profile = Get-Content -LiteralPath $profilePath -Raw

function Set-XmlElement([string]$Name, [string]$Value, [bool]$CreateIfMissing = $false) {
    $node = $profile.SelectSingleNode("//*[local-name()='$Name']")
    if (-not $node -and $CreateIfMissing) {
        $node = $profile.CreateElement($Name, $profile.DocumentElement.NamespaceURI)
        $gamePathNode = $profile.SelectSingleNode("//*[local-name()='GamePath']")
        if ($gamePathNode -and $gamePathNode.ParentNode -eq $profile.DocumentElement) {
            [void]$profile.DocumentElement.InsertAfter($node, $gamePathNode)
        } else {
            [void]$profile.DocumentElement.AppendChild($node)
        }
    }
    if (-not $node) { throw "TeknoParrot profile lacks $Name." }
    $node.InnerText = $Value
}
function Get-ProfileField([string]$Name) {
    foreach ($field in $profile.SelectNodes("//*[local-name()='FieldInformation']")) {
        $nameNode = $field.SelectSingleNode("./*[local-name()='FieldName']")
        if ($nameNode -and $nameNode.InnerText -eq $Name) { return $field }
    }
    return $null
}
function Set-ProfileField([string]$Name, [string]$Value, [bool]$Required = $true) {
    $field = Get-ProfileField $Name
    if (-not $field) {
        if ($Required) { throw "TeknoParrot profile lacks field '$Name'." }
        return
    }
    $valueNode = $field.SelectSingleNode("./*[local-name()='FieldValue']")
    if (-not $valueNode) { throw "TeknoParrot field '$Name' lacks FieldValue." }
    $valueNode.InnerText = $Value
}

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
        $accessField = Get-ProfileField 'AccessCode'
        $cardField = Get-ProfileField 'Card ID'
        $profileAccess = if ($accessField) { [string]$accessField.SelectSingleNode("./*[local-name()='FieldValue']").InnerText } else { '' }
        $profileCard = if ($cardField) { [string]$cardField.SelectSingleNode("./*[local-name()='FieldValue']").InnerText } else { '' }
        if ($profileAccess -match '^\d{20}$' -and $profileCard -match '^[0-9A-Fa-f]{32}$') {
            $accessCode = $profileAccess
            $cardId = $profileCard.ToUpperInvariant()
        }
    }
    if (-not $accessCode -or -not $cardId) {
        $accessCode = New-RandomDigits 20
        $cardId = New-RandomHex 16
    }
    $configuredSerial = if ($config.PSObject.Properties.Name -contains 'DriveSerial') { [string]$config.DriveSerial } else { 'AUTO' }
    $driveSerial = if ($configuredSerial -eq 'AUTO') { New-RandomDigits 12 } else { $configuredSerial }
    $identity = [pscustomobject][ordered]@{
        AccessCode = $accessCode
        CardId = $cardId
        DriveSerial = $driveSerial
        ProfileFile = $baseProfile.Name
    }
    [IO.File]::WriteAllText($identityPath, ($identity | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

if ([string]$identity.AccessCode -notmatch '^\d{20}$') { throw "Invalid AccessCode in $identityPath" }
if ([string]$identity.CardId -notmatch '^[0-9A-Fa-f]{32}$') { throw "Invalid CardId in $identityPath" }
if ([string]$identity.DriveSerial -notmatch '^\d{12}$') { throw "Invalid DriveSerial in $identityPath" }

Backup-File $cardPath
[IO.File]::WriteAllText($cardPath, "[card]`r`naccessCode=$($identity.AccessCode)`r`nchipId=$($identity.CardId.ToUpperInvariant())`r`n", [Text.UTF8Encoding]::new($false))

$writablePath = Join-Path $amcus 'WritableConfig.ini'
Backup-File $writablePath
[IO.File]::WriteAllText($writablePath, "[RuntimeConfig]`r`nmode=`r`nnetID=1`r`nserialID=$($identity.DriveSerial)`r`n", [Text.UTF8Encoding]::new($false))

Set-XmlElement 'GamePath' $gameExe
Set-XmlElement 'GamePath2' (Join-Path $amcus 'AMAuthd.exe') $true
Set-XmlElement 'HasTwoExecutables' 'true' $true
Set-XmlElement 'LaunchSecondExecutableFirst' 'true' $true
Set-XmlElement 'ExecutableName2' 'amauthd.exe' $true
Set-ProfileField 'TerminalMode' '0'
Set-ProfileField 'TerminalEmulator' '1'
Set-ProfileField 'Banapass Connection' '1'
Set-ProfileField 'WhiteScreenFix' '1'
Set-ProfileField 'Windowed' '1'
Set-ProfileField 'NetworkAdapterIP' $config.AdapterIp
Set-ProfileField 'RouterIP' $config.RouterIp
Set-ProfileField 'AccessCode' ([string]$identity.AccessCode) $false
Set-ProfileField 'Card ID' ([string]$identity.CardId) $false
$customName = if ($config.PSObject.Properties.Name -contains 'CustomName' -and [string]$config.CustomName -ne 'AUTO') {
    [string]$config.CustomName
} else {
    'CAB' + ([string]$identity.AccessCode).Substring(16, 4)
}
Set-ProfileField 'CustomName' $customName $false
$profile.Save($profilePath)

$borderlessBat = Join-Path $tpRoot 'WMMT6-Borderless.bat'
$borderlessScript = Join-Path $tpRoot 'WMMT6-Borderless.ps1'
$borderlessConfig = Join-Path $tpRoot 'WMMT6-Borderless.json'
foreach ($target in $borderlessBat, $borderlessScript, $borderlessConfig) { Backup-File $target }
Copy-Item -LiteralPath (Join-Path $borderlessSourceRoot 'WMMT6-Borderless.bat') -Destination $borderlessBat -Force
Copy-Item -LiteralPath (Join-Path $borderlessSourceRoot 'WMMT6-Borderless.ps1') -Destination $borderlessScript -Force
$borderlessSettings = [ordered]@{
    GameExecutable = $gameExe
    ProfileFile = $baseProfile.Name
}
[IO.File]::WriteAllText($borderlessConfig, ($borderlessSettings | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

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
    New-NetRoute -DestinationPrefix '225.0.0.1/32' -InterfaceIndex $adapter.InterfaceIndex `
        -NextHop $config.AdapterIp -RouteMetric 1 -PolicyStore PersistentStore | Out-Null
}

$firewallEntries = @(@{ Name = 'WMMT6 Cabinet'; Program = $gameExe })
if ($maxiExe) { $firewallEntries += @{ Name = 'WMMT6 MaxiTerminal'; Program = $maxiExe } }
foreach ($entry in $firewallEntries) {
    if (-not (Get-NetFirewallRule -DisplayName $entry.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $entry.Name -Direction Inbound -Action Allow -Program $entry.Program | Out-Null
    }
}

& (Join-Path $env:WINDIR 'System32\regsvr32.exe') /s (Join-Path $amcus 'iauthdll.dll')
if ($LASTEXITCODE -ne 0) { throw 'iauthdll.dll registration failed.' }

Write-Host ''
Write-Host 'WMMT6 client configuration completed successfully.' -ForegroundColor Green
Write-Host "Backups: $backupRoot"
Write-Host "Server: https://$($config.ServerIp):9002"
Write-Host "TeknoParrot profile: $profilePath"
Write-Host "Borderless launcher: $borderlessBat"
Write-Host "Client identity: $identityPath"
if (-not $maxiExe) { Write-Host 'MaxiTerminal: skipped (venue service; not required for client setup)' }
