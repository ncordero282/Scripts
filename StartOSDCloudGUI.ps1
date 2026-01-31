<#
.SYNOPSIS
    Master OSDCloud Deployment Script
    FIXES INCLUDED:
    1. Auto-Repairs DNS (Fixes "Could not resolve name" errors)
    2. Corrected GitHub URLs (Removed 'refs/heads')
    3. Robust Module Loading
#>

# --- CONFIGURATION (CHECK THESE!) ---
# REPLACE this with your actual wallpaper URL, or leave commented out if you don't have one yet.
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 

# FIXED URL: Removed '/refs/heads/' so this download works correctly
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
# ------------------------------------

# ==========================================
# PHASE 1: NETWORK SELF-HEALING (Crucial)
# ==========================================
Write-Host ">>> Phase 1: Verifying Connectivity..." -ForegroundColor Cyan

# 1. Check if we can ping Google (8.8.8.8)
if (-not (Test-Connection 8.8.8.8 -Count 1 -Quiet)) {
    Write-Warning "Ping failed. Attempting to reset Network Adapter..."
    Get-NetAdapter | Where-Object Status -eq 'Up' | Restart-NetAdapter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

# 2. Check if we can resolve names (DNS Check)
try {
    $null = [System.Net.Dns]::GetHostEntry("github.com")
    Write-Host "    [OK] DNS is working." -ForegroundColor Green
} catch {
    Write-Warning "    [!] DNS Resolution failed. Forcing Google DNS (8.8.8.8)..."
    # This command fixes the "Could not resolve webrequest name" error automatically
    Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 8.8.8.8
    Start-Sleep -Seconds 2
}

# Final Check
if (-not (Test-Connection "github.com" -Count 1 -Quiet)) {
    Write-Error "CRITICAL: Still cannot reach GitHub. Please check your ethernet cable."
    Pause
}

# ==========================================
# PHASE 2: MODULE LOADING
# ==========================================
Write-Host ">>> Phase 2: Loading OSDCloud Modules..." -ForegroundColor Cyan

# Import standard modules
Import-Module OSD -Force -ErrorAction SilentlyContinue
Import-Module OSDCloud -Force -ErrorAction SilentlyContinue

# Emergency: If Start-OSDCloudGUI is missing, download it now.
if (-not (Get-Command Start-OSDCloudGUI -ErrorAction SilentlyContinue)) {
    Write-Warning "Modules not loaded from USB. Downloading from Internet..."
    Install-Module OSD -Force -AllowClobber -Scope CurrentUser
    Import-Module OSD -Force
}

# ==========================================
# PHASE 3: LAUNCH GUI
# ==========================================
Write-Host ">>> Phase 3: Launching GUI..." -ForegroundColor Cyan
Write-Warning "IMPORTANT: Do NOT check 'Restart' in the GUI. Let this script handle the reboot."
try {
    Start-OSDCloudGUI
} catch {
    Write-Error "Failed to launch GUI: $($_.Exception.Message)"
    Pause
    exit
}

# ==========================================
# PHASE 4: POST-PROCESSING
# ==========================================
Write-Host ">>> Phase 4: Detecting Windows Drive..." -ForegroundColor Cyan
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
    if ($WallpaperUrl -and $WallpaperUrl -ne "https://your-url-here.com/wallpaper.jpg") {
        Write-Host "  > Downloading Wallpaper..." -ForegroundColor Cyan
        $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.jpg"
        try {
            Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Warning "    [!] Wallpaper download failed. Check URL."
        }
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
        Write-Host "    [OK] Script injected to Startup." -ForegroundColor Green
    } catch {
        Write-Error "    [FAIL] Could not download Autopilot Script. Check URL: $AutopilotScriptUrl"
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

    # --- E. REBOOT ---
    Write-Host ">>> Imaging Complete!" -ForegroundColor Green
    Write-Host "Rebooting in 10 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Error "CRITICAL: Could not find Windows installation! Customizations skipped."
    Pause
}
