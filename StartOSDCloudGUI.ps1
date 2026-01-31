<#
.SYNOPSIS
    MASTER OSDCloud Launcher (Legacy Compatible)
    - Updated for PNG Wallpaper
    - Fixed GitHub URL structure automatically
#>

# --- CONFIGURATION (UPDATED) ---
# 1. Wallpaper (PNG)
# NOTE: The script downloads this file. Your Autopilot script must apply it.
# IMPORTANT: You need to put the URL to your PNG file here. 
# Right now it is just a placeholder because you only gave me the path, not the URL for the image itself.
$WallpaperUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/CompanyWallpaper.png" 

# 2. Autopilot Script (Fixed URL)
# I removed '/refs/heads/' so this link will actually work.
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
# ---------------------

Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   STARTING OSDCLOUD MASTER SCRIPT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. NETWORK CHECK (Legacy Safe)
Write-Host ">>> [1/5] Verifying Network..." -ForegroundColor Yellow
if (Test-Connection "8.8.8.8" -Count 1 -Quiet) {
    Write-Host "    [OK] Internet Connected." -ForegroundColor Green
} else {
    Write-Warning "    [!] Ping failed. Attempting blind DNS fix..."
    try {
        cmd.exe /c "netsh interface ip set dns name='Ethernet' static 8.8.8.8"
        cmd.exe /c "netsh interface ip set dns name='Wi-Fi' static 8.8.8.8"
        Start-Sleep -Seconds 2
    } catch {}
    
    if (-not (Test-Connection "github.com" -Count 1 -Quiet)) {
        Write-Error "CRITICAL: No Internet Access. Check cable."
    }
}

# 2. MODULE LOADER
Write-Host ">>> [2/5] Loading OSDCloud Modules..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable OSDCloud)) {
    Write-Warning "    [!] Modules missing. Downloading..."
    try {
        Install-Module OSD -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        Import-Module OSD -Force
        Install-Module OSDCloud -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        Write-Host "    [OK] Downloaded." -ForegroundColor Green
    } catch {
        Write-Error "CRITICAL: Download failed."
        Pause
        Exit
    }
} else {
    Import-Module OSD -Force -ErrorAction SilentlyContinue
    Import-Module OSDCloud -Force -ErrorAction SilentlyContinue
}

# 3. LAUNCH GUI
Write-Host ">>> [3/5] Launching GUI..." -ForegroundColor Yellow
try {
    Start-OSDCloudGUI
} catch {
    Write-Error "CRITICAL GUI ERROR: $($_.Exception.Message)"
    Pause
    Exit
}

# 4. POST-PROCESSING
Write-Host ">>> [4/5] Starting Customizations..." -ForegroundColor Yellow

$OSDisk = $null
$Drives = Get-PSDrive -PSProvider FileSystem
foreach ($Drive in $Drives) {
    if (Test-Path "$($Drive.Root)Windows\System32\Config") { $OSDisk = $Drive.Root; break }
}

if ($OSDisk) {
    Write-Host "    [OK] Windows found on $OSDisk" -ForegroundColor Green

    # A. Wallpaper (PNG)
    # We download it to the path you specified: C:\Windows\Web\Wallpaper\Windows\CompanyWallpaper.png
    if ($WallpaperUrl -and $WallpaperUrl -ne "placeholder") {
        Write-Host "    -> Downloading Wallpaper..."
        $WallDest = "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.png"
        try { Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallDest -UseBasicParsing -ErrorAction Stop } catch { Write-Warning "    [!] Wallpaper download failed." }
    }

    # B. Bloatware
    Write-Host "    -> Removing Bloatware..."
    $Bloatware = @("*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*","*Solitaire*","*OfficeHub*","*MixedReality*","*OneNote*","*People*","*Skype*","*YourPhone*","*Zune*","*Xbox*","*GamingApp*","*Outlook*","*Teams*","*Todo*","*Todos*","*PowerAutomate*","*Copilot*")
    foreach ($App in $Bloatware) {
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # C. Autopilot Script
    Write-Host "    -> Injecting Autopilot Script..."
    $StartupDir = "$OSDisk\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
    if (-not (Test-Path $StartupDir)) { New-Item -Path $StartupDir -ItemType Directory -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$StartupDir\AutopilotScript.ps1" -UseBasicParsing -ErrorAction Stop
        Write-Host "    [OK] Script Injected." -ForegroundColor Green
    } catch {
        Write-Error "    [FAIL] Script Download Failed."
    }

    # D. Audit Mode
    Write-Host "    -> Configuring Audit Mode..."
    $UnattendContent = '<?xml version="1.0" encoding="utf-8"?><unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><settings pass="oobeSystem"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><Reseal><Mode>Audit</Mode></Reseal></component></settings></unattend>'
    $UnattendContent | Out-File -FilePath "$OSDisk\Windows\Panther\unattend.xml" -Encoding UTF8 -Force

    # 5. FINISH
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Rebooting in 10 seconds..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Error "CRITICAL: No Windows installation found!"
    Pause
}
