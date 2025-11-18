# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - After deployment, copies AutoPilot script into C:\OSDCloud\AutoPilot
# - Creates a desktop shortcut "Run AutoPilot Enrollment" for use in Audit Mode

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

    # Create a desktop shortcut to run AutoPilot in full Windows (Audit Mode)
    $PublicDesktop = "C:\Users\Public\Desktop"
    New-Item -ItemType Directory -Path $PublicDesktop -Force | Out-Null

    $ShortcutPath = Join-Path $PublicDesktop "Run AutoPilot Enrollment.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut     = $WScriptShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath       = "powershell.exe"
    $Shortcut.Arguments        = "-ExecutionPolicy Bypass -File `"$TargetScript`""
    $Shortcut.WorkingDirectory = $TargetRoot
    $Shortcut.WindowStyle      = 1
    $Shortcut.IconLocation     = "%SystemRoot%\System32\shell32.dll,1"
    $Shortcut.Save()

    # Drop a small README for the tech
    $ReadmePath = Join-Path $TargetRoot "README.txt"
    @"
OSDCloud + AutoPilot Workflow

1. After imaging, when Windows first boots and shows the OOBE screen,
   press Ctrl+Shift+F3 to enter Audit Mode.

2. In Audit Mode (Administrator desktop), double-click:
   'Run AutoPilot Enrollment' shortcut on the desktop.

3. Follow the prompts in the AutoPilot script (including Microsoft sign-in
   and authentication code steps).

4. When AutoPilot is finished, run Sysprep to return to OOBE, e.g.:
   Start -> Run:
   C:\Windows\System32\Sysprep\Sysprep.exe /oobe /reboot /quiet

"@ | Set-Content -Path $ReadmePath -Encoding UTF8

    Write-Host "AutoPilot script and desktop shortcut staged successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to stage AutoPilot script into deployed OS: $_" -ForegroundColor Yellow
}

Write-Host "You can now reboot the system. On first boot, press Ctrl+Shift+F3 to enter Audit Mode and run AutoPilot." -ForegroundColor Yellow
Write-Host "Rebooting via wpeutil reboot..." -ForegroundColor Cyan

wpeutil reboot

Stop-Transcript
