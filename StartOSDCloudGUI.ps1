# Master OSDCloud WinPE script:
# - Enables Windows Update via SetupComplete in the new OS
# - Optionally runs your AutoPilot enrollment script in WinPE after deployment
# - Cancels any pending auto-reboot from OSDCloud so AutoPilot can finish

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

Write-Host "OSDCloud deployment completed. Attempting to cancel any pending reboot..." -ForegroundColor Cyan

# Try to cancel any pending shutdown/reboot that OSDCloud scheduled
try {
    shutdown.exe /a | Out-Null
    Write-Host "Pending shutdown/reboot canceled (if any)." -ForegroundColor Green
} catch {
    Write-Host "No pending shutdown to cancel or shutdown /a failed: $_" -ForegroundColor Yellow
}

# --------------------------------------------
# Prepare logging for AutoPilot
# --------------------------------------------
$LogRoot = 'C:\OSDCloud\Logs'
$null = New-Item -ItemType Directory -Path $LogRoot -Force -ErrorAction SilentlyContinue
$AutoPilotLog = Join-Path $LogRoot 'AutoPilot_WinPE.log'

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

        # Run your script with full interactivity AND log its output to C:\OSDCloud\Logs
        Write-Host "Starting AutoPilot script (logging to $AutoPilotLog)..." -ForegroundColor Cyan

        & powershell.exe -ExecutionPolicy Bypass -File $LocalScript *>> $AutoPilotLog
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host "AutoPilot script exited with code $exitCode" -ForegroundColor Yellow
            [System.Windows.Forms.MessageBox]::Show(
                "AutoPilot script exited with code $exitCode. 
Error details are logged in:
$AutoPilotLog

You can review this log later from Windows.",
                "AutoPilot Warning",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        } else {
            Write-Host "AutoPilot script execution completed successfully." -ForegroundColor Green
            [System.Windows.Forms.MessageBox]::Show(
                "AutoPilot enrollment has finished successfully.
You can now reboot the system to continue to Windows.",
                "OSDCloud - AutoPilot Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    }
    catch {
        $msg = "Error running AutoPilot script: $_"
        Write-Host $msg -ForegroundColor Red

        # Log the error to C:\OSDCloud\Logs as well
        $msg | Out-File -FilePath $AutoPilotLog -Encoding UTF8 -Append

        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while running AutoPilot. 
Details have been logged to:
$AutoPilotLog

You can review this log later from Windows.",
            "AutoPilot Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# --------------------------------------------
# Final: let YOU control the reboot
# --------------------------------------------
[System.Windows.Forms.MessageBox]::Show(
    "OSDCloud deployment is complete.

If you ran AutoPilot, its output (and any errors) are in:
$AutoPilotLog

Click OK to reboot now and boot from the internal drive.",
    "OSDCloud - Ready to Reboot",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

Write-Host "Rebooting system via wpeutil reboot..." -ForegroundColor Cyan
wpeutil reboot

Stop-Transcript
