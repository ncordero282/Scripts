#OSDCloud creator tool
# OSDCloud module created by David Segura
# https://osdcloud.osdeploy.com/get-started
# 
#--------------------------------------------
#----------------Pre-Reqs--------------------
#--------------------------------------------
[CmdletBinding()]
param(
    [string]$ScriptPath,
    [switch]$BuildIso
)

# Check if ScriptPath is provided and execute OSDCloud.ps1 if valid
if ($ScriptPath) {
    & $ScriptPath
}

param (
    [switch]$ADK,
    [string]$workspace,
    [ValidateSet('Dell', 'HP','Nutanix','VMware','Wifi')]
    $WinPEDrivers,
    [switch]$New,
    [switch]$BuildISO,
    $CustomURL,
    [switch]$BuildUSB
)



#Install Win11 ADK and WinPE ADK
If($ADK){
    Write-Host "Downloading ADKsetup.exe..."
    $downloads = "$env:USERPROFILE\downloads"
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2271337" -OutFile $downloads\adksetup.exe
    
    Write-Host "Installing ADK for Windows 11"
    start-process -FilePath "$downloads\adksetup.exe" -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait
    
    Write-Host "Downloading ADKWinpesetup.exe..."
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2271338" -OutFile $downloads\adkwinpesetup.exe
    Write-Host "Installing ADK WinPE for Windows 11"
    start-process -FilePath "$downloads\adkwinpesetup.exe" -ArgumentList "/quiet /features OptionId.WindowsPreinstallationEnvironment" -Wait
}

if($New){
    Write-Host "Installing OSDCloud Powershell Module"
    Install-Module OSD -Force
    
    Write-Host "Setting up OSDCloud template..."
    New-OSDCloudtemplate -Verbose

}
if($workspace){

    New-OSDCloudworkspace -WorkspacePath $workspace
}

if ($WinPEDrivers) {
    Edit-OSDCloudwinpe -CloudDriver $WinPEDrivers
}

if($CustomURL){
    Edit-OSDCloudwinpe -WebPSScript $CustomURL 
}
if($BuildISO){
    New-OSDCloudiso
}

if($BuildUSB){
    New-OSDCloudusb
}
