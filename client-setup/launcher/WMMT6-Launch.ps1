[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $quotedScript = '"' + $PSCommandPath.Replace('"', '""') + '"'
    $child = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -WorkingDirectory $PSScriptRoot `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScript)
    exit $child.ExitCode
}

$configPath = Join-Path $PSScriptRoot 'WMMT6-Launch.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing $configPath. Run Configure-Client.bat again."
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$gameExe = [IO.Path]::GetFullPath([string]$config.GameExecutable)
$authExe = [IO.Path]::GetFullPath([string]$config.AuthExecutable)
$muchaExe = [IO.Path]::GetFullPath([string]$config.MuchaExecutable)
$openParrot = [IO.Path]::GetFullPath([string]$config.OpenParrotPath)
$adapterIp = [string]$config.AdapterIp
$serverUri = [string]$config.ServerUri
$profileFile = [IO.Path]::GetFileName([string]$config.ProfileFile)
$teknoParrotExe = Join-Path $PSScriptRoot 'TeknoParrotUi.exe'
$profilePath = Join-Path $PSScriptRoot "UserProfiles\$profileFile"

foreach ($required in $gameExe, $authExe, $muchaExe, $openParrot, $teknoParrotExe, $profilePath) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required launch file is missing: $required" }
}
[xml]$profileXml = Get-Content -LiteralPath $profilePath -Raw
function Get-ProfileValue([string]$Name) {
    $field = @($profileXml.GameProfile.ConfigValues.FieldInformation) |
        Where-Object { [string]$_.FieldName -eq $Name } |
        Select-Object -First 1
    if (-not $field) { return $null }
    return [string]$field.FieldValue
}
$whiteScreenFix = Get-ProfileValue 'WhiteScreenFix'
$windowed = Get-ProfileValue 'Windowed'
if ($whiteScreenFix -ne '1') {
    throw "WhiteScreenFix must be 1 to prevent flashing (current value: '$whiteScreenFix'). Run Configure-Client.bat again."
}
if ($windowed -ne '0') {
    throw "Windowed must be 0 to avoid the unstable window hook (current value: '$windowed'). Run Configure-Client.bat again."
}
if ((Get-FileHash -LiteralPath $openParrot -Algorithm SHA256).Hash -ne [string]$config.OpenParrotSha256) {
    throw 'OpenParrot64.dll changed after client configuration. Run Configure-Client.bat again before launching.'
}
if (-not (Get-NetIPAddress -AddressFamily IPv4 -IPAddress $adapterIp -ErrorAction SilentlyContinue)) {
    throw "The configured client adapter address is not active: $adapterIp"
}

$logRoot = Join-Path $PSScriptRoot 'WMMT6-Launch-Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logPath = Join-Path $logRoot ("launch-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function Write-LaunchLog([string]$Message) {
    $line = "{0:yyyy-MM-dd HH:mm:ss.fff} {1}" -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

$mutex = [Threading.Mutex]::new($false, 'Local\Bayshore-WMMT6-Safe-Launcher')
if (-not $mutex.WaitOne(0)) { throw 'Another WMMT6 safe launcher is already running.' }

function Get-ProcessAtPath([string]$Name, [string]$ExpectedPath) {
    foreach ($candidate in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        try {
            if ([IO.Path]::GetFullPath($candidate.Path) -ieq $ExpectedPath) { return $candidate }
        }
        catch { }
    }
    return $null
}

function Stop-ProcessAtPath([string]$Name, [string]$ExpectedPath) {
    $candidate = Get-ProcessAtPath $Name $ExpectedPath
    if ($candidate) {
        Write-LaunchLog "Stopping stale $Name process $($candidate.Id)."
        Stop-Process -Id $candidate.Id -Force -ErrorAction Stop
        try { $candidate.WaitForExit(5000) } catch { }
    }
}

function Save-LatestWerReport([datetime]$StartedAt) {
    $werRoot = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
    if (-not (Test-Path -LiteralPath $werRoot -PathType Container)) { return }
    $latest = Get-ChildItem -LiteralPath $werRoot -Directory -Filter 'AppCrash_wmn6r.exe*' -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -ge $StartedAt.AddMinutes(-1) |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { return }
    $destination = Join-Path $logRoot ("WER-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $latest.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-LaunchLog "Copied the latest WER report to $destination"
}

$startedAuth = $null
$game = $null
$launchStarted = Get-Date
$exitCode = 0
try {
    Write-LaunchLog 'Safe launch started. WhiteScreenFix=1, Windowed=0; no external resolution/window helper is used.'
    Write-LaunchLog "Profile=$profileFile Adapter=$adapterIp Server=$serverUri"
    Write-LaunchLog "OpenParrot SHA256=$($config.OpenParrotSha256)"

    $existingGame = Get-ProcessAtPath 'wmn6r' $gameExe
    if ($existingGame) { throw "The configured wmn6r.exe is already running (PID $($existingGame.Id))." }

    Stop-ProcessAtPath 'AMAuthd' $authExe
    Stop-ProcessAtPath 'muchacd' $muchaExe

    Write-LaunchLog 'Checking Bayshore before starting the cabinet.'
    & curl.exe --insecure --silent --fail --max-time 5 "$serverUri/readyz" *> $null
    if ($LASTEXITCODE -ne 0) { throw "Bayshore is not ready at $serverUri. Start the server stack before the client." }

    $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '225.0.0.1/32' -ErrorAction SilentlyContinue |
        Where-Object {
            $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $_.InterfaceIndex -IPAddress $adapterIp -ErrorAction SilentlyContinue
            $null -ne $address
        } | Select-Object -First 1
    if (-not $route) { throw "The WMMT6 multicast route 225.0.0.1/32 is missing from adapter $adapterIp. Run Configure-Client.bat again as administrator." }

    Write-LaunchLog 'Starting AMAuth directly (OpenParrot is not injected into AMAuth).'
    $startedAuth = Start-Process -FilePath $authExe -WorkingDirectory (Split-Path $authExe -Parent) `
        -WindowStyle Minimized -PassThru
    Start-Sleep -Seconds 3
    $startedAuth.Refresh()
    if ($startedAuth.HasExited) { throw "AMAuth exited before the game started (exit code $($startedAuth.ExitCode))." }

    Write-LaunchLog 'Starting the existing single-executable TeknoParrot profile.'
    Start-Process -FilePath $teknoParrotExe -ArgumentList "--profile=$profileFile" -WorkingDirectory $PSScriptRoot | Out-Null

    $deadline = (Get-Date).AddMinutes(2)
    do {
        $game = Get-ProcessAtPath 'wmn6r' $gameExe
        if ($game) { break }
        $startedAuth.Refresh()
        if ($startedAuth.HasExited) { throw "AMAuth exited while waiting for WMMT6 (exit code $($startedAuth.ExitCode))." }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not $game) { throw 'TeknoParrot did not start the configured wmn6r.exe within two minutes.' }

    Write-LaunchLog "wmn6r.exe started as PID $($game.Id). Waiting for it to exit."
    while (-not $game.HasExited) {
        Start-Sleep -Seconds 1
        $game.Refresh()
    }
    try { $exitCode = $game.ExitCode } catch { $exitCode = -1 }
    $runtime = [Math]::Round(((Get-Date) - $launchStarted).TotalSeconds, 1)
    Write-LaunchLog "wmn6r.exe exited after $runtime seconds with code $exitCode."
    if ($exitCode -ne 0 -or $runtime -lt 30) {
        Save-LatestWerReport $launchStarted
        throw "WMMT6 terminated unexpectedly (exit code $exitCode, runtime ${runtime}s). See $logPath"
    }
}
catch {
    Write-LaunchLog "ERROR: $($_.Exception.Message)"
    Save-LatestWerReport $launchStarted
    $exitCode = 1
}
finally {
    if ($startedAuth -and -not $startedAuth.HasExited) {
        Write-LaunchLog "Stopping launcher-owned AMAuth process $($startedAuth.Id)."
        Stop-Process -Id $startedAuth.Id -Force -ErrorAction SilentlyContinue
    }
    Stop-ProcessAtPath 'muchacd' $muchaExe
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

exit $exitCode

