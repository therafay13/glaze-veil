#requires -Version 5.1
<#
.SYNOPSIS
  GlazeWM desktop helper: wallpaper overlay + app icon cache for Attaquer.

.DESCRIPTION
  - Shows a wallpaper overlay over the desktop (covering icons) on monitors
    that currently display at least one non-minimized GlazeWM window.
  - Hides the overlay when a monitor's displayed workspace has no visible apps,
    so the normal desktop + shortcuts return.
  - Extracts real .exe icons into the local Attaquer pack dynamic icons folder
    so the top bar can show any open app's icon.

  Started by GlazeWM startup_commands. Stopped by shutdown_commands / mutex exit.
#>
[CmdletBinding()]
param(
  [string]$GlazeCli = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe',
  [string]$IconCacheDir = '',
  [string]$OverlayTitle = 'GlzrWallpaperOverlay',
  [int]$PollMs = 750
)

$ErrorActionPreference = 'Continue'

# Single-instance
$mutexName = 'Global\GlazeVM_Zebar_DesktopHelper'
$script:mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:mutex.WaitOne(0)) {
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $IconCacheDir) {
  $IconCacheDir = Join-Path $env:USERPROFILE '.glzr\zebar\attaquer\dist\assets\icons\dynamic'
}
New-Item -ItemType Directory -Force -Path $IconCacheDir | Out-Null
$script:IconCacheDir = $IconCacheDir
$script:GlazeCli = $GlazeCli
$script:OverlayTitle = $OverlayTitle
$script:PollMs = $PollMs

$logDir = Join-Path $PSScriptRoot '..\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$script:LogFile = Join-Path $logDir 'desktop-helper.log'

$script:Overlays = @{}
$script:LastWallpaper = $null
$script:WallpaperImage = $null

function Write-Log([string]$Message) {
  $line = '{0:u} {1}' -f (Get-Date), $Message
  Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

if (-not ('GlzrNative' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class GlzrNative {
  public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_NOACTIVATE = 0x0010;
  public const uint SWP_SHOWWINDOW = 0x0040;

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
  public static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool DestroyIcon(IntPtr hIcon);
}
"@
}

function Get-CurrentWallpaperPath {
  $path = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
  if ($path -and (Test-Path -LiteralPath $path)) { return $path }
  return $null
}

function Get-SafeIconFileName([string]$ProcessName) {
  # Must stay in sync with Attaquer dynamic icon JS sanitizer.
  $safe = [regex]::Replace($ProcessName, '[<>:"/\\|?*\x00-\x1F]', '_')
  $safe = [regex]::Replace($safe, '\s+', '_')
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unknown' }
  return "$safe.png"
}

function Save-ProcessIcon([string]$ProcessName) {
  $outFile = Join-Path $script:IconCacheDir (Get-SafeIconFileName $ProcessName)
  if ((Test-Path -LiteralPath $outFile) -and ((Get-Item -LiteralPath $outFile).Length -gt 0)) {
    return
  }

  try {
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -or $_.Path } |
      Select-Object -First 1
    if (-not $proc) {
      $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $proc) { return }

    $exePath = $null
    try { $exePath = $proc.Path } catch { }
    if (-not $exePath) {
      try { $exePath = $proc.MainModule.FileName } catch { }
    }
    if (-not $exePath -or -not (Test-Path -LiteralPath $exePath)) { return }

    $hIcon = [GlzrNative]::ExtractIcon([IntPtr]::Zero, $exePath, 0)
    if ($hIcon -eq [IntPtr]::Zero -or $hIcon -eq [IntPtr]::new(-1)) { return }

    try {
      $tmp = [System.Drawing.Icon]::FromHandle($hIcon)
      $icon = [System.Drawing.Icon]$tmp.Clone()
      $bmp = $icon.ToBitmap()
      $bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
      $icon.Dispose()
      Write-Log "Cached icon for $ProcessName -> $outFile"
    }
    finally {
      [void][GlzrNative]::DestroyIcon($hIcon)
    }
  }
  catch {
    Write-Log "Icon extract failed for ${ProcessName}: $($_.Exception.Message)"
  }
}

function Query-GlazeJson([string]$Subcommand) {
  if (-not (Test-Path -LiteralPath $script:GlazeCli)) { return $null }
  try {
    $raw = & $script:GlazeCli query $Subcommand 2>$null
    if (-not $raw) { return $null }
    return ($raw | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

function Test-NodeHasVisibleWindow($Node) {
  if (-not $Node) { return $false }
  if ($Node.type -eq 'window') {
    $stateType = $null
    if ($Node.state -and $Node.state.type) { $stateType = [string]$Node.state.type }
    if ($stateType -eq 'minimized') { return $false }
    $display = [string]$Node.displayState
    if ([string]::IsNullOrEmpty($display) -or $display -eq 'shown') { return $true }
    return $false
  }
  if ($Node.children) {
    foreach ($child in $Node.children) {
      if (Test-NodeHasVisibleWindow $child) { return $true }
    }
  }
  return $false
}

function Get-WindowsFromNode($Node, [System.Collections.Generic.List[object]]$List) {
  if (-not $Node) { return }
  if ($Node.type -eq 'window') {
    $List.Add($Node) | Out-Null
    return
  }
  if ($Node.children) {
    foreach ($child in $Node.children) {
      Get-WindowsFromNode $child $List
    }
  }
}

function Ensure-WallpaperImage {
  $path = Get-CurrentWallpaperPath
  if (-not $path) { return $false }
  if ($path -eq $script:LastWallpaper -and $script:WallpaperImage) { return $true }
  try {
    if ($script:WallpaperImage) {
      $script:WallpaperImage.Dispose()
      $script:WallpaperImage = $null
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $script:WallpaperImage = [System.Drawing.Image]::FromStream($ms)
    $ms.Dispose()
    $script:LastWallpaper = $path
    Write-Log "Loaded wallpaper: $path"
    return $true
  }
  catch {
    Write-Log "Failed loading wallpaper: $($_.Exception.Message)"
    return $false
  }
}

function New-OverlayForScreen([System.Windows.Forms.Screen]$Screen) {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = $script:OverlayTitle
  $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $form.ShowInTaskbar = $false
  $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $form.Bounds = $Screen.Bounds
  $form.TopMost = $false
  $form.Enabled = $false
  $form.BackColor = [System.Drawing.Color]::Black
  $form.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Stretch
  if ($script:WallpaperImage) { $form.BackgroundImage = $script:WallpaperImage }

  [void]$form.Handle
  [void][GlzrNative]::SetWindowPos(
    $form.Handle,
    [GlzrNative]::HWND_BOTTOM,
    $Screen.Bounds.X, $Screen.Bounds.Y, $Screen.Bounds.Width, $Screen.Bounds.Height,
    ([GlzrNative]::SWP_NOACTIVATE -bor [GlzrNative]::SWP_SHOWWINDOW)
  )
  $form.Hide()
  return $form
}

function Sync-Overlays {
  [void](Ensure-WallpaperImage)

  $screens = [System.Windows.Forms.Screen]::AllScreens
  $activeKeys = @{}
  $monitorsNeedingOverlay = @{}

  $wsResp = Query-GlazeJson 'workspaces'
  if ($wsResp -and $wsResp.success -and $wsResp.data -and $wsResp.data.workspaces) {
    foreach ($ws in $wsResp.data.workspaces) {
      if (-not $ws.isDisplayed) { continue }
      if (-not (Test-NodeHasVisibleWindow $ws)) { continue }
      $cx = [int]($ws.x + ($ws.width / 2))
      $cy = [int]($ws.y + ($ws.height / 2))
      foreach ($screen in $screens) {
        if ($screen.Bounds.Contains($cx, $cy)) {
          $monitorsNeedingOverlay[$screen.DeviceName] = $true
          break
        }
      }
    }
  }

  foreach ($screen in $screens) {
    $key = $screen.DeviceName
    $activeKeys[$key] = $true
    if (-not $script:Overlays.ContainsKey($key)) {
      $script:Overlays[$key] = New-OverlayForScreen $screen
    }
    $form = $script:Overlays[$key]
    if ($form.Bounds -ne $screen.Bounds) {
      $form.Bounds = $screen.Bounds
    }
    if ($script:WallpaperImage -and $form.BackgroundImage -ne $script:WallpaperImage) {
      $form.BackgroundImage = $script:WallpaperImage
    }

    $shouldShow = $monitorsNeedingOverlay.ContainsKey($key)
    if ($shouldShow) {
      if (-not $form.Visible) {
        $form.Show()
      }
      [void][GlzrNative]::SetWindowPos(
        $form.Handle,
        [GlzrNative]::HWND_BOTTOM,
        $screen.Bounds.X, $screen.Bounds.Y, $screen.Bounds.Width, $screen.Bounds.Height,
        ([GlzrNative]::SWP_NOACTIVATE)
      )
    }
    else {
      if ($form.Visible) { $form.Hide() }
    }
  }

  foreach ($key in @($script:Overlays.Keys)) {
    if (-not $activeKeys.ContainsKey($key)) {
      try { $script:Overlays[$key].Close(); $script:Overlays[$key].Dispose() } catch { }
      $script:Overlays.Remove($key)
    }
  }

  if ($wsResp -and $wsResp.data -and $wsResp.data.workspaces) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($ws in $wsResp.data.workspaces) {
      Get-WindowsFromNode $ws $list
    }
    foreach ($w in $list) {
      $pn = [string]$w.processName
      if ([string]::IsNullOrWhiteSpace($pn)) { continue }
      if ($pn -in @('zebar', 'powershell', 'pwsh', 'GlazeWM')) { continue }
      Save-ProcessIcon -ProcessName $pn
    }
  }
}

function Stop-HelperCleanup {
  foreach ($key in @($script:Overlays.Keys)) {
    try { $script:Overlays[$key].Close(); $script:Overlays[$key].Dispose() } catch { }
  }
  $script:Overlays.Clear()
  if ($script:WallpaperImage) {
    try { $script:WallpaperImage.Dispose() } catch { }
    $script:WallpaperImage = $null
  }
  try { $script:mutex.ReleaseMutex() } catch { }
  try { $script:mutex.Dispose() } catch { }
}

Write-Log 'Desktop helper started'
$stopFile = Join-Path $PSScriptRoot 'STOP_DESKTOP_HELPER'
if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue }

try {
  while ($true) {
    if (Test-Path $stopFile) {
      Write-Log 'Stop file detected; exiting'
      break
    }
    try {
      Sync-Overlays
    }
    catch {
      Write-Log "Loop error: $($_.Exception.Message)"
    }
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds $script:PollMs
  }
}
finally {
  Stop-HelperCleanup
  Write-Log 'Desktop helper stopped'
}
