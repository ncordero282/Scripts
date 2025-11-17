# Minimal OSDCloud GUI launcher
# - Picks the best drive (not X:) for OSDCloud working folder
# - Launches Start-OSDCloudGUI only
# - NO WindowsUpdate, NO Autopilot yet (we'll add later once this is stable)

Start-Transcript -Path X:\Windows\Temp\OSDCloud.log -Force

# Ensure OSD module is loaded
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import OSD module: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

# ---------------------------------------------
# Pick the best drive for OSDCloud working path
# ---------------------------------------------
# Avoid X: (RAM disk) because it's too small for WIMs and driver packs
# Prefer the drive with the most free space
try {
    $drives = Get-PSDrive -PSProvider FileSystem |
              Where-Object { $_.Name -ne 'X' -and $_.Free -gt 5GB }

    if ($drives) {
        $best = $drives | Sort-Object Free -Descending | Select-Object -First 1
        $OSDCloudRoot = "$($best.Name):\OSDCloud"
    } else {
        # Fallback to C:\OSDCloud if no big drives detected
        $OSDCloudRoot = "C:\OSDCloud"
    }

    Write-Host "Using OSDCloud working folder: $OSDCloudRoot" -ForegroundColor Cyan
    $env:OSDCloudPath = $OSDCloudRoot

    if (-not (Test-Path $OSDCloudRoot)) {
        New-Item -ItemType Directory -Path $OSDCloudRoot -Force | Out-Null
    }
} catch {
    Write-Host "Failed to evaluate working drive. Falling back to C:\OSDCloud. Error: $_" -ForegroundColor Yellow
    $env:OSDCloudPath = "C:\OSDCloud"
    if (-not (Test-Path "C:\OSDCloud")) {
        New-Item -ItemType Directory -Path "C:\OSDCloud" -Force | Out-Null
    }
}

# ---------------------------------------------
# Show basic model info (just informational)
# ---------------------------------------------
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $Manufacturer = $cs.Manufacturer
    $Model        = $cs.Model
} catch {
    $Manufacturer = "Unknown"
    $Model        = "Unknown"
}

Write-Host "Manufacturer: $Manufacturer"
Write-Host "Model       : $Model"

# ---------------------------------------------
# Launch the built-in OSDCloud GUI
# ---------------------------------------------
Write-Host "Launching OSDCloud GUI..." -ForegroundColor Cyan
try {
    Start-OSDCloudGUI
} catch {
    Write-Host "Start-OSDCloudGUI failed: $_" -ForegroundColor Red
    Stop-Transcript
    return
}

Write-Host "OSDCloud GUI has exited." -ForegroundColor Cyan
Write-Host "If deployment finished successfully, you can reboot with:" -ForegroundColor Yellow
Write-Host "  wpeutil reboot" -ForegroundColor Yellow

Stop-Transcript
