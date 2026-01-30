<#
.SYNOPSIS
    Wrapper for Start-OSDCloudGUI to apply Custom Bloatware Removal, Wallpaper, and Audit Mode.
    
.DESCRIPTION
    1. Launches OSDCloudGUI (User must NOT check "Restart" in the GUI).
    2. Modifies the offline OS to remove bloatware.
    3. Injects custom Unattend.xml to force Audit Mode.
    4. Injects Autopilot script to run on first login.
    5. Automatically reboots the machine.
#>

# --- CONFIGURATION SECTION ---
# REPLACE THIS with your direct image URL (JPG/PNG)
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 

# Your Autopilot Script URL
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/AutopilotScript.ps1"
# -----------------------------

# 1. Initialize OSDCloud Environment
if (-not (Get-Module -ListAvailable OSD)) {
    Install-Module OSD -Force
}
Import-Module OSD -Force

# 2. Launch OSDCloud GUI
Write-Host ">>> Launching OSDCloud GUI..." -ForegroundColor Cyan
Write-Warning "IMPORTANT: Do NOT check 'Restart' or 'Shutdown' in the GUI. Let this script handle the reboot."
Start-OSDCloudGUI

# 3. Post-Processing (Runs after GUI closes)
$OSDisk = "C:\" 

if (Test-Path "$OSDisk\Windows\System32") {
    Write-Host ">>> OS Detected. Starting Post-Processing..." -ForegroundColor Green

    # --- A. Set Windows Wallpaper ---
    Write-Host "  > Setting Wallpaper..." -ForegroundColor Cyan
    $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\img0.jpg"
    
    # Backup original
    if (Test-Path $WallPath) { Move-Item $WallPath "$WallPath.bak" -Force }
    
    # Download custom wallpaper
    try {
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Warning "  ! Failed to download wallpaper. Restoring default."
        if (Test-Path "$WallPath.bak") { Move-Item "$WallPath.bak" $WallPath -Force }
    }

    # --- B. Remove Bloatware (Offline Removal) ---
    Write-Host "  > Removing Bloatware..." -ForegroundColor Cyan
    $Bloatware = @(
        "*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*",
        "*MicrosoftSolitaireCollection*","*MicrosoftOfficeHub*","*MixedReality*",
        "*OneNote*","*People*","*SkypeApp*","*Wallet*","*YourPhone*","*Zune*"
    )
    foreach ($App in $Bloatware) {
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # --- C. Inject Autopilot Script ---
    Write-Host "  > Injecting Autopilot Script..." -ForegroundColor Cyan
    $ScriptDest = "$OSDisk\Windows\Temp\AutopilotScript.ps1"
    Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile $ScriptDest -UseBasicParsing

    # --- D. Configure Audit Mode & RunSynchronous ---
    Write-Host "  > Configuring Boot to Audit Mode..." -ForegroundColor Cyan
    
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
    <settings pass="auditUser">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Temp\AutopilotScript.ps1</Path>
                    <Description>Run Custom Autopilot Script</Description>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
</unattend>
"@
    $UnattendPath = "$OSDisk\Windows\Panther\unattend.xml"
    if (-not (Test-Path "$OSDisk\Windows\Panther")) { New-Item -Path "$OSDisk\Windows\Panther" -ItemType Directory -Force }
    $UnattendContent | Out-File -FilePath $UnattendPath -Encoding UTF8 -Force

    Write-Host ">>> Post-Processing Complete. Rebooting in 5 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Error "OSDCloud did not complete or C:\ is not mounted. Script aborted."
}
