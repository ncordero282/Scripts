# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - Runs the OSDCloud GUI
# - After deployment, stages AutoPilot script into <OSDrive>:\OSDCloud\AutoPilot
# - Creates a "Run AutoPilot Enrollment" desktop shortcut in the deployed OS
#   (you will run it manually in Audit Mode)

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
# Optional: enable driver updates as well
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

# --------------------------------------------
# Detect the deployed Windows volume (do NOT assume C:)
# --------------------------------------------
Write-Host "Detecting deployed Windows volume..." -ForegroundColor Cyan

$osDriveLetter = $null

try {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'X' }

    foreach ($d in $drives) {
        $path = "$($d.Name):\Windows\System32\config\SYSTEM"
        if (Test-Path $path) {
            $osDriveLetter = $d.Name
            break
        }
    }
} catch {
    Write-Host "Error while scanning drives for OS volume: $_" -ForegroundColor Red
}

if (-not $osDriveLetter) {
    Write-Host "Could not find deployed Windows volume (no drive with \Windows\System32\config\SYSTEM)." -ForegroundColor Red
    Write-Host "AutoPilot staging will be skipped." -ForegroundColor Red
    Stop-Transcript
    return
}

$osRoot = "$osDriveLetter`:"

Write-Host "Deployed Windows detected on drive: $osDriveLetter`:" -ForegroundColor Green

# --------------------------------------------
# Stage AutoPilot script into the deployed OS
# --------------------------------------------
$AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
$TargetRoot         = Join-Path $osRoot "OSDCloud\AutoPilot"
$TargetScript       = Join-Path $TargetRoot "AutoPilotScript.ps1"

try {
    Write-Host "Staging AutoPilot script into deployed OS at $TargetScript" -ForegroundColor Cyan

    # Ensure target folder exists
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

    # Download latest AutoPilot script into <OSDrive>:\OSDCloud\AutoPilot
    Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $TargetScript -UseBasicParsing
    Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

    # --------------------------------------------
    # Create desktop shortcut in deployed OS
    # --------------------------------------------
    $PublicDesktop = Join-Path $osRoot "Users\Public\Desktop"
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

    # Drop README for techs
    $ReadmePath = Join-Path $TargetRoot "README.txt"
    @"
OSDCloud + AutoPilot Workflow

1. OSDCloud has deployed Windows and enabled Windows Update via SetupComplete.

2. On first boot, Windows may apply updates and reboot once.

3. When you see the first OOBE screen, press Ctrl+Shift+F3 to enter Audit Mode.

4. In Audit Mode (Administrator desktop), double-click:
   'Run AutoPilot Enrollment' on the desktop.

5. Follow all prompts in the AutoPilot script, including:
   - Microsoft admin sign-in
   - Authentication code steps
   - Any other manual entries you require.

6. When AutoPilot is finished, sysprep back to OOBE, for example:
   $osRoot\Windows\System32\Sysprep\Sysprep.exe /oobe /reboot /quiet

"@ | Set-Content -Path $ReadmePath -Encoding UTF8

    Write-Host "AutoPilot script and desktop shortcut staged successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to stage AutoPilot script or create shortcut: $_" -ForegroundColor Yellow
}

Write-Host "You can now reboot the system. After updates and first boot:" -ForegroundColor Yellow
Write-Host "  - At OOBE, press Ctrl+Shift+F3 to enter Audit Mode," -ForegroundColor Yellow
Write-Host "  - Then double-click 'Run AutoPilot Enrollment' on the desktop." -ForegroundColor Yellow

Write-Host "Rebooting via wpeutil reboot..." -ForegroundColor Cyan
wpeutil reboot

Stop-Transcript
