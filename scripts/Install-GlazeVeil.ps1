#requires -Version 5.1
<#
.SYNOPSIS
  Sets up glaze-veil on this machine: local Attaquer pack, Zebar settings, and GlazeWM snippet paths.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

Write-Host "glaze-veil repo: $RepoRoot"

$glzrZebar = Join-Path $env:USERPROFILE '.glzr\zebar'
$glzrGlaze = Join-Path $env:USERPROFILE '.glzr\glazewm'
$localPack = Join-Path $glzrZebar 'attaquer'
$marketplace = Join-Path $env:APPDATA 'zebar\downloads\iattaquer.attaquer@1.0.1'

if (-not (Test-Path $glzrZebar)) {
  New-Item -ItemType Directory -Force -Path $glzrZebar | Out-Null
}
if (-not (Test-Path $glzrGlaze)) {
  New-Item -ItemType Directory -Force -Path $glzrGlaze | Out-Null
}

# 1) Local Attaquer pack
if (-not (Test-Path (Join-Path $localPack 'zpack.json'))) {
  if (-not (Test-Path $marketplace)) {
    Write-Warning "Marketplace pack not found at:`n  $marketplace`nInstall Attaquer from the Zebar marketplace first, then re-run this installer."
  }
  else {
    Write-Host "Copying Attaquer marketplace pack -> local pack 'attaquer'"
    Copy-Item $marketplace $localPack -Recurse -Force
  }
}
else {
  Write-Host "Local pack already present: $localPack"
}

if (Test-Path (Join-Path $localPack 'zpack.json')) {
  & (Join-Path $PSScriptRoot 'Apply-AttaquerDynamicIcons.ps1') -PackRoot $localPack
}

# 2) Zebar settings (attaquer on startup)
$settingsSrc = Join-Path $RepoRoot 'templates\zebar-settings.json'
$settingsDst = Join-Path $glzrZebar 'settings.json'
[System.IO.File]::WriteAllText($settingsDst, ((Get-Content $settingsSrc -Raw).Trim() + "`n"), $utf8)
Write-Host "Wrote $settingsDst (UTF-8 no BOM)"

# 3) Print GlazeWM wiring
$start = Join-Path $RepoRoot 'scripts\Start-DesktopHelper.ps1'
$stop = Join-Path $RepoRoot 'scripts\Stop-DesktopHelper.ps1'

Write-Host ""
Write-Host "==== Add/merge into %USERPROFILE%\.glzr\glazewm\config.yaml ===="
Write-Host @"
  startup_commands:
    - 'shell-exec zebar'
    - 'shell-exec powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $start'

  shutdown_commands:
    - 'shell-exec powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $stop'
    - 'shell-exec taskkill /IM zebar.exe /F'

  config_reload_commands:
    - 'shell-exec powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $start'

gaps:
  inner_gap: '10px'
  outer_gap:
    top: '36px'
    right: '10px'
    bottom: '10px'
    left: '10px'

# Under window_rules ignore match list, add:
# - window_title: { equals: 'GlzrWallpaperOverlay' }
"@
Write-Host "==== end snippet ===="
Write-Host ""
Write-Host "Save config.yaml as UTF-8 WITHOUT BOM, then Alt+Shift+R (or restart GlazeWM)."
Write-Host "Restart Zebar so the local attaquer pack loads."
Write-Host "Done."
