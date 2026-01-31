<#
.SYNOPSIS
    All-in-One OSDCloud Deployment Script
    Updates: Extended Bloatware List (Xbox/Teams/Outlook) & Fixed Startup Logic
#>

# --- CONFIGURATION ---
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/AutopilotScript.ps1"
# ---------------------

# 1. SELF-HEALING: Fix OSD Module & Drivers
Write-Host ">>> verifying OSDCloud Modules..." -ForegroundColor Cyan
if (Get-Module OSD) { Remove-Module OSD -Force -ErrorAction SilentlyContinue }
Install-Module OSD -Force -AllowClobber -Scope CurrentUser
Import-Module OSD -Force

# 2. LAUNCH THE GUI
Write-Host ">>> Launching OSDCloud GUI..." -ForegroundColor Cyan
Write-Warning "IMPORTANT: Do NOT check 'Restart' in the GUI."
Start-OSDCloudGUI

# 3. POST-PROCESSING (Runs immediately after you close the GUI)
$OSDisk = "C:\" 

if (Test-Path "$OSDisk\Windows\System32") {
    Write-Host ">>> OS Detected. Starting Customizations..." -ForegroundColor Green

    # --- A. Wallpaper (Download Only) ---
    # NOTE: The AutopilotScript must apply this via Registry!
    Write-Host "  > Downloading Wallpaper..." -ForegroundColor Cyan
    $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\CompanyWallpaper.jpg"
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing

    # --- B. Remove Bloatware (UPDATED LIST) ---
    Write-Host "  > Removing Bloatware..." -ForegroundColor Cyan
    # Added: Xbox, Teams, Outlook, ToDo based on your screenshots
    $Bloatware = @(
        "*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*",
        "*Solitaire*","*OfficeHub*","*MixedReality*","*OneNote*",
        "*People*","*Skype*","*YourPhone*","*Zune*",
        "*Xbox*","*Outlook*","*Teams*","*ToDo*","*PowerAutomate*","*Copilot*"
    )
    foreach ($App in $Bloatware) {
        Write-Host "    Removing: $App" -ForegroundColor DarkGray
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # --- C. Inject Autopilot Script (Startup Persistence) ---
    # We use ProgramData so it runs for ANY user (including Audit Admin)
    Write-Host "  > Injecting Autopilot Script to Startup..." -ForegroundColor Cyan
    $StartupDir = "$OSDisk\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
    if (-not (Test-Path $StartupDir)) { New-Item -Path $StartupDir -ItemType Directory -Force }
    
    # Download the script directly to the startup folder
    Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile "$StartupDir\AutopilotScript.ps1" -UseBasicParsing
    
    # VERIFICATION: Check if file exists
    if (Test-Path "$StartupDir\AutopilotScript.ps1") {
        Write-Host "    [OK] Script injected successfully." -ForegroundColor Green
    } else {
        Write-Error "    [FAIL] Script download failed!"
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
    Write-Host ">>> Imaging Complete! Rebooting in 5 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Warning "OSDCloud GUI closed but no OS was found on C:\. Skipping post-processing."
}
