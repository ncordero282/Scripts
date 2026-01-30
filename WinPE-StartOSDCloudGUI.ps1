# WinPE-StartOSDCloudGUI.ps1
# Runs in WinPE before the GUI starts

try {
    Import-Module OSD -Force
} catch {}

# Stage your custom SetupComplete payload from the USB (OSDCloudUSB NTFS partition)
# so Windows Setup can run wallpaper/debloat/audit actions later
try {
    Set-SetupCompleteOSDCloudUSB
} catch {
    # If you want, add simple visibility in WinPE:
    Write-Host "WARN: Set-SetupCompleteOSDCloudUSB failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Launch the GUI
Start-OSDCloudGUI
