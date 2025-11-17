# Master PowerShell Script to Launch OSDCloud GUI with Optional AutoPilot (Manual Reboot with Reminder)

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force

# Get system model
$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

# Determine Dell driver pack name
switch -Wildcard ($Model) {
    "*Latitude 7400*" { $DriverPack = "Dell Latitude 7400 Driver Pack" }
    "*Latitude 7410*" { $DriverPack = "Dell Latitude 7410 Driver Pack" }
    "*OptiPlex 7080*" { $DriverPack = "Dell OptiPlex 7080 Driver Pack" }
    default { $DriverPack = "Generic or Unsupported Model" }
}

Write-Host "Model Detected: $Model"
Write-Host "Driver Pack: $DriverPack"

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

# Launch the default OSDCloud GUI
Start-OSDCloudGUI

# Wait until OSDCloud GUI finishes
Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# Run AutoPilot immediately if enabled
if ($AutoPilotEnabled) {
    Write-Host "Running AutoPilot enrollment script..." -ForegroundColor Cyan
    
    try {
        # Download & run AutoPilot script directly from your GitHub repo
        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        $LocalScript = "X:\Windows\Temp\AutoPilotScript.ps1"

        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $LocalScript -UseBasicParsing
        Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

        # Execute AutoPilot script immediately after OSDCloud finishes
        & powershell.exe -ExecutionPolicy Bypass -File $LocalScript

        Write-Host "AutoPilot script execution completed." -ForegroundColor Green

        # Popup reminder for reboot
        [System.Windows.Forms.MessageBox]::Show(
            "AutoPilot enrollment has finished. Please manually REBOOT the system to complete enrollment.",
            "OSDCloud - Reboot Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        Write-Host "Error running AutoPilot script: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while running AutoPilot. Check OSDCloud.log for details.",
            "AutoPilot Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

Stop-Transcript

