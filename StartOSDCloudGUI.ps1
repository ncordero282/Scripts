<#
.SYNOPSIS
    MASTER OSDCloud Launcher
    - Method: REGISTRY INJECTION (Fixes "Script didn't run")
    - Wallpaper: "Baked In" via Default User Registry (No script needed later)
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/NYCParksWallpaper.png"
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutopilotScript.ps1"
# ---------------------

Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   STARTING OSDCLOUD MASTER SCRIPT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. NETWORK & MODULES
Write-Host ">>> [1/5] Checking System..." -ForegroundColor Yellow
if (-not (Test-Connection "8.8.8.8" -Count 1 -Quiet)) {
    Write-Warning "Network connection lost. Attempting to restore..."
    cmd.exe /c "netsh interface ip set dns name='Ethernet' static 8.8.8.8"
    Start-Sleep -Seconds 3
}

if (-not (Get-Module -ListAvailable OSDCloud)) {
    Install-Module OSD -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
    Import-Module OSD -Force
    Install-Module OSDCloud -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
} else {
    Import-Module OSD -Force
    Import-Module OSDCloud -Force
}

# 2. LAUNCH GUI
Write-Host ">>> [2/5] Launching GUI..." -ForegroundColor Yellow
try {
    Start-OSDCloudGUI
} catch {
    Write-Error "CRITICAL: GUI Failed. $($_.Exception.Message)"
    Pause
    Exit
}

# 3. POST-PROCESSING PREP
Write-Host ">>> [3/5] Locating New OS..." -ForegroundColor Yellow
$OSDisk = $null
$Drives = Get-PSDrive -PSProvider FileSystem
foreach ($Drive in $Drives) {
    if (Test-Path "$($Drive.Root)Windows\System32\config\SOFTWARE") { $OSDisk = $Drive.Root; break }
}

if ($OSDisk) {
    Write-Host "    [OK] Windows found on $OSDisk" -ForegroundColor Green

    # 4. DOWNLOAD ASSETS
    Write-Host ">>> [4/5] Downloading Assets..." -ForegroundColor Yellow
    
    # Verify Network Again
    if (-not (Test-Connection "github.com" -Count 1 -Quiet)) {
        Write-Warning "    [!] Network dropped. Re-initializing..."
        Get-NetAdapter | Where-Object Status -eq 'Up' | Restart-NetAdapter -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
    }

    # A. Wallpaper (Download Only)
    $WallDest = "$OSDisk\Windows\Web\Wallpaper\Windows\NYCParksWallpaper.png"
    try { 
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallDest -UseBasicParsing -ErrorAction Stop
        Write-Host "    [OK] Wallpaper Downloaded." -ForegroundColor Green
    } catch { 
        Write-Warning "    [!] Wallpaper Download Failed. (Check URL/Network)" 
    }

    # B. Autopilot Script (Download Only)
    $HiddenDir = "$OSDisk\ProgramData\Autopilot"
    if (-not (Test-Path $HiddenDir)) { New-Item -Path $HiddenDir -ItemType Directory -Force | Out-Null }
    
    try {
        Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$HiddenDir\AutopilotScript.ps1" -UseBasicParsing -ErrorAction Stop
        Write-Host "    [OK] Autopilot Script Downloaded." -ForegroundColor Green
    } catch {
        Write-Error "    [CRITICAL] Autopilot Script Download Failed!"
        Pause
    }

    # 5. REGISTRY MAGIC (The Separation Fix)
    Write-Host ">>> [5/5] Injecting Configuration..." -ForegroundColor Yellow
    
    # --- PART A: Set Wallpaper for Default User (So it applies automatically) ---
    $DefaultUserHive = "$OSDisk\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultUserHive) {
        Write-Host "    -> Baking in Wallpaper..."
        reg load "HKU\OFFLINE_DEFAULT" $DefaultUserHive | Out-Null
        
        # Set the wallpaper path in the registry
        New-ItemProperty -Path "HKU\OFFLINE_DEFAULT\Control Panel\Desktop" -Name "Wallpaper" -Value "C:\Windows\Web\Wallpaper\Windows\NYCParksWallpaper.png" -PropertyType String -Force | Out-Null
        
        # Unload the hive
        [gc]::Collect()
        reg unload "HKU\OFFLINE_DEFAULT" | Out-Null
        Write-Host "       [OK] Wallpaper Set." -ForegroundColor Green
    }

    # --- PART B: Set RunOnce for Autopilot Script ---
    $SoftwareHive = "$OSDisk\Windows\System32\config\SOFTWARE"
    if (Test-Path $SoftwareHive) {
        Write-Host "    -> Setting Autopilot Trigger..."
        reg load "HKLM\OFFLINE_SOFTWARE" $SoftwareHive | Out-Null
        
        $RunCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Maximized -File `"C:\ProgramData\Autopilot\AutopilotScript.ps1`""
        New-ItemProperty -Path "HKLM:\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "SetupAutopilot" -Value $RunCmd -Force | Out-Null
        
        [gc]::Collect()
        reg unload "HKLM\OFFLINE_SOFTWARE" | Out-Null
        Write-Host "       [OK] Trigger Set." -ForegroundColor Green
    }

    # Audit Mode Unattend
    $UnattendContent = '<?xml version="1.0" encoding="utf-8"?><unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"><settings pass="oobeSystem"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><Reseal><Mode>Audit</Mode></Reseal></component></settings></unattend>'
    $UnattendContent | Out-File -FilePath "$OSDisk\Windows\Panther\unattend.xml" -Encoding UTF8 -Force

    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Rebooting in 10 seconds..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force

} else {
    Write-Error "CRITICAL: New OS not detected."
    Pause
}
