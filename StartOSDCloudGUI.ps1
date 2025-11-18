# Minimal OSDCloud GUI launcher that forces all work to C:\OSDCloud

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force

# Load OSD module
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import OSD module: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

# Force OSDCloud to use C:\OSDCloud (NOT the USB) for all downloads / offline OS
$env:OSDCloudPath = 'C:\OSDCloud'
Write-Host "OSDCloud working path: $env:OSDCloudPath" -ForegroundColor Cyan

if (-not (Test-Path $env:OSDCloudPath)) {
    New-Item -ItemType Directory -Path $env:OSDCloudPath -Force | Out-Null
}

# Launch the built-in OSDCloud GUI
Write-Host "Launching OSDCloud GUI..." -ForegroundColor Cyan
try {
    Start-OSDCloudGUI
} catch {
    Write-Host "Start-OSDCloudGUI failed: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSDCloud GUI has exited." -ForegroundColor Cyan
Write-Host "If deployment finished, run 'wpeutil reboot' and boot from the internal drive." -ForegroundColor Yellow

Stop-Transcript
