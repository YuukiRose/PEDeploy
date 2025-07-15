# Import required modules
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
    Import-Module "$PSScriptRoot\..\Imaging\ImageCapture.psm1" -Force -ErrorAction Stop
    Import-Module "$PSScriptRoot\..\Core\DeviceInformation.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import required modules: $_" -ForegroundColor Red
    throw "Required modules not found"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ScreenResolution {
    [CmdletBinding()]
    param()
    
    try {
        # Get primary screen resolution
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        
        Write-LogMessage "ImageCapture: Detected screen resolution: ${screenWidth}x${screenHeight}" "INFO"
        
        # Calculate scaling factors based on common base resolution (1920x1080)
        $baseWidth = 1920
        $baseHeight = 1080
        
        $scaleFactorX = $screenWidth / $baseWidth
        $scaleFactorY = $screenHeight / $baseHeight
        
        # Use the smaller scale factor to maintain aspect ratio
        $scaleFactor = [Math]::Min($scaleFactorX, $scaleFactorY)
        
        # Set minimum and maximum scale limits - increased minimum from 0.8 to 1.0
        $scaleFactor = [Math]::Max(1.0, [Math]::Min(2.0, $scaleFactor))
        
        Write-LogMessage "ImageCapture: Calculated UI scale factor: $scaleFactor" "INFO"
        
        return @{
            Width = $screenWidth
            Height = $screenHeight
            ScaleFactor = $scaleFactor
            ScaleX = $scaleFactorX
            ScaleY = $scaleFactorY
        }
    }
    catch {
        Write-LogMessage "ImageCapture: Error detecting screen resolution: $_" "WARNING"
        # Return default values if detection fails
        return @{
            Width = 1920
            Height = 1080
            ScaleFactor = 1.0
            ScaleX = 1.0
            ScaleY = 1.0
        }
    }
}

function Scale-UIElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Value,
        
        [Parameter(Mandatory)]
        [double]$ScaleFactor
    )
    
    return [int]($Value * $ScaleFactor)
}

function Show-ImageCaptureMenu {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "=== Image Capture Menu ===" "INFO"
        
        # Detect screen resolution and calculate scaling
        $screenInfo = Get-ScreenResolution
        $scaleX = $screenInfo.Width / 1280.0
        $scaleY = $screenInfo.Height / 800.0
        $scale = [Math]::Min($scaleX, $scaleY)
        $scale = [Math]::Min($scale, 1.5)
        $scale = [Math]::Max($scale, 0.7)

        Write-LogMessage "ImageCapture: Using aspect-ratio aware UI scale: $scale for screen $($screenInfo.Width)x$($screenInfo.Height)" "INFO"

        # Scale font sizes based on resolution
        $baseFontSize = 9
        $titleFontSize = 16
        $buttonFontSize = 9
        $groupFontSize = 9

        $scaledBaseFontSize = [Math]::Max(8, [int]($baseFontSize * $scale))
        $scaledTitleFontSize = [Math]::Max(12, [int]($titleFontSize * $scale))
        $scaledButtonFontSize = [Math]::Max(8, [int]($buttonFontSize * $scale))
        $scaledGroupFontSize = [Math]::Max(8, [int]($groupFontSize * $scale))

        # Create main form with scaled dimensions - made resizable
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Windows Image Capture Tool"
        $form.Size = New-Object System.Drawing.Size([int](650 * $scale), [int](850 * $scale))
        $form.MinimumSize = New-Object System.Drawing.Size([int](600 * $scale), [int](800 * $scale))
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "Sizable"
        $form.MaximizeBox = $true
        $form.MinimizeBox = $true
        $form.BackColor = [System.Drawing.Color]::FromArgb(234,247,255)

        # TableLayoutPanel for main layout
        $mainTable = New-Object System.Windows.Forms.TableLayoutPanel
        $mainTable.Dock = 'Fill'
        $mainTable.ColumnCount = 1
        $mainTable.RowCount = 8
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 90 $scale)))) # Logo/title
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 80 $scale)))) # Customer
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 140 $scale)))) # Image ID
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 80 $scale)))) # Source
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 120 $scale)))) # Options
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 80 $scale)))) # Status
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) # Spacer
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 50 $scale)))) # Buttons

        # --- Row 0: Logo and Title ---
        $headerPanel = New-Object System.Windows.Forms.Panel
        $headerPanel.Dock = 'Fill'
        $headerPanel.BackColor = [System.Drawing.Color]::Transparent
        $logoPictureBox = New-Object System.Windows.Forms.PictureBox
        $logoPictureBox.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 80 $scale))
        $logoPictureBox.Location = New-Object System.Drawing.Point(10, 5)
        $logoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        try {
            $logoPath = "Y:\\DeploymentModules\\Assets\\Logo\\SHI.png"
            if (Test-Path $logoPath) {
                $logoPictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
            }
        } catch {}
        $headerPanel.Controls.Add($logoPictureBox)
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Network Boot Image Capture"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledTitleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 140 $scale), (Scale-UIElement 20 $scale))
        $titleLabel.Size = New-Object System.Drawing.Size([int](480 * $scale), [int](30 * $scale))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $headerPanel.Controls.Add($titleLabel)
        $subtitleLabel = New-Object System.Windows.Forms.Label
        $subtitleLabel.Text = "Captures sysprepped Windows installations for deployment"
        $subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $subtitleLabel.ForeColor = [System.Drawing.Color]::Gray
        $subtitleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 140 $scale), (Scale-UIElement 50 $scale))
        $subtitleLabel.Size = New-Object System.Drawing.Size([int](480 * $scale), [int](20 * $scale))
        $subtitleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $headerPanel.Controls.Add($subtitleLabel)
        $mainTable.Controls.Add($headerPanel, 0, 0)

        # --- Row 1: Customer Selection ---
        $customerGroupBox = New-Object System.Windows.Forms.GroupBox
        $customerGroupBox.Text = "Step 1: Customer Selection"
        $customerGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $customerGroupBox.Dock = 'Fill'
        $customerLabel = New-Object System.Windows.Forms.Label
        $customerLabel.Text = "Select Customer:"
        $customerLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $customerLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $customerLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $customerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $customerGroupBox.Controls.Add($customerLabel)
        $customerComboBox = New-Object System.Windows.Forms.ComboBox
        $customerComboBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $customerComboBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 23 $scale))
        $customerComboBox.Size = New-Object System.Drawing.Size((Scale-UIElement 350 $scale), (Scale-UIElement 25 $scale))
        $customerComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $customerGroupBox.Controls.Add($customerComboBox)
        $newCustomerButton = New-Object System.Windows.Forms.Button
        $newCustomerButton.Text = "Add New"
        $newCustomerButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $newCustomerButton.Location = New-Object System.Drawing.Point((Scale-UIElement 480 $scale), (Scale-UIElement 22 $scale))
        $newCustomerButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 27 $scale))
        $newCustomerButton.BackColor = [System.Drawing.Color]::LightGreen
        $customerGroupBox.Controls.Add($newCustomerButton)
        $customers = Get-CustomerList
        foreach ($customer in $customers) { $customerComboBox.Items.Add($customer) | Out-Null }
        if ($customers.Count -gt 0) { $customerComboBox.SelectedIndex = 0 }
        $mainTable.Controls.Add($customerGroupBox, 0, 1)

        # --- Row 2: Image Identification ---
        $imageGroupBox = New-Object System.Windows.Forms.GroupBox
        $imageGroupBox.Text = "Step 2: Image Identification"
        $imageGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $imageGroupBox.Dock = 'Fill'

        # Use a TableLayoutPanel inside the group box for spacing
        $imageTable = New-Object System.Windows.Forms.TableLayoutPanel
        $imageTable.Dock = 'Fill'
        $imageTable.ColumnCount = 2
        $imageTable.RowCount = 3
        $imageTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 120 $scale))))
        $imageTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $imageTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 40 $scale))))
        $imageTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 40 $scale))))
        $imageTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 40 $scale))))
        $imageTable.Padding = '0,0,20,0'  # Add right padding for gap

        # Image ID
        $imageIdLabel = New-Object System.Windows.Forms.Label
        $imageIdLabel.Text = "Image ID:"
        $imageIdLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageIdLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageTable.Controls.Add($imageIdLabel, 0, 0)
        $imageIdTextBox = New-Object System.Windows.Forms.TextBox
        $imageIdTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageIdTextBox.Dock = 'Fill'
        $imageTable.Controls.Add($imageIdTextBox, 1, 0)

        # Image Name
        $imageNameLabel = New-Object System.Windows.Forms.Label
        $imageNameLabel.Text = "Image Name:"
        $imageNameLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageNameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageTable.Controls.Add($imageNameLabel, 0, 1)
        $imageNameTextBox = New-Object System.Windows.Forms.TextBox
        $imageNameTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageNameTextBox.Dock = 'Fill'
        $imageTable.Controls.Add($imageNameTextBox, 1, 1)

        # Description
        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = "Description:"
        $descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $descriptionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageTable.Controls.Add($descriptionLabel, 0, 2)
        $descriptionTextBox = New-Object System.Windows.Forms.TextBox
        $descriptionTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $descriptionTextBox.Dock = 'Fill'
        $imageTable.Controls.Add($descriptionTextBox, 1, 2)

        $imageGroupBox.Controls.Add($imageTable)
        $mainTable.Controls.Add($imageGroupBox, 0, 2)

        # --- Row 3: Source Configuration ---
        $sourceGroupBox = New-Object System.Windows.Forms.GroupBox
        $sourceGroupBox.Text = "Step 3: Source Configuration"
        $sourceGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $sourceGroupBox.Dock = 'Fill'
        
        # Source drive with scaled dimensions and anchoring
        $sourceDriveLabel = New-Object System.Windows.Forms.Label
        $sourceDriveLabel.Text = "Source Drive:"
        $sourceDriveLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $sourceDriveLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $sourceDriveLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $sourceDriveLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $sourceGroupBox.Controls.Add($sourceDriveLabel)
        
        $sourceDriveComboBox = New-Object System.Windows.Forms.ComboBox
        $sourceDriveComboBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $sourceDriveComboBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 23 $scale))
        $sourceDriveComboBox.Size = New-Object System.Drawing.Size((Scale-UIElement 350 $scale), (Scale-UIElement 25 $scale))
        $sourceDriveComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $sourceGroupBox.Controls.Add($sourceDriveComboBox)
        
        # Refresh drives button with scaled dimensions and anchoring
        $refreshDrivesButton = New-Object System.Windows.Forms.Button
        $refreshDrivesButton.Text = "Refresh"
        $refreshDrivesButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $refreshDrivesButton.Location = New-Object System.Drawing.Point((Scale-UIElement 480 $scale), (Scale-UIElement 22 $scale))
        $refreshDrivesButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 27 $scale))
        $refreshDrivesButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
        $sourceGroupBox.Controls.Add($refreshDrivesButton)
        
        $mainTable.Controls.Add($sourceGroupBox, 0, 3)

        # --- Row 3.5: Capture Method Selection ---
        $captureMethodGroupBox = New-Object System.Windows.Forms.GroupBox
        $captureMethodGroupBox.Text = "Capture Method"
        $captureMethodGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $captureMethodGroupBox.Dock = 'Fill'
        $captureMethodGroupBox.Height = (Scale-UIElement 60 $scale)

        $wimRadio = New-Object System.Windows.Forms.RadioButton
        $wimRadio.Text = "WIM Capture"
        $wimRadio.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $wimRadio.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 25 $scale))
        $wimRadio.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 25 $scale))
        $wimRadio.Checked = $true
        $captureMethodGroupBox.Controls.Add($wimRadio)

        $ffuRadio = New-Object System.Windows.Forms.RadioButton
        $ffuRadio.Text = "FFU Capture"
        $ffuRadio.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $ffuRadio.Location = New-Object System.Drawing.Point((Scale-UIElement 160 $scale), (Scale-UIElement 25 $scale))
        $ffuRadio.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 25 $scale))
        $ffuRadio.Checked = $false
        $captureMethodGroupBox.Controls.Add($ffuRadio)

        $mainTable.Controls.Add($captureMethodGroupBox, 0, 4)
        $mainTable.RowStyles.Insert(4, (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 60 $scale))))

        # --- Row 5: Capture Options ---
        $optionsGroupBox = New-Object System.Windows.Forms.GroupBox
        $optionsGroupBox.Text = "Step 4: Capture Options"
        $optionsGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $optionsGroupBox.Dock = 'Fill'
        
        # Compression with scaled dimensions
        $compressionLabel = New-Object System.Windows.Forms.Label
        $compressionLabel.Text = "Compression:"
        $compressionLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $compressionLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $compressionLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $compressionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $optionsGroupBox.Controls.Add($compressionLabel)
        
        $compressionComboBox = New-Object System.Windows.Forms.ComboBox
        $compressionComboBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $compressionComboBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 23 $scale))
        $compressionComboBox.Size = New-Object System.Drawing.Size((Scale-UIElement 200 $scale), (Scale-UIElement 25 $scale))
        $compressionComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $compressionComboBox.Items.AddRange(@("Maximum (slower, smaller)", "Fast (faster, larger)", "None (fastest, largest)"))
        $compressionComboBox.SelectedIndex = 0
        $optionsGroupBox.Controls.Add($compressionComboBox)
        
        # Verification options with scaled dimensions
        $verifyCheckBox = New-Object System.Windows.Forms.CheckBox
        $verifyCheckBox.Text = "Verify image integrity after capture"
        $verifyCheckBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $verifyCheckBox.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 55 $scale))
        $verifyCheckBox.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), (Scale-UIElement 25 $scale))
        $optionsGroupBox.Controls.Add($verifyCheckBox)
        
        $integrityCheckBox = New-Object System.Windows.Forms.CheckBox
        $integrityCheckBox.Text = "Perform integrity check during capture"
        $integrityCheckBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $integrityCheckBox.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 85 $scale))
        $integrityCheckBox.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), (Scale-UIElement 25 $scale))
        $optionsGroupBox.Controls.Add($integrityCheckBox)
        
        $mainTable.Controls.Add($optionsGroupBox, 0, 5)

        # --- Row 6: Status ---
        $statusGroupBox = New-Object System.Windows.Forms.GroupBox
        $statusGroupBox.Text = "Pre-Capture Status"
        $statusGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $statusGroupBox.Dock = 'Fill'
        
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Text = "Gathering device information..."
        $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $statusLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $statusLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 470 $scale), (Scale-UIElement 45 $scale))
        $statusLabel.ForeColor = [System.Drawing.Color]::Blue
        $statusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $statusGroupBox.Controls.Add($statusLabel)
        
        # Device Info button with anchoring
        $deviceInfoButton = New-Object System.Windows.Forms.Button
        $deviceInfoButton.Text = "Device Info"
        $deviceInfoButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $deviceInfoButton.Location = New-Object System.Drawing.Point((Scale-UIElement 495 $scale), (Scale-UIElement 25 $scale))
        $deviceInfoButton.Size = New-Object System.Drawing.Size((Scale-UIElement 90 $scale), (Scale-UIElement 45 $scale))
        $deviceInfoButton.BackColor = [System.Drawing.Color]::LightBlue
        $deviceInfoButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
        $statusGroupBox.Controls.Add($deviceInfoButton)
        
        $mainTable.Controls.Add($statusGroupBox, 0, 6)

        # --- Row 7: Buttons ---
        $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttonPanel.Dock = 'Right'
        $buttonPanel.FlowDirection = 'LeftToRight'
        $buttonPanel.WrapContents = $false
        $buttonPanel.Padding = '0,0,10,0'
        $buttonPanel.Height = [int](40 * $scale)
        $buttonPanel.AutoSize = $true
        $buttonPanel.AutoSizeMode = 'GrowAndShrink'

        $captureButton = New-Object System.Windows.Forms.Button
        $captureButton.Text = "Start Capture"
        $captureButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize, [System.Drawing.FontStyle]::Bold)
        $captureButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
        $captureButton.BackColor = [System.Drawing.Color]::LightGreen
        $buttonPanel.Controls.Add($captureButton)

        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
        $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
        $buttonPanel.Controls.Add($cancelButton)

        $mainTable.Controls.Add($buttonPanel, 0, 7)

        $form.Controls.Add($mainTable)

        # Debug button removed; now uses global debug value from deployment menu

        # Event handlers
        $refreshDrivesButton.Add_Click({
            RefreshDriveList -ComboBox $sourceDriveComboBox -StatusLabel $statusLabel
        })
        
        $newCustomerButton.Add_Click({
            $newCustomer = Show-NewCustomerDialog
            if ($newCustomer) {
                $customerComboBox.Items.Add($newCustomer)
                $customerComboBox.SelectedItem = $newCustomer
            }
        })
        
        # Show/hide Step 4 (optionsGroupBox) based on radio selection
        $wimRadio.Add_CheckedChanged({
            if ($wimRadio.Checked) {
                $optionsGroupBox.Visible = $true
                $optionsGroupBox.Enabled = $true
                $script:CaptureMethod = 'WIM'
            }
        })
        $ffuRadio.Add_CheckedChanged({
            if ($ffuRadio.Checked) {
                $optionsGroupBox.Visible = $false
                $optionsGroupBox.Enabled = $false
                $script:CaptureMethod = 'FFU'
            }
        })
        $optionsGroupBox.Visible = $wimRadio.Checked
        $script:CaptureMethod = if ($wimRadio.Checked) { 'WIM' } else { 'FFU' }

        $sourceDriveComboBox.Add_SelectedIndexChanged({
            UpdateCaptureStatus -SourceDrive $sourceDriveComboBox.SelectedItem -StatusLabel $statusLabel
        })
        
        $deviceInfoButton.Add_Click({
            Show-DeviceInformationDialog
        })
        
        $captureButton.Add_Click({
            Start-ImageCaptureProcess -Form $form -CustomerComboBox $customerComboBox -ImageIdTextBox $imageIdTextBox -ImageNameTextBox $imageNameTextBox -DescriptionTextBox $descriptionTextBox -SourceDriveComboBox $sourceDriveComboBox -CompressionComboBox $compressionComboBox -VerifyCheckBox $verifyCheckBox -IntegrityCheckBox $integrityCheckBox
        })
        
        $cancelButton.Add_Click({
            $form.Close()
        })
        
        # Initial load
        RefreshDriveList -ComboBox $sourceDriveComboBox -StatusLabel $statusLabel
        
        # Gather device information in background
        try {
            $deviceInfo = Get-DeviceBasicInfo
            if ($deviceInfo -and $deviceInfo.Manufacturer -and $deviceInfo.Model -and $deviceInfo.SerialNumber) {
                $statusLabel.Text = "Device: $($deviceInfo.Manufacturer) $($deviceInfo.Model) (S/N: $($deviceInfo.SerialNumber))"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
            } else {
                $statusLabel.Text = "Warning: Could not gather complete device information"
                $statusLabel.ForeColor = [System.Drawing.Color]::Orange
            }
        } catch {
            $statusLabel.Text = "Warning: Could not gather device information"
            $statusLabel.ForeColor = [System.Drawing.Color]::Orange
            Write-LogMessage "Failed to gather device info: $_" "WARNING"
        }
        
        # Show form
        $result = $form.ShowDialog()
        $form.Dispose()
        
    } catch {
        Write-LogMessage "Error in Image Capture Menu: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function RefreshDriveList {
    param(
        [System.Windows.Forms.ComboBox]$ComboBox,
        [System.Windows.Forms.Label]$StatusLabel
    )
    
    try {
        $ComboBox.Items.Clear()
        
        # Get all drives but exclude X: and other system drives
        $excludedDrives = @('X', 'A', 'B')  # Exclude X: drive and floppy drives
        
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { 
            $_.Used -gt 0 -and 
            (Test-Path "$($_.Name):\Windows") -and
            $_.Name -notin $excludedDrives
        }
        
        if ($drives.Count -eq 0) {
            $StatusLabel.Text = "Warning: No valid Windows installations found! (X: drive and system drives are excluded)"
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            Write-LogMessage "No valid Windows installations found for capture (excluding X: drive)" "WARNING"
            return
        }
        
        foreach ($drive in $drives) {
            $sizeGB = [Math]::Round($drive.Used / 1GB, 1)
            $displayText = "$($drive.Name): ($sizeGB GB) - Windows found"
            $ComboBox.Items.Add($displayText)
            Write-LogMessage "Added drive option: $displayText" "VERBOSE"
        }
        
        if ($drives.Count -gt 0) {
            $ComboBox.SelectedIndex = 0
        }
        
        $StatusLabel.Text = "Success: Found $($drives.Count) valid Windows installation(s) (X: drive excluded)"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Green
        Write-LogMessage "Found $($drives.Count) valid drives for image capture (X: drive excluded)" "INFO"
        
    } catch {
        $StatusLabel.Text = "Error refreshing drives: $_"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        Write-LogMessage "Error refreshing drive list: $_" "ERROR"
    }
}

function UpdateCaptureStatus {
    param(
        [string]$SourceDrive,
        [System.Windows.Forms.Label]$StatusLabel
    )
    
    if ([string]::IsNullOrWhiteSpace($SourceDrive)) {
        return
    }
    
    try {
        $driveLetter = $SourceDrive.Split(':')[0] + ":"
        $windowsPath = "$driveLetter\Windows"
        $sysprepPath = "$windowsPath\System32\Sysprep\Panther\setupact.log"
        
        if (Test-Path $sysprepPath) {
            $sysprepContent = Get-Content $sysprepPath -ErrorAction SilentlyContinue
            if ($sysprepContent -match "Sysprep_Generalize_Complete") {
                $StatusLabel.Text = "Success: Sysprep generalization verified - Ready for capture"
                $StatusLabel.ForeColor = [System.Drawing.Color]::Green
            } else {
                $StatusLabel.Text = "Warning: Could not verify sysprep generalization"
                $StatusLabel.ForeColor = [System.Drawing.Color]::Orange
            }
        } else {
            $StatusLabel.Text = "Warning: No sysprep log found - Ensure system was sysprepped"
            $StatusLabel.ForeColor = [System.Drawing.Color]::Orange
        }
        
    } catch {
        $StatusLabel.Text = "Error checking sysprep status: $_"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        Write-LogMessage "Error checking sysprep status: $_" "ERROR"
    }
}

function Show-NewCustomerDialog {
    # Apply scaling to the new customer dialog as well
    $screenInfo = Get-ScreenResolution
    $scale = [Math]::Max(1.0, $screenInfo.ScaleFactor)
    
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Add New Customer"
    $dialog.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 200 $scale))
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter new customer name:"
    $label.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 30 $scale))
    $label.Size = New-Object System.Drawing.Size((Scale-UIElement 200 $scale), (Scale-UIElement 20 $scale))
    $dialog.Controls.Add($label)
    
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 60 $scale))
    $textBox.Size = New-Object System.Drawing.Size((Scale-UIElement 340 $scale), (Scale-UIElement 25 $scale))
    $dialog.Controls.Add($textBox)
    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point((Scale-UIElement 200 $scale), (Scale-UIElement 110 $scale))
    $okButton.Size = New-Object System.Drawing.Size((Scale-UIElement 75 $scale), (Scale-UIElement 30 $scale))
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($okButton)
    
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 285 $scale), (Scale-UIElement 110 $scale))
    $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 75 $scale), (Scale-UIElement 30 $scale))
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancelButton)
    
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton
    
    $result = $dialog.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        $customerName = $textBox.Text.Trim()
        
        # Validate customer name
        if ($customerName -match '[<>:"/\\|?*]') {
            [System.Windows.Forms.MessageBox]::Show("Customer name contains invalid characters!", "Invalid Name", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $null
        }
        
        # Check if customer already exists
        $existingCustomers = Get-CustomerList
        if ($customerName -in $existingCustomers) {
            [System.Windows.Forms.MessageBox]::Show("Customer '$customerName' already exists!", "Duplicate Customer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $null
        }
        
        return $customerName
    }
    
    return $null
}

# In Add-CaptureLogEntry, store all log lines and filter based on $script:ShowVerboseLogs
function Add-CaptureLogEntry {
    param(
        [System.Windows.Forms.TextBox]$LogTextBox,
        [string]$Message,
        [string]$Level = "INFO"
    )
    if ($LogTextBox -and -not $LogTextBox.IsDisposed) {
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $levelIndicator = switch ($Level) {
            "ERROR" { "[ERROR]" }
            "WARNING" { "[WARN]" }
            "SUCCESS" { "[OK]" }
            "DISM" { "[DISM]" }
            "PROGRESS" { "[PROG]" }
            "VERBOSE" { "[VERB]" }
            default { "[INFO]" }
        }
        $logEntry = "$timestamp $levelIndicator $Message"
        if (-not $script:AllLogLines) { $script:AllLogLines = @() }
        $script:AllLogLines += $logEntry
        $linesToShow = $script:AllLogLines | Where-Object { $script:ShowVerboseLogs -or ($_ -notmatch '\[VERB\]') }
        $LogTextBox.Lines = $linesToShow
        $LogTextBox.SelectionStart = $LogTextBox.Text.Length
        $LogTextBox.ScrollToCaret()
    }
}

function Update-CaptureProgress {
    param(
        [int]$PercentComplete,
        [string]$Status,
        [string]$DetailedMessage = ""
    )
    
    try {
        # Update progress bar and status if available
        if ($script:CaptureProgressBar -and -not $script:CaptureProgressBar.IsDisposed) {
            if ($script:CaptureProgressBar.InvokeRequired) {
                $script:CaptureProgressBar.BeginInvoke([Action]{
                    try {
                        $script:CaptureProgressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                    } catch { }
                }) | Out-Null
            } else {
                $script:CaptureProgressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
            }
        }
        
        # Update status label
        if ($script:CaptureStatusLabel -and -not $script:CaptureStatusLabel.IsDisposed) {
            if ($script:CaptureStatusLabel.InvokeRequired) {
                $script:CaptureStatusLabel.BeginInvoke([Action]{
                    try {
                        $script:CaptureStatusLabel.Text = $Status
                    } catch { }
                }) | Out-Null
            } else {
                $script:CaptureStatusLabel.Text = $Status
            }
        }
        
        # Update percentage label
        if ($script:CapturePercentLabel -and -not $script:CapturePercentLabel.IsDisposed) {
            if ($script:CapturePercentLabel.InvokeRequired) {
                $script:CapturePercentLabel.BeginInvoke([Action]{
                    try {
                        $script:CapturePercentLabel.Text = "$PercentComplete%"
                    } catch { }
                }) | Out-Null
            } else {
                $script:CapturePercentLabel.Text = "$PercentComplete%"
            }
        }
        
        # Add to capture log with more detail - use VERBOSE level for progress messages
        if ($script:CaptureLogTextBox) {
            if ($DetailedMessage) {
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message $DetailedMessage -Level "VERBOSE"
            }
            if ($PercentComplete -gt 0) {
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Progress: $PercentComplete% - $Status" -Level "VERBOSE"
            }
        }
        
        # Force UI refresh
        if ($script:CaptureForm -and -not $script:CaptureForm.IsDisposed) {
            if ($script:CaptureForm.InvokeRequired) {
                $script:CaptureForm.BeginInvoke([Action]{
                    try {
                        $script:CaptureForm.Refresh()
                    } catch { }
                }) | Out-Null
            } else {
                $script:CaptureForm.Refresh()
            }
        }
        
    } catch {
        Write-LogMessage "Error updating capture progress: $_" "WARNING"
    }
}

function Start-ImageCaptureProcess {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Windows.Forms.ComboBox]$CustomerComboBox,
        [System.Windows.Forms.TextBox]$ImageIdTextBox,
        [System.Windows.Forms.TextBox]$ImageNameTextBox,
        [System.Windows.Forms.TextBox]$DescriptionTextBox,
        [System.Windows.Forms.ComboBox]$SourceDriveComboBox,
        [System.Windows.Forms.ComboBox]$CompressionComboBox,
        [System.Windows.Forms.CheckBox]$VerifyCheckBox,
        [System.Windows.Forms.CheckBox]$IntegrityCheckBox
    )
    
    try {
        # Validate inputs
        if ($CustomerComboBox.SelectedItem -eq $null) {
            [System.Windows.Forms.MessageBox]::Show("Please select a customer.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($ImageIdTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter an Image ID.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($ImageNameTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter an Image Name.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ($SourceDriveComboBox.SelectedItem -eq $null) {
            [System.Windows.Forms.MessageBox]::Show("Please select a source drive.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # Get values
        $selectedCustomer = $CustomerComboBox.SelectedItem.ToString()
        $imageID = $ImageIdTextBox.Text.Trim()
        $imageName = $ImageNameTextBox.Text.Trim()
        $description = if ([string]::IsNullOrWhiteSpace($DescriptionTextBox.Text)) { "Captured Windows Image for $selectedCustomer" } else { $DescriptionTextBox.Text.Trim() }
        $sourceDrive = $SourceDriveComboBox.SelectedItem.ToString().Split(':')[0] + ":"
        
        $compression = switch ($CompressionComboBox.SelectedIndex) {
            1 { "fast" }
            2 { "none" }
            default { "max" }
        }
        
        # Pre-capture disk space check
        try {
            $zDriveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "Z:" }
            if ($zDriveInfo) {
                $freeSpaceGB = [Math]::Round($zDriveInfo.FreeSpace / 1GB, 2)
                if ($freeSpaceGB -lt 20) {
                    $spaceWarning = "Warning: Low disk space on Z: drive ($freeSpaceGB GB free). Image capture may fail if insufficient space is available.`n`nProceed anyway?"
                    $spaceResult = [System.Windows.Forms.MessageBox]::Show($spaceWarning, "Low Disk Space Warning", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    if ($spaceResult -ne [System.Windows.Forms.DialogResult]::Yes) {
                        return
                    }
                }
            }
        } catch {
            Write-LogMessage "Could not check Z: drive space: $_" "WARNING"
        }
        
        # Determine capture method
        $captureMethod = $script:CaptureMethod
        $outputExt = if ($captureMethod -eq 'FFU') { 'ffu' } else { 'wim' }
        $outputPath = "Z:\CustomerImages\$selectedCustomer\$imageID\$imageID.$outputExt"

        # Build summary based on method
        if ($captureMethod -eq 'FFU') {
            $summary = @"
Customer: $selectedCustomer
Image ID: $imageID
Image Name: $imageName
Description: $description
Source Drive: $sourceDrive
Capture Method: FFU
Output: $outputPath

This may take several minutes to hours depending on image size.

IMPORTANT NOTES:
- Ensure sufficient disk space is available on Z: drive
- Source system should be sysprepped and shut down cleanly
- Close all running applications to avoid file locks
- Consider running from WinPE for best results

Proceed with image capture?
"@
        } else {
            $summary = @"
Customer: $selectedCustomer
Image ID: $imageID
Image Name: $imageName
Description: $description
Source Drive: $sourceDrive
Compression: $compression
Verify: $(if ($VerifyCheckBox.Checked) { 'Yes' } else { 'No' })
Integrity Check: $(if ($IntegrityCheckBox.Checked) { 'Yes' } else { 'No' })
Output: $outputPath

This may take several minutes to hours depending on image size and compression.

IMPORTANT NOTES:
- Ensure sufficient disk space is available on Z: drive
- Source system should be sysprepped and shut down cleanly
- Close all running applications to avoid file locks
- Consider running from WinPE for best results

Proceed with image capture?
"@
        }

        $confirmResult = [System.Windows.Forms.MessageBox]::Show($summary, "Confirm Image Capture", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        # Start capture process
        $Form.Hide()

        # Create enhanced progress form with capture log
        $CapProgForm = Show-CaptureProgressDialog

        try {
            # Add initial log entries
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "=== IMAGE CAPTURE STARTED ==="
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Customer: $selectedCustomer"
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Image ID: $imageID"
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Image Name: $imageName"
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Source Drive: $sourceDrive"
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Capture Method: $captureMethod"
            if ($captureMethod -eq 'WIM') {
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Compression: $compression"
            }
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Output Path: $outputPath"

            # Use only supported parameters for Invoke-ImageCapture
            $captureParams = @{
                ImageName = $imageName
                CustomerName = $selectedCustomer
                ImageID = $imageID
                Description = $description
                SourceDrive = $sourceDrive
                Compression = $compression
                Verify = $VerifyCheckBox.Checked
                CheckIntegrity = $IntegrityCheckBox.Checked
                CaptureMethod = $captureMethod
            }
            
            Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Starting DISM capture operation..."
            Update-CaptureProgress -PercentComplete 10 -Status "Starting DISM capture operation..." -DetailedMessage "Initializing Windows Imaging (DISM) capture process"
            
            # Start the capture in a background job so we can monitor progress
            $captureJob = Start-Job -ScriptBlock {
                param($CaptureParams, $ModulePath)
                
                try {
                    # Import required modules in the job
                    Import-Module "$ModulePath\..\Imaging\ImageCapture.psm1" -Force
                    Import-Module "$ModulePath\..\Core\Logging.psm1" -Force
                    
                    # Execute the capture
                    $result = Invoke-ImageCapture @CaptureParams
                    return $result
                } catch {
                    return @{
                        Success = $false
                        Message = $_.Exception.Message
                        Error = $_
                    }
                }
            } -ArgumentList $captureParams, $PSScriptRoot
            
            # Monitor the capture process with simulated progress updates
            $startTime = Get-Date
            $progressPhases = @(
                @{ Percent = 15; Status = "Analyzing source drive..."; Message = "Scanning source files and calculating image size" },
                @{ Percent = 25; Status = "Starting image capture..."; Message = "Beginning DISM capture operation" },
                @{ Percent = 35; Status = "Capturing system files..."; Message = "Processing Windows system files and registry" },
                @{ Percent = 50; Status = "Capturing program files..."; Message = "Processing installed applications and program data" },
                @{ Percent = 65; Status = "Capturing user data..."; Message = "Processing user profiles and application data" },
                @{ Percent = 80; Status = "Finalizing image..."; Message = "Completing image capture and applying compression" },
                @{ Percent = 90; Status = "Verifying image..."; Message = "Performing integrity checks on captured image" }
            )
            
            $phaseIndex = 0
            $lastUpdate = Get-Date
            
            while ($captureJob.State -eq "Running") {
                $elapsed = (Get-Date) - $startTime
                
                # Update progress every 15 seconds or when moving to next phase
                if (((Get-Date) - $lastUpdate).TotalSeconds -ge 15 -and $phaseIndex -lt $progressPhases.Count) {
                    $currentPhase = $progressPhases[$phaseIndex]
                    Update-CaptureProgress -PercentComplete $currentPhase.Percent -Status $currentPhase.Status -DetailedMessage $currentPhase.Message
                    $phaseIndex++
                    $lastUpdate = Get-Date
                }
                
                # Check for cancellation
                if ($script:CaptureCancelled) {
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Attempting to stop capture job..." -Level "WARNING"
                    Stop-Job -Job $captureJob
                    Remove-Job -Job $captureJob
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Capture operation cancelled" -Level "WARNING"
                    Update-CaptureProgress -PercentComplete 0 -Status "Capture cancelled" -DetailedMessage "User cancelled the capture operation"
                    break
                }
                
                Start-Sleep -Seconds 2
                
                # Add periodic log entries to show activity - use VERBOSE level
                if (($elapsed.TotalSeconds % 30) -lt 2) {
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Capture in progress... Elapsed time: $([int]$elapsed.TotalMinutes) minutes" -Level "VERBOSE"
                }
            }
            
            # Get the result
            if ($captureJob.State -eq "Completed" -and -not $script:CaptureCancelled) {
                $captureResult = Receive-Job -Job $captureJob
                Remove-Job -Job $captureJob
                
                # Final progress update
                Update-CaptureProgress -PercentComplete 95 -Status "Processing capture results..." -DetailedMessage "Analyzing capture results and updating configuration"
                
                # Final log entries
                if ($captureResult.Success) {
                    Update-CaptureProgress -PercentComplete 100 -Status "Capture completed successfully!" -DetailedMessage "Image capture completed and saved successfully"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "=== CAPTURE COMPLETED SUCCESSFULLY ===" -Level "SUCCESS"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Final image path: $($captureResult.ImagePath)" -Level "SUCCESS"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Image size: $($captureResult.ImageSize)" -Level "SUCCESS"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Capture duration: $($captureResult.CaptureDuration)" -Level "SUCCESS"
                    
                    # Keep the log open for a moment to show completion
                    Start-Sleep -Seconds 3
                } else {
                    Update-CaptureProgress -PercentComplete 0 -Status "Capture failed" -DetailedMessage "Image capture failed - check log for details"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "=== CAPTURE FAILED ===" -Level "ERROR"
                    Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Error: $($captureResult.Message)" -Level "ERROR"
                    
                    # Keep the log open longer for error review
                    Start-Sleep -Seconds 5
                }
            } elseif ($script:CaptureCancelled) {
                $captureResult = @{
                    Success = $false
                    Message = "Capture cancelled by user"
                }
            } else {
                # Job failed or had an error
                $captureResult = @{
                    Success = $false
                    Message = "Capture job failed or encountered an error"
                }
                if ($captureJob.State -eq "Failed") {
                    $jobError = Receive-Job -Job $captureJob -ErrorAction SilentlyContinue
                    if ($jobError) {
                        $captureResult.Message = "Job error: $jobError"
                    }
                }
                Remove-Job -Job $captureJob -Force
                
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "=== CAPTURE FAILED ===" -Level "ERROR"
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "Error: $($captureResult.Message)" -Level "ERROR"
            }

            # Safely close the progress form if it's a Form object
            if ($CapProgForm -and $CapProgForm -is [System.Windows.Forms.Form]) {
                $CapProgForm.Close()
            } else {
                Write-LogMessage "[WARNING] CapProgForm is not a Form object, skipping Close() to avoid error. Actual type: $($CapProgForm.GetType().FullName)" "WARNING"
            }

            # Show results with option to save log
            if ($captureResult.Success) {
                $resultMessage = @"
Success: Image capture completed successfully!

Capture Details:
- Image Path: $($captureResult.ImagePath)
- Image Size: $($captureResult.ImageSize)
- Duration: $($captureResult.CaptureDuration)
- Config Updated: $(if ($captureResult.ConfigUpdated) { 'Yes' } else { 'No' })

The captured image is now ready for network deployment.

Would you like to save the capture log?
"@
                $saveLogResult = [System.Windows.Forms.MessageBox]::Show($resultMessage, "Capture Successful", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
                
                if ($saveLogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Save-CaptureLog -LogText $script:CaptureLogTextBox.Text -ImageID $imageID -CustomerName $selectedCustomer
                }
            } else {
                $errorMessage = @"
Image capture failed:

$($captureResult.Message)

Would you like to save the capture log for troubleshooting?
"@
                
                # Add troubleshooting tips based on error
                if ($captureResult.Message -match "space") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Free up space on Z: drive`n- Consider using higher compression`n- Clean up source drive temporary files"
                } elseif ($captureResult.Message -match "conflict|exists") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Reboot source system to WinPE`n- Ensure sysprep was run properly`n- Close all running applications`n- Try capturing from a clean boot"
                } elseif ($captureResult.Message -match "Winre\.wim") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Boot to WinPE for capture`n- Exclude Recovery folder`n- Check for Windows Update processes"
                }
                
                $saveLogResult = [System.Windows.Forms.MessageBox]::Show($errorMessage, "Capture Failed", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Error)
                
                if ($saveLogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Save-CaptureLog -LogText $script:CaptureLogTextBox.Text -ImageID $imageID -CustomerName $selectedCustomer -Failed $true
                }
            }
            
        } catch {
            if ($script:CaptureLogTextBox) {
                Add-CaptureLogEntry -LogTextBox $script:CaptureLogTextBox -Message "CRITICAL ERROR: $_" -Level "ERROR"
            }
            $CapProgForm.Close()
            [System.Windows.Forms.MessageBox]::Show("An error occurred during capture:`n`n$_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        
        $Form.Close()
        
    } catch {
        Write-LogMessage "Error in image capture process: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-CaptureProgressDialog {
    # Detect screen resolution for progress dialog scaling
    $screenInfo = Get-ScreenResolution
    $scale = $screenInfo.ScaleFactor
    
    # Scale font sizes
    $baseFontSize = [Math]::Max(8, [int](10 * $scale))
    $boldFontSize = [Math]::Max(8, [int](9 * $scale))

    $progressForm = New-Object System.Windows.Forms.Form
    $progressForm.Text = "Image Capture in Progress"
    $progressForm.Size = New-Object System.Drawing.Size((Scale-UIElement 800 $scale), (Scale-UIElement 600 $scale))
    $progressForm.StartPosition = "CenterScreen"
    $progressForm.FormBorderStyle = "Sizable"
    $progressForm.MaximizeBox = $true
    $progressForm.MinimizeBox = $true
    $progressForm.MinimumSize = New-Object System.Drawing.Size((Scale-UIElement 600 $scale), (Scale-UIElement 400 $scale))

    # TableLayoutPanel for responsive layout
    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'
    $table.ColumnCount = 2
    $table.RowCount = 4
    $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 85)))
    $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 15)))
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 36 $scale)))) # Status
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 32 $scale)))) # Progress
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) # Log
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, (Scale-UIElement 50 $scale)))) # Buttons

    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Initializing capture..."
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", $baseFontSize, [System.Drawing.FontStyle]::Bold)
    $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $statusLabel.Dock = 'Fill'
    $table.SetColumnSpan($statusLabel, 2)
    $table.Controls.Add($statusLabel, 0, 0)

    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $progressBar.Dock = 'Fill'
    $table.Controls.Add($progressBar, 0, 1)

    # Percentage label
    $percentLabel = New-Object System.Windows.Forms.Label
    $percentLabel.Text = "0%"
    $percentLabel.Font = New-Object System.Drawing.Font("Segoe UI", $boldFontSize, [System.Drawing.FontStyle]::Bold)
    $percentLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $percentLabel.Dock = 'Fill'
    $table.Controls.Add($percentLabel, 1, 1)

    # Log group box
    $logGroupBox = New-Object System.Windows.Forms.GroupBox
    $logGroupBox.Text = "Capture Log"
    $logGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $baseFontSize, [System.Drawing.FontStyle]::Bold)
    $logGroupBox.Dock = 'Fill'
    $table.SetColumnSpan($logGroupBox, 2)
    $table.Controls.Add($logGroupBox, 0, 2)

    # Log textbox inside group box
    $logTextBox = New-Object System.Windows.Forms.TextBox
    $logTextBox.Font = New-Object System.Drawing.Font("Consolas", [Math]::Max(8, [int](9 * $scale)))
    $logTextBox.Multiline = $true
    $logTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $logTextBox.ReadOnly = $true
    $logTextBox.BackColor = [System.Drawing.Color]::Black
    $logTextBox.ForeColor = [System.Drawing.Color]::LimeGreen
    $logTextBox.WordWrap = $false
    $logTextBox.Dock = 'Fill'
    $logGroupBox.Controls.Add($logTextBox)

    # FlowLayoutPanel for action buttons
    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.Dock = 'Fill'
    $buttonPanel.Padding = '0,8,8,8'

    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel Capture"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $baseFontSize)
    $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
    $cancelButton.AutoSize = $true
    $buttonPanel.Controls.Add($cancelButton)
    $table.SetColumnSpan($buttonPanel, 2)
    $table.Controls.Add($buttonPanel, 0, 3)

    $progressForm.Controls.Add($table)

    # Initialize the log
    Add-CaptureLogEntry -LogTextBox $logTextBox -Message "Image capture process started"
    Add-CaptureLogEntry -LogTextBox $logTextBox -Message "Initializing DISM operations..."

    # Set up global references for callback access
    $script:CaptureProgressBar = $progressBar
    $script:CaptureStatusLabel = $statusLabel
    $script:CapturePercentLabel = $percentLabel
    $script:CaptureLogTextBox = $logTextBox
    $script:CaptureForm = $progressForm
    $script:CaptureCancelled = $false

    # Cancel button event
    $cancelButton.Add_Click({
        $script:CaptureCancelled = $true
        Add-CaptureLogEntry -LogTextBox $logTextBox -Message "CANCELLATION REQUESTED BY USER" -Level "WARNING"
        $cancelButton.Enabled = $false
        $cancelButton.Text = "Cancelling..."
    })

    $progressForm.Show()
    $progressForm.Refresh()

    return $progressForm
}

function Save-CaptureLog {
    param(
        [string]$LogText,
        [string]$ImageID,
        [string]$CustomerName,
        [switch]$Failed
    )
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $status = if ($Failed) { "FAILED" } else { "SUCCESS" }
        $logFileName = "CaptureLog_${CustomerName}_${ImageID}_${status}_${timestamp}.txt"
        
        # Create the customer image log directory path
        $customerImageLogDir = "Z:\CustomerImages\$CustomerName\$ImageID\Logs"
        
        # Ensure we're in the right thread apartment for COM operations
        [System.Threading.Thread]::CurrentThread.SetApartmentState([System.Threading.ApartmentState]::STA)
        
        # Only use the fallback method for saving log files, do not use SaveFileDialog at all
        try {
            # Create the customer image log directory if it doesn't exist
            if (-not (Test-Path $customerImageLogDir)) {
                New-Item -Path $customerImageLogDir -ItemType Directory -Force | Out-Null
                Write-LogMessage "Created customer image log directory: $customerImageLogDir" "INFO"
            }
            $defaultLogPath = Join-Path $customerImageLogDir $logFileName
            # Create header for the log file
            $logHeader = @" 
===================================================================
IMAGE CAPTURE LOG
===================================================================
Customer: $CustomerName
Image ID: $ImageID
Capture Status: $status
Log Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Image Directory: Z:\CustomerImages\$CustomerName\$ImageID\
===================================================================

"@
            $fullLogContent = $logHeader + $LogText
            # Save to customer image log directory
            [System.IO.File]::WriteAllText($defaultLogPath, $fullLogContent, [System.Text.Encoding]::UTF8)
            [System.Windows.Forms.MessageBox]::Show("Capture log saved to:`n$defaultLogPath`n`n(Log was saved automatically)", "Log Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Write-LogMessage "Capture log saved to customer image directory: $defaultLogPath" "INFO"
        } catch {
            # Final fallback if all log save attempts fail
            $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
            $desktopLogPath = Join-Path $desktopPath $logFileName
            $logHeader = @" 
===================================================================
IMAGE CAPTURE LOG
===================================================================
Customer: $CustomerName
Image ID: $ImageID
Capture Status: $status
Log Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Image Directory: Z:\CustomerImages\$CustomerName\$ImageID\
===================================================================

"@
            $fullLogContent = $logHeader + $LogText
            [System.IO.File]::WriteAllText($desktopLogPath, $fullLogContent, [System.Text.Encoding]::UTF8)
            [System.Windows.Forms.MessageBox]::Show("Capture log saved to desktop:`n$desktopLogPath`n`n(All other save attempts failed)", "Log Saved (Desktop Fallback)", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            Write-LogMessage "Capture log saved to desktop fallback: $desktopLogPath" "WARNING"
        }
    } catch {
        Write-LogMessage "Error in Save-CaptureLog: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred while saving the capture log: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-DeviceInformationDialog {
    try {
        Write-LogMessage "Gathering comprehensive device information..." "INFO"
        
        # Show progress while gathering info
        $progressForm = New-Object System.Windows.Forms.Form
        $progressForm.Text = "Gathering Device Information"
       
        $progressForm.Size = New-Object System.Drawing.Size(400, 150)
        $progressForm.StartPosition = "CenterParent"
        $progressForm.FormBorderStyle = "FixedDialog"
        $progressForm.MaximizeBox = $false
        $progressForm.MinimizeBox = $false
        $progressForm.ControlBox = $false
        
        $progressLabel = New-Object System.Windows.Forms.Label
        $progressLabel.Text = "Gathering device information, please wait..."
        $progressLabel.Location = New-Object System.Drawing.Point(50, 30)

        $progressLabel.Size = New-Object System.Drawing.Size(300, 40)
        $progressLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $progressForm.Controls.Add($progressLabel)
        
        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(50, 80)
        $progressBar.Size = New-Object System.Drawing.Size(300, 20)
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $progressForm.Controls.Add($progressBar)
        
        $progressForm.Show()
        $progressForm.Refresh()
        
        # Gather comprehensive device information
        $deviceInfo = Get-DeviceInformation
        # Remove unwanted drives from deviceInfo.Storage.LogicalDrives and PhysicalDrives if present
        $excludeDrives = @('V', 'X', 'W', 'Y', 'Z')
        if ($deviceInfo.Storage -and $deviceInfo.Storage.LogicalDrives) {
            $deviceInfo.Storage.LogicalDrives = @($deviceInfo.Storage.LogicalDrives | Where-Object {
                $driveLetter = $_.Name
                if (-not $driveLetter -and $_ -is [string]) { $driveLetter = $_ }
                if ($driveLetter) {
                    $letter = $driveLetter.Substring(0,1).ToUpper()
                    $excludeDrives -notcontains $letter
                } else {
                    $true
                }
            })
        }
        if ($deviceInfo.Storage -and $deviceInfo.Storage.PhysicalDrives) {
            $deviceInfo.Storage.PhysicalDrives = @($deviceInfo.Storage.PhysicalDrives | Where-Object {
                $driveLetter = $_.Name
                if (-not $driveLetter -and $_ -is [string]) { $driveLetter = $_ }
                if ($driveLetter) {
                    $letter = $driveLetter.Substring(0,1).ToUpper()
                    $excludeDrives -notcontains $letter
                } else {
                    $true
                }
            })
        }
        
        $progressForm.Close()
        
        # Create device information display form
        $infoForm = New-Object System.Windows.Forms.Form
        $infoForm.Text = "Device Information - $($deviceInfo.BasicInfo.Manufacturer) $($deviceInfo.BasicInfo.Model)"
        $infoForm.Size = New-Object System.Drawing.Size(800, 600)
        $infoForm.StartPosition = "CenterParent"
        $infoForm.FormBorderStyle = "Sizable"
        
        # Create tab control
        $tabControl = New-Object System.Windows.Forms.TabControl
        $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
        
        # Basic Information Tab
        $basicTab = New-Object System.Windows.Forms.TabPage
        $basicTab.Text = "Basic Info"
        
        $basicText = @"
BASIC DEVICE INFORMATION
========================

Manufacturer: $($deviceInfo.BasicInfo.Manufacturer)
Model: $($deviceInfo.BasicInfo.Model)
Serial Number: $($deviceInfo.BasicInfo.SerialNumber)
Asset Tag: $(if ($deviceInfo.BasicInfo.AssetTag) { $deviceInfo.BasicInfo.AssetTag } else { 'Not Available' })
System Type: $($deviceInfo.BasicInfo.SystemType)
PC System Type: $($deviceInfo.BasicInfo.PCSystemType)
Total Physical Memory: $($deviceInfo.BasicInfo.TotalPhysicalMemoryGB) GB

DEPLOYMENT SUMMARY
==================
[OK] Manufacturer: $($deviceInfo.BasicInfo.Manufacturer)
[OK] Model: $($deviceInfo.BasicInfo.Model)
[OK] Serial Number: $($deviceInfo.BasicInfo.SerialNumber)
$(if ($deviceInfo.BasicInfo.AssetTag) { "[OK] Asset Tag: $($deviceInfo.BasicInfo.AssetTag)" } else { "[--] Asset Tag: Not Available" })
"@
        
        $basicTextBox = New-Object System.Windows.Forms.TextBox
        $basicTextBox.Text = $basicText
        $basicTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $basicTextBox.Multiline = $true
        $basicTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $basicTextBox.ReadOnly = $true
        $basicTextBox.Font = New-Object System.Drawing.Font("Consolas",  9)
        $basicTab.Controls.Add($basicTextBox)
        
        # Hardware Specifications Tab
        $specsTab = New-Object System.Windows.Forms.TabPage
        $specsTab.Text = "Hardware Specs"
        
        $specsText = Format-DeviceInformationReport -DeviceInfo $deviceInfo
        
        $specsTextBox = New-Object System.Windows.Forms.TextBox
        $specsTextBox.Text = $specsText
        $specsTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $specsTextBox.Multiline = $true
        $specsTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
        $specsTextBox.ReadOnly = $true
        $specsTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
        $specsTab.Controls.Add($specsTextBox)
        
        # Summary Tab
        $summaryTab = New-Object System.Windows.Forms.TabPage
        $summaryTab.Text = "Summary"
        
        $summaryText = @"
DEVICE SUMMARY FOR DEPLOYMENT
==============================

Primary Information:
- Manufacturer: $($deviceInfo.Summary.Manufacturer)
- Model: $($deviceInfo.Summary.Model)
- Serial Number: $($deviceInfo.Summary.SerialNumber)
- Asset Tag: $(if ($deviceInfo.Summary.AssetTag) { $deviceInfo.Summary.AssetTag } else { 'Not Available' })

Hardware Overview:
- Processors: $($deviceInfo.Summary.ProcessorCount)
- Total Memory: $($deviceInfo.Summary.TotalMemoryGB) GB
- Storage Devices: $($deviceInfo.Summary.StorageDevices)
- Network Adapters: $($deviceInfo.Summary.NetworkAdapters)

Data Gathering Status:
- Errors Encountered: $(if ($deviceInfo.Summary.HasErrors) { "Yes ($($deviceInfo.Summary.ErrorCount))" } else { "None" })
- Gathering Time: $($deviceInfo.GatheredAt)

$(if ($deviceInfo.Summary.HasErrors) {
"ERROR DETAILS:
$(($deviceInfo.Errors | ForEach-Object { "- $_" }) -join "`n")"
} else {
"[OK] All device information gathered successfully"
})

DEPLOYMENT READINESS
====================
[OK] Basic device identification available
[OK] Hardware specifications cataloged
$(if ($deviceInfo.BasicInfo.AssetTag) { "[OK] Asset tag available for tracking" } else { "[--] No asset tag available" })
$(if (-not $deviceInfo.Summary.HasErrors) { "[OK] No errors during information gathering" } else { "[!!] Some errors occurred during gathering" })

This device is ready for image capture and deployment.
"@
        
        $summaryTextBox = New-Object System.Windows.Forms.TextBox
        $summaryTextBox.Text = $summaryText
        $summaryTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $summaryTextBox.Multiline = $true
        $summaryTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $summaryTextBox.ReadOnly = $true
        $summaryTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $summaryTab.Controls.Add($summaryTextBox)
        
        # Add tabs to control
        $tabControl.TabPages.Add($basicTab)
        $tabControl.TabPages.Add($summaryTab)
        $tabControl.TabPages.Add($specsTab)
        
        $infoForm.Controls.Add($tabControl)
        
        # Add buttons
        $buttonPanel = New-Object System.Windows.Forms.Panel
        $buttonPanel.Height = 50
        $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
        
        $saveButton = New-Object System.Windows.Forms.Button
        $saveButton.Text = "Save Report"
        $saveButton.Location = New-Object System.Drawing.Point(20, 10)
        $saveButton.Size = New-Object System.Drawing.Size(100, 30)
        $buttonPanel.Controls.Add($saveButton)
        
        $copyButton = New-Object System.Windows.Forms.Button
        $copyButton.Text = "Copy to Clipboard"
        $copyButton.Location = New-Object System.Drawing.Point(130, 10)
        $copyButton.Size = New-Object System.Drawing.Size(120, 30)
        $buttonPanel.Controls.Add($copyButton)
        
        $closeButton = New-Object System.Windows.Forms.Button
        $closeButton.Text = "Close"
        $closeButton.Location = New-Object System.Drawing.Point(660, 10)
        $closeButton.Size = New-Object System.Drawing.Size(100, 30)
        $closeButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $buttonPanel.Controls.Add($closeButton)
        
        $infoForm.Controls.Add($buttonPanel)
        
        # Button events
        $saveButton.Add_Click({
            try {
                # Prompt for Customer and OrderNumber if not available
                $customerName = $null
                $orderNumber = $null
                if ($script:selectedCustomer) { $customerName = $script:selectedCustomer }
                if ($global:selectedCustomer) { $customerName = $global:selectedCustomer }
                if ($script:orderNumber) { $orderNumber = $script:orderNumber }
                if ($global:orderNumber) { $orderNumber = $global:orderNumber }

                if (-not $customerName -or -not $orderNumber) {
                    # Show dialog to select/add customer and enter order number
                    $dialog = New-Object System.Windows.Forms.Form
                    $dialog.Text = "Enter Customer and Order Number"
                    $dialog.Size = New-Object System.Drawing.Size(420, 210)
                    $dialog.StartPosition = "CenterParent"
                    $dialog.FormBorderStyle = "FixedDialog"
                    $dialog.MaximizeBox = $false
                    $dialog.MinimizeBox = $false

                    $customerLabel = New-Object System.Windows.Forms.Label
                    $customerLabel.Text = "Customer Name:"
                    $customerLabel.Location = New-Object System.Drawing.Point(20, 20)
                    $customerLabel.Size = New-Object System.Drawing.Size(110, 20)
                    $dialog.Controls.Add($customerLabel)

                    $customerComboBox = New-Object System.Windows.Forms.ComboBox
                    $customerComboBox.Location = New-Object System.Drawing.Point(130, 18)
                    $customerComboBox.Size = New-Object System.Drawing.Size(180, 25)
                    $customerComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
                    $customerComboBox.Items.AddRange((Get-CustomerList))
                    if ($customerName) { $customerComboBox.SelectedItem = $customerName }
                    $dialog.Controls.Add($customerComboBox)

                    $addCustomerButton = New-Object System.Windows.Forms.Button
                    $addCustomerButton.Text = "Add New"
                    $addCustomerButton.Location = New-Object System.Drawing.Point(320, 17)
                    $addCustomerButton.Size = New-Object System.Drawing.Size(75, 25)
                    $dialog.Controls.Add($addCustomerButton)

                    $orderLabel = New-Object System.Windows.Forms.Label
                    $orderLabel.Text = "Order Number:"
                    $orderLabel.Location = New-Object System.Drawing.Point(20, 60)
                    $orderLabel.Size = New-Object System.Drawing.Size(110, 20)
                    $dialog.Controls.Add($orderLabel)

                    $orderTextBox = New-Object System.Windows.Forms.TextBox
                    $orderTextBox.Location = New-Object System.Drawing.Point(130, 58)
                    $orderTextBox.Size = New-Object System.Drawing.Size(180, 25)
                    if ($orderNumber) { $orderTextBox.Text = $orderNumber }
                    $dialog.Controls.Add($orderTextBox)

                    $continueButton = New-Object System.Windows.Forms.Button
                    $continueButton.Text = "Continue"
                    $continueButton.Location = New-Object System.Drawing.Point(130, 110)
                    $continueButton.Size = New-Object System.Drawing.Size(90, 30)
                    $dialog.Controls.Add($continueButton)

                    $closeButton2 = New-Object System.Windows.Forms.Button
                    $closeButton2.Text = "Close"
                    $closeButton2.Location = New-Object System.Drawing.Point(230, 110)
                    $closeButton2.Size = New-Object System.Drawing.Size(90, 30)
                    $closeButton2.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                    $dialog.Controls.Add($closeButton2)

                    $addCustomerButton.Add_Click({
                        $newCustomer = Show-NewCustomerDialog
                        if ($newCustomer) {
                            # --- Begin: Create new customer directory and minimal Config.json (match DeploymentMenu.psm1 logic) ---
                            $customerConfigRoot = Join-Path (Split-Path $PSScriptRoot -Parent) '..\..\Config\CustomerConfig'
                            $customerDir = Join-Path $customerConfigRoot $newCustomer
                            $configPath = Join-Path $customerDir 'Config.json'
                            if (-not (Test-Path $customerDir)) {
                                try {
                                    New-Item -Path $customerDir -ItemType Directory -Force | Out-Null
                                } catch {
                                    [System.Windows.Forms.MessageBox]::Show("Failed to create customer directory: $customerDir`n`n$_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                                    return
                                }
                            }
                            if (-not (Test-Path $configPath)) {
                                $minimalConfig = @{ Images = @(); FFUImages = @(); WIMImages = @(); CustomerName = $newCustomer }
                                try {
                                    $minimalConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8 -Force
                                } catch {
                                    [System.Windows.Forms.MessageBox]::Show("Failed to create Config.json for new customer: $configPath`n`n$_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                                    return
                                }
                            }
                            # --- End: Create new customer directory and minimal Config.json ---
                            $customerComboBox.Items.Add($newCustomer)
                            $customerComboBox.SelectedItem = $newCustomer
                        }
                    })

                    $continueButton.Add_Click({
                        if (-not $customerComboBox.SelectedItem) {
                            [System.Windows.Forms.MessageBox]::Show("Please select or add a customer.", "Missing Customer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                            return
                        }
                        if ([string]::IsNullOrWhiteSpace($orderTextBox.Text)) {
                            [System.Windows.Forms.MessageBox]::Show("Please enter an order number.", "Missing Order Number", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                            return
                        }
                        $dialog.Tag = @{ Customer = $customerComboBox.SelectedItem.ToString(); Order = $orderTextBox.Text.Trim() }
                        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
                        $dialog.Close()
                    })

                    $dialog.AcceptButton = $continueButton
                    $dialog.CancelButton = $closeButton2

                    $result = $dialog.ShowDialog()
                    if ($result -ne [System.Windows.Forms.DialogResult]::OK -or -not $dialog.Tag) {
                        return
                    }
                    $customerName = $dialog.Tag.Customer
                    $orderNumber = $dialog.Tag.Order
                    # Optionally update global/script variables
                    $script:selectedCustomer = $customerName
                    $script:orderNumber = $orderNumber
                }

                $fileBase = "DeviceInfo_${customerName}_${orderNumber}_$($deviceInfo.BasicInfo.SerialNumber)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                $defaultDir = "W:\Logs\$customerName\$orderNumber\DeviceReports"
                if (-not (Test-Path $defaultDir)) {
                    try { New-Item -Path $defaultDir -ItemType Directory -Force | Out-Null } catch {}
                }
                $txtPath = Join-Path $defaultDir ("$fileBase.txt")
                $csvPath = Join-Path $defaultDir ("$fileBase.csv")

                $fullReport = Format-DeviceInformationReport -DeviceInfo $deviceInfo
                $fullReport | Set-Content -Path $txtPath -Force
                # XML export
                $xmlPath = [System.IO.Path]::ChangeExtension($txtPath, 'xml')
                function ConvertTo-XmlElement {
                    param($doc, $name, $value)
                    $element = $doc.CreateElement($name)
                    if ($null -eq $value) {
                        $element.InnerText = ''
                    } elseif ($value -is [System.Collections.IDictionary] -or $value -is [Hashtable]) {
                        foreach ($k in $value.Keys) {
                            $child = ConvertTo-XmlElement $doc $k $value[$k]
                            $element.AppendChild($child) | Out-Null
                        }
                    } elseif ($value -is [PSCustomObject]) {
                        $props = $value | Get-Member -MemberType NoteProperty,Property | Select-Object -ExpandProperty Name
                        foreach ($k in $props) {
                            $child = ConvertTo-XmlElement $doc $k $value.$k
                            $element.AppendChild($child) | Out-Null
                        }
                    } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                        foreach ($item in $value) {
                            $child = ConvertTo-XmlElement $doc 'Item' $item
                            $element.AppendChild($child) | Out-Null
                        }
                    } else {
                        $element.InnerText = $value.ToString()
                    }
                    return $element
                }
                $doc = New-Object System.Xml.XmlDocument
                $root = $doc.CreateElement('DeviceInfo')
                # Add <Summary> first if present
                if ($deviceInfo.PSObject.Properties['Summary']) {
                    $summaryElem = ConvertTo-XmlElement $doc 'Summary' $deviceInfo.Summary
                    $root.AppendChild($summaryElem) | Out-Null
                }
                # Add all other properties
                foreach ($prop in $deviceInfo.PSObject.Properties.Name) {
                    if ($prop -ne 'Summary') {
                        $childElem = ConvertTo-XmlElement $doc $prop $deviceInfo[$prop]
                        $root.AppendChild($childElem) | Out-Null
                    }
                }
                $doc.AppendChild($root) | Out-Null
                $doc.Save($xmlPath)
                [System.Windows.Forms.MessageBox]::Show("Device information saved to:`n$txtPath`n$xmlPath", "Report Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error saving report: $_", "Save Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        $copyButton.Add_Click({
            try {
                $reportText = Format-DeviceInformationReport -DeviceInfo $deviceInfo
                [System.Windows.Forms.Clipboard]::SetText($reportText)
                [System.Windows.Forms.MessageBox]::Show("Device information copied to clipboard.", "Copied", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error copying to clipboard: $_", "Copy Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        $closeButton.Add_Click({
            $infoForm.Close()
        })
        
        # Show the form
        $infoForm.ShowDialog() | Out-Null
        $infoForm.Dispose()
        
    } catch {
        Write-LogMessage "Error showing device information dialog: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error gathering device information: $_", "Device Information Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Export-ModuleMember -Function Show-ImageCaptureMenu, Show-NewCustomerDialog
