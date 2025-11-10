<# ========================================================================
 NewStartOSDCloudGUI.ps1
 - Launches OSDCloud GUI to image the device
 - (Optional) Stages AutoPilot to run in AUDIT mode on first boot
 - Installs Windows Updates while in AUDIT mode
 - Returns to OOBE automatically by default

 Works in WinPE with OSD module available.
 Logging:
   WinPE transcript:          X:\Windows\Temp\OSDCloud.log
   SetupComplete audit log:   C:\Windows\Temp\SetupComplete-Audit.log
   Audit bootstrap transcript: C:\Windows\Temp\AutoPilot-Bootstrap.log
   Windows Update log:        C:\Windows\Temp\WindowsUpdate-Audit.log
======================================================================== #>

# ----- WinPE session logging -----
try { Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force } catch {}

# Speed up web calls
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----- Basic hardware info (informational only) -----
try {
    $Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
} catch {
    $Model = "Unknown Model"
}
Write-Host "Model Detected: $Model"

# ----- WinForms for simple prompts -----
Add-Type -AssemblyName System.Windows.Forms

# ====== SETTINGS YOU CAN TUNE ======
# Public RAW URL to your AutoPilot script. Recommend: AutopilotSubmit.ps1 (the *real* logic).
# Make sure this is PUBLICLY reachable (private repos will 404 from WinPE/Audit).
$AutoPilotScriptUrl = 'https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotSubmit.ps1'

# Whether to include driver updates during Audit-mode Windows Update.
$IncludeDriverUpdates = $false

# Whether to return to OOBE after AutoPilot + Windows Updates (recommended).
$ReturnToOOBE = $true
# ====================================


# Prompt: enable AutoPilot after deployment?
$dialogResult = [System.Windows.Forms.MessageBox]::Show(
    "Would you like to ENABLE AutoPilot after deployment (device will boot to AUDIT mode, run AutoPilot, install Windows Updates, then return to OOBE)?",
    "OSDCloud - AutoPilot Option",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

$AutoPilotEnabled = $dialogResult -eq [System.Windows.Forms.DialogResult]::Yes
if ($AutoPilotEnabled) {
    Write-Host "AutoPilot ENABLED. Device will reboot to AUDIT then run AutoPilot + Windows Updates." -ForegroundColor Green
} else {
    Write-Host "AutoPilot DISABLED. Skipping Audit/AutoPilot staging." -ForegroundColor Yellow
}

# ----- Launch OSDCloud GUI (imaging happens here) -----
try {
    Start-OSDCloudGUI
}
catch {
    Write-Host "ERROR: Failed to start or complete OSDCloud GUI: $($_.Exception.Message)" -ForegroundColor Red
    [System.Windows.Forms.MessageBox]::Show(
        "OSDCloud imaging failed or was cancelled. See X:\Windows\Temp\OSDCloud.log",
        "OSDCloud Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    Stop-Transcript | Out-Null
    return
}

Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# ----- Helper: locate new OS partition from WinPE -----
function Get-OSVolume {
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root.TrimEnd('\') }
        foreach ($root in $drives) {
            if (Test-Path "$root\Windows\System32\Sysprep\Sysprep.exe") { return $root }
        }
    } catch {}
    return $null
}

# ----- If AutoPilot is enabled, stage Audit mode + AutoPilot + WU -----
if ($AutoPilotEnabled) {
    $OSRoot = Get-OSVolume
    if (-not $OSRoot) {
        Write-Host "ERROR: Could not locate deployed Windows volume from WinPE." -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "Could not locate the new Windows partition. Audit/AutoPilot staging skipped.",
            "Staging Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        Stop-Transcript | Out-Null
        return
    }

    Write-Host "Detected OS volume: $OSRoot" -ForegroundColor Cyan

    # Paths inside the deployed OS
    $SetupScriptsDir  = Join-Path $OSRoot "Windows\Setup\Scripts"
    $TempDir          = Join-Path $OSRoot "Windows\Temp"
    $AutoPilotScript  = Join-Path $TempDir "AutopilotSubmit.ps1"  # where we'll place your AutoPilot logic
    $BootstrapScript  = Join-Path $TempDir "RunAutoPilot.ps1"     # runs in AUDIT mode
    $SetupCompleteCmd = Join-Path $SetupScriptsDir "SetupComplete.cmd"

    # Ensure directories exist
    New-Item -Path $SetupScriptsDir -ItemType Directory -Force | Out-Null
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

    # Small helper: test URL availability before we commit
    function Test-Url200 {
        param([Parameter(Mandatory)][string]$Url)
        try {
            $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 20
            return ($r.StatusCode -eq 200)
        } catch { return $false }
    }

    try {
        if (-not (Test-Url200 -Url $AutoPilotScriptUrl)) {
            throw "AutoPilot URL not accessible (404/private?) -> $AutoPilotScriptUrl"
        }

        # Download your AutoPilot script into the deployed OS
        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $AutoPilotScript -UseBasicParsing -ErrorAction Stop
        Write-Host "AutoPilot script staged to $AutoPilotScript" -ForegroundColor Green

        # ====== Write the AUDIT-mode bootstrap (RunAutoPilot.ps1) ======
@"
# ===== C:\Windows\Temp\RunAutoPilot.ps1 =====
# Runs after first boot into AUDIT mode
# 1) Executes your AutoPilot script
# 2) Installs Windows Updates (software; drivers optional)
# 3) Returns to OOBE (configurable)

\$LogPath = 'C:\Windows\Temp\AutoPilot-Bootstrap.log'
Start-Transcript -Path \$LogPath -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Settings you can tweak ----
\$AutoPilotScript   = 'C:\Windows\Temp\AutopilotSubmit.ps1'
\$IncludeDrivers    = $IncludeDriverUpdates
\$ReturnToOOBE      = $ReturnToOOBE
\$RebootWhenNeeded  = \$true
\$WULog             = 'C:\Windows\Temp\WindowsUpdate-Audit.log'
# --------------------------------

function Install-WindowsUpdates {
    param([bool]\$IncludeDrivers = \$false,[string]\$Log = 'C:\Windows\Temp\WindowsUpdate-Audit.log')
    "[$(Get-Date -Format s)] Starting Windows Update in Audit Mode" | Tee-Object -FilePath \$Log -Append | Out-Null
    try {
        \$session  = New-Object -ComObject Microsoft.Update.Session
        \$searcher = \$session.CreateUpdateSearcher()
        \$criteria = "IsInstalled=0 and IsHidden=0 and Type='Software'"
        if (\$IncludeDrivers) { \$criteria = "IsInstalled=0 and IsHidden=0 and (Type='Software' or Type='Driver')" }
        "Search criteria: \$criteria" | Tee-Object -FilePath \$Log -Append | Out-Null
        \$result = \$searcher.Search(\$criteria)
        if (-not \$result.Updates -or \$result.Updates.Count -eq 0) { "No updates found." | Tee-Object -FilePath \$Log -Append | Out-Null; return @{ Installed=0; RebootRequired=\$false } }
        \$updates = New-Object -ComObject Microsoft.Update.UpdateColl
        for (\$i=0; \$i -lt \$result.Updates.Count; \$i++) { \$u = \$result.Updates.Item(\$i); if (-not \$u.EulaAccepted) { \$u.AcceptEula() | Out-Null }; [void]\$updates.Add(\$u) }
        "Queued \$([int]\$updates.Count) update(s) for download..." | Tee-Object -FilePath \$Log -Append | Out-Null
        \$downloader = \$session.CreateUpdateDownloader(); \$downloader.Updates = \$updates; \$dl = \$downloader.Download()
        "Installing updates..." | Tee-Object -FilePath \$Log -Append | Out-Null
        \$installer = \$session.CreateUpdateInstaller(); \$installer.Updates = \$updates; \$inst = \$installer.Install()
        "Install result: \$([int]\$inst.ResultCode); RebootRequired: \$([bool]\$inst.RebootRequired)" | Tee-Object -FilePath \$Log -Append | Out-Null
        return @{ Installed=\$inst.Updates.Count; RebootRequired=[bool]\$inst.RebootRequired }
    } catch { "WU error: \$($_.Exception.Message)" | Tee-Object -FilePath \$Log -Append | Out-Null; return @{ Installed=0; RebootRequired=\$false; Error=\$_.Exception.Message } }
}

try {
    if (Test-Path \$AutoPilotScript) {
        Write-Host "Running AutoPilot: \$AutoPilotScript"
        & powershell.exe -ExecutionPolicy Bypass -NoProfile -File \$AutoPilotScript
        Write-Host "AutoPilot completed."
    } else {
        Write-Warning "AutoPilot script not found at \$AutoPilotScript"
    }

    \$wu = Install-WindowsUpdates -IncludeDrivers:\$IncludeDrivers -Log \$WULog
    Write-Host "WU summary: Installed=\$([int]\$wu.Installed) RebootRequired=\$([bool]\$wu.RebootRequired)"

    if (\$ReturnToOOBE) {
        Write-Host "Returning to OOBE..."
        & "\$env:WINDIR\System32\Sysprep\Sysprep.exe" /oobe /reboot /quit
    } elseif (\$RebootWhenNeeded -and \$wu.RebootRequired) {
        Write-Host "Rebooting to complete updates..."
        Restart-Computer -Force
    }
}
catch { Write-Error "Bootstrap error: \$($_.Exception.Message)" }
finally { Stop-Transcript }
# ===== end file =====
"@ | Set-Content -Path $BootstrapScript -Encoding UTF8

        Write-Host "Bootstrap script created at $BootstrapScript" -ForegroundColor Green

        # ====== SetupComplete: Set RunOnce then force AUDIT mode ======
@"
@echo off
echo %date% %time% - SetupComplete starting > C:\Windows\Temp\SetupComplete-Audit.log 2>&1

rem Run the bootstrap once at first Audit desktop sign-in
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v RunAutoPilot /t REG_SZ /d "powershell -ExecutionPolicy Bypass -NoProfile -File C:\Windows\Temp\RunAutoPilot.ps1" /f >> C:\Windows\Temp\SetupComplete-Audit.log 2>&1

rem Switch to AUDIT mode and reboot
"%WINDIR%\System32\Sysprep\Sysprep.exe" /audit /reboot >> C:\Windows\Temp\SetupComplete-Audit.log 2>&1
"@ | Set-Content -Path $SetupCompleteCmd -Encoding ASCII

        Write-Host "SetupComplete.cmd created at $SetupCompleteCmd" -ForegroundColor Green

        [System.Windows.Forms.MessageBox]::Show(
            "Imaging complete. On first boot, Windows will enter AUDIT mode, run AutoPilot, install updates, then return to OOBE.",
            "OSDCloud Staging Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Write-Host "Error staging Audit/AutoPilot: $($_.Exception.Message)" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while staging Audit/AutoPilot. Check X:\Windows\Temp\OSDCloud.log",
            "Staging Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}
else {
    Write-Host "Skipping Audit/AutoPilot staging; device will go to normal OOBE." -ForegroundColor Yellow
}

try { Stop-Transcript | Out-Null } catch {}
