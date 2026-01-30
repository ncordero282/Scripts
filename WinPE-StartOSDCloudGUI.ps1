# WinPE-StartOSDCloudGUI.ps1 (StartURL)
# Purpose: Stage SetupComplete payload from OSDCloudUSB -> local disk, then launch OSDCloud GUI

$ErrorActionPreference = 'Continue'

function WL {
    param([string]$Msg)
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] $Msg"
        Write-Host $line
        if (-not (Test-Path 'X:\Temp')) { New-Item -ItemType Directory -Path 'X:\Temp' -Force | Out-Null }
        Add-Content -Path 'X:\Temp\WinPE-StartOSDCloudGUI.log' -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

WL "=== WinPE StartURL BEGIN ==="

try {
    WL "Importing OSD module..."
    Import-Module OSD -Force -ErrorAction Stop
    WL "OSD module imported."
} catch {
    WL "ERROR: Import-Module OSD failed: $($_.Exception.Message)"
}

try {
    WL "Running Set-SetupCompleteOSDCloudUSB (stage E:\OSDCloud\Scripts\SetupComplete -> C:\OSDCloud\Scripts\SetupComplete)..."
    Set-SetupCompleteOSDCloudUSB
    WL "Set-SetupCompleteOSDCloudUSB completed."
} catch {
    WL "WARN: Set-SetupCompleteOSDCloudUSB failed: $($_.Exception.Message)"
    WL "Continuing anyway..."
}

try {
    WL "Launching OSDCloud GUI..."
    Start-OSDCloudGUI
    WL "Start-OSDCloudGUI invoked."
} catch {
    WL "ERROR: Start-OSDCloudGUI failed: $($_.Exception.Message)"
}

WL "=== WinPE StartURL END ==="
