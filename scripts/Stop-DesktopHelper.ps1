#requires -Version 5.1
# Signal helper to exit cleanly, then force-kill stragglers if needed.
$stopFile = Join-Path $PSScriptRoot 'STOP_DESKTOP_HELPER'
Set-Content -Path $stopFile -Value (Get-Date).ToString('u') -Encoding UTF8
Start-Sleep -Milliseconds 900

Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*GlazeDesktopHelper.ps1*' } |
  ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
  }

if (Test-Path $stopFile) {
  Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
}
