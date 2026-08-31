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

$configPath = Join-Path $PSScriptRoot 'WMMT6-Borderless.json'
$teknoParrotExe = Join-Path $PSScriptRoot 'TeknoParrotUi.exe'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Missing $configPath. Run Configure-Client.bat again." }
if (-not (Test-Path -LiteralPath $teknoParrotExe -PathType Leaf)) { throw "Missing $teknoParrotExe." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$gameExe = [IO.Path]::GetFullPath([string]$config.GameExecutable)
$authExe = [IO.Path]::GetFullPath([string]$config.AuthExecutable)
$profileFile = [IO.Path]::GetFileName([string]$config.ProfileFile)
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw "Configured game executable is missing: $gameExe" }
if (-not (Test-Path -LiteralPath $authExe -PathType Leaf)) { throw "Configured AMAuth executable is missing: $authExe" }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "UserProfiles\$profileFile") -PathType Leaf)) {
    throw "Configured TeknoParrot profile is missing: $profileFile"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('WmmtBorderlessNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WmmtBorderlessNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr value);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
}
'@
}

function Get-ConfiguredGameProcess {
    foreach ($candidate in @(Get-Process -Name 'wmn6r' -ErrorAction SilentlyContinue)) {
        try {
            if ([IO.Path]::GetFullPath($candidate.Path) -ieq $gameExe) { return $candidate }
        }
        catch { }
    }
    return $null
}

function Get-ConfiguredAuthProcess {
    foreach ($candidate in @(Get-Process -Name 'AMAuthd' -ErrorAction SilentlyContinue)) {
        try {
            if ([IO.Path]::GetFullPath($candidate.Path) -ieq $authExe) { return $candidate }
        }
        catch { }
    }
    return $null
}

$game = Get-ConfiguredGameProcess
$startedAuth = $null
if (-not $game) {
    $auth = Get-ConfiguredAuthProcess
    if (-not $auth) {
        Write-Host 'Starting AMAuth outside TeknoParrot injection...'
        $startedAuth = Start-Process -FilePath $authExe -WorkingDirectory (Split-Path $authExe -Parent) -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 2
        if ($startedAuth.HasExited) { throw "AMAuth exited before WMMT6 started (exit code $($startedAuth.ExitCode))." }
    }
    Write-Host "Launching TeknoParrot single-executable profile $profileFile..."
    Start-Process -FilePath $teknoParrotExe -ArgumentList "--profile=$profileFile" -WorkingDirectory $PSScriptRoot
}

$processDeadline = (Get-Date).AddMinutes(2)
do {
    $game = Get-ConfiguredGameProcess
    if ($game) { break }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $processDeadline)
if (-not $game) { throw 'TeknoParrot did not start the configured wmn6r.exe within two minutes.' }

$windowDeadline = (Get-Date).AddMinutes(1)
do {
    $game.Refresh()
    if ($game.HasExited) { throw 'WMMT6 exited before creating its game window.' }
    $window = $game.MainWindowHandle
    if ($window -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $windowDeadline)
if ($window -eq [IntPtr]::Zero) { throw 'WMMT6 did not create a usable window within one minute.' }

$monitor = [WmmtBorderlessNative]::MonitorFromWindow($window, 2)
$monitorInfo = New-Object WmmtBorderlessNative+MONITORINFO
$monitorInfo.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type][WmmtBorderlessNative+MONITORINFO])
if (-not [WmmtBorderlessNative]::GetMonitorInfo($monitor, [ref]$monitorInfo)) { throw 'Could not read the WMMT6 monitor bounds.' }
$bounds = $monitorInfo.rcMonitor
$monitorWidth = $bounds.Right - $bounds.Left
$monitorHeight = $bounds.Bottom - $bounds.Top
$targetWidth = $monitorWidth
$targetHeight = [int][Math]::Round($monitorWidth / (16.0 / 9.0))
if ($targetHeight -gt $monitorHeight) {
    $targetHeight = $monitorHeight
    $targetWidth = [int][Math]::Round($monitorHeight * (16.0 / 9.0))
}
$targetLeft = $bounds.Left + [int](($monitorWidth - $targetWidth) / 2)
$targetTop = $bounds.Top + [int](($monitorHeight - $targetHeight) / 2)

$originalStyle = [WmmtBorderlessNative]::GetWindowLongPtr($window, -16)
$originalExStyle = [WmmtBorderlessNative]::GetWindowLongPtr($window, -20)
$originalRect = New-Object WmmtBorderlessNative+RECT
[void][WmmtBorderlessNative]::GetWindowRect($window, [ref]$originalRect)
$removeStyle = [long](0x00C00000L -bor 0x00040000L -bor 0x20000000L -bor 0x01000000L -bor 0x00080000L -bor 0x00020000L -bor 0x00010000L)
$removeExStyle = [long](0x00000001L -bor 0x00000200L -bor 0x00020000L)
function Set-WmmtBorderlessWindow([IntPtr]$Handle) {
    if ($Handle -eq [IntPtr]::Zero) { return }
    $liveStyle = [WmmtBorderlessNative]::GetWindowLongPtr($Handle, -16).ToInt64()
    $liveExStyle = [WmmtBorderlessNative]::GetWindowLongPtr($Handle, -20).ToInt64()
    $newStyle = $liveStyle -band (-bnot $removeStyle)
    $newExStyle = $liveExStyle -band (-bnot $removeExStyle)
    if ($newStyle -ne $liveStyle) {
        [void][WmmtBorderlessNative]::SetWindowLongPtr($Handle, -16, [IntPtr]$newStyle)
    }
    if ($newExStyle -ne $liveExStyle) {
        [void][WmmtBorderlessNative]::SetWindowLongPtr($Handle, -20, [IntPtr]$newExStyle)
    }
}

$backdrop = New-Object System.Windows.Forms.Form
$backdrop.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$backdrop.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$backdrop.ShowInTaskbar = $false
$backdrop.BackColor = [Drawing.Color]::Black
$backdrop.TopMost = $true
$backdrop.Bounds = New-Object Drawing.Rectangle($bounds.Left, $bounds.Top, $monitorWidth, $monitorHeight)

try {
    $backdrop.Show()
    Set-WmmtBorderlessWindow $window
    Write-Host "WMMT6 borderless mode active at ${targetWidth}x${targetHeight}. Close the game to exit."
    while (-not $game.HasExited) {
        $game.Refresh()
        if ($game.MainWindowHandle -ne [IntPtr]::Zero) { $window = $game.MainWindowHandle }
        Set-WmmtBorderlessWindow $window
        [void][WmmtBorderlessNative]::SetWindowPos(
            $window, [IntPtr](-1), $targetLeft, $targetTop, $targetWidth, $targetHeight, [uint32]0x0060
        )
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 250
    }
}
finally {
    if ($backdrop -and -not $backdrop.IsDisposed) { $backdrop.Close(); $backdrop.Dispose() }
    if ($game -and -not $game.HasExited -and $window -ne [IntPtr]::Zero) {
        [void][WmmtBorderlessNative]::SetWindowLongPtr($window, -16, $originalStyle)
        [void][WmmtBorderlessNative]::SetWindowLongPtr($window, -20, $originalExStyle)
        [void][WmmtBorderlessNative]::SetWindowPos(
            $window, [IntPtr](-2), $originalRect.Left, $originalRect.Top,
            ($originalRect.Right - $originalRect.Left), ($originalRect.Bottom - $originalRect.Top), [uint32]0x0060
        )
    }
    if ($startedAuth -and -not $startedAuth.HasExited) { Stop-Process -Id $startedAuth.Id -Force -ErrorAction SilentlyContinue }
}
