<#
.SYNOPSIS
    All-in-One OSDCloud Deployment Script (Fixed for StartOSDCloudGUI.ps1)
    - Auto-detects OSDCloud Modules (Fixes GUI not launching)
    - Auto-detects Windows Drive
    - Includes Wallpaper & Startup Script Logic
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/AutopilotScript.ps1"
# ---------------------

# 1. VERIFY INTERNET (Crucial Check)
Write-Host ">>> Checking Internet Connection..." -ForegroundColor Cyan
if (-not (Test-Connection 8.8.8.8 -Count 1 -Quiet)) {
    Write-Warning "No Internet Connection detected! OSDCloud requires Internet."
    Write-Host "Please check your network cable."
    Pause
}

# 2. LOAD MODULES (Fixes 'Command Not Found')
Write-Host ">>> Loading OSDCloud Modules..." -ForegroundColor Cyan
# We force import to ensure the 'Start-OSDCloudGUI' command is available
Import-Module OSD -Force -ErrorAction SilentlyContinue
Import-Module OSDCloud -Force -ErrorAction SilentlyContinue

# Emergency Check: If module is missing, download it.
if (-not (Get-Command Start-OSDCloudGUI -ErrorAction SilentlyContinue)) {
    Write-Warning "OSDCloudGUI command not found. Attempting emergency download..."
    Install-Module OSD -Force -AllowClobber -Scope CurrentUser
    Import-Module OSD -Force
}

# 3. LAUNCH THE GUI
Write-Host ">>> Launching OSDCloud GUI..." -ForegroundColor Cyan
try {
    Start-OSDCloudGUI
} catch {
    Write-Error "CRITICAL ERROR: Failed to launch GUI."
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Press Enter to exit..."
    Pause
    exit
}

# 4. POST-PROCESSING (Runs after GUI closes)
Write-Host ">>> Detecting Windows Drive..." -ForegroundColor Cyan
$OSDisk = $null
$Drives = Get-PSDrive -PSProvider FileSystem
foreach ($Drive in $Drives) {
    if (Test-Path "$($Drive.Root)Windows\System32\Config") {
        $OSDisk = $Drive.Root
        break
    }
}

if ($OSDisk) {
    Write-Host ">>> OS Detected on $OSDisk. Starting Customizations..." -ForegroundColor Green

    # --- A. Wallpaper ---
    Write-Host "  > Downloading Wallpaper..." -ForegroundColor Cyan
    $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.jpg"
    try {
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Warning "    [!] Failed to download Wallpaper."
    }

    # --- B. Remove Bloatware ---
    Write-Host "  > Removing Bloatware..." -ForegroundColor Cyan
    $Bloatware = @(
        "*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*",
        "*Solitaire*","*OfficeHub*","*MixedReality*","*OneNote*",
        "*People*","*Skype*","*YourPhone*","*Zune*",
        "*Xbox*","*GamingApp*","*Outlook*","*Teams*","*Todo*","*Todos*","*PowerAutomate*","*Copilot*"
    )
    foreach ($App in $Bloatware) {
        Write-Host "    Scanning for: $App" -ForegroundColor DarkGray
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # --- C. Inject Autopilot Script ---
    Write-Host "  > Injecting Autopilot Script..." -ForegroundColor Cyan
    $StartupDir = "$OSDisk\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
    if (-not (Test-Path $StartupDir)) { New-Item -Path $StartupDir -ItemType Directory -Force }
    try {
        Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$StartupDir\AutopilotScript.ps1" -UseBasicParsing -ErrorAction Stop
        Write-Host "    [OK] Script injected." -ForegroundColor Green
    } catch {
        Write-Error "    [FAIL] Could not download Autopilot Script!"
    }

    # --- D. Force Audit Mode ---
    Write-Host "  > Configuring Audit Mode..." -ForegroundColor Cyan
    $UnattendContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <Reseal>
                <Mode>Audit</Mode>
            </Reseal>
        </component>
    </settings>
</unattend>
"@
    $UnattendContent | Out-File -FilePath "$OSDisk\Windows\Panther\unattend.xml" -Encoding UTF8 -Force

    # --- E. VERIFY & REBOOT ---
    Write-Host ">>> Imaging Complete!" -ForegroundColor Green
    Write-Host "If you see no red errors above, press Enter to reboot." -ForegroundColor Yellow
    Pause
    Restart-Computer -Force
} else {
    Write-Error "CRITICAL: Could not find Windows installation!"
    Pause
}
