<#
.SYNOPSIS
WinPE Startup script for OSDCloud USB

.DESCRIPTION
- Runs in WinPE via Edit-OSDCloudWinPE -StartURL
- Stages custom SetupComplete payload from the OSDCloudUSB (NTFS) partition to the local OS drive
  using Set-SetupCompleteOSDCloudUSB
- Launches the OSDCloud GUI

.NOTES
Raw URL:
https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/WinPE-StartOSDCloudGUI.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Message"

    # WinPE console
    switch ($Level) {
        'INFO'  { Write-Host $line -ForegroundColor Cyan }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
    }

    # Best-effort log file in WinPE (X:\Temp usually exists)
    try {
        $logDir = 'X:\Temp'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path (Join-Path $logDir 'WinPE-StartOSDCloudGUI.log') -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

Write-Log "=== WinPE Start Script BEGIN ===" "INFO"

# Import OSD module
try {
    Import-Module OSD -Force -ErrorAction Stop
    Write-Log "Imported OSD module" "INFO"
} catch {
    Write-Log "Failed to import OSD module: $($_.Exception.Message)" "ERROR"
}

# Stage custom SetupComplete payload from USB -> local disk
# This is the KEY FIX: it copies \OSDCloud\Scripts\SetupComplete from the USB to C:\OSDCloud\Scripts\SetupComplete
try {
    Write-Log "Running Set-SetupCompleteOSDCloudUSB to stage SetupComplete payload..." "INFO"
    Set-SetupCompleteOSDCloudUSB
    Write-Log "Set-SetupCompleteOSDCloudUSB completed" "INFO"
} catch {
    Write-Log "Set-SetupCompleteOSDCloudUSB failed: $($_.Exception.Message)" "WARN"
}

# Launch OSDCloud GUI
try {
    Write-Log "Launching OSDCloud GUI (Start-OSDCloudGUI)..." "INFO"
    Start-OSDCloudGUI
} catch {
    Write-Log "Failed to launch OSDCloud GUI: $($_.Exception.Message)" "ERROR"
}

Write-Log "=== WinPE Start Script END ===" "INFO"
