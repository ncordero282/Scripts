<#
.SYNOPSIS
    Starts the OSDCloud GUI and launches the AutoPilot submission script automatically in Audit Mode.
#>

# Launch OSDCloud GUI
Write-Host "`nLaunching OSDCloud GUI..." -ForegroundColor Cyan

Import-Module OSD -Force
Start-OSDCloudGUI

# ==========================================
# AutoPilot Submission Script Runner (Audit Mode)
# ==========================================
Write-Host "`nStarting AutoPilot registration process..." -ForegroundColor Cyan

# Define script source and destination
$AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotSubmit.ps1"
$AutoPilotScriptPath = "$env:ProgramData\AutopilotSubmit.ps1"

# Download and run AutoPilot script
try {
    Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $AutoPilotScriptPath -UseBasicParsing -ErrorAction Stop
    Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$AutoPilotScriptPath`"" -Verb RunAs
}
catch {
    Write-Host "Failed to download or run the AutoPilot script: $_" -ForegroundColor Red
}
