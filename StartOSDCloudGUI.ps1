<#
.SYNOPSIS
WinPE StartURL script for OSDCloud

.DESCRIPTION
- Safe OSD import (timeout to prevent hangs)
- Enables Windows Update via OSDCloud global flags
- Stages custom SetupComplete payload from USB to C:\OSDCloud\Scripts\SetupComplete
- Launches OSDCloud GUI
- OPTIONAL: stages AutoPilot script into deployed OS + creates desktop shortcut

.NOTES
Place this file in GitHub as:
WinPE-StartOSDCloudGUI.ps1

Use StartURL:
https://raw.githubusercontent.com/ncordero282/Scripts/main/WinPE-StartOSDCloudGUI.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# -------------------------
# Logging
# -------------------------
function WL {
    param(
        [Parameter(Mandatory=$true)][string]$Msg,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts][$Level] $Msg"
        Write-Host $line

        if (-not (Test-Path 'X:\Temp')) { New-Item -ItemType Directory -Path 'X:\Temp' -Force | Out-Null }
        Add-Content -Path 'X:\Temp\WinPE-StartOSDCloudGUI.log' -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

function Has-Command($name) {
    try { return [bool](Get-Command $name -ErrorAction SilentlyContinue) } catch { return $false }
}

WL "=== WinPE StartURL BEGIN ==="
WL "PSVersion: $($PSVersionTable.PSVersion)" "INFO"

# -------------------------
# Safe Import OSD (prevents hangs)
# -------------------------
WL "Importing OSD module (30s timeout)..." "INFO"

try {
    $job = Start-Job -ScriptBlock {
        $ProgressPreference='SilentlyContinue'
        Import-Module OSD -Force
        "IMPORTED"
    }

    $done = Wait-Job $job -Timeout 30
    if ($done) {
        $result = Receive-Job $job -ErrorAction SilentlyContinue
        WL "OSD import job completed: $result" "INFO"
    } else {
        WL "WARN: Import-Module OSD timed out after 30 seconds." "WARN"
    }

    Remove-Job $job -Force -ErrorAction SilentlyContinue
}
catch {
    WL "WARN: Import-Module OSD attempt failed: $($_.Exception.Message)" "WARN"
}

# -------------------------
# Your old behavior: enable Windows Update
# -------------------------
if (-not $Global:OSDCloud) { $Global:OSDCloud = [ordered]@{} }

$Global:OSDCloud.WindowsUpdate = $true
# Optional drivers via Windows Update:
# $Global:OSDCloud.WindowsUpdateDrivers = $true

WL "OSDCloud flag set: WindowsUpdate=$($Global:OSDCloud.WindowsUpdate)" "INFO"

# -------------------------
# KEY FIX: stage custom SetupComplete payload from USB -> local disk
# (E:\OSDCloud\Scripts\SetupComplete -> C:\OSDCloud\Scripts\SetupComplete)
# -------------------------
if (Has-Command "Set-SetupCompleteOSDCloudUSB") {
    WL "Running Set-SetupCompleteOSDCloudUSB to stage SetupComplete payload..." "INFO"
    try {
        Set-SetupCompleteOSDCloudUSB
        WL "Set-SetupCompleteOSDCloudUSB completed." "INFO"
    } catch {
        WL "WARN: Set-SetupCompleteOSDCloudUSB failed: $($_.Exception.Message)" "WARN"
    }
} else {
    WL "WARN: Set-SetupCompleteOSDCloudUSB command not found (OSD may not be loaded)." "WARN"
}

# -------------------------
# Launch OSDCloud GUI
# -------------------------
if (Has-Command "Start-OSDCloudGUI") {
    WL "Launching OSDCloud GUI..." "INFO"
    try {
        Start-OSDCloudGUI
        WL "Start-OSDCloudGUI returned (deployment likely completed or user exited)." "INFO"
    } catch {
        WL "ERROR: Start-OSDCloudGUI failed: $($_.Exception.Message)" "ERROR"
        WL "=== WinPE StartURL END ===" "ERROR"
        return
    }
} else {
    WL "ERROR: Start-OSDCloudGUI command not found." "ERROR"
    WL "=== WinPE StartURL END ===" "ERROR"
    return
}

# -------------------------
# OPTIONAL: post-deployment AutoPilot staging
# If you do NOT want this, set $EnableAutopilotStaging = $false
# -------------------------
$EnableAutopilotStaging = $true

if ($EnableAutopilotStaging) {

    WL "Detecting deployed Windows volume (not assuming C:)..." "INFO"
    $osDriveLetter = $null

    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'X' }

        foreach ($d in $drives) {
            $path = "$($d.Name):\Windows\System32\config\SYSTEM"
            if (Test-Path $path) { $osDriveLetter = $d.Name; break }
        }
    } catch {
        WL "WARN: Error while scanning drives for OS volume: $($_.Exception.Message)" "WARN"
    }

    if (-not $osDriveLetter) {
        WL "WARN: Could not find deployed Windows volume. Skipping AutoPilot staging." "WARN"
    }
    else {
        $osRoot = "$osDriveLetter`:"
        WL "Deployed Windows detected on drive: $osRoot" "INFO"

        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        $TargetRoot         = Join-Path $osRoot "OSDCloud\AutoPilot"
        $TargetScript       = Join-Path $TargetRoot "AutoPilotScript.ps1"

        try {
            WL "Staging AutoPilot script to: $TargetScript" "INFO"
            New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
            Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $TargetScript -UseBasicParsing
            WL "AutoPilot script downloaded successfully." "INFO"

            # Create Public Desktop shortcut
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

            WL "AutoPilot shortcut created on Public Desktop." "INFO"
        }
        catch {
            WL "WARN: Failed AutoPilot staging/shortcut: $($_.Exception.Message)" "WARN"
        }
    }
}

WL "Rebooting WinPE..." "INFO"
wpeutil reboot

WL "=== WinPE StartURL END ===" "INFO"
