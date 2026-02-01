<#
.SYNOPSIS
    WinPE Boot Script for OSDCloud (Final Fix)
#>
$LogFile = "X:\Windows\Temp\WinPE-StartOSDCloudGUI.log"
Start-Transcript -Path $LogFile

Write-Host ">>> Initializing OSDCloud Environment..." -ForegroundColor Cyan

# 1. Import OSD Module
Import-Module OSD -Force -ErrorAction SilentlyContinue

# 2. Launch OSDCloud GUI
# IMPORTANT: You MUST UNCHECK "Reboot on Completion" in the GUI.
Write-Host "Launching GUI..."
Start-OSDCloudGUI

# 3. POST-IMAGE INJECTION
# This runs only after the GUI closes.
Write-Host ">>> Starting Post-Imaging Injection..." -ForegroundColor Magenta

$USBDrive = Get-Volume | Where-Object { $_.FileSystemLabel -eq "OSDCloudUSB" } | Select-Object -First 1

if ($USBDrive) {
    $USBLetter = "$($USBDrive.DriveLetter):"
    $Source = "$USBLetter\OSDCloud\Scripts\SetupComplete"
    
    # A) Stage payload
    $Dest = "C:\OSDCloud\Scripts\SetupComplete"
    New-Item -Path $Dest -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$Source\*" -Destination $Dest -Recurse -Force
    Write-Host "   [+] Payload staged." -ForegroundColor Green
    
    # B) FORCE the Windows Hook
    $SetupDir = "C:\Windows\Setup\Scripts"
    New-Item -Path $SetupDir -ItemType Directory -Force | Out-Null
    
    $CmdContent = @"
@echo off
echo [SETUPCOMPLETE] Starting >> C:\Windows\Temp\SetupComplete.log
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\OSDCloud\Scripts\SetupComplete\SetupComplete-Actions.ps1" >> C:\Windows\Temp\SetupComplete.log 2>&1
"@
    Set-Content -Path "$SetupDir\SetupComplete.cmd" -Value $CmdContent -Encoding ASCII
    Write-Host "   [+] SetupComplete.cmd installed." -ForegroundColor Green

} else {
    Write-Warning "CRITICAL: OSDCloudUSB drive not found!"
}

# 4. FINAL REBOOT (Handles the restart automatically)
Write-Host ">>> Injection Complete. Rebooting..." -ForegroundColor Cyan
Stop-Transcript
wpeutil reboot
