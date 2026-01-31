<#
.SYNOPSIS
    MASTER OSDCloud Launcher
    - Forces Module Import (Fixes "No GUI")
    - Network Self-Healing (Fixes DNS/IP issues)
    - Error Trapping (Keeps window open on failure)
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 
# Fixed URL (No 'refs/heads')
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
# ---------------------

Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   STARTING OSDCLOUD MASTER SCRIPT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. NETWORK CHECK (Double Check)
Write-Host ">>> [1/5] Verifying Network..." -ForegroundColor Yellow
if (-not (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPAddress -notlike "127.0.0.1" })) {
    Write-Error "CRITICAL: No IP Address found! Please check cable/Wi-Fi."
    Pause
    Exit
}

# DNS Fix (Just in case)
try {
    $null = [System.Net.Dns]::GetHostEntry("github.com")
    Write-Host "    [OK] Connection Verified." -ForegroundColor Green
} catch {
    Write-Warning "    [!] DNS Issue Detected. Fixing..."
    Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 8.8.8.8
    Start-Sleep -Seconds 2
}

# 2. MODULE LOADER (The "No GUI" Fix)
Write-Host ">>> [2/5] Loading OSDCloud Modules..." -ForegroundColor Yellow
try {
    # We explicitly import these to ensure the command exists in THIS session
    Import-Module OSD -Force -ErrorAction Stop
    Import-Module OSDCloud -Force -ErrorAction Stop
    Write-Host "    [OK] Modules Loaded." -ForegroundColor Green
} catch {
    Write-Warning "    [!] Modules missing. Attempting Emergency Download..."
    try {
        Install-Module OSD -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        Import-Module OSD -Force
        Write-Host "    [OK] Modules Downloaded." -ForegroundColor Green
    } catch {
        Write-Error "CRITICAL: Failed to load OSDCloud modules. Internet might be blocked."
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause
        Exit
    }
}

# 3. LAUNCH GUI
Write-Host ">>> [3/5] Launching GUI..." -ForegroundColor Yellow
Write-Warning "IMPORTANT: Do NOT check 'Restart' in the GUI."

try {
    # This is the command that was silently failing before
    Start-OSDCloudGUI
} catch {
    Write-Error "CRITICAL GUI ERROR: $($_.Exception.Message)"
    Write-Host "The script cannot continue." -ForegroundColor Red
    Pause
    Exit
}

# 4. POST-PROCESSING (Runs after you close the GUI)
Write-Host ">>> [4/5] Starting Customizations..." -ForegroundColor Yellow

# Find the Windows Drive
$OSDisk = $null
$Drives = Get-PSDrive -PSProvider FileSystem
foreach ($Drive in $Drives) {
    if (Test-Path "$($Drive.Root)Windows\System32\Config") { $OSDisk = $Drive.Root; break }
}

if ($OSDisk) {
    Write-Host "    [OK] Windows found on $OSDisk" -ForegroundColor Green

    # A. Wallpaper
    if ($WallpaperUrl -and $WallpaperUrl -ne "https://your-url-here.com/wallpaper.jpg") {
        Write-Host "    -> Downloading Wallpaper..."
        try { Invoke-WebRequest -Uri $WallpaperUrl -OutFile "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.jpg" -UseBasicParsing -ErrorAction Stop } catch { Write-Warning "Wallpaper failed." }
    }

    # B. Bloatware (Updated List)
    Write-Host "    -> removing Bloatware..."
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
        Write-Error "    [FAIL] Download Failed: $AutopilotScriptUrl"
    }

    # D. Audit Mode
    Write-Host "    -> Configuring Audit Mode..."
    $UnattendContent = '<?xml version="1.0" encoding="utf-8"?><unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><settings pass="oobeSystem"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><Reseal><Mode>Audit</Mode></Reseal></component></settings></unattend>'
    $UnattendContent | Out-File -FilePath "$OSDisk\Windows\Panther\unattend.xml" -Encoding UTF8 -Force

    # 5. FINISH
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Rebooting in 10 seconds... (Press CTRL+C to cancel)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Error "CRITICAL: No Windows installation found! Customizations skipped."
    Pause
}
