$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'launcher\WMMT6-Client.Common.ps1')
function Assert-Equal($Expected, $Actual, [string]$Label) {
    if ($Expected -cne $Actual) { throw "$Label : expected '$Expected', received '$Actual'" }
}
$fixture = "-- Service settings`r`nmPcbId = 1`r`nmCalibHandleCenter = 12345`r`nmFreePlay = 1`r`n"
$fixtureStream = [IO.MemoryStream]::new()
$gzip = [IO.Compression.GZipStream]::new($fixtureStream, [IO.Compression.CompressionMode]::Compress, $true)
$bytes = [Text.Encoding]::UTF8.GetBytes($fixture)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Dispose()
$fixtureBytes = $fixtureStream.ToArray()
$fixtureStream.Dispose()
foreach ($cabinet in 1..4) {
    $updated = Set-WmmtCabinetSettings $fixtureBytes $cabinet
    $expected = $fixture.Replace('mPcbId = 1', "mPcbId = $($cabinet - 1)")
    Assert-Equal $expected (Read-WmmtSettings $updated) "Service cabinet $cabinet and preserved calibration"
    Assert-Equal $expected (Read-WmmtSettings (Set-WmmtCabinetSettings $updated $cabinet)) 'Rerun preserves settings'
}
foreach ($invalid in 0, 5) {
    $rejected = $false
    try { $null = Set-WmmtCabinetSettings $fixtureBytes $invalid } catch { $rejected = $true }
    Assert-Equal $true $rejected "Reject cabinet $invalid"
}
foreach ($case in @(
    @(0, $false, $false, 'NormalExit'),
    @(0, $true, $false, 'UserExit'),
    @(-1, $true, $false, 'UserExit'),
    @(1, $true, $false, 'UserExit'),
    @(1, $false, $false, 'UnexpectedExit'),
    @(-1, $false, $false, 'UnexpectedExit'),
    @(-1073741819, $true, $false, 'Crash'),
    @(0, $true, $true, 'Crash')
)) {
    Assert-Equal $case[3] (Get-WmmtExitOutcome $case[0] $case[1] $case[2]) "Exit classification $($case -join ', ')"
}
Write-Host 'Passed: cabinet 1-4 mapping, preserved service settings, reruns, invalid numbers, Esc exits and crash classification.'
