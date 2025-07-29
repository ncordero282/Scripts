<#
.SYNOPSIS
    Master OSDCloud GUI starter script that:
    - Launches OSDCloud GUI
    - Submits AutoPilot hash via PowerShell script
    - Installs all Windows updates in Audit Mode
    - Reboots if required
#>

# ===============================
# Launch OSDCloud GUI
# ===============================
Write-Host "`n[OSDCloud] Launching GUI..." -ForegroundColor Cyan
Import-Module OSD -Force
Start-OSDCloudGUI

# ===============================
# Run AutoPilot Submission Script
# ===============================
Write-Host "`n[AutoPilot] Starting enrollment submission..." -ForegroundColor Cyan

$AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotSubmit.ps1"
$AutoPilotScriptPath = "$env:ProgramData\AutopilotSubmit.ps1"

try {
    Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $AutoPilotScriptPath -UseBasicParsing -ErrorAction Stop
    Write-Host "[AutoPilot] Script downloaded successfully." -ForegroundColor Green

    # Run the script as admin and wait for completion
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$AutoPilotScriptPath`"" -Verb RunAs -Wait
    Write-Host "[AutoPilot] Submission complete." -ForegroundColor Green
}
catch {
    Write-Host "[AutoPilot] ERROR: $_" -ForegroundColor Red
}

# ===============================
# Install Windows Updates
# ===============================
Write-Host "`n[Updates] Installing Windows and driver updates..." -ForegroundColor Cyan

try {
    Start-Service wuauserv

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Install-Module -Name PSWindowsUpdate -Force -AllowClobber
    }

    Import-Module PSWindowsUpdate

    Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -MicrosoftUpdate

    if (Get-WURebootStatus) {
        Write-Host "`n[Updates] Reboot required. Restarting now..." -ForegroundColor Yellow
        Restart-Computer -Force
    } else {
        Write-Host "[Updates] All updates installed. No reboot required." -ForegroundColor Green
    }
}
catch {
    Write-Host "[Updates] ERROR: $_" -ForegroundColor Red
}

# ===============================
# Final Instructions (Optional)
# ===============================
Write-Host "`n[Complete] AutoPilot and updates are done." -ForegroundColor Green
Write-Host "[Next Step] When you're ready, exit Audit Mode and continue enrollment using:" -ForegroundColor Yellow
Write-Host "`nC:\Windows\System32\Sysprep\Sysprep.exe /oobe /reboot /quiet" -ForegroundColor Yellow
