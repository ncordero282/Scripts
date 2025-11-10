# Master PowerShell Script to Launch OSDCloud GUI and Boot to AUDIT MODE
# Runs in WinPE (X:\). Creates SetupComplete.cmd on the target OS to invoke sysprep /audit /reboot.

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force
$ErrorActionPreference = 'Stop'

function Write-Stage($msg){ Write-Host "==> $msg" -ForegroundColor Cyan }

# Detect model (optional; you can extend the switch if you want to branch later)
$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
switch -Wildcard ($Model) {
    "*Latitude 7400*" { $DriverPack = "Dell Latitude 7400 Driver Pack" }
    "*Latitude 7410*" { $DriverPack = "Dell Latitude 7410 Driver Pack" }
    "*OptiPlex 7080*" { $DriverPack = "Dell OptiPlex 7080 Driver Pack" }
    default           { $DriverPack = "Generic or Unsupported Model" }
}
Write-Host "Model Detected: $Model"
Write-Host "Driver Pack (informational): $DriverPack"

# Launch OSDCloud GUI
Write-Stage "Launching OSDCloud GUI"
Start-OSDCloudGUI

Write-Host "OSDCloud deployment completed." -ForegroundColor Green

# After OSDCloud finishes, locate the newly applied Windows volume.
Write-Stage "Locating the newly deployed Windows installation"

# Heuristic: pick the drive that has \Windows\System32\Sysprep\Sysprep.exe
$targetWindows = $null
Get-Volume | Where-Object DriveLetter | ForEach-Object {
    $dl = $_.DriveLetter + ':'
    if (Test-Path "$dl\Windows\System32\Sysprep\Sysprep.exe") {
        $targetWindows = $dl
    }
}

if (-not $targetWindows) {
    # Fallback scan common letters if Get-Volume is limited in WinPE
    foreach ($dl in @('C:','D:','E:','F:','G:')) {
        if (Test-Path "$dl\Windows\System32\Sysprep\Sysprep.exe") {
            $targetWindows = $dl
            break
        }
    }
}

if (-not $targetWindows) {
    Write-Warning "Could not find target Windows volume. Audit Mode setup was not applied."
    Stop-Transcript
    return
}

Write-Host "Target Windows volume: $targetWindows" -ForegroundColor Yellow

# Create SetupComplete.cmd to switch the system into Audit Mode on first boot.
# SetupComplete runs after Setup completes and BEFORE OOBE starts.
Write-Stage "Creating SetupComplete.cmd to enter AUDIT MODE on first boot"

$setupScripts = Join-Path $targetWindows 'Windows\Setup\Scripts'
New-Item -ItemType Directory -Path $setupScripts -Force | Out-Null

$setupCompletePath = Join-Path $setupScripts 'SetupComplete.cmd'

$setupCompleteContent = @'
@echo off
REM ==========================================
REM SetupComplete.cmd - Force Audit Mode
REM ==========================================
echo [%DATE% %TIME%] SetupComplete: Invoking Sysprep /audit /reboot > "%WINDIR%\Temp\SetupComplete_Audit.log" 2>&1
if exist "%WINDIR%\System32\Sysprep\Sysprep.exe" (
    "%WINDIR%\System32\Sysprep\Sysprep.exe" /audit /reboot >> "%WINDIR%\Temp\SetupComplete_Audit.log" 2>&1
) else (
    echo Sysprep not found. >> "%WINDIR%\Temp\SetupComplete_Audit.log" 2>&1
    exit /b 1
)
exit /b 0
'@

Set-Content -Path $setupCompletePath -Value $setupCompleteContent -Encoding ASCII -Force

# Extra: ensure Scripts dir is allowed and file is present
if (Test-Path $setupCompletePath) {
    Write-Host "SetupComplete.cmd created at $setupCompletePath" -ForegroundColor Green
} else {
    Write-Warning "Failed to create SetupComplete.cmd — verify permissions and volume mapping."
}

Write-Host "`nAll requested actions completed. System will boot into AUDIT MODE after deployment." -ForegroundColor Green
Stop-Transcript
