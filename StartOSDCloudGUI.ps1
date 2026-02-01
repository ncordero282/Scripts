<#
.SYNOPSIS
    WinPE Boot Script for OSDCloud
.DESCRIPTION
    1. Robustly imports OSD module (timeout protection)
    2. Stages USB payload to C:\OSDCloud\Scripts\SetupComplete
    3. Enables Windows Updates
    4. Launches GUI
#>

$LogFile = "X:\Windows\Temp\WinPE-StartOSDCloudGUI.log"
Start-Transcript -Path $LogFile

Write-Host ">>> Initializing OSDCloud Environment..." -ForegroundColor Cyan

# 1. Robust OSD Import with Timeout
Write-Host "Importing OSD Module..."
$Job = Start-Job -ScriptBlock { Import-Module OSD -Force -PassThru }
if (Wait-Job $Job -Timeout 30) {
    Receive-Job $Job | Out-Null
    Write-Host "OSD Module Imported Successfully." -ForegroundColor Green
} else {
    Write-Warning "OSD Module import timed out or failed. Attempting standard import..."
    Stop-Job $Job
    Import-Module OSD -ErrorAction SilentlyContinue
}

# 2. Stage USB Payload
# This OSD function copies \OSDCloud\Scripts\SetupComplete from USB -> Local Disk
# It looks for USBs with OSDCloud structure automatically.
Write-Host "Staging SetupComplete payload from USB..."
try {
    Set-SetupCompleteOSDCloudUSB -Verbose
} catch {
    Write-Warning "Failed to run Set-SetupCompleteOSDCloudUSB. Payload might not be staged."
}

# 3. Configure Global Settings
$Global:OSDCloud = @{
    WindowsUpdate = $true
}

# 4. Launch GUI
Write-Host "Launching OSDCloud GUI..."
Start-OSDCloudGUI

Stop-Transcript
