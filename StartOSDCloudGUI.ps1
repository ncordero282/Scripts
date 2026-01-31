<#
.SYNOPSIS
    NYC Parks OSDCloud Wrapper (Audit Mode Edition)
    1. Images via OSDCloud.
    2. Injects Wallpaper Offline.
    3. Configures "One-Time Admin AutoLogon" to bypass Session 0 limits.
    4. Runs Autopilot Upload Interactively on first boot.
    5. Reseals (Sysprep) back to OOBE automatically.
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/NYCParksWallpaper.png"
$LogFile = "X:\OSDCloud_Wrapper.log"
Start-Transcript -Path $LogFile -Append

# 1. RUN OSDCLOUD
Write-Host ">>> STARTING OSDCLOUD GUI..." -ForegroundColor Cyan
Start-OSDCloudGUI -NoReboot

# 2. DETECT OFFLINE OS DRIVE
Write-Host ">>> DETECTING WINDOWS PARTITION..." -ForegroundColor Cyan
# Look for the volume containing the Windows folder
$OSVolume = Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\Windows\explorer.exe" } | Select-Object -First 1

if (-not $OSVolume) {
    Write-Host "CRITICAL ERROR: Windows OS Drive not found!" -ForegroundColor Red
    Start-Sleep 20
    Exit
}

$DriveLetter = "$($OSVolume.DriveLetter):"
Write-Host "OS Found on [$DriveLetter]" -ForegroundColor Green

# 3. INJECT WALLPAPER (OFFLINE)
Write-Host ">>> INJECTING WALLPAPER..." -ForegroundColor Cyan
$TempWall = "$env:TEMP\NYCParksWallpaper.png"
$TargetWallDir = "$DriveLetter\Windows\Web\Wallpaper\Windows"
$TargetWallFile = "$TargetWallDir\img0.jpg"

try {
    # Download
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $TempWall -UseBasicParsing
    
    # Overwrite
    if (Test-Path $TempWall) {
        Copy-Item -Path $TempWall -Destination $TargetWallFile -Force
        
        # Also hit the 4K folder for safety
        if (Test-Path "$DriveLetter\Windows\Web\4K\Wallpaper\Windows") {
            Copy-Item -Path $TempWall -Destination "$DriveLetter\Windows\Web\4K\Wallpaper\Windows\img0_3840x2160.jpg" -Force
        }
        
        # Clear Cache (Important!)
        Remove-Item "$DriveLetter\Users\*\AppData\Roaming\Microsoft\Windows\Themes\TranscodedWallpaper" -Force -ErrorAction SilentlyContinue
        
        Write-Host "Wallpaper injected." -ForegroundColor Green
    }
} catch {
    Write-Host "Wallpaper Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. PREPARE AUTOPILOT SCRIPT (THE "AUDIT MODE" PAYLOAD)
Write-Host ">>> STAGING AUTOPILOT SCRIPT..." -ForegroundColor Cyan

# We create the script that will run AFTER the reboot, inside the Admin desktop
$PayloadDir = "$DriveLetter\Windows\Setup\Scripts"
if (-not (Test-Path $PayloadDir)) { New-Item -Path $PayloadDir -ItemType Directory -Force | Out-Null }

$FinalScriptPath = "C:\Windows\Setup\Scripts\Invoke-Autopilot-Audit.ps1"

# Note: We use backticks (`) to escape variables that should execute LATER, not NOW.
$PSPayload = @"
Start-Transcript -Path "C:\Windows\Temp\Autopilot_Audit_Log.txt"

# A. Wait for Network
Write-Host "Waiting for Network Connection..." -ForegroundColor Cyan
`$MaxRetries = 100
while (!(Test-Connection -ComputerName "google.com" -Count 1 -Quiet)) {
    Write-Host "Waiting for internet..."
    Start-Sleep -Seconds 3
    `$RetryCount++
    if (`$RetryCount -gt `$MaxRetries) { break }
}

# B. Install Autopilot Module
Write-Host "Installing Autopilot Tools..." -ForegroundColor Cyan
Set-ExecutionPolicy Bypass -Scope Process -Force
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Install-Module -Name WindowsAutopilotIntune -Force -AllowClobber

# C. Run Upload (INTERACTIVE PROMPT WILL NOW APPEAR!)
Write-Host ">>> LAUNCHING AUTOPILOT UPLOAD <<<" -ForegroundColor Green
Write-Host "Please sign in to the popup window." -ForegroundColor Yellow

try {
    Get-WindowsAutopilotInfo -Online -ErrorAction Stop
} catch {
    Write-Host "Autopilot Error (Or already registered): `$(`$_.Exception.Message)" -ForegroundColor Red
    Start-Sleep -Seconds 5
}

# D. Cleanup & Reseal
Write-Host ">>> DEPLOYMENT COMPLETE. RESEALING..." -ForegroundColor Green
Write-Host "The PC will shutdown in 10 seconds."
Start-Sleep -Seconds 10

# Disable AutoLogon
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Force -ErrorAction SilentlyContinue

# Sysprep back to OOBE and Shutdown
& "C:\Windows\System32\Sysprep\sysprep.exe" /oobe /shutdown
Stop-Transcript
"@

Set-Content -Path "$PayloadDir\Invoke-Autopilot-Audit.ps1" -Value $PSPayload

# 5. CONFIGURE AUTO-LOGON (THE BRIDGE)
# We use SetupComplete.cmd to configure the registry so the PC boots into Admin Desktop once.
Write-Host ">>> CONFIGURING ADMIN AUTO-LOGON..." -ForegroundColor Cyan

$SetupCompletePath = "$PayloadDir\SetupComplete.cmd"

$CMDContent = @"
@echo off
:: 1. Enable Built-in Admin
net user administrator /active:yes
net user administrator ""

:: 2. Configure AutoLogon in Registry
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d Administrator /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "" /f

:: 3. Add Script to RunOnce (So it launches when Admin logs in)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "RunAutopilot" /t REG_SZ /d "powershell.exe -WindowStyle Maximized -ExecutionPolicy Bypass -File $FinalScriptPath" /f
"@

Set-Content -Path $SetupCompletePath -Value $CMDContent

# 6. REBOOT
Stop-Transcript
Write-Host ">>> DONE. REBOOTING INTO AUTOPILOT ENROLLMENT..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
