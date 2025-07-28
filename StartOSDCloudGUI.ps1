Write-Host -ForegroundColor Yellow "Starting Custom OSDCloud Deployment ..."
cls
Write-Host "==================== NYC IT Deployment ====================" -ForegroundColor Yellow
Write-Host "============= Powered by OSDCloud + Brooks =================" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "1: Zero-Touch Win11 24H2 | English | Enterprise" -ForegroundColor Yellow
Write-Host "2: Manual OS Selection (GUI)" -ForegroundColor Yellow
Write-Host "3: Exit`n" -ForegroundColor Yellow

$input = Read-Host "Please make a selection"

# ========== Setup ==========

Import-Module OSD -Force
Install-Module OSD -Force

# ========== Detect Dell Model + Download Drivers ==========

$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
Write-Host "`nDetected Dell Model: $Model" -ForegroundColor Cyan

try {
    Start-OSDDellDriverPackDownload -Model $Model -OperatingSystem 'Windows 11 x64'
} catch {
    Write-Warning "Driver download failed for model: $Model"
}

# ========== Run AutoPilot Script (Webhook) ==========

Start-Transcript -Path "X:\Generated Hash Keys\AutoPilotLog.txt"
Set-ExecutionPolicy Bypass -Scope Process -Force

$global:clientId = "7ee59b78-92d6-45e0-a2d9-a530fecbd6d3"
$global:authUrl = "https://login.microsoftonline.com/nyco365.onmicrosoft.com"
$global:resource = "https://graph.microsoft.com/"
$global:webhookurl = "https://80251b4f-5295-4911-a0d0-3e0e3692a407.webhook.eus2.azure-automation.net/webhooks?token=5j%2fr5ZMAMeRUkkFHI7Qpg%2b22tru%2f6Z%2f4Hb54CjlUflg%3d"
$global:Devicecode = $null
$global:Token = $null

function Request-DeviceCode {
    $postParams = @{ resource = "$global:resource"; client_id = "$global:clientId" }
    $DevicecodeResponse = Invoke-RestMethod -Method POST -Uri "$global:authUrl/oauth2/devicecode" -Body $postParams
    $global:Devicecode = $DevicecodeResponse
    Write-Host "`nFrom your managed device, $($DevicecodeResponse.message)" -ForegroundColor Green
}

function Get-Token {
    $tokenParams = @{ grant_type = "device_code"; resource = "$global:resource"; client_id = "$global:clientId"; code = "$($global:Devicecode.device_code)" }
    $tokenResponse = Invoke-RestMethod -Method POST -Uri "$global:authUrl/oauth2/token" -Body $tokenParams
    $global:Token = $tokenResponse
}

function SendTo-Autopilot {
    Get-Token
    $DeviceHashData = (Get-WmiObject -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
    $SerialNumber = (Get-WmiObject -Class "Win32_BIOS").SerialNumber

    if ($DeviceHashData -eq $null -or $SerialNumber -eq $null) {
        Write-Host "Failed to get DeviceHardwareData or SerialNumber" -ForegroundColor Red
        return
    }

    Write-Host "Device Serial Number: $SerialNumber" -ForegroundColor Green

    $body = @{ 
        "SerialNumber" = "$SerialNumber"; 
        "DeviceHashData" = "$DeviceHashData"; 
        "token_type" = "$($global:Token.token_type)"; 
        "id_token" = "$($global:Token.id_token)"; 
        "access_token" = "$($global:Token.access_token)";
    }

    $params = @{
        ContentType = 'application/json'
        Headers = @{ 'Date' = "$(Get-Date)" }
        Body = ($body | ConvertTo-Json)
        Method = 'Post'
        URI = $global:webhookurl
    }

    Invoke-RestMethod @params
    Start-Sleep -Seconds 3
    Write-Host "Confirmation email will be sent shortly. Wait before continuing." -ForegroundColor Green
}

Request-DeviceCode
Read-Host "`nPress ENTER after logging in with the device code above..."
SendTo-Autopilot
Stop-Transcript

# ========== Handle Menu Selections ==========

switch ($input) {
    '1' {
        # Deploy Win11 24H2 Enterprise in Zero-Touch mode
        Start-OSDCloud -OSLanguage en-us -OSBuild 24H2 -OSEdition Enterprise -ZTI

        # ========== Post-Install: Run Windows Updates ==========
        Write-Host "`nInstalling Windows updates..." -ForegroundColor Cyan
        try {
            Install-PackageProvider -Name NuGet -Force
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber
            Import-Module PSWindowsUpdate
            Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -Verbose
            Restart-Computer -Force
        } catch {
            Write-Warning "Windows Update process failed: $_"
        }
    }
    '2' {
        Start-OSDCloudGUI
    }
    '3' {
        Exit
    }
}

wpeutil reboot
