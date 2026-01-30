<#
.SYNOPSIS
    Wrapper for Start-OSDCloudGUI to apply Custom Bloatware Removal, Wallpaper, and Audit Mode.
#>

# 1. Initialize OSDCloud Environment
if (-not (Get-Module -ListAvailable OSD)) {
    Install-Module OSD -Force
}
Import-Module OSD -Force

# 2. Define Your Resources
$WallpaperUrl   = "https://your-url-here.com/wallpaper.jpg" # Replace with your actual wallpaper URL
$AutopilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/AutopilotScript.ps1"

# 3. Launch OSDCloud GUI
# IMPORTANT: When the GUI opens, perform your deployment but DO NOT CHECK "Reboot" or "Shutdown".
# You need the script to continue running after the OS is applied.
Write-Host ">>> Launching OSDCloud GUI..." -ForegroundColor Cyan
Start-OSDCloudGUI

# 4. Post-Processing (Runs after GUI closes)
$OSDisk = "C:\" # OSDCloud typically mounts the applied OS to C:\ in WinPE

if (Test-Path "$OSDisk\Windows\System32") {
    Write-Host ">>> OS Detected. Starting Post-Processing..." -ForegroundColor Green

    # --- A. Set Windows Wallpaper ---
    Write-Host "  > Setting Wallpaper..." -ForegroundColor Cyan
    $WallPath = "$OSDisk\Windows\Web\Wallpaper\Windows\img0.jpg"
    # Backup original
    if (Test-Path $WallPath) { Move-Item $WallPath "$WallPath.bak" -Force }
    # Download yours (using curl/Invoke-WebRequest)
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallPath -UseBasicParsing

    # --- B. Remove Bloatware (Offline Removal) ---
    Write-Host "  > Removing Bloatware..." -ForegroundColor Cyan
    # Define list of apps to remove (wildcards supported)
    $Bloatware = @(
        "*BingWeather*","*GetHelp*","*GetStarted*","*Microsoft3DViewer*",
        "*MicrosoftSolitaireCollection*","*MicrosoftOfficeHub*","*MixedReality*",
        "*OneNote*","*People*","*SkypeApp*","*Wallet*","*YourPhone*","*Zune*"
    )
    foreach ($App in $Bloatware) {
        Get-AppxProvisionedPackage -Path $OSDisk | Where-Object {$_.DisplayName -like $App} | Remove-AppxProvisionedPackage -Path $OSDisk -ErrorAction SilentlyContinue
    }

    # --- C. Inject Autopilot Script for Audit Mode ---
    Write-Host "  > Injecting Autopilot Script..." -ForegroundColor Cyan
    $ScriptDest = "$OSDisk\Windows\Temp\AutopilotScript.ps1"
    Invoke-WebRequest -Uri $AutopilotScriptUrl -OutFile $ScriptDest -UseBasicParsing

    # --- D. Configure Audit Mode Unattend ---
    Write-Host "  > Configuring Boot to Audit Mode..." -ForegroundColor Cyan
    
    # We create a specific Unattend.xml that forces Audit Mode and runs your script
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

    Write-Host ">>> Post-Processing Complete. You may now reboot." -ForegroundColor Green
    # Optional: Automatically reboot
    # Restart-Computer -Force
} else {
    Write-Warning "OSDCloud did not complete or C:\ is not mounted. Post-processing skipped."
}
