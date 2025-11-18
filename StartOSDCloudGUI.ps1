# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - Optionally runs your AutoPilot enrollment script in WinPE after deployment

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
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
    $Model = $cs.Model
    $Mfg   = $cs.Manufacturer
} catch {
    $Model = "Unknown"
    $Mfg   = "Unknown"
}

Write-Host "Manufacturer: $Mfg"
Write-Host "Model       : $Model"

# -------------------------------
# Prompt for AutoPilot enrollment
# -------------------------------
Add-Type -AssemblyName System.Windows.Forms

$dialogResult = [System.Windows.Forms.MessageBox]::Show(
    "Would you like to ENABLE AutoPilot enrollment after deployment?",
    "OSDCloud - AutoPilot Option",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    $AutoPilotEnabled = $true
    Write-Host "AutoPilot ENABLED. It will run after deployment." -ForegroundColor Green
} else {
    $AutoPilotEnabled = $false
    Write-Host "AutoPilot DISABLED. It will NOT run after deployment." -ForegroundColor Yellow
}

# --------------------------------------------
# Enable Windows Update in the deployed image
# --------------------------------------------
if (-not $Global:OSDCloud) {
    $Global:OSDCloud = [ordered]@{}
}

# Tell OSDCloud to add SetupComplete to run Start-WindowsUpdate
$Global:OSDCloud.WindowsUpdate = $true
# Optional: also let Windows try to pull driver updates
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
# Run AutoPilot script (in WinPE) if enabled
# --------------------------------------------
if ($AutoPilotEnabled) {
    Write-Host "Running AutoPilot enrollment script from GitHub..." -ForegroundColor Cyan

    try {
        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        $LocalScript        = "X:\Windows\Temp\AutoPilotScript.ps1"

        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $LocalScript -UseBasicParsing
        Write-Host "AutoPilot script downloaded successfully to $LocalScript" -ForegroundColor Green

        # Run your script with full interactivity for manual input
        & powershell.exe -ExecutionPolicy Bypass -File $LocalScript

        Write-Host "AutoPilot script execution completed." -ForegroundColor Green

        [System.Windows.Forms.MessageBox]::Show(
            "AutoPilot enrollment has finished. 
After you close this message, REBOOT the system to continue to OOBE.",
            "OSDCloud - AutoPilot Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-Host "Error running AutoPilot script: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while running AutoPilot. Check OSDCloudGUI.log for details.",
            "AutoPilot Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

Write-Host "If everything is done, reboot with:  wpeutil reboot" -ForegroundColor Yellow
Write-Host "Then boot from the internal drive into OOBE." -ForegroundColor Yellow

Stop-Transcript
