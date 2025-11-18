# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - After deployment, stages AutoPilot script into C:\OSDCloud\AutoPilot
# - Registers a RunOnce in the deployed OS so that when you go to Audit Mode,
#   the AutoPilot script auto-launches at first logon (Administrator)

Start-Transcript -Path X:\Windows\Temp\OSDCloudGUI.log -Force

# Ensure OSD module is loaded
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import OSD module: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

# -------------------------------
# Show basic hardware info (FYI)
# -------------------------------
try {
    $cs    = Get-CimInstance -ClassName Win32_ComputerSystem
    $Model = $cs.Model
    $Mfg   = $cs.Manufacturer
} catch {
    $Model = "Unknown"
    $Mfg   = "Unknown"
}

Write-Host "Manufacturer: $Mfg"
Write-Host "Model       : $Model"

# --------------------------------------------
# Enable Windows Update in the deployed image
# --------------------------------------------
if (-not $Global:OSDCloud) {
    $Global:OSDCloud = [ordered]@{}
}

$Global:OSDCloud.WindowsUpdate = $true
# Optional:
# $Global:OSDCloud.WindowsUpdateDrivers = $true

Write-Host "OSDCloud WindowsUpdate flag set to: $($Global:OSDCloud.WindowsUpdate)" -ForegroundColor Cyan

# --------------------------------------------
# Launch the OSDCloud GUI
# --------------------------------------------
Write-Host "Launching OSDCloud GUI..." -ForegroundColor Cyan

try {
    Start-OSDCloudGUI
} catch {
    Write-Host "Start-OSDCloudGUI failed: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# At this point, the new OS should be on C:

# --------------------------------------------
# Stage AutoPilot script into the deployed OS
# --------------------------------------------
$AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
$TargetRoot         = "C:\OSDCloud\AutoPilot"
$TargetScript       = Join-Path $TargetRoot "AutoPilotScript.ps1"

try {
    Write-Host "Staging AutoPilot script into deployed OS at $TargetScript" -ForegroundColor Cyan

    # Ensure target folder exists
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

    # Download the latest AutoPilot script into C:\OSDCloud\AutoPilot
    Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $TargetScript -UseBasicParsing
    Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

    # --------------------------------------------
    # Register RunOnce in the OFFLINE OS so Audit Mode auto-runs AutoPilot
    # --------------------------------------------
    Write-Host "Configuring RunOnce in offline OS to auto-launch AutoPilot in Audit Mode..." -ForegroundColor Cyan

    $OfflineSoftware = "C:\Windows\System32\config\SOFTWARE"
    $TempHiveName    = "OSDCloudOS"

    # Load the offline SOFTWARE hive from the deployed OS
    & reg.exe load HKLM\$TempHiveName $OfflineSoftware | Out-Null

    $runOnceKey = "HKLM\$TempHiveName\Microsoft\Windows\CurrentVersion\RunOnce"
    $runOnceName = "RunAutoPilot"
    $runOnceCmd  = "powershell.exe -ExecutionPolicy Bypass -File `"C:\OSDCloud\AutoPilot\AutoPilotScript.ps1`""

    # Create / update the RunOnce entry
    & reg.exe add $runOnceKey /v $runOnceName /t REG_SZ /d "$runOnceCmd" /f | Out-Null

    # Unload the hive
    & reg.exe unload HKLM\$TempHiveName | Out-Null

    Write-Host "RunOnce configured. AutoPilot will auto-start at first logon (e.g., Audit Mode)." -ForegroundColor Green

    # Optional: drop a README for the tech
    $ReadmePath = Join-Path $TargetRoot "README.txt"
    @"
OSDCloud + AutoPilot Workflow

1. OSDCloud has deployed Windows and enabled Windows Update via SetupComplete.

2. On first boot, Windows may apply updates and reboot once.

3. When you see the first OOBE screen, press Ctrl+Shift+F3 to enter Audit Mode.

4. When Windows logs into Audit Mode (Administrator), the following will happen AUTOMATICALLY:
   - 'AutoPilotScript.ps1' will run from:
     C:\OSDCloud\AutoPilot\AutoPilotScript.ps1

5. Follow all prompts in the AutoPilot script (including Microsoft sign-in and authentication code steps).

6. When AutoPilot is finished, you can sysprep back to OOBE, for example:
   C:\Windows\System32\Sysprep\Sysprep.exe /oobe /reboot /quiet

"@ | Set-Content -Path $ReadmePath -Encoding UTF8

    Write-Host "AutoPilot staging and RunOnce configuration completed." -ForegroundColor Green
}
catch {
    Write-Host "Failed to stage AutoPilot script or configure RunOnce: $_" -ForegroundColor Yellow
}

Write-Host "You can now reboot the system. On first boot, if you press Ctrl+Shift+F3 into Audit Mode," -ForegroundColor Yellow
Write-Host "the AutoPilot script will auto-launch for manual Microsoft authentication and enrollment." -ForegroundColor Yellow

Write-Host "Rebooting via wpeutil reboot..." -ForegroundColor Cyan
wpeutil reboot

Stop-Transcript
