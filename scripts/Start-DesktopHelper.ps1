#requires -Version 5.1
# Launcher used by GlazeWM startup_commands. Detaches a hidden helper process.
$helper = Join-Path $PSScriptRoot 'GlazeDesktopHelper.ps1'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helper`""
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false
[void][System.Diagnostics.Process]::Start($psi)
