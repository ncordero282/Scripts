# OSDCloud Creator Tool with Auto GUI Integration
# Author: Brooks Peppin + Extended by ChatGPT
# https://www.osdcloud.com/

[CmdletBinding()]
param (
    [switch]$ADK,
    [string]$workspace,
    [ValidateSet('Dell', 'HP','Nutanix','VMware','Wifi')] $WinPEDrivers,
    [switch]$New,
    [switch]$BuildISO,
    [switch]$BuildUSB,
    [string]$CustomURL,
    [switch]$LaunchGUI
)

function Install-LatestModules {
    Write-Host "Installing latest OSD module from PSGallery..."
    Install-Module -Name OSD -Force -AllowClobber

    Write-Host "Installing OSDCloudGUI module..."
    Install-Module -Name OSDCloudGUI -Force -AllowClobber
}

# Step 1: Install ADK + WinPE Add-on
if ($ADK) {
    $downloads = "$env:USERPROFILE\Downloads"
    Write-Host "Downloading ADKsetup.exe..."
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2120254" -OutFile "$downloads\adksetup.exe"

    Write-Host "Installing ADK Deployment Tools..."
    Start-Process -FilePath "$downloads\adksetup.exe" -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait

    Write-Host "Downloading ADKWinPESetup.exe..."
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2120253" -OutFile "$downloads\adkwinpesetup.exe"

    Write-Host "Installing ADK WinPE Addon..."
    Start-Process -FilePath "$downloads\adkwinpesetup.exe" -ArgumentList "/quiet /features OptionId.WindowsPreinstallationEnvironment" -Wait
}

# Step 2: Install modules and create OSDCloud template
if ($New) {
    Install-LatestModules
    Write-Host "Creating new OSDCloud template..."
    New-OSDCloud.Template -Verbose
}

# Step 3: Create OSDCloud Workspace
if ($workspace) {
    Write-Host "Creating OSDCloud workspace at: $workspace"
    New-OSDCloud.Workspace -WorkspacePath $workspace
}

# Step 4: Define GUI startup script (hosted raw)
$GUIStartupScript = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/StartOSDCloudGUI.ps1?token=GHSAT0AAAAAADIEHMUQ4HLJVEREIKVGHLE42EHNK4Q"

# Step 5: Inject WinPE Drivers + Required Modules + GUI Startup Script
if ($WinPEDrivers) {
    Write-Host "Injecting WinPE drivers ($WinPEDrivers) and required modules..."
    Edit-OSDCloud.WinPE -CloudDriver $WinPEDrivers -AddModule OSD,OSDCloudGUI,Microsoft.PowerShell.Archive -WebPSScript $GUIStartupScript
} else {
    Write-Host "Injecting required modules and GUI script (no drivers)..."
    Edit-OSDCloud.WinPE -AddModule OSD,OSDCloudGUI,Microsoft.PowerShell.Archive -WebPSScript $GUIStartupScript
}

# Optional: Override GUI script if user specifies one
if ($CustomURL) {
    Write-Host "Overriding default GUI script with: $CustomURL"
    Edit-OSDCloud.WinPE -WebPSScript $CustomURL
}

# Step 6: Build ISO
if ($BuildISO) {
    Write-Host "Building OSDCloud ISO..."
    New-OSDCloud.ISO
}

# Step 7: Build USB
if ($BuildUSB) {
    Write-Host "Building OSDCloud USB..."
    New-OSDCloud.USB
}

# Step 8: Launch GUI in current session (optional)
if ($LaunchGUI) {
    Write-Host "Launching OSDCloud GUI in this session..."
    Start-OSDCloudGUI
}
