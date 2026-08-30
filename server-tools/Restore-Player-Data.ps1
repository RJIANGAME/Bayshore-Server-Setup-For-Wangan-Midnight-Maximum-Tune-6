[CmdletBinding()]
param([string]$DumpPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DatabaseTools.Common.ps1')

$layout = Get-BayshoreLayout
$settings = Get-DatabaseSettings $layout.ServerRoot
if (-not $DumpPath) { $DumpPath = Select-DatabaseDump $layout 'Select the dump that will replace the current Bayshore save' }
$DumpPath = (Resolve-Path -LiteralPath $DumpPath).Path
Test-DatabaseDump $layout $DumpPath

Confirm-DestructiveAction 'RESTORE' `
    "This deletes the current player database and replaces it with '$DumpPath'. A safety backup will be created first."

Stop-BayshoreApplication $layout
Ensure-PostgresRunning $layout $settings
$safetyBackup = New-DatabaseBackup $layout $settings 'before-restore'
$pgRestore = Find-PostgresTool $layout.ServerRoot 'pg_restore'

Write-Host 'Restoring the selected database dump...'
Invoke-WithDatabasePassword $settings {
    & $pgRestore -h $settings.HostName -p $settings.Port -U $settings.User -d $settings.Database `
        --clean --if-exists --no-owner --no-privileges --single-transaction --exit-on-error $DumpPath
}
if ($LASTEXITCODE -ne 0) {
    throw "Restore failed. The original destination data is safe in '$safetyBackup'."
}

Write-Host 'Restore completed. Start Bayshore and test a known card.' -ForegroundColor Green
Write-Host "Rollback backup: $safetyBackup"
