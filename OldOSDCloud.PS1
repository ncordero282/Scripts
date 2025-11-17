# Clear screen and start message
Write-Host "Starting Brooks' Custom OSDCloud ..." -ForegroundColor Yellow
Clear-Host

# Display main menu
Write-Host "===================== Main Menu =======================" -ForegroundColor Yellow
Write-Host "================ Nelson Cordero =================" -ForegroundColor Yellow
Write-Host "====================NYC Parks=====================" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "1: Zero-Touch Win10 24H2 | English | Enterprise" -ForegroundColor Yellow
Write-Host "2: Zero-Touch Win10 25H2 | English | Enterprise" -ForegroundColor Yellow
Write-Host "3: I'll select it myself" -ForegroundColor Yellow
Write-Host "4: Exit`n" -ForegroundColor Yellow

# Get user input
$input = Read-Host "Please make a selection"

# Execute based on user input
switch ($input) {
    '1' {
        Write-Host "Loading OSDCloud..." -ForegroundColor Yellow
        Start-OSDCloud -OSLanguage en-us -OSBuild 24H2 -OSEdition Enterprise -ZTI
        break
    }
    '2' {
        Write-Host "Loading OSDCloud..." -ForegroundColor Yellow
        Start-OSDCloud -OSLanguage en-us -OSBuild 25H2 -OSEdition Enterprise -ZTI
        break
    }
    '3' {
        Write-Host "Loading OSDCloud..." -ForegroundColor Yellow
        Start-OSDCloud
        break
    }
    '4' {
        Write-Host "Exiting script..." -ForegroundColor Yellow
        exit
        break  # This line is redundant but ensures clarity
    }
    default {
        Write-Host "Invalid selection. Please choose from 1 to 4." -ForegroundColor Red
        break
    }
}

# Consider the context for reboot command, if running in a WinPE environment
# wpeutil reboot
