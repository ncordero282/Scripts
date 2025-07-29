# Master PowerShell Script to Launch OSDCloud GUI with Customization and AutoPilot Notice

Start-Transcript -Path X:\Windows\Temp\OSDCloudGUI.log -Force

# Get system model
$Model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model

# Determine Dell driver pack name
switch -Wildcard ($Model) {
    "*Latitude 7400*" { $DriverPack = "Dell Latitude 7400 Driver Pack" }
    "*Latitude 7410*" { $DriverPack = "Dell Latitude 7410 Driver Pack" }
    "*OptiPlex 7080*" { $DriverPack = "Dell OptiPlex 7080 Driver Pack" }
    default { $DriverPack = "Generic or Unsupported Model" }
}

# Autopilot status message
$AutoPilotEnabled = $true
$AutoPilotStatus = if ($AutoPilotEnabled) {
    "AutoPilot is ENABLED and will run after deployment."
} else {
    "AutoPilot is NOT enabled."
}

# Load WinForms for simple GUI
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "OSDCloud GUI"
$form.Width = 550
$form.Height = 300
$form.StartPosition = "CenterScreen"

$labelTitle = New-Object System.Windows.Forms.Label
$labelTitle.Text = "Welcome to OSDCloud Deployment"
$labelTitle.Font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)
$labelTitle.AutoSize = $true
$labelTitle.Location = New-Object System.Drawing.Point(20,20)
$form.Controls.Add($labelTitle)

$labelModel = New-Object System.Windows.Forms.Label
$labelModel.Text = "Model Detected: $Model"
$labelModel.Location = New-Object System.Drawing.Point(20,70)
$labelModel.AutoSize = $true
$form.Controls.Add($labelModel)

$labelDriver = New-Object System.Windows.Forms.Label
$labelDriver.Text = "Driver Pack: $DriverPack"
$labelDriver.Location = New-Object System.Drawing.Point(20,100)
$labelDriver.AutoSize = $true
$form.Controls.Add($labelDriver)

$labelAutoPilot = New-Object System.Windows.Forms.Label
$labelAutoPilot.Text = $AutoPilotStatus
$labelAutoPilot.ForeColor = 'Green'
$labelAutoPilot.Location = New-Object System.Drawing.Point(20,130)
$labelAutoPilot.AutoSize = $true
$form.Controls.Add($labelAutoPilot)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = "Start OSDCloud GUI"
$buttonStart.Width = 200
$buttonStart.Height = 30
$buttonStart.Location = New-Object System.Drawing.Point(20,180)
$buttonStart.Add_Click({
    $form.Close()
    Start-OSDCloudGUI
})
$form.Controls.Add($buttonStart)

$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

Stop-Transcript
