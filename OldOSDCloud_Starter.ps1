<#
.SYNOPSIS
    OSDCloud starter / creator tool.

.DESCRIPTION
    - Creates or reuses an OSDCloud workspace
    - Injects WinPE CloudDrivers (e.g. Dell)
    - Configures WinPE to run a custom GUI script from a URL
    - Builds an ISO and/or USB from the workspace

.PARAMETER WorkspacePath
    Folder to use as the OSDCloud workspace (e.g. C:\Users\ncord\Desktop\NewOSDCloud)

.PARAMETER WinPEDrivers
    Manufacturer for WinPE CloudDrivers: Dell, HP, Lenovo, Microsoft, or *

.PARAMETER CustomUrl
    URL to your StartOSDCloudGUI.ps1 script (raw GitHub URL)

.PARAMETER BuildISO
    Build an ISO from the workspace.

.PARAMETER BuildUSB
    Build a USB from the workspace (you’ll be prompted for the disk).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspacePath,

    [ValidateSet('Dell','HP','Lenovo','Microsoft','*')]
    [string]$WinPEDrivers = 'Dell',

    [string]$CustomUrl,

    [switch]$BuildISO,
    [switch]$BuildUSB
)

Write-Host "==== OSDCloud Starter ====" -ForegroundColor Cyan
Write-Host "Workspace : $WorkspacePath" -ForegroundColor Cyan
Write-Host "CloudDriver: $WinPEDrivers" -ForegroundColor Cyan
if ($CustomUrl) { Write-Host "Custom GUI URL: $CustomUrl" -ForegroundColor Cyan }

# Ensure OSD module is present
if (-not (Get-Module -ListAvailable -Name OSD)) {
    Write-Host "OSD module not found. Installing from PSGallery..." -ForegroundColor Yellow
    Install-Module OSD -Force
}
Import-Module OSD -Force

# Ensure workspace folder exists
if (-not (Test-Path $WorkspacePath)) {
    Write-Host "Creating workspace folder: $WorkspacePath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $WorkspacePath -Force | Out-Null
}

# Create workspace structure if needed
if (-not (Test-Path (Join-Path $WorkspacePath 'Media'))) {
    Write-Host "Initializing new OSDCloud workspace..." -ForegroundColor Yellow
    New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
}

Set-OSDCloudWorkspace -WorkspacePath $WorkspacePath

# Build WinPE with CloudDrivers and startup script
$editParams = @{
    WorkspacePath = $WorkspacePath
    CloudDriver   = $WinPEDrivers
}

if ($CustomUrl) {
    # Use PowerShell's irm | iex instead of WebPSScript (avoids curl dependency for GUI script)
    $editParams.StartPSCommand = "irm $CustomUrl | iex"
}

Write-Host "Updating WinPE image (Edit-OSDCloudWinPE)..." -ForegroundColor Yellow
Edit-OSDCloudWinPE @editParams

# Build ISO / USB
if ($BuildISO) {
    Write-Host "Building OSDCloud ISO..." -ForegroundColor Yellow
    New-OSDCloudISO -WorkspacePath $WorkspacePath
}

if ($BuildUSB) {
    Write-Host "Building OSDCloud USB..." -ForegroundColor Yellow
    New-OSDCloudUSB -WorkspacePath $WorkspacePath
}

Write-Host "OSDCloud Starter completed." -ForegroundColor Green
