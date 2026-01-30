<#
.SYNOPSIS
    Wrapper for Start-OSDCloudGUI to apply Custom Bloatware Removal, Wallpaper, and Audit Mode.
    FIXES: 
    1. Updates OSD module to fix "Invoke-ParseDate" error (Driver failure).
    2. Adds correct XML namespaces to fix "Unattend Answer File" error.
#>

# --- CONFIGURATION SECTION ---
$WallpaperUrl = "https://your-url-here.com/wallpaper.jpg" 
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/AutopilotScript.ps1"
# -----------------------------

# 1. FIX: Repair OSD Module (Fixes "Invoke-ParseDate" error)
Write-Host ">>> Checking OSD Module Version..." -ForegroundColor Cyan
if (Get-Module OSD) { Remove-Module OSD -Force -ErrorAction SilentlyContinue }
# Force install the latest version to ensure drivers download correctly
Install-Module OSD -Force -AllowClobber -Scope CurrentUser
Import-Module OSD -Force

# 2. Launch OSDCloud GUI
Write-Host ">>> Launching OSDCloud GUI..." -ForegroundColor Cyan
Write-Warning "IMPORTANT: Do NOT check 'Restart' in the GUI."
Start-OSDCloudGUI

# 3. Post-Processing
$OSDisk = "C:\" 

if (Test-Path "$OSDisk\Windows\System32") {
    Write-Host ">>> OS Detected. Starting Post-Processing..." -ForegroundColor Green

    # --- A. Set Wallpaper ---
    Write-Host "  > Setting Wallpaper..." -ForegroundColor Cyan
    $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\img0.jpg"
    if (Test-Path $WallPath) { Move-Item $WallPath "$WallPath.bak" -Force }
    try {
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing -ErrorAction Stop
    } catch {
        if (Test-Path "$WallPath.bak") { Move-Item "$WallPath.bak" $WallPath -Force }
    }

    # --- B. Remove Bloatware ---
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

    # --- D. Configure Audit Mode (FIXED XML) ---
    Write-Host "  > Configuring Boot to Audit Mode..." -ForegroundColor Cyan
    
    # ADDED: xmlns:wcm definition to fix the parsing error
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
