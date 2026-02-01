<#
.SYNOPSIS
    Minimal WinPE Boot Script for OSDCloud
    Relies entirely on unattend.xml for customization.
#>
$LogFile = "X:\Windows\Temp\WinPE-StartOSDCloudGUI.log"
Start-Transcript -Path $LogFile

Write-Host ">>> Initializing OSDCloud..." -ForegroundColor Cyan

# 1. Import OSD Module
Import-Module OSD -Force -ErrorAction SilentlyContinue

# 2. Launch GUI
# OSDCloud will automatically detect your custom unattend.xml on the USB.
Start-OSDCloudGUI

Stop-Transcript
