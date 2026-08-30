[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DatabaseTools.Common.ps1')

$layout = Get-BayshoreLayout
$settings = Get-DatabaseSettings $layout.ServerRoot
New-DatabaseBackup $layout $settings | Out-Null
Write-Host "Backups are stored in: $($layout.BackupRoot)"
