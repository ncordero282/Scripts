# OSDCloud GUI launcher with automatic Windows Update via SetupComplete

Start-Transcript -Path X:\Windows\Temp\OSDCloudGUI.log -Force

# Load OSD module
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import OSD module: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSD module imported successfully." -ForegroundColor Green

# ----------------------------------------------------------
# Enable OSDCloud SetupComplete Windows Update for this run
# ----------------------------------------------------------
if (-not $Global:OSDCloud) {
    $Global:OSDCloud = [ordered]@{}
}

# This tells OSDCloud to create SetupComplete scripts in the new OS
# that will run Start-WindowsUpdate on first boot (before OOBE).
$Global:OSDCloud.WindowsUpdate = $true

# Optional: also let Windows try to pull driver updates
# $Global:OSDCloud.WindowsUpdateDrivers = $true

Write-Host "OSDCloud WindowsUpdate flag set to: $($Global:OSDCloud.WindowsUpdate)" -ForegroundColor Cyan

# ----------------------------------------------------------
# Launch the built-in OSDCloud GUI
# ----------------------------------------------------------
Write-Host "Launching OSDCloud GUI..." -ForegroundColor Cyan

try {
    Start-OSDCloudGUI
} catch {
    Write-Host "Start-OSDCloudGUI failed: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSDCloud GUI has exited." -ForegroundColor Cyan
Write-Host "If deployment finished, reboot with 'wpeutil reboot' and boot from the internal drive." -ForegroundColor Yellow

Stop-Transcript
