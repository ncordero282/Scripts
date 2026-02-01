# --- 1. THE "EXPLORER CHECK" (Fixes Timing) ---
Write-Host "Setup initialized..." -ForegroundColor Yellow
Write-Host "Waiting for Desktop (Explorer.exe)..." -NoNewline

# Loop forever until the Desktop Taskbar is actually running
while (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 2
    Write-Host "." -NoNewline
}
Write-Host " [Found]" -ForegroundColor Green

# Add 10 seconds of pure padding just to be safe
Write-Host "Stabilizing..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# ----------------------------------------

# --- 3. AUTOPILOT LOGIC ---
$global:clientId = "7ee59b78-92d6-45e0-a2d9-a530fecbd6d3"
$global:authUrl = "https://login.microsoftonline.com/nyco365.onmicrosoft.com"
$global:resource = "https://graph.microsoft.com/"
$global:webhookurl = "https://80251b4f-5295-4911-a0d0-3e0e3692a407.webhook.eus2.azure-automation.net/webhooks?token=Z1srgtPU1t8r55KAysdUVYEESJ88TwPwuld4MqYtyjs%3d%22"

$global:Devicecode = $null
$global:Token = $null

function Request-DeviceCode {
    if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
        Write-Host "Please run PowerShell in elevated mode"
        return
    }

    $postParams = @{ resource = "$global:resource"; client_id = "$global:clientId" }
    try {
        $DevicecodeResponse = Invoke-RestMethod -Method POST -Uri "$global:authUrl/oauth2/devicecode" -Body $postParams
        $global:Devicecode = $DevicecodeResponse
        Write-Host "From your managed device, " $DevicecodeResponse.message

        # Open Edge in InPrivate mode
        Start-Process "msedge.exe" -ArgumentList "https://microsoft.com/devicelogin --inprivate"

        # Prompt the user to enter the code at the opened URL
        Write-Host "Please enter the code at the opened URL: $($DevicecodeResponse.user_code)"
        Read-Host "Press Enter after you have entered the code to continue..."
    } catch {
        Write-Error "Failed to request device code. Check internet connection."
    }
}

function Get-Token {
    $tokenParams = @{ grant_type = "device_code"; resource = "$global:resource"; client_id = "$global:clientId"; code = "$($global:Devicecode.device_code)" }
    try {
        $tokenResponse = Invoke-RestMethod -Method POST -Uri "$global:authUrl/oauth2/token" -Body $tokenParams
        $global:Token = $tokenResponse
    } catch {
        Write-Host "Failed to obtain token. Please check your network connection or credentials."
        return
    }
}

function SendTo-Autopilot {
    Get-Token

    if ($Global:Token -eq $null) {
        Write-Host "You didn't authenticate to Azure AD, please start over."
        return
    }

    if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
        Write-Host "Please run PowerShell in elevated mode"
        return
    }

    $DeviceHashData = (Get-WmiObject -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
    $SerialNumber = (Get-WmiObject -Class "Win32_BIOS" -Verbose:$false).SerialNumber
    Write-Host "Device Serial Number: " $SerialNumber

    $id_token = $global:Token.id_token
    $token_type = $global:Token.token_type
    $access_token = $global:Token.access_token
    $body = @{ 
        "SerialNumber" = "$SerialNumber"; 
        "DeviceHashData" = "$DeviceHashData"; 
        "token_type" = "$token_type"; 
        "id_token" = "$id_token"; 
        "access_token" = "$access_token"; 
    }

    $params = @{
        ContentType = 'application/json'
        Headers = @{ 'Date' = "$(Get-Date)"; }
        Body = ($body | ConvertTo-Json)
        Method = 'Post'
        URI = $global:webhookurl
    }

    try {
        Invoke-RestMethod @params
        Start-Sleep -Seconds 3
        Write-Host "Email will be sent in a few minutes to your email address." 
    } catch {
        Write-Host "Failed to send data to Autopilot. Please check your network connection or try again later."
    }
}

# --- EXECUTION ---
Request-DeviceCode
SendTo-Autopilot
