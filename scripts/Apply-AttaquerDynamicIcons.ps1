#requires -Version 5.1
<#
.SYNOPSIS
  Patches a local Attaquer Zebar pack so open apps load icons from dist/assets/icons/dynamic/.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$PackRoot
)

$ErrorActionPreference = 'Stop'

$jsPath = Join-Path $PackRoot 'dist\assets\index-BCOZ0Kx4.js'
if (-not (Test-Path $jsPath)) {
  # Try to find the hashed bundle
  $jsPath = Get-ChildItem (Join-Path $PackRoot 'dist\assets') -Filter 'index-*.js' |
    Where-Object { $_.Name -notlike '*optional*' } |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $jsPath -or -not (Test-Path $jsPath)) {
  throw "Could not find Attaquer bundle JS under $PackRoot\dist\assets"
}

$dynamicDir = Join-Path $PackRoot 'dist\assets\icons\dynamic'
New-Item -ItemType Directory -Force -Path $dynamicDir | Out-Null

$backup = "$jsPath.pre-dynamic-icons"
if (-not (Test-Path $backup)) {
  Copy-Item $jsPath $backup -Force
  Write-Host "Backup: $backup"
}

$js = [System.IO.File]::ReadAllText($jsPath)

# Prefer already-patched file
if ($js -match 'assets/icons/dynamic/') {
  Write-Host "Dynamic icon hook already present in $(Split-Path $jsPath -Leaf)"
}
else {
  $oldRender = 'D(i,()=>s[t.window.processName]??s.process)'
  if ($js -notlike "*$oldRender*") {
    throw "Expected icon render hook not found. This pack build may differ from attaquer@1.0.1 — patch manually (see DOCUMENTATION.md)."
  }

  $newRender = (
    'D(i,()=>{' +
    'const n=String(t.window.processName||"unknown");' +
    'const safe=n.replace(/[<>:"/\\\\|?*\x00-\x1F]/g,"_").replace(/\s+/g,"_");' +
    'const fb=s[n]??s.process;' +
    'const img=document.createElement("img");' +
    'img.className="app-icon";' +
    'img.alt=n;' +
    'img.onerror=()=>{' +
      'img.onerror=null;' +
      'const src=(fb&&(fb.src||(typeof fb.getAttribute==="function"&&fb.getAttribute("src"))))||"./assets/icons/icons8-application-32.png";' +
      'img.src=src;' +
    '};' +
    'img.src="./assets/icons/dynamic/"+safe+".png";' +
    'return img;' +
    '})'
  )

  $js = $js.Replace($oldRender, $newRender)
  Write-Host "Patched dynamic icon renderer"
}

# Point FocusWindow script at local pack if marketplace path is present
$oldFocus = '%userprofile%/AppData/Roaming/zebar/downloads/iattaquer.attaquer@1.0.1/dist/assets/scripts/FocusWindow.ahk'
$newFocus = '%userprofile%/.glzr/zebar/attaquer/dist/assets/scripts/FocusWindow.ahk'
if ($js.Contains($oldFocus)) {
  $js = $js.Replace($oldFocus, $newFocus)
  Write-Host "Updated FocusWindow.ahk path to local pack"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($jsPath, $js, $utf8)
Write-Host "Wrote $jsPath"
