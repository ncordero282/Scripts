# OSDCloud Creator Tool with GUI Auto-Launch and Cleaned Parameters
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
    Write-Host "Installing latest OSD and OSDCloudGUI modules..."

    try {
        Install-Module -Name OSD -Force -AllowClobber -ErrorAction Stop
        Install-Module -Name OSDCloudGUI -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Error "❌ Failed to install one or both modules from PSGallery. Check your internet connection or NuGet settings."
        exit 1
    }

    try {
        Import-Module OSD -Force -ErrorAction Stop
        Import-Module OSDCloudGUI -Force -ErrorAction Stop
    } catch {
        Write-Error "❌ Modules were installed, but failed to import into this session. Try running PowerShell as Administrator."
        exit 1
    }

    if (-not (Get-Command New-OSDCloudWorkspace -ErrorAction SilentlyContinue)) {
        Write-Error "❌ 'OSD' module is installed but its cmdlets are not available in this session. Check for conflicting environments or OneDrive restrictions."
        exit 1
    }

    Write-Host "✅ Modules installed and imported successfully.`n"
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

# Step 2: Install and import modules, and create OSDCloud template
if ($New) {
    Install-LatestModules
    Write-Host "Creating new OSDCloud template..."
    New-OSDCloudTemplate -Verbose
}

# Step 3: Create OSDCloud Workspace
if ($workspace) {
    Write-Host "Creating OSDCloud workspace at: $workspace"
    New-OSDCloudWorkspace -WorkspacePath $workspace
}

# Step 4: Define GUI startup script (hosted raw)
$GUIStartupScript = "https://raw.githubusercontent.com/ncordero282/Scripts/refs/heads/main/StartOSDCloudGUI.ps1?token=GHSAT0AAAAAADIEHMUQ4HLJVEREIKVGHLE42EHNK4Q"

# Step 5: Inject WinPE Drivers + GUI Startup Script (no -AddModule)
if ($WinPEDrivers) {
    Write-Host "Injecting WinPE drivers ($WinPEDrivers) and GUI startup script..."
    Edit-OSDCloudWinPE -CloudDriver $WinPEDrivers -WebPSScript $GUIStartupScript
} else {
    Write-Host "Injecting GUI startup script only (no drivers)..."
    Edit-OSDCloudWinPE -WebPSScript $GUIStartupScript
}

# Optional: Override GUI script if user provides one
if ($CustomURL) {
    Write-Host "Overriding default GUI script with: $CustomURL"
    Edit-OSDCloudWinPE -WebPSScript $CustomURL
}

# Step 6: Build ISO
if ($BuildISO) {
    Write-Host "Building OSDCloud ISO..."
    New-OSDCloudISO
}

# Step 7: Build USB
if ($BuildUSB) {
    Write-Host "Building OSDCloud USB..."
    New-OSDCloudUSB
}

# Step 8: Launch GUI in current session (optional)
if ($LaunchGUI) {
    Write-Host "Launching OSDCloud GUI in this session..."
    Start-OSDCloudGUI
}
