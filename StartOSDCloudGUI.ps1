<#
.SYNOPSIS
    WinPE Boot Script for OSDCloud (Hardened)
#>
$LogFile = "X:\Windows\Temp\WinPE-StartOSDCloudGUI.log"
Start-Transcript -Path $LogFile

Write-Host ">>> Initializing OSDCloud Environment..." -ForegroundColor Cyan

# 1. Import OSD Module
Import-Module OSD -Force -ErrorAction SilentlyContinue

# 2. Launch OSDCloud GUI
# We run this FIRST so the OS is laid down on the disk.
# The script will pause here until the GUI finishes and you click "Start".
Write-Host "Launching GUI..."
Start-OSDCloudGUI

# 3. POST-IMAGE INJECTION (Run this AFTER the GUI closes/finishes)
# This block runs after the OS is applied but BEFORE the reboot.
Write-Host ">>> Starting Post-Imaging Injection..." -ForegroundColor Magenta

# Detect the USB (Look for OSDCloudUSB label)
$USBDrive = Get-Volume | Where-Object { $_.FileSystemLabel -eq "OSDCloudUSB" } | Select-Object -First 1

if ($USBDrive) {
    $USBLetter = "$($USBDrive.DriveLetter):"
    $Source = "$USBLetter\OSDCloud\Scripts\SetupComplete"
    
    # A) Stage payload to C:\OSDCloud
    $Dest = "C:\OSDCloud\Scripts\SetupComplete"
    New-Item -Path $Dest -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$Source\*" -Destination $Dest -Recurse -Force
    Write-Host "   [+] Payload staged from USB." -ForegroundColor Green
    
    # B) FORCE the Windows Hook (The critical missing step)
    $SetupDir = "C:\Windows\Setup\Scripts"
    New-Item -Path $SetupDir -ItemType Directory -Force | Out-Null
    
    # Create the command file that Windows looks for
    $CmdContent = @"
@echo off
echo [SETUPCOMPLETE] Starting Custom Actions >> C:\Windows\Temp\SetupComplete.log
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\OSDCloud\Scripts\SetupComplete\SetupComplete-Actions.ps1" >> C:\Windows\Temp\SetupComplete.log 2>&1
"@
    Set-Content -Path "$SetupDir\SetupComplete.cmd" -Value $CmdContent -Encoding ASCII
    Write-Host "   [+] SetupComplete.cmd hook forcefully installed." -ForegroundColor Green

} else {
    Write-Warning "CRITICAL: OSDCloudUSB drive not found! Custom scripts will not run."
}

Stop-Transcript
