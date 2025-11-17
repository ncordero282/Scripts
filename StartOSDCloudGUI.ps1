# Master PowerShell Script to Launch OSDCloud GUI with Optional AutoPilot
# and enable SetupComplete Windows Update (no Audit Mode).

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force

# Ensure OSD module is loaded
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import OSD module: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

# Get system model
try {
    $Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
} catch {
    $Model = "Unknown Model"
}

# Determine Dell driver pack name (for information only)
switch -Wildcard ($Model) {
    "*Latitude 7400*" { $DriverPack = "Dell Latitude 7400 Driver Pack" }
    "*Latitude 7410*" { $DriverPack = "Dell Latitude 7410 Driver Pack" }
    "*OptiPlex 7080*" { $DriverPack = "Dell OptiPlex 7080 Driver Pack" }
    default           { $DriverPack = "Generic or Unsupported Model" }
}

Write-Host "Model Detected: $Model"
Write-Host "Driver Pack   : $DriverPack"

# Load WinForms for dialogs
Add-Type -AssemblyName System.Windows.Forms

# Ask admin about AutoPilot
$dialogResult = [System.Windows.Forms.MessageBox]::Show(
    "Would you like to ENABLE AutoPilot after deployment?",
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

# -------------------------------------------------------------------
# Enable OSDCloud SetupComplete Windows Update for this deployment
# -------------------------------------------------------------------
if (-not $Global:OSDCloud) {
    $Global:OSDCloud = [ordered]@{}
}

# Tell OSDCloud to create SetupComplete and run Start-WindowsUpdate
$Global:OSDCloud.WindowsUpdate = $true
# Optional: also try to pull driver updates
# $Global:OSDCloud.WindowsUpdateDrivers = $true

# Launch the default OSDCloud GUI
Write-Host "Launching OSDCloud GUI..." -ForegroundColor Cyan
try {
    Start-OSDCloudGUI
} catch {
    Write-Host "Start-OSDCloudGUI failed: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# Run AutoPilot immediately if enabled
if ($AutoPilotEnabled) {
    Write-Host "Running AutoPilot enrollment script..." -ForegroundColor Cyan

    try {
        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        $LocalScript        = "X:\Windows\Temp\AutoPilotScript.ps1"

        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $LocalScript -UseBasicParsing
        Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

        & powershell.exe -ExecutionPolicy Bypass -File $LocalScript

        Write-Host "AutoPilot script execution completed." -ForegroundColor Green

        [System.Windows.Forms.MessageBox]::Show(
            "AutoPilot enrollment has finished. Please manually REBOOT the system to complete enrollment.",
            "OSDCloud - Reboot Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-Host "Error running AutoPilot script: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while running AutoPilot. Check OSDCloud.log for details.",
            "AutoPilot Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

Stop-Transcript
