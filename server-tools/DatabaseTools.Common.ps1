Set-StrictMode -Version Latest

function Get-BayshoreLayout {
    $packageRoot = Split-Path $PSScriptRoot -Parent
    $serverRoot = if (Test-Path -LiteralPath (Join-Path $packageRoot 'server\.env')) {
        Join-Path $packageRoot 'server'
    }
    elseif (Test-Path -LiteralPath (Join-Path $packageRoot '.env')) {
        $packageRoot
    }
    else {
        throw "Bayshore .env was not found. Put the BAT files and server-tools folder in the Bayshore server root."
    }

    [pscustomobject]@{
        PackageRoot = $packageRoot
        ServerRoot  = $serverRoot
        BackupRoot  = Join-Path $packageRoot 'backups'
    }
}

function Get-DatabaseSettings([string]$ServerRoot) {
    $envPath = Join-Path $ServerRoot '.env'
    $envText = [IO.File]::ReadAllText($envPath)
    $match = [regex]::Match(
        $envText,
        '(?m)^POSTGRES_URL=postgresql://([^:]+):([^@]+)@([^:]+):(\d+)/([^\r\n]+)$'
    )
    if (-not $match.Success) { throw "POSTGRES_URL in '$envPath' is invalid." }

    [pscustomobject]@{
        User     = $match.Groups[1].Value
        Password = $match.Groups[2].Value
        HostName = $match.Groups[3].Value
        Port     = [int]$match.Groups[4].Value
        Database = $match.Groups[5].Value.Trim()
    }
}

function Find-PostgresTool([string]$ServerRoot, [string]$Name) {
    $runtime = Join-Path $ServerRoot '.runtime\postgresql'
    $tool = Get-ChildItem -LiteralPath $runtime -Filter "$Name.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $tool) { $tool = Get-Command $Name -ErrorAction SilentlyContinue }
    if (-not $tool) { throw "$Name.exe was not found under '$runtime' or in PATH." }
    if ($tool -is [IO.FileInfo]) { return $tool.FullName }
    return $tool.Source
}

function Invoke-WithDatabasePassword($Settings, [scriptblock]$Action) {
    $previousPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $Settings.Password
    try { & $Action }
    finally { $env:PGPASSWORD = $previousPassword }
}

function Ensure-PostgresRunning($Layout, $Settings) {
    Write-Host 'Checking portable PostgreSQL...'
    $psql = Find-PostgresTool $Layout.ServerRoot 'psql'
    $probeExitCode = Invoke-WithDatabasePassword $Settings {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $psql -X -q -h $Settings.HostName -p $Settings.Port -U $Settings.User `
                -d $Settings.Database -c 'SELECT 1' *> $null
            $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
    }
    if ([int]$probeExitCode -eq 0) {
        Write-Host 'PostgreSQL is ready.'
        return
    }

    $pgCtl = Find-PostgresTool $Layout.ServerRoot 'pg_ctl'
    $dataRoot = Join-Path $Layout.ServerRoot '.data\postgres'
    $versionPath = Join-Path $dataRoot 'PG_VERSION'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Portable PostgreSQL data was not found at '$dataRoot'. Complete Bayshore server setup first."
    }
    $logPath = Join-Path $Layout.ServerRoot '.data\postgres.log'
    $quotedData = '"' + $dataRoot.Replace('"', '\"') + '"'
    $quotedLog = '"' + $logPath.Replace('"', '\"') + '"'
    $postgresOptions = '"-p {0} -h {1}"' -f $Settings.Port, $Settings.HostName
    $arguments = "start -D $quotedData -l $quotedLog -w -o $postgresOptions"

    Write-Host 'PostgreSQL is stopped; starting it now...'
    $startProcess = Start-Process -FilePath $pgCtl -ArgumentList $arguments -PassThru -WindowStyle Hidden
    if (-not $startProcess.WaitForExit(30000)) {
        try { $startProcess.Kill() } catch { }
        throw "Portable PostgreSQL startup timed out. Check '$logPath'."
    }
    $startProcess.Refresh()
    if ($startProcess.ExitCode -ne 0) {
        throw "Portable PostgreSQL did not start (pg_ctl exit $($startProcess.ExitCode)). Check '$logPath'."
    }

    $verifyExitCode = Invoke-WithDatabasePassword $Settings {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $psql -X -q -h $Settings.HostName -p $Settings.Port -U $Settings.User `
                -d $Settings.Database -c 'SELECT 1' *> $null
            $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
    }
    if ([int]$verifyExitCode -ne 0) { throw 'PostgreSQL started, but the Bayshore database connection failed.' }
    Write-Host 'PostgreSQL is ready.'
}

function Stop-BayshoreApplication($Layout) {
    $stopScript = Join-Path $Layout.ServerRoot 'scripts\Stop.ps1'
    if (Test-Path -LiteralPath $stopScript) {
        & $stopScript
        if ($LASTEXITCODE -ne 0) { throw 'Bayshore did not stop cleanly.' }
    }
}

function New-DatabaseBackup($Layout, $Settings, [string]$Prefix = 'bayshore') {
    Ensure-PostgresRunning $Layout $Settings
    New-Item -ItemType Directory -Force -Path $Layout.BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $output = Join-Path $Layout.BackupRoot "$Prefix-$stamp.dump"
    $counter = 1
    while (Test-Path -LiteralPath $output) {
        $output = Join-Path $Layout.BackupRoot "$Prefix-$stamp-$counter.dump"
        $counter++
    }

    $pgDump = Find-PostgresTool $Layout.ServerRoot 'pg_dump'
    Write-Host "Creating player-data backup in '$($Layout.BackupRoot)'..."
    Invoke-WithDatabasePassword $Settings {
        & $pgDump -h $Settings.HostName -p $Settings.Port -U $Settings.User `
            -d $Settings.Database --format=custom --file=$output
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) {
        throw 'Database backup failed.'
    }
    Test-DatabaseDump $Layout $output
    Write-Host "Backup created: $output" -ForegroundColor Green
    return $output
}

function Select-DatabaseDump($Layout, [string]$Title) {
    New-Item -ItemType Directory -Force -Path $Layout.BackupRoot | Out-Null
    $selected = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $Title
        $dialog.InitialDirectory = $Layout.BackupRoot
        $dialog.Filter = 'Bayshore database dumps (*.dump)|*.dump|All files (*.*)|*.*'
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.FileName
        }
        $dialog.Dispose()
    }
    catch {
        Write-Warning 'The file picker could not be opened; enter the dump path manually.'
    }

    if (-not $selected) { $selected = Read-Host 'Full path of the .dump file' }
    $selected = $selected.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $selected -PathType Leaf)) {
        throw "Dump file not found: $selected"
    }
    return (Resolve-Path -LiteralPath $selected).Path
}

function Test-DatabaseDump($Layout, [string]$DumpPath) {
    $pgRestore = Find-PostgresTool $Layout.ServerRoot 'pg_restore'
    & $pgRestore --list $DumpPath *> $null
    if ($LASTEXITCODE -ne 0) { throw "'$DumpPath' is not a readable PostgreSQL custom dump." }
}

function Confirm-DestructiveAction([string]$Word, [string]$Message) {
    Write-Host ''
    Write-Warning $Message
    $answer = Read-Host "Type $Word to continue"
    if ($answer -cne $Word) { throw 'Operation cancelled; the confirmation text did not match.' }
}

function ConvertTo-SqlLiteral([string]$Value) {
    return $Value.Replace("'", "''")
}

function Invoke-PsqlScalar($Layout, $Settings, [string]$Database, [string]$Sql) {
    $psql = Find-PostgresTool $Layout.ServerRoot 'psql'
    $result = Invoke-WithDatabasePassword $Settings {
        $Sql | & $psql -X -q -A -t -v ON_ERROR_STOP=1 -h $Settings.HostName -p $Settings.Port `
            -U $Settings.User -d $Database
    }
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL query failed against database '$Database'." }
    return (($result | Out-String).Trim())
}
