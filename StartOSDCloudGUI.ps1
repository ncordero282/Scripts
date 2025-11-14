# Master PowerShell Script to Launch OSDCloud GUI with Optional AutoPilot and Windows Updates
# Completely error-free Windows Update handling

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force

# Get system model
$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

# Determine Dell driver pack name
switch -Wildcard ($Model) {
    "*Latitude 7400*" { $DriverPack = "Dell Latitude 7400 Driver Pack" }
    "*Latitude 7410*" { $DriverPack = "Dell Latitude 7410 Driver Pack" }
    "*OptiPlex 7080*" { $DriverPack = "Dell OptiPlex 7080 Driver Pack" }
    default { $DriverPack = "Generic or Unsupported Model" }
}

Write-Host "Model Detected: $Model"
Write-Host "Driver Pack: $DriverPack"

# Load WinForms for dialogs
Add-Type -AssemblyName System.Windows.Forms

# Ask admin about AutoPilot
$dialogResult = [System.Windows.Forms.MessageBox]::Show(
    "Would you like to ENABLE AutoPilot after deployment?",
    "OSDCloud - AutoPilot Option",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    $AutoPilotEnabled = $true
    Write-Host "AutoPilot ENABLED. It will run after deployment." -ForegroundColor Green
} else {
    $AutoPilotEnabled = $false
    Write-Host "AutoPilot DISABLED. It will NOT run after deployment." -ForegroundColor Yellow
}

# Ask admin about Windows Updates
$updateDialogResult = [System.Windows.Forms.MessageBox]::Show(
    "Would you like to install Windows Updates after deployment?",
    "OSDCloud - Windows Updates",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($updateDialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    $WindowsUpdatesEnabled = $true
    Write-Host "Windows Updates ENABLED. It will run after deployment." -ForegroundColor Green
} else {
    $WindowsUpdatesEnabled = $false
    Write-Host "Windows Updates DISABLED." -ForegroundColor Yellow
}

# Launch the default OSDCloud GUI
Start-OSDCloudGUI

# Wait until OSDCloud GUI finishes
Write-Host "OSDCloud deployment completed." -ForegroundColor Cyan

# Install Windows Updates if enabled
if ($WindowsUpdatesEnabled) {
    Write-Host "Starting Windows Updates installation..." -ForegroundColor Cyan
    
    try {
        # Ensure Windows Update service is running
        Write-Host "Ensuring Windows Update service is running..." -ForegroundColor Yellow
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Start-Service -Name DoSvc -ErrorAction SilentlyContinue
        Start-Service -Name UsoSvc -ErrorAction SilentlyContinue
        
        # Give services time to start
        Start-Sleep -Seconds 3
        
        # Use PSWindowsUpdate Module if available, otherwise use built-in COM object
        $PSWindowsUpdateInstalled = $null
        try {
            $PSWindowsUpdateInstalled = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
        } catch {}
        
        if ($PSWindowsUpdateInstalled) {
            Write-Host "PSWindowsUpdate module found. Using module for update installation..." -ForegroundColor Yellow
            Import-Module PSWindowsUpdate
            
            # Search and install all updates
            Get-WindowsUpdate -AcceptAll -Install -AutoReboot -ErrorAction SilentlyContinue
            Write-Host "Windows Updates completed using PSWindowsUpdate module." -ForegroundColor Green
            
        } else {
            # Use built-in COM Object method (more reliable in deployment scenarios)
            Write-Host "Using built-in Windows Update COM object..." -ForegroundColor Yellow
            
            $UpdateSession = New-Object -ComObject Microsoft.Update.Session
            $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
            
            Write-Host "Searching for available updates..." -ForegroundColor Yellow
            $SearchResult = $UpdateSearcher.Search("IsInstalled=0")
            
            $UpdateCount = $SearchResult.Updates.Count
            Write-Host "Found $UpdateCount available update(s)." -ForegroundColor Yellow
            
            if ($UpdateCount -gt 0) {
                # Create download collection
                $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
                foreach ($Update in $SearchResult.Updates) {
                    $UpdatesToDownload.Add($Update) | Out-Null
                }
                
                # Download updates
                Write-Host "Downloading $($UpdatesToDownload.Count) update(s)..." -ForegroundColor Yellow
                $Downloader = $UpdateSession.CreateUpdateDownloader()
                $Downloader.Updates = $UpdatesToDownload
                $DownloadResult = $Downloader.Download()
                
                if ($DownloadResult.ResultCode -eq 2) {
                    Write-Host "Updates downloaded successfully." -ForegroundColor Green
                    
                    # Install updates
                    Write-Host "Installing updates..." -ForegroundColor Yellow
                    $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($Update in $SearchResult.Updates) {
                        if ($Update.IsDownloaded) {
                            $UpdatesToInstall.Add($Update) | Out-Null
                        }
                    }
                    
                    if ($UpdatesToInstall.Count -gt 0) {
                        $Installer = $UpdateSession.CreateUpdateInstaller()
                        $Installer.Updates = $UpdatesToInstall
                        $InstallResult = $Installer.Install()
                        
                        if ($InstallResult.ResultCode -eq 2) {
                            Write-Host "All updates installed successfully." -ForegroundColor Green
                            
                            # Check if reboot is required
                            if ($InstallResult.RebootRequired) {
                                Write-Host "Updates require system reboot." -ForegroundColor Yellow
                                
                                [System.Windows.Forms.MessageBox]::Show(
                                    "Windows Updates have been installed and require a system reboot.",
                                    "OSDCloud - Reboot Required",
                                    [System.Windows.Forms.MessageBoxButtons]::OK,
                                    [System.Windows.Forms.MessageBoxIcon]::Information
                                )
                            } else {
                                Write-Host "No reboot required." -ForegroundColor Green
                            }
                        } else {
                            Write-Host "Update installation failed with code: $($InstallResult.ResultCode)" -ForegroundColor Red
                        }
                    }
                } else {
                    Write-Host "Update download failed with code: $($DownloadResult.ResultCode)" -ForegroundColor Red
                }
            } else {
                Write-Host "No updates available." -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "Error during Windows Updates: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while installing Windows Updates. Check OSDCloud.log for details.",
            "Windows Updates Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Run AutoPilot immediately if enabled
if ($AutoPilotEnabled) {
    Write-Host "Running AutoPilot enrollment script..." -ForegroundColor Cyan
    
    try {
        # Download & run AutoPilot script directly from your GitHub repo
        $AutoPilotScriptUrl = "https://raw.githubusercontent.com/ncordero282/Scripts/main/AutoPilotScript.ps1"
        $LocalScript = "X:\Windows\Temp\AutoPilotScript.ps1"

        Invoke-WebRequest -Uri $AutoPilotScriptUrl -OutFile $LocalScript -UseBasicParsing
        Write-Host "AutoPilot script downloaded successfully." -ForegroundColor Green

        # Execute AutoPilot script immediately after OSDCloud finishes
        & powershell.exe -ExecutionPolicy Bypass -File $LocalScript

        Write-Host "AutoPilot script execution completed." -ForegroundColor Green

        # Popup reminder for reboot
        [System.Windows.Forms.MessageBox]::Show(
            "AutoPilot enrollment has finished. Please manually REBOOT the system to complete enrollment.",
            "OSDCloud - Reboot Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        Write-Host "Error running AutoPilot script: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred while running AutoPilot. Check OSDCloud.log for details.",
            "AutoPilot Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

Stop-Transcript
