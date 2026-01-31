<#
.SYNOPSIS
    Master OSDCloud Deployment Script (Network Wait Version)
    - Waits for DHCP assignment (Fixes "IP not yet assigned" error)
    - Auto-Repairs DNS
    - Launches GUI safely
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
# ---------------------

# ==========================================
# PHASE 1: WAIT FOR IP ADDRESS (The Fix)
# ==========================================
Write-Host ">>> Phase 1: Waiting for Network..." -ForegroundColor Cyan

$MaxRetries = 60
$RetryCount = 0
$IP = $null

# Keep looping until we find a valid IPv4 address (ignoring 169.254 self-assigned IPs)
while (-not $IP -and $RetryCount -lt $MaxRetries) {
    $IP = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPAddress -notlike "127.0.0.1" }
    
    if (-not $IP) {
        Write-Host "  Waiting for DHCP... ($RetryCount / $MaxRetries)" -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline # Overwrite line for cleanliness
        $RetryCount++
    }
}

if ($IP) {
    Write-Host "`n  [OK] IP Address Assigned: $($IP.IPAddress)" -ForegroundColor Green
} else {
    Write-Error "`nCRITICAL: DHCP Timed Out! No IP Address received."
    Write-Host "Please check your ethernet cable."
    Pause
    exit
}

# ==========================================
# PHASE 2: VERIFY & FIX DNS
# ==========================================
Write-Host ">>> Phase 2: Verifying Internet Access..." -ForegroundColor Cyan

try {
    # Try to resolve GitHub. If it fails, we force Google DNS.
    $null = [System.Net.Dns]::GetHostEntry("github.com")
    Write-Host "  [OK] DNS is working." -ForegroundColor Green
} catch {
    Write-Warning "  [!] DNS Resolution failed. Forcing Google DNS (8.8.8.8)..."
    Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 8.8.8.8
    Start-Sleep -Seconds 2
}

# Final Ping Check
if (-not (Test-Connection "github.com" -Count 1 -Quiet)) {
    Write-Error "CRITICAL: Connected to network but cannot reach Internet."
    Pause
}

# ==========================================
# PHASE 3: LOAD MODULES & LAUNCH GUI
# ==========================================
Write-Host ">>> Phase 3: Launching OSDCloud GUI..." -ForegroundColor Cyan

# 1. Load Modules
Import-Module OSD -Force -ErrorAction SilentlyContinue
Import-Module OSDCloud -Force -ErrorAction SilentlyContinue

# 2. Emergency Download if Module is missing
if (-not (Get-Command Start-OSDCloudGUI -ErrorAction SilentlyContinue)) {
    Write-Warning "Modules missing. Downloading..."
    Install-Module OSD -Force -AllowClobber -Scope CurrentUser
    Import-Module OSD -Force
}

# 3. Start GUI
try {
    Start-OSDCloudGUI
} catch {
    Write-Error "Failed to launch GUI: $($_.Exception.Message)"
    Pause
    exit
}

# ==========================================
# PHASE 4: POST-PROCESSING (Runs after GUI)
# ==========================================
Write-Host ">>> Phase 4: Customizations..." -ForegroundColor Cyan

# Find Windows Drive
$OSDisk = $null
$Drives = Get-PSDrive -PSProvider FileSystem
foreach ($Drive in $Drives) {
    if (Test-Path "$($Drive.Root)Windows\System32\Config") {
        $OSDisk = $Drive.Root
        break
    }
}

if ($OSDisk) {
    Write-Host "  > OS Detected on $OSDisk" -ForegroundColor Green

    # --- A. Wallpaper ---
    if ($WallpaperUrl -and $WallpaperUrl -ne "https://your-url-here.com/wallpaper.jpg") {
        $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.jpg"
        try { Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing -ErrorAction Stop } catch {}
    }

    # --- B. Remove Bloatware ---
    Write-Host "  > Removing Bloatware..." -ForegroundColor Cyan
    $Bloatware = @("*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*","*Solitaire*","*OfficeHub*","*MixedReality*","*OneNote*","*People*","*Skype*","*YourPhone*","*Zune*","*Xbox*","*GamingApp*","*Outlook*","*Teams*","*Todo*","*Todos*","*PowerAutomate*","*Copilot*")
    foreach ($App in $Bloatware) {
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # --- C. Inject Autopilot Script ---
    Write-Host "  > Injecting Autopilot Script..." -ForegroundColor Cyan
    $StartupDir = "$OSDisk\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
    if (-not (Test-Path $StartupDir)) { New-Item -Path $StartupDir -ItemType Directory -Force }
    try { Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$StartupDir\AutopilotScript.ps1" -UseBasicParsing -ErrorAction Stop } catch { Write-Warning "Script Download Failed" }

    # --- D. Force Audit Mode ---
    Write-Host "  > Setting Audit Mode..." -ForegroundColor Cyan
    $UnattendContent = '<?xml version="1.0" encoding="utf-8"?><unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><settings pass="oobeSystem"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><Reseal><Mode>Audit</Mode></Reseal></component></settings></unattend>'
    $UnattendContent | Out-File -FilePath "$OSDisk\Windows\Panther\unattend.xml" -Encoding UTF8 -Force

    # --- E. REBOOT ---
    Write-Host ">>> COMPLETE! Rebooting in 5 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Error "CRITICAL: No Windows OS found on C: through Z:"
    Pause
}
