<#
.SYNOPSIS
    NYC Parks OSDCloud Wrapper (DELIVERY ONLY)
    - Job 1: Run OSDCloud (User must uncheck Reboot).
    - Job 2: Download Assets to C:\ProgramData\Autopilot.
    - Job 3: Set RunOnce Trigger.
    - Job 4: Set Audit Mode.
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/NYCParksWallpaper.png"
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
$LogFile = "X:\OSDCloud_Wrapper.log"
Start-Transcript -Path $LogFile -Append

# 1. LOAD MODULES
Write-Host ">>> LOADING MODULES..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable OSDCloud)) { Install-Module OSDCloud -Force }
Import-Module OSDCloud -Force
Import-Module OSD -Force

# 2. RUN GUI (INSTRUCTIONS)
Clear-Host
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "                 STOP AND READ" -ForegroundColor Red
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "1. UNCHECK 'Reboot on Completion' (Bottom Left)." -ForegroundColor White
Write-Host "2. UNCHECK 'Microsoft Update Catalog' (Drivers Tab)." -ForegroundColor White
Write-Host "3. Click START." -ForegroundColor White
Write-Host "4. When finished, CLOSE THE GUI (Click X)." -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host ">>> STARTING OSDCLOUD GUI..." -ForegroundColor Cyan

Start-OSDCloudGUI

# --- CHECKPOINT ---
Write-Host "Waiting for GUI to close..." -ForegroundColor Yellow
Pause

# 3. FIND WINDOWS DRIVE
Write-Host ">>> DETECTING WINDOWS PARTITION..." -ForegroundColor Cyan
$OSVolume = Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\Windows\explorer.exe" } | Select-Object -First 1

if (-not $OSVolume) {
    Write-Host "CRITICAL: Windows Drive not found." -ForegroundColor Red
    Start-Sleep 20
    Exit
}
$DriveLetter = "$($OSVolume.DriveLetter):"
Write-Host "OS Found on [$DriveLetter]" -ForegroundColor Green

# 4. DOWNLOAD ASSETS (Delivery Phase)
Write-Host ">>> DELIVERING ASSETS..." -ForegroundColor Cyan
$HiddenDir = "$DriveLetter\ProgramData\Autopilot"
if (-not (Test-Path $HiddenDir)) { New-Item -Path $HiddenDir -ItemType Directory -Force | Out-Null }

# Download Wallpaper (Just save it, don't apply it yet)
Invoke-WebRequest -Uri $WallpaperUrl -OutFile "$HiddenDir\NYCParksWallpaper.png" -UseBasicParsing

# Download Autopilot Script
Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$HiddenDir\AutopilotScript.ps1" -UseBasicParsing

Write-Host "    [OK] Files Delivered to C:\ProgramData\Autopilot" -ForegroundColor Green

# 5. INJECT RUNONCE (Trigger Phase)
Write-Host ">>> SETTING TRIGGER..." -ForegroundColor Cyan
$SoftwareHive = "$DriveLetter\Windows\System32\config\SOFTWARE"

if (Test-Path $SoftwareHive) {
    reg load "HKLM\OFFLINE_SOFTWARE" $SoftwareHive | Out-Null
    
    $RunOnceKey = "HKLM:\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    $Command = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Maximized -File `"C:\ProgramData\Autopilot\AutopilotScript.ps1`""
    
    New-ItemProperty -Path $RunOnceKey -Name "SetupAutopilot" -Value $Command -Force | Out-Null
    
    [gc]::Collect()
    reg unload "HKLM\OFFLINE_SOFTWARE" | Out-Null
    Write-Host "    [OK] Trigger Set." -ForegroundColor Green
}

# 6. UNATTEND XML (Audit Mode Phase)
Write-Host ">>> CONFIGURING AUDIT MODE..." -ForegroundColor Cyan
$UnattendContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <Reseal>
                <Mode>Audit</Mode>
            </Reseal>
        </component>
    </settings>
</unattend>
"@
Set-Content -Path "$DriveLetter\Windows\Panther\unattend.xml" -Value $UnattendContent -Encoding UTF8

# 7. FINISH
Stop-Transcript
Write-Host ">>> DONE. REBOOTING..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
