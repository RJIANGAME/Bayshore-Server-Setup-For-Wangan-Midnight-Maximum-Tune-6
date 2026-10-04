function Read-WmmtSettings([byte[]]$Bytes) {
    $inputStream = [IO.MemoryStream]::new($Bytes, $false)
    $gzip = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
    $outputStream = [IO.MemoryStream]::new()
    try {
        $gzip.CopyTo($outputStream)
        return [Text.Encoding]::UTF8.GetString($outputStream.ToArray())
    } finally {
        $gzip.Dispose()
        $inputStream.Dispose()
        $outputStream.Dispose()
    }
}

function Set-WmmtCabinetSettings([byte[]]$Bytes, [ValidateRange(1, 4)][int]$CabinetId) {
    $text = Read-WmmtSettings $Bytes
    $pattern = '(?m)^(\s*mPcbId\s*=\s*)\d+(\s*(?:--[^\r\n]*)?)$'
    if ([regex]::Matches($text, $pattern).Count -ne 1) {
        throw 'Game settings must contain exactly one mPcbId assignment. No settings were changed.'
    }
    # The game's Service menu displays 1-4; the saved PCB ID is zero-based (0-3).
    $pcbId = $CabinetId - 1
    $text = [regex]::Replace($text, $pattern, { param($match) $match.Groups[1].Value + $pcbId + $match.Groups[2].Value })
    $outputStream = [IO.MemoryStream]::new()
    $gzip = [IO.Compression.GZipStream]::new($outputStream, [IO.Compression.CompressionMode]::Compress, $true)
    try {
        $encoded = [Text.UTF8Encoding]::new($false).GetBytes($text)
        $gzip.Write($encoded, 0, $encoded.Length)
        $gzip.Dispose()
        return ,$outputStream.ToArray()
    } finally {
        $gzip.Dispose()
        $outputStream.Dispose()
    }
}

function Get-WmmtExitOutcome([int]$ExitCode, [bool]$EscapeRequested, [bool]$HasCrashReport) {
    # NTSTATUS failures (including access violations) remain errors, even near Esc.
    $nativeFailure = $ExitCode -lt 0 -and $ExitCode -ne -1
    if ($HasCrashReport -or $nativeFailure) { return 'Crash' }
    if ($EscapeRequested) { return 'UserExit' }
    if ($ExitCode -eq 0) { return 'NormalExit' }
    return 'UnexpectedExit'
}
