# Master PowerShell Script to Launch OSDCloud GUI and run AutoPilot in AUDIT mode

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
    "Would you like to ENABLE AutoPilot after deployment (in Audit Mode)?",
    "OSDCloud - AutoPilot Option",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

$AutoPilotEnabled = $dialogResult -eq [System.Windows.Forms.DialogResult]::Yes
if ($AutoPilotEnabled) {
    Write-Host "AutoPilot ENABLED. Device will reboot to AUDIT and then run AutoPilot." -ForegroundColor Green
} else {
    Write-Host "AutoPilot DISABLED. No Audit switch or AutoPilot will run." -ForegroundColor Yellow
}

# Launch the default OSDCloud GUI (handles OS deployment)
Start-OSDCloudGUI

# Wait until OSDCloud GUI finishes
Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# Helper: find the newly deployed Windows volume from WinPE
function Get-OSVolume {
    $candidates = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root.TrimEnd('\') }
    foreach ($root in $candidates) {
        if (Test-Path "$root\Windows\System32\Sysprep\Sysprep.exe") { return $root }
    }
    return $null
}

$OSRoot = Get-OSVolume
if (-not $OSRoot) {
    Write-Host "ERROR: Could not locate the deployed Windows volume from WinPE." -ForegroundColor Red
    goto :EndScript
}

Write-Host "Detected OS volume: $OSRoot" -ForegroundColor Cyan

# If AutoPilot is enabled, stage for AUDIT mode and schedule AutoPilot to run at first Audit logon
if ($AutoPilotEnabled) {
    try {
        # Paths inside the deployed OS
        $SetupScriptsDir   = Join-Path $OSRoot "Windows\Setup\Scripts"
        $TempDir           = Join-Path $OSRoot "Windows\Temp"
        $AutoPilotScript   = Join-Path $TempDir "AutoPilotScript.ps1"
        $BootstrapScript   = Join-Path $TempDir "RunAutoPilot.ps1"
        $SetupCompleteCmd  = Join-Path $SetupScriptsDir "SetupComplete.cmd"

        # Ensure directories exist
        New-Item -Path $SetupScriptsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

        # Download your AutoPilot script into the deployed OS
        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $AutoPilotScript -UseBasicParsing
        Write-Host "AutoPilot script staged to $AutoPilotScript" -ForegroundColor Green

        # Create a small bootstrap that ensures execution policy and logs
        @"
# Bootstrap created by OSDCloud
Start-Transcript -Path C:\Windows\Temp\AutoPilot-Bootstrap.log -Force
try {
    # Optional: If your script needs TLS 1.2 for any web calls
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Run the downloaded AutoPilot script
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\Windows\Temp\AutoPilotScript.ps1"
}
catch {
    Write-Host "AutoPilot bootstrap error: $($_.Exception.Message)"
}
Stop-Transcript
"@ | Set-Content -Path $BootstrapScript -Encoding UTF8

        Write-Host "Bootstrap script created at $BootstrapScript" -ForegroundColor Green

        # SetupComplete: set RunOnce to run AutoPilot bootstrap, then switch to AUDIT and reboot
        @"
@echo off
rem Log to temp
echo %date% %time% - SetupComplete starting > C:\Windows\Temp\SetupComplete-Audit.log 2>&1

rem Ensure RunOnce launches the bootstrap at first Audit desktop sign-in
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v RunAutoPilot /t REG_SZ /d "powershell -ExecutionPolicy Bypass -NoProfile -File C:\Windows\Temp\RunAutoPilot.ps1" /f >> C:\Windows\Temp\SetupComplete-Audit.log 2>&1

rem Switch to AUDIT mode and reboot
"%WINDIR%\System32\Sysprep\Sysprep.exe" /audit /reboot >> C:\Windows\Temp\SetupComplete-Audit.log 2>&1
"@ | Set-Content -Path $SetupCompleteCmd -Encoding ASCII

        Write-Host "SetupComplete.cmd created at $SetupCompleteCmd" -ForegroundColor Green
        Write-Host "On first boot, Windows will enter AUDIT mode and AutoPilot will run automatically." -ForegroundColor Cyan

        # Optional heads-up to the tech
        [System.Windows.Forms.MessageBox]::Show(
            "OS deployment is complete. On first boot, the PC will RESTART into AUDIT mode and then AutoPilot will run automatically. No manual action needed.",
            "OSDCloud - Audit + AutoPilot",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        Write-Host "Error staging Audit/AutoPilot: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while staging Audit/AutoPilot. Check OSDCloud.log.",
            "AutoPilot Staging Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
} else {
    Write-Host "Skipping Audit/AutoPilot staging." -ForegroundColor Yellow
}

:EndScript
Stop-Transcript
