#requires -Version 5.1
# Restores GlazeWM/Zebar configs from a dated backup under <repo>\backups\
param(
  [string]$BackupDir = (
    Get-ChildItem (Join-Path $PSScriptRoot '..\backups') -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
      Sort-Object Name -Descending |
      Select-Object -First 1 -ExpandProperty FullName
  )
)

$ErrorActionPreference = 'Stop'
if (-not $BackupDir -or -not (Test-Path $BackupDir)) {
  throw "Backup folder not found. Pass -BackupDir explicitly."
}

Write-Host "Restoring from $BackupDir"
& (Join-Path $PSScriptRoot 'Stop-DesktopHelper.ps1')

$utf8 = New-Object System.Text.UTF8Encoding $false
$cfg = Get-Content (Join-Path $BackupDir 'glazewm\config.yaml') -Raw
if ($cfg.Length -gt 0 -and [int][char]$cfg[0] -eq 0xFEFF) { $cfg = $cfg.Substring(1) }
[System.IO.File]::WriteAllText("$env:USERPROFILE\.glzr\glazewm\config.yaml", $cfg.TrimStart(), $utf8)

$settings = Get-Content (Join-Path $BackupDir 'zebar\settings.json') -Raw
if ($settings.Length -gt 0 -and [int][char]$settings[0] -eq 0xFEFF) { $settings = $settings.Substring(1) }
[System.IO.File]::WriteAllText("$env:USERPROFILE\.glzr\zebar\settings.json", $settings.TrimStart(), $utf8)

Write-Host 'Restored config.yaml and settings.json (UTF-8 no BOM).'
Write-Host 'Reload GlazeWM with Alt+Shift+R, then restart Zebar from the tray / GlazeWM.'
Write-Host 'Optional: remove local pack folder to fully revert Attaquer patches:'
Write-Host "  Remove-Item `"$env:USERPROFILE\.glzr\zebar\attaquer`" -Recurse -Force"
