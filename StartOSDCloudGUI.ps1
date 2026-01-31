<#
.SYNOPSIS
    NYC Parks OSDCloud Wrapper (BRUTE FORCE EDITION)
    - Wallpaper: Physically overwrites the default Windows image file.
    - Trigger: Injects RunOnce directly into Offline Registry (Bypasses SetupComplete).
    - Mode: Audit Mode via Unattend.xml.
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

# 2. RUN GUI (MANUAL REBOOT CHECK)
Clear-Host
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "                 INSTRUCTIONS" -ForegroundColor Yellow
Write-Host "1. When the GUI opens, UNCHECK 'Reboot on Completion'." -ForegroundColor White
Write-Host "2. Click START." -ForegroundColor White
Write-Host "3. When imaging finishes, CLOSE THE GUI (Click X)." -ForegroundColor White
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

# 4. BRUTE FORCE WALLPAPER (Overwrite Defaults)
Write-Host ">>> OVERWRITING DEFAULT WALLPAPER..." -ForegroundColor Cyan
$TempWall = "$env:TEMP\NYCParksWallpaper.png"
try {
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $TempWall -UseBasicParsing
    
    # Overwrite the standard 4K and default wallpapers
    # Windows has no choice but to show this image now.
    Copy-Item -Path $TempWall -Destination "$DriveLetter\Windows\Web\Wallpaper\Windows\img0.jpg" -Force
    Copy-Item -Path $TempWall -Destination "$DriveLetter\Windows\Web\4K\Wallpaper\Windows\img0_3840x2160.jpg" -Force
    
    Write-Host "    [OK] Default Wallpaper Replaced." -ForegroundColor Green
} catch {
    Write-Warning "Wallpaper Download Failed."
}

# 5. STAGE AUTOPILOT SCRIPT
Write-Host ">>> DOWNLOADING AUTOPILOT SCRIPT..." -ForegroundColor Cyan
$HiddenDir = "$DriveLetter\ProgramData\Autopilot"
if (-not (Test-Path $HiddenDir)) { New-Item -Path $HiddenDir -ItemType Directory -Force | Out-Null }
$LocalScriptPath = "$HiddenDir\AutopilotScript.ps1"

try {
    Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile $LocalScriptPath -UseBasicParsing
    Write-Host "    [OK] Script Saved to $LocalScriptPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to download Autopilot Script!"
}

# 6. INJECT RUNONCE (DIRECT REGISTRY EDIT)
# We load the offline registry and write the command directly. 
# This bypasses SetupComplete.cmd entirely.
Write-Host ">>> INJECTING STARTUP TRIGGER..." -ForegroundColor Cyan
$SoftwareHive = "$DriveLetter\Windows\System32\config\SOFTWARE"

if (Test-Path $SoftwareHive) {
    reg load "HKLM\OFFLINE_SOFTWARE" $SoftwareHive | Out-Null
    
    $RunOnceKey = "HKLM:\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    
    # The Command: Launches PowerShell, loads your script.
    # We rely on the "Smart Wait" inside your AutopilotScript.ps1 for timing.
    $Command = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Maximized -File `"C:\ProgramData\Autopilot\AutopilotScript.ps1`""
    
    New-ItemProperty -Path $RunOnceKey -Name "SetupAutopilot" -Value $Command -Force | Out-Null
    
    [gc]::Collect()
    reg unload "HKLM\OFFLINE_SOFTWARE" | Out-Null
    Write-Host "    [OK] Registry Trigger Set." -ForegroundColor Green
} else {
    Write-Error "CRITICAL: Could not load Registry Hive."
}

# 7. UNATTEND XML (FORCE AUDIT MODE)
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

# 8. FINISH
Stop-Transcript
Write-Host ">>> DONE. REBOOTING..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
