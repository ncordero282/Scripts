<#
.SYNOPSIS
    NYC Parks OSDCloud Wrapper (Fixed)
    1. Loads Modules.
    2. Runs OSDCloud GUI (USER MUST UNCHECK REBOOT).
    3. Injects Wallpaper.
    4. Injects Unattend.xml to force Audit Mode.
    5. Stages Autopilot Upload script for first boot.
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/NYCParksWallpaper.png"
$LogFile = "X:\OSDCloud_Wrapper.log"
Start-Transcript -Path $LogFile -Append

# 1. PRE-FLIGHT CHECK
Write-Host ">>> LOADING MODULES..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable OSDCloud)) {
    Write-Warning "OSDCloud Module not found. Attempting install..."
    Install-Module OSDCloud -Force
}
Import-Module OSDCloud -Force
Import-Module OSD -Force

# 2. RUN OSDCLOUD
Clear-Host
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "                 INSTRUCTIONS" -ForegroundColor Yellow
Write-Host "1. When the GUI opens, UNCHECK 'Reboot on Completion'." -ForegroundColor White
Write-Host "2. Click START." -ForegroundColor White
Write-Host "3. When imaging finishes, CLOSE THE GUI (Click X)." -ForegroundColor White
Write-Host "   (The script will then continue to inject settings)" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host ">>> STARTING OSDCLOUD GUI..." -ForegroundColor Cyan

# REMOVED -NoReboot (This was the cause of the error)
Start-OSDCloudGUI

# --- THE HUMAN GATE ---
Write-Host "===================================================" -ForegroundColor Yellow
Write-Host "   CHECKPOINT: Did the imaging complete successfully?" -ForegroundColor Yellow
Write-Host "   (If the PC rebooted already, you forgot to uncheck the box!)" -ForegroundColor Yellow
Write-Host "===================================================" -ForegroundColor Yellow
Pause

# 3. DETECT OFFLINE OS DRIVE
Write-Host ">>> DETECTING WINDOWS PARTITION..." -ForegroundColor Cyan
$OSVolume = Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\Windows\explorer.exe" } | Select-Object -First 1

if (-not $OSVolume) {
    Write-Host "CRITICAL ERROR: Windows OS Drive not found!" -ForegroundColor Red
    Write-Host "The drive might not be mounted or imaging failed."
    Start-Sleep 20
    Exit
}

$DriveLetter = "$($OSVolume.DriveLetter):"
Write-Host "OS Found on [$DriveLetter]" -ForegroundColor Green

# 4. INJECT WALLPAPER (OFFLINE)
Write-Host ">>> INJECTING WALLPAPER..." -ForegroundColor Cyan
$TempWall = "$env:TEMP\NYCParksWallpaper.png"
$TargetWallDir = "$DriveLetter\Windows\Web\Wallpaper\Windows"
$TargetWallFile = "$TargetWallDir\img0.jpg"

try {
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $TempWall -UseBasicParsing
    
    if (Test-Path $TempWall) {
        # Copy to default lock screen path
        Copy-Item -Path $TempWall -Destination $TargetWallFile -Force
        
        # Copy to 4K path
        if (Test-Path "$DriveLetter\Windows\Web\4K\Wallpaper\Windows") {
            Copy-Item -Path $TempWall -Destination "$DriveLetter\Windows\Web\4K\Wallpaper\Windows\img0_3840x2160.jpg" -Force
        }
        
        # Clear Cache
        Remove-Item "$DriveLetter\Users\*\AppData\Roaming\Microsoft\Windows\Themes\TranscodedWallpaper" -Force -ErrorAction SilentlyContinue
        Write-Host "Wallpaper injected." -ForegroundColor Green
    }
} catch {
    Write-Host "Wallpaper Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 5. CONFIGURE AUDIT MODE (UNATTEND.XML)
Write-Host ">>> CONFIGURING UNATTEND.XML (AUDIT MODE)..." -ForegroundColor Cyan
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
$UnattendPath = "$DriveLetter\Windows\Panther\unattend.xml"
if (-not (Test-Path "$DriveLetter\Windows\Panther")) { New-Item -Path "$DriveLetter\Windows\Panther" -ItemType Directory -Force }
Set-Content -Path $UnattendPath -Value $UnattendContent -Encoding UTF8

# 6. STAGE AUTOPILOT SCRIPT
Write-Host ">>> STAGING PAYLOAD..." -ForegroundColor Cyan

$PayloadDir = "$DriveLetter\Windows\Setup\Scripts"
if (-not (Test-Path $PayloadDir)) { New-Item -Path $PayloadDir -ItemType Directory -Force | Out-Null }

$FinalScriptPath = "C:\Windows\Setup\Scripts\Invoke-Autopilot-Audit.ps1"

# Note: We use the 'Smart Wait' logic here to ensure Windows is ready
$PSPayload = @"
Start-Transcript -Path "C:\Windows\Temp\Autopilot_Audit_Log.txt"

# A. Wait for Network
Write-Host "Waiting for Network Connection..." -ForegroundColor Cyan
`$RetryCount = 0
`$MaxRetries = 100
while (!(Test-Connection -ComputerName "google.com" -Count 1 -Quiet)) {
    Write-Host "Waiting for internet..."
    Start-Sleep -Seconds 3
    `$RetryCount++
    if (`$RetryCount -gt `$MaxRetries) { break }
}

# B. Install Autopilot Tools
Write-Host "Installing Autopilot Tools..." -ForegroundColor Cyan
Set-ExecutionPolicy Bypass -Scope Process -Force
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Install-Module -Name WindowsAutopilotIntune -Force -AllowClobber

# C. Run Upload
Write-Host ">>> LAUNCHING AUTOPILOT UPLOAD <<<" -ForegroundColor Green
Write-Host "Please sign in to the popup window." -ForegroundColor Yellow

try {
    Get-WindowsAutopilotInfo -Online -ErrorAction Stop
} catch {
    Write-Host "Autopilot Error: `$(`$_.Exception.Message)" -ForegroundColor Red
    Start-Sleep -Seconds 5
}

# D. Cleanup & Reseal
Write-Host ">>> DEPLOYMENT COMPLETE. RESEALING..." -ForegroundColor Green
Write-Host "The PC will shutdown in 10 seconds."
Start-Sleep -Seconds 10

# Sysprep back to OOBE and Shutdown
& "C:\Windows\System32\Sysprep\sysprep.exe" /oobe /shutdown
Stop-Transcript
"@

Set-Content -Path "$PayloadDir\Invoke-Autopilot-Audit.ps1" -Value $PSPayload

# 7. SETUPCOMPLETE.CMD (THE TRIGGER)
Write-Host ">>> CONFIGURING RUNONCE TRIGGER..." -ForegroundColor Cyan

$SetupCompletePath = "$PayloadDir\SetupComplete.cmd"
$CMDContent = @"
@echo off
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "RunAutopilot" /t REG_SZ /d "powershell.exe -WindowStyle Maximized -ExecutionPolicy Bypass -File $FinalScriptPath" /f
"@

Set-Content -Path $SetupCompletePath -Value $CMDContent

# 8. FINISH
Stop-Transcript
Write-Host ">>> DONE. REBOOTING..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
