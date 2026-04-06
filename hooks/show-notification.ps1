param(
    [string]$Title = 'Claude Code',
    [string]$Message = 'Blocked',
    [string]$Command = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable modern visual styles
[System.Windows.Forms.Application]::EnableVisualStyles()

# Dark theme colors
$bgColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$fgColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
$accentColor = [System.Drawing.Color]::FromArgb(220, 50, 50)
$cmdBgColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$btnBgColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$btnHoverColor = [System.Drawing.Color]::FromArgb(75, 75, 75)

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.Size = New-Object System.Drawing.Size(620, 280)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.BackColor = $bgColor
$form.ForeColor = $fgColor
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# Red accent bar at top
$bar = New-Object System.Windows.Forms.Panel
$bar.Location = New-Object System.Drawing.Point(0, 0)
$bar.Size = New-Object System.Drawing.Size(620, 4)
$bar.BackColor = $accentColor
$form.Controls.Add($bar)

# Icon
$icon = New-Object System.Windows.Forms.Label
$icon.Location = New-Object System.Drawing.Point(20, 20)
$icon.Size = New-Object System.Drawing.Size(36, 36)
$icon.Font = New-Object System.Drawing.Font('Segoe UI', 20)
$icon.ForeColor = $accentColor
$icon.Text = [char]0x26A0
$form.Controls.Add($icon)

# Message
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(62, 22)
$label.Size = New-Object System.Drawing.Size(530, 35)
$label.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$label.ForeColor = $fgColor
$label.Text = $Message
$form.Controls.Add($label)

# Command textbox
if ($Command) {
    $cmdBox = New-Object System.Windows.Forms.TextBox
    $cmdBox.Location = New-Object System.Drawing.Point(20, 65)
    $cmdBox.Size = New-Object System.Drawing.Size(565, 90)
    $cmdBox.Multiline = $true
    $cmdBox.ReadOnly = $true
    $cmdBox.ScrollBars = 'Vertical'
    $cmdBox.Font = New-Object System.Drawing.Font('Cascadia Code, Consolas', 12)
    $cmdBox.Text = $Command
    $cmdBox.BackColor = $cmdBgColor
    $cmdBox.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $cmdBox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($cmdBox)
}

# Helper: style a button
function Style-Button($btn) {
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $btn.FlatAppearance.BorderSize = 1
    $btn.BackColor = $btnBgColor
    $btn.ForeColor = $fgColor
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_MouseEnter({ $this.BackColor = $btnHoverColor })
    $btn.Add_MouseLeave({ $this.BackColor = $btnBgColor })
}

# OK button
$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Location = New-Object System.Drawing.Point(220, 195)
$btnOk.Size = New-Object System.Drawing.Size(90, 32)
$btnOk.Text = 'OK'
$btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
Style-Button $btnOk
$form.Controls.Add($btnOk)
$form.AcceptButton = $btnOk

# Open Log button
$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Location = New-Object System.Drawing.Point(320, 195)
$btnLog.Size = New-Object System.Drawing.Size(110, 32)
$btnLog.Text = 'Open Log'
Style-Button $btnLog
$btnLog.Add_Click({
    $logFile = Join-Path $PSScriptRoot 'hook-blocks.log'
    if (Test-Path $logFile) {
        Invoke-Item $logFile
    }
})
$form.Controls.Add($btnLog)

$form.ShowDialog() | Out-Null
$form.Dispose()
