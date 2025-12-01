# =====================================================================
# Master OSDCloud WinPE script (with WS1 PPKG integration)
# - Enables Windows Update via SetupComplete in the new OS
# - Runs the OSDCloud GUI
# - After deployment:
#     * Stages AutoPilot script into <OSDrive>:\OSDCloud\AutoPilot
#     * Creates "Run AutoPilot Enrollment" desktop shortcut in the deployed OS
#     * Copies WS1 PPKG from the OSDCloud USB into <OSDrive>:\WS1\PPKG
#     * Creates SetupComplete.cmd + Apply-WS1PPKG.ps1 so Windows auto-applies PPKG
#     * Stages a WS1 RunOnce helper script in <OSDrive>:\OSDCloud\WS1
# =====================================================================

Start-Transcript -Path X:\Windows\Temp\OSDCloudGUI.log -Force

# -------------------------------
# CONFIG: Workspace ONE PPKG
# -------------------------------
# Name of the PPKG file on your OSDCloud USB under \WS1
$WS1PpkgFileName = 'WS1-Dropship.ppkg'   # <-- change if needed

# Volume label of your OSDCloud USB (used if Get-Volume exists; otherwise we just scan drives)
$WS1UsbLabel     = 'OSDCloud'

# Toggle if you ever want to disable the SetupComplete behavior
$EnableWS1PPKGSetupComplete = $true

# -------------------------------
# FUNCTIONS
# -------------------------------

function Get-UsbDriveWithPPKG {
    param(
        [Parameter(Mandatory = $true)][string]$PpkgFileName,
        [Parameter(Mandatory = $true)][string]$UsbLabel
    )

    # Try using Get-Volume if available (not always present in WinPE)
    $usbDriveLetter = $null

    if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
        try {
            $vol = Get-Volume -FileSystemLabel $UsbLabel -ErrorAction SilentlyContinue
            if ($vol) {
                $usbDriveLetter = $vol.DriveLetter
            }
        } catch {
            # ignore and fall back to PSDrive scan
        }
    }

    # Fallback: scan all filesystem drives except X: and look for \WS1\<PPKG>
    if (-not $usbDriveLetter) {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'X' }
        foreach ($d in $drives) {
            $candidate = "$($d.Name):\WS1\$PpkgFileName"
            if (Test-Path $candidate) {
                $usbDriveLetter = $d.Name
                break
            }
        }
    }

    return $usbDriveLetter
}

function Invoke-WS1PPKGSetupComplete {
    param(
        [Parameter(Mandatory = $true)][string]$OsRoot,       # e.g. "C:"
        [Parameter(Mandatory = $true)][string]$PpkgFileName,
        [Parameter(Mandatory = $true)][string]$UsbLabel
    )

    Write-Host "=== [WS1 PPKG] Configure SetupComplete start ===" -ForegroundColor Cyan

    # Normalize OS root (ensure it's like C:)
    $osDrive = $OsRoot.TrimEnd('\')

    # 1) Locate the USB drive
    Write-Host "Locating OSDCloud USB for PPKG..." -ForegroundColor Cyan
    $usbDriveLetter = Get-UsbDriveWithPPKG -PpkgFileName $PpkgFileName -UsbLabel $UsbLabel

    if (-not $usbDriveLetter) {
        Write-Host "ERROR: Could not find a USB drive containing \WS1\$PpkgFileName." -ForegroundColor Red
        return
    }

    $usbDrive   = "$usbDriveLetter`:"
    $ppkgSource = Join-Path $usbDrive "WS1\$PpkgFileName"

    if (-not (Test-Path $ppkgSource)) {
        Write-Host "ERROR: PPKG not found at $ppkgSource" -ForegroundColor Red
        return
    }

    Write-Host "Found PPKG on USB at $ppkgSource" -ForegroundColor Green

    # 2) Copy PPKG into target OS: <OSDrive>:\WS1\PPKG\<PPKG>
    $destFolder = Join-Path $osDrive 'WS1\PPKG'
    if (-not (Test-Path $destFolder)) {
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
    }

    $ppkgDest = Join-Path $destFolder $PpkgFileName
    Write-Host "Copying PPKG to $ppkgDest..." -ForegroundColor Cyan
    Copy-Item -Path $ppkgSource -Destination $ppkgDest -Force

    # Log path inside OS
    $logPath = Join-Path $destFolder 'PPKG_Install.log'

    # 3) Create Setup\Scripts folder in the deployed OS
    $setupScripts = Join-Path $osDrive 'Windows\Setup\Scripts'
    if (-not (Test-Path $setupScripts)) {
        New-Item -Path $setupScripts -ItemType Directory -Force | Out-Null
    }

    # 4) Create the PowerShell script that applies the PPKG when SetupComplete runs
    $psScriptPath = Join-Path $setupScripts 'Apply-WS1PPKG.ps1'
    $psContent = @"
\$ppkgPath = '$ppkgDest'
\$logPath  = '$logPath'

try {
    if (Test-Path \$ppkgPath) {
        Add-Content -Path \$logPath -Value ("`$(Get-Date) - Starting PPKG install from \$ppkgPath")
        Install-ProvisioningPackage -PackagePath \$ppkgPath -ForceInstall -QuietInstall -ErrorAction Stop
        Add-Content -Path \$logPath -Value ("`$(Get-Date) - PPKG install completed successfully.")
    } else {
        Add-Content -Path \$logPath -Value ("`$(Get-Date) - PPKG not found at \$ppkgPath")
    }
}
catch {
    Add-Content -Path \$logPath -Value ("`$(Get-Date) - ERROR: \$($_.Exception.Message)")
}
"@

    Set-Content -Path $psScriptPath -Value $psContent -Encoding UTF8
    Write-Host "Created Apply-WS1PPKG.ps1 at $psScriptPath" -ForegroundColor Green

    # 5) Create SetupComplete.cmd which Windows will run automatically at end of setup
    $setupCompletePath = Join-Path $setupScripts 'SetupComplete.cmd'
    $setupCompleteContent = @"
@echo off
REM Apply Workspace ONE PPKG after Windows setup completes
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SystemRoot%\Setup\Scripts\Apply-WS1PPKG.ps1"
"@

    Set-Content -Path $setupCompletePath -Value $setupCompleteContent -Encoding ASCII
    Write-Host "Created SetupComplete.cmd at $setupCompletePath" -ForegroundColor Green

    Write-Host "=== [WS1 PPKG] SetupComplete configuration done. PPKG will apply automatically. ===" -ForegroundColor Cyan
}

function Stage-WS1PPKGRunOnceHelper {
    param(
        [Parameter(Mandatory = $true)][string]$OsRoot,        # e.g. "C:"
        [Parameter(Mandatory = $true)][string]$PpkgFileName
    )

    $osDrive  = $OsRoot.TrimEnd('\')
    $ws1Folder = Join-Path $osDrive 'OSDCloud\WS1'

    if (-not (Test-Path $ws1Folder)) {
        New-Item -ItemType Directory -Path $ws1Folder -Force | Out-Null
    }

    $runOnceScriptPath = Join-Path $ws1Folder 'Register-WS1PPKG-RunOnce.ps1'

    # Use a single-quoted here-string so no variables are expanded at generation time.
    $runOnceContent = @'
param(
    [string]$PpkgFileName = 'PPKGNAME_PLACEHOLDER',
    [string]$UsbDriveLetter = 'D'    # change if your USB is not D:
)

Write-Host "=== [WS1 PPKG] RunOnce registration start ===" -ForegroundColor Cyan

$usbPath   = "$UsbDriveLetter:\WS1\$PpkgFileName"
$localRoot = 'C:\WS1\PPKG'
$localPath = Join-Path $localRoot $PpkgFileName

if (-not (Test-Path $usbPath)) {
    Write-Host "ERROR: PPKG not found on USB at $usbPath" -ForegroundColor Red
    return
}

if (-not (Test-Path $localRoot)) {
    New-Item -Path $localRoot -ItemType Directory -Force | Out-Null
}

Write-Host "Copying PPKG from $usbPath to $localPath..." -ForegroundColor Cyan
Copy-Item -Path $usbPath -Destination $localPath -Force

$runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -NoProfile -Command `"Install-ProvisioningPackage -PackagePath '$localPath' -ForceInstall -QuietInstall`""

Write-Host "Setting HKLM RunOnce entry to apply PPKG on next logon..." -ForegroundColor Cyan

$runOnceKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
New-Item -Path $runOnceKey -Force | Out-Null
Set-ItemProperty -Path $runOnceKey -Name "ApplyWS1PPKG" -Value $runOnceCommand

Write-Host "RunOnce registration complete. PPKG will install at the next logon." -ForegroundColor Green
Write-Host "=== [WS1 PPKG] RunOnce registration done ===" -ForegroundColor Cyan
'@

    # Replace placeholder with the actual PPKG file name from config
    $runOnceContent = $runOnceContent.Replace('PPKGNAME_PLACEHOLDER', $PpkgFileName)

    Set-Content -Path $runOnceScriptPath -Value $runOnceContent -Encoding UTF8

    $readmePath = Join-Path $ws1Folder 'README_WS1PPKG.txt'
    $readme = @"
Register-WS1PPKG-RunOnce.ps1

This helper script lets you apply the Workspace ONE PPKG via HKLM\RunOnce
after the OS is fully online.

Usage (run from an elevated PowerShell session in Windows, with the OSDCloud USB still inserted):

    cd "$ws1Folder"
    .\Register-WS1PPKG-RunOnce.ps1 -PpkgFileName '$PpkgFileName' -UsbDriveLetter 'D'

Adjust -UsbDriveLetter if your USB is not D:.
"@

    Set-Content -Path $readmePath -Value $readme -Encoding UTF8

    Write-Host "Staged WS1 RunOnce helper at $runOnceScriptPath" -ForegroundColor Green
}

# -------------------------------
# Ensure OSD module is loaded
# -------------------------------
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
    Write-Host "AutoPilot and WS1 PPKG staging will be skipped." -ForegroundColor Red
    Stop-Transcript
    return
}

$osRoot = "$osDriveLetter`:"

Write-Host "Deployed Windows detected on drive: $osRoot" -ForegroundColor Green

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

# --------------------------------------------
# Configure WS1 PPKG via SetupComplete + stage RunOnce helper
# --------------------------------------------
if ($EnableWS1PPKGSetupComplete) {
    Invoke-WS1PPKGSetupComplete -OsRoot $osRoot -PpkgFileName $WS1PpkgFileName -UsbLabel $WS1UsbLabel
} else {
    Write-Host "WS1 PPKG SetupComplete integration disabled by config." -ForegroundColor Yellow
}

# Always stage the RunOnce helper so you have an alternative method later
Stage-WS1PPKGRunOnceHelper -OsRoot $osRoot -PpkgFileName $WS1PpkgFileName

Write-Host "You can now reboot the system. After updates and first boot:" -ForegroundColor Yellow
Write-Host "  - At OOBE, press Ctrl+Shift+F3 to enter Audit Mode," -ForegroundColor Yellow
Write-Host "  - Then double-click 'Run AutoPilot Enrollment' on the desktop." -ForegroundColor Yellow
Write-Host "  - WS1 PPKG will be auto-applied via SetupComplete (and RunOnce helper is available inside OS)." -ForegroundColor Yellow

Write-Host "Rebooting via wpeutil reboot..." -ForegroundColor Cyan
wpeutil reboot

Stop-Transcript
