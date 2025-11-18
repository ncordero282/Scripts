# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - After deployment, stages AutoPilot script into <OSDrive>:\OSDCloud\AutoPilot
# - Adds a Startup cmd that auto-runs AutoPilot ONLY in Audit Mode

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

# --------------------------------------------
# Detect the deployed Windows volume (NOT assuming C:)
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
    exit
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

    # Download the latest AutoPilot script into <OSDrive>:\OSDCloud\AutoPilot
    Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $TargetScript -UseBasicParsing
    Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

    # --------------------------------------------
    # Create wrapper CMD that only runs in Audit Mode
    # --------------------------------------------
    $WrapperCmd = Join-Path $TargetRoot "LaunchAutoPilot.cmd"

    @"
@echo off
REM Only run in Audit Mode (AuditInProgress = 1)
reg query "HKLM\System\Setup" /v AuditInProgress | find "0x1" >nul
if errorlevel 1 goto :EOF

powershell.exe -ExecutionPolicy Bypass -File "$TargetScript"
"@ | Set-Content -Path $WrapperCmd -Encoding ASCII

    Write-Host "Created LaunchAutoPilot.cmd wrapper at $WrapperCmd" -ForegroundColor Green

    # --------------------------------------------
    # Add wrapper to All Users Startup folder on the deployed OS
    # --------------------------------------------
    $StartupFolder = Join-Path $osRoot "ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    New-Item -ItemType Directory -Path $StartupFolder -Force | Out-Null

    $StartupCmd = Join-Path $StartupFolder "LaunchAutoPilot.cmd"
    Copy-Item $WrapperCmd -Destination $StartupCmd -Force

    Write-Host "LaunchAutoPilot.cmd copied to Startup: $StartupCmd" -ForegroundColor Green

    # Optional README for the tech
    $ReadmePath = Join-Path $TargetRoot "README.txt"
    @"
OSDCloud + AutoPilot Workflow

1. OSDCloud has deployed Windows and enabled Windows Update via SetupComplete.

2. On first boot, Windows may apply updates and reboot once.

3. When you see the first OOBE screen, press Ctrl+Shift+F3 to enter Audit Mode.

4. When Windows logs into Audit Mode (Administrator), the following will happen AUTOMATICALLY:
   - LaunchAutoPilot.cmd in the Startup folder will run.
   - It will check HKLM\System\Setup\AuditInProgress.
   - If AuditInProgress = 1, it will run:
       $TargetScript
     and show all normal Microsoft sign-in / auth prompts.

5. When AutoPilot finishes, you can sysprep back to OOBE, for example:
   $osRoot`Windows\System32\Sysprep\Sysprep.exe /oobe /reboot /quiet

6. On later user logons (after sysprep), AuditInProgress = 0,
   so LaunchAutoPilot.cmd exits immediately and does nothing.

"@ | Set-Content -Path $ReadmePath -Encoding UTF8

    Write-Host "AutoPilot staging and Startup configuration completed." -ForegroundColor Green
}
catch {
    Write-Host "Failed to stage AutoPilot script or configure Startup: $_" -ForegroundColor Yellow
}

Write-Host "You can now reboot the system. On first boot, press Ctrl+Shift+F3 into Audit Mode;" -ForegroundColor Yellow
Write-Host "when the Administrator desktop appears, AutoPilot will auto-launch." -ForegroundColor Yellow

Write-Host "Rebooting via wpeutil reboot..." -ForegroundColor Cyan
wpeutil reboot

Stop-Transcript
