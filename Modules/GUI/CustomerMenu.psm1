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
    [CmdletBinding()
    ]
    param()
    
    try {
        Write-LogMessage "=== Image Capture Menu ===" "INFO"
        
        # Detect screen resolution and calculate scaling
        $screenInfo = Get-ScreenResolution
        $scale = $screenInfo.ScaleFactor
        
        Write-LogMessage "ImageCapture: Using UI scale factor: $scale for screen resolution $($screenInfo.Width)x$($screenInfo.Height)" "INFO"
        
        # Scale font sizes based on resolution
        $baseFontSize = 9
        $titleFontSize = 16
        $buttonFontSize = 9
        $groupFontSize = 9
        
        $scaledBaseFontSize = [Math]::Max(8, [int]($baseFontSize * $scale))
        $scaledTitleFontSize = [Math]::Max(12, [int]($titleFontSize * $scale))
        $scaledButtonFontSize = [Math]::Max(8, [int]($buttonFontSize * $scale))
        $scaledGroupFontSize = [Math]::Max(8, [int]($groupFontSize * $scale))
        
        # Create main form with scaled dimensions - increased height to prevent button clipping
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Windows Image Capture Tool"
        $form.Size = New-Object System.Drawing.Size((Scale-UIElement 600 $scale), (Scale-UIElement 820 $scale))
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.BackColor = [System.Drawing.Color]::White
        
        # Title label with scaled dimensions and font
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Network Boot Image Capture"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledTitleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 20 $scale))
        $titleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 30 $scale))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $form.Controls.Add($titleLabel)
        
        # Subtitle label with scaled dimensions and font
        $subtitleLabel = New-Object System.Windows.Forms.Label
        $subtitleLabel.Text = "Captures sysprepped Windows installations for deployment"
        $subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $subtitleLabel.ForeColor = [System.Drawing.Color]::Gray
        $subtitleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 50 $scale))
        $subtitleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 20 $scale))
        $subtitleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $form.Controls.Add($subtitleLabel)
        
        # Customer selection group with scaled dimensions
        $customerGroupBox = New-Object System.Windows.Forms.GroupBox
        $customerGroupBox.Text = "Step 1: Customer Selection"
        $customerGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $customerGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 80 $scale))
        $customerGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 80 $scale))
        $form.Controls.Add($customerGroupBox)
        
        # Customer dropdown with scaled dimensions
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
        $customerComboBox.Size = New-Object System.Drawing.Size((Scale-UIElement 300 $scale), (Scale-UIElement 25 $scale))
        $customerComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $customerGroupBox.Controls.Add($customerComboBox)
        
        # Add New Customer button with scaled dimensions
        $newCustomerButton = New-Object System.Windows.Forms.Button
        $newCustomerButton.Text = "Add New"
        $newCustomerButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $newCustomerButton.Location = New-Object System.Drawing.Point((Scale-UIElement 430 $scale), (Scale-UIElement 22 $scale))
        $newCustomerButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 27 $scale))
        $newCustomerButton.BackColor = [System.Drawing.Color]::LightGreen
        $customerGroupBox.Controls.Add($newCustomerButton)
        
        # Load customers
        $customers = Get-CustomerList
        foreach ($customer in $customers) {
            $customerComboBox.Items.Add($customer) | Out-Null
        }
        if ($customers.Count -gt 0) {
            $customerComboBox.SelectedIndex = 0
        }
        
        # Image identification group with scaled dimensions
        $imageGroupBox = New-Object System.Windows.Forms.GroupBox
        $imageGroupBox.Text = "Step 2: Image Identification"
        $imageGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $imageGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 170 $scale))
        $imageGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 140 $scale))
        $form.Controls.Add($imageGroupBox)
        
        # Image ID with scaled dimensions
        $imageIdLabel = New-Object System.Windows.Forms.Label
        $imageIdLabel.Text = "Image ID:"
        $imageIdLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageIdLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $imageIdLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $imageIdLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageGroupBox.Controls.Add($imageIdLabel)
        
        $imageIdTextBox = New-Object System.Windows.Forms.TextBox
        $imageIdTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageIdTextBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 23 $scale))
        $imageIdTextBox.Size = New-Object System.Drawing.Size((Scale-UIElement 300 $scale), (Scale-UIElement 25 $scale))
        $imageGroupBox.Controls.Add($imageIdTextBox)
        
        # Helper label for Image ID with scaled dimensions
        $imageIdHelpLabel = New-Object System.Windows.Forms.Label
        $imageIdHelpLabel.Text = "(e.g., WIN11-OFFICE-V1)"
        $imageIdHelpLabel.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(7, [int](8 * $scale)))
        $imageIdHelpLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 425 $scale), (Scale-UIElement 25 $scale))
        $imageIdHelpLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 20 $scale))
        $imageIdHelpLabel.ForeColor = [System.Drawing.Color]::Gray
        $imageGroupBox.Controls.Add($imageIdHelpLabel)
        
        # Image Name with scaled dimensions
        $imageNameLabel = New-Object System.Windows.Forms.Label
        $imageNameLabel.Text = "Image Name:"
        $imageNameLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageNameLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 55 $scale))
        $imageNameLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $imageNameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageGroupBox.Controls.Add($imageNameLabel)
        
        $imageNameTextBox = New-Object System.Windows.Forms.TextBox
        $imageNameTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $imageNameTextBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 53 $scale))
        $imageNameTextBox.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 25 $scale))
        $imageGroupBox.Controls.Add($imageNameTextBox)
        
        # Helper label for Image Name with scaled dimensions
        $imageNameHelpLabel = New-Object System.Windows.Forms.Label
        $imageNameHelpLabel.Text = "(e.g., Windows 11 with Office 365)"
        $imageNameHelpLabel.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(7, [int](8 * $scale)))
        $imageNameHelpLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 78 $scale))
        $imageNameHelpLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 200 $scale), (Scale-UIElement 15 $scale))
        $imageNameHelpLabel.ForeColor = [System.Drawing.Color]::Gray
        $imageGroupBox.Controls.Add($imageNameHelpLabel)
        
        # Description with scaled dimensions
        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = "Description:"
        $descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $descriptionLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 100 $scale))
        $descriptionLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $descriptionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $imageGroupBox.Controls.Add($descriptionLabel)
        
        $descriptionTextBox = New-Object System.Windows.Forms.TextBox
        $descriptionTextBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $descriptionTextBox.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 98 $scale))
        $descriptionTextBox.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 25 $scale))
        $imageGroupBox.Controls.Add($descriptionTextBox)
        
        # Helper label for Description with scaled dimensions
        $descriptionHelpLabel = New-Object System.Windows.Forms.Label
        $descriptionHelpLabel.Text = "(optional description)"
        $descriptionHelpLabel.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(7, [int](8 * $scale)))
        $descriptionHelpLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 120 $scale), (Scale-UIElement 123 $scale))
        $descriptionHelpLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 15 $scale))
        $descriptionHelpLabel.ForeColor = [System.Drawing.Color]::Gray
        $imageGroupBox.Controls.Add($descriptionHelpLabel)
        
        # Source configuration group with scaled dimensions
        $sourceGroupBox = New-Object System.Windows.Forms.GroupBox
        $sourceGroupBox.Text = "Step 3: Source Configuration"
        $sourceGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $sourceGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 320 $scale))
        $sourceGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 80 $scale))
        $form.Controls.Add($sourceGroupBox)
        
        # Source drive with scaled dimensions
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
        $sourceDriveComboBox.Size = New-Object System.Drawing.Size((Scale-UIElement 300 $scale), (Scale-UIElement 25 $scale))
        $sourceDriveComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $sourceGroupBox.Controls.Add($sourceDriveComboBox)
        
        # Refresh drives button with scaled dimensions
        $refreshDrivesButton = New-Object System.Windows.Forms.Button
        $refreshDrivesButton.Text = "Refresh"
        $refreshDrivesButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $refreshDrivesButton.Location = New-Object System.Drawing.Point((Scale-UIElement 430 $scale), (Scale-UIElement 22 $scale))
        $refreshDrivesButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 27 $scale))
        $sourceGroupBox.Controls.Add($refreshDrivesButton)
        
        # Compression and verification group with scaled dimensions
        $optionsGroupBox = New-Object System.Windows.Forms.GroupBox
        $optionsGroupBox.Text = "Step 4: Capture Options"
        $optionsGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $optionsGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 410 $scale))
        $optionsGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 120 $scale))
        $form.Controls.Add($optionsGroupBox)
        
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
        
        # Status group with scaled dimensions
        $statusGroupBox = New-Object System.Windows.Forms.GroupBox
        $statusGroupBox.Text = "Pre-Capture Status"
        $statusGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledGroupFontSize, [System.Drawing.FontStyle]::Bold)
        $statusGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 540 $scale))
        $statusGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 550 $scale), (Scale-UIElement 80 $scale))
        $form.Controls.Add($statusGroupBox)
        
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Text = "Gathering device information..."
        $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $statusLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 15 $scale), (Scale-UIElement 25 $scale))
        $statusLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 420 $scale), (Scale-UIElement 45 $scale))
        $statusLabel.ForeColor = [System.Drawing.Color]::Blue
        $statusGroupBox.Controls.Add($statusLabel)
        
        # Device Info button
        $deviceInfoButton = New-Object System.Windows.Forms.Button
        $deviceInfoButton.Text = "Device Info"
        $deviceInfoButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $deviceInfoButton.Location = New-Object System.Drawing.Point((Scale-UIElement 445 $scale), (Scale-UIElement 25 $scale))
        $deviceInfoButton.Size = New-Object System.Drawing.Size((Scale-UIElement 90 $scale), (Scale-UIElement 45 $scale))
        $deviceInfoButton.BackColor = [System.Drawing.Color]::LightBlue
        $statusGroupBox.Controls.Add($deviceInfoButton)
        
        # Buttons with scaled dimensions - positioned to prevent clipping
        $captureButton = New-Object System.Windows.Forms.Button
        $captureButton.Text = "Start Capture"
        $captureButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize, [System.Drawing.FontStyle]::Bold)
        $captureButton.Location = New-Object System.Drawing.Point((Scale-UIElement 350 $scale), (Scale-UIElement 640 $scale))
        $captureButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
        $captureButton.BackColor = [System.Drawing.Color]::LightGreen
        $captureButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($captureButton)
        
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 470 $scale), (Scale-UIElement 640 $scale))
        $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
        $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
        $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($cancelButton)
        
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
        
        # Enhanced confirmation with disk space info
        $summary = @"
Customer: $selectedCustomer
Image ID: $imageID
Image Name: $imageName
Description: $description
Source Drive: $sourceDrive
Compression: $compression
Verify: $(if ($VerifyCheckBox.Checked) { 'Yes' } else { 'No' })
Integrity Check: $(if ($IntegrityCheckBox.Checked) { 'Yes' } else { 'No' })
Output: Z:\CustomerImages\$selectedCustomer\$imageID\$imageID.wim

This may take several minutes to hours depending on image size and compression.

IMPORTANT NOTES:
- Ensure sufficient disk space is available on Z: drive
- Source system should be sysprepped and shut down cleanly
- Close all running applications to avoid file locks
- Consider running from WinPE for best results

Proceed with image capture?
"@
        
        $confirmResult = [System.Windows.Forms.MessageBox]::Show($summary, "Confirm Image Capture", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        # Start capture process
        $Form.Hide()
        
        # Create progress form with real progress bar
        $progressForm = Show-CaptureProgressDialog
        
        try {
            # Set up progress callback for real-time updates
            Set-CaptureProgressCallback -Callback {
                param($PercentComplete, $Status)
                
                try {
                    if ($progressForm -and -not $progressForm.IsDisposed) {
                        if ($progressForm.InvokeRequired) {
                            $progressForm.BeginInvoke([Action]{
                                try {
                                    # Find controls by type instead of assuming structure
                                    $progressBar = $null
                                    $statusLabel = $null
                                    $percentLabel = $null
                                    
                                    foreach ($control in $progressForm.Controls) {
                                        if ($control -is [System.Windows.Forms.ProgressBar]) {
                                            $progressBar = $control
                                        } elseif ($control -is [System.Windows.Forms.Label]) {
                                            if ($control.Font.Bold) {
                                                $percentLabel = $control
                                            } else {
                                                $statusLabel = $control
                                            }
                                        }
                                    }
                                    
                                    if ($progressBar) {
                                        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                                        $progressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                                    }
                                    if ($statusLabel) {
                                        $statusLabel.Text = $Status
                                    }
                                    if ($percentLabel) {
                                        $percentLabel.Text = "$PercentComplete%"
                                    }
                                    $progressForm.Refresh()
                                    
                                } catch {
                                    Write-LogMessage "Progress UI update error: $_" "WARNING"
                                }
                            }) | Out-Null
                        } else {
                            try {
                                # Find controls by type
                                $progressBar = $null
                                $statusLabel = $null
                                $percentLabel = $null
                                
                                foreach ($control in $progressForm.Controls) {
                                    if ($control -is [System.Windows.Forms.ProgressBar]) {
                                        $progressBar = $control
                                    } elseif ($control -is [System.Windows.Forms.Label]) {
                                        if ($control.Font.Bold) {
                                            $percentLabel = $control
                                        } else {
                                            $statusLabel = $control
                                        }
                                    }
                                }
                                
                                if ($progressBar) {
                                    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                                    $progressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                                }
                                if ($statusLabel) {
                                    $statusLabel.Text = $Status
                                }
                                if ($percentLabel) {
                                    $percentLabel.Text = "$PercentComplete%"
                                }
                                $progressForm.Refresh()
                                
                            } catch {
                                Write-LogMessage "Direct progress UI update error: $_" "WARNING"
                            }
                        }
                    }
                } catch {
                    Write-LogMessage "Progress callback error: $_" "WARNING"
                }
            }
            
            $captureParams = @{
                ImageName = $imageName
                CustomerName = $selectedCustomer
                ImageID = $imageID
                Description = $description
                SourceDrive = $sourceDrive
                Compression = $compression
                Verify = $VerifyCheckBox.Checked
                CheckIntegrity = $IntegrityCheckBox.Checked
            }
            
            $captureResult = Invoke-ImageCapture @captureParams
            
            $progressForm.Close()
            
            # Show results
            if ($captureResult.Success) {
                $resultMessage = @"
Success: Image capture completed successfully!

Capture Details:
- Image Path: $($captureResult.ImagePath)
- Image Size: $($captureResult.ImageSize)
- Duration: $($captureResult.CaptureDuration)
- Config Updated: $(if ($captureResult.ConfigUpdated) { 'Yes' } else { 'No' })

The captured image is now ready for network deployment.
"@
                [System.Windows.Forms.MessageBox]::Show($resultMessage, "Capture Successful", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                # Enhanced error message with troubleshooting tips
                $errorMessage = "Image capture failed:`n`n$($captureResult.Message)"
                
                if ($captureResult.Message -match "space") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Free up space on Z: drive`n- Consider using higher compression`n- Clean up source drive temporary files"
                } elseif ($captureResult.Message -match "conflict|exists") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Reboot source system to WinPE`n- Ensure sysprep was run properly`n- Close all running applications`n- Try capturing from a clean boot"
                } elseif ($captureResult.Message -match "Winre\.wim") {
                    $errorMessage += "`n`nTROUBLESHOOTING:`n- Boot to WinPE for capture`n- Exclude Recovery folder`n- Check for Windows Update processes"
                }
                
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Capture Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
            
        } catch {
            $progressForm.Close()
            [System.Windows.Forms.MessageBox]::Show("An error occurred during capture:`n`n$_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        
        $Form.Close()
        
    } catch {
        Write-LogMessage "Error in image capture process: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-CustomerSelectionMenu {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "=== Customer Selection Menu ===" "INFO"
        
        # Detect screen resolution and calculate scaling
        $screenInfo = Get-ScreenResolution
        $scale = $screenInfo.ScaleFactor
        
        Write-LogMessage "CustomerMenu: Using UI scale factor: $scale for screen resolution $($screenInfo.Width)x$($screenInfo.Height)" "INFO"
        
        # Scale font sizes based on resolution
        $baseFontSize = 9
        $titleFontSize = 16
        $buttonFontSize = 9
        $groupFontSize = 9
        
        $scaledBaseFontSize = [Math]::Max(8, [int]($baseFontSize * $scale))
        $scaledTitleFontSize = [Math]::Max(12, [int]($titleFontSize * $scale))
        $scaledButtonFontSize = [Math]::Max(8, [int]($buttonFontSize * $scale))
        $scaledGroupFontSize = [Math]::Max(8, [int]($groupFontSize * $scale))
        
        # Create main form with scaled dimensions
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Select Customer"
        $form.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 300 $scale))
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.BackColor = [System.Drawing.Color]::White
        
        # Title label with scaled dimensions and font
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Customer Selection"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $scaledTitleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 20 $scale))
        $titleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 360 $scale), (Scale-UIElement 30 $scale))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $form.Controls.Add($titleLabel)
        
        # Customer list box with scaled dimensions
        $customerListBox = New-Object System.Windows.Forms.ListBox
        $customerListBox.Font = New-Object System.Drawing.Font("Segoe UI", $scaledBaseFontSize)
        $customerListBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 70 $scale))
        $customerListBox.Size = New-Object System.Drawing.Size((Scale-UIElement 360 $scale), (Scale-UIElement 150 $scale))
        $form.Controls.Add($customerListBox)
        
        # OK button with scaled dimensions
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $okButton.Location = New-Object System.Drawing.Point((Scale-UIElement 100 $scale), (Scale-UIElement 240 $scale))
        $okButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 30 $scale))
        $okButton.BackColor = [System.Drawing.Color]::LightGreen
        $form.Controls.Add($okButton)
        
        # Cancel button with scaled dimensions
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", $scaledButtonFontSize)
        $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 200 $scale), (Scale-UIElement 240 $scale))
        $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), (Scale-UIElement 30 $scale))
        $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
        $form.Controls.Add($cancelButton)
        
        # Load customer list
        $customers = Get-CustomerList
        Write-LogMessage "Found $($customers.Count) customers" "INFO"
        
        if ($customers.Count -eq 0) {
            Write-LogMessage "No customers found" "WARNING"
            [System.Windows.Forms.MessageBox]::Show("No customers found. Please create a customer first.", "No Customers", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            $form.Dispose()
            return $null
        }
        
        foreach ($customer in $customers) {
            $customerListBox.Items.Add($customer) | Out-Null
            Write-LogMessage "Added customer to list: $customer" "VERBOSE"
        }
        
        # Select first customer by default if available
        if ($customers.Count -gt 0) {
            $customerListBox.SelectedIndex = 0
            Write-LogMessage "Default selected customer: $($customerListBox.SelectedItem)" "INFO"
        }
        
        # Variable to store the selected customer
        $selectedCustomerResult = $null
        
        # OK button click event
        $okButton.Add_Click({
            if ($customerListBox.SelectedItem) {
                $selectedCustomerResult = $customerListBox.SelectedItem.ToString()
                Write-LogMessage "Customer selected in dialog: $selectedCustomerResult" "INFO"
                
                # Validate customer has config
                $configPath = "Y:\DeploymentModules\Config\CustomerConfig\$selectedCustomerResult\Config.json"
                Write-LogMessage "Checking config path: $configPath" "VERBOSE"
                
                if (-not (Test-Path $configPath)) {
                    Write-LogMessage "Customer config not found: $configPath" "ERROR"
                    [System.Windows.Forms.MessageBox]::Show("Customer configuration not found for: $selectedCustomerResult`n`nConfig path: $configPath", "Configuration Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    $selectedCustomerResult = $null
                    return
                }
                
                Write-LogMessage "Customer config found at: $configPath" "INFO"
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            } else {
                Write-LogMessage "No customer selected in dialog" "WARNING"
                [System.Windows.Forms.MessageBox]::Show("Please select a customer.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        })
        
        # Cancel button click event
        $cancelButton.Add_Click({
            Write-LogMessage "Customer selection cancelled" "INFO"
            $selectedCustomerResult = $null
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $form.Close()
        })
        
        # Show form and get result
        Write-LogMessage "Showing customer selection dialog" "INFO"
        $result = $form.ShowDialog()
        $form.Dispose()
        
        Write-LogMessage "Dialog result: $result" "INFO"
        Write-LogMessage "Selected customer result: $selectedCustomerResult" "INFO"
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $selectedCustomerResult) {
            Write-LogMessage "Returning selected customer: $selectedCustomerResult" "SUCCESS"
            return $selectedCustomerResult
        } else {
            Write-LogMessage "Customer selection cancelled or failed" "INFO"
            return $null
        }
        
    } catch {
        Write-LogMessage "Error in customer selection: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $null
    }
}

Export-ModuleMember -Function Show-ImageCaptureMenu, Show-CustomerSelectionMenu