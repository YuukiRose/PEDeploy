# Import required modules
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import Logging module: $_" -ForegroundColor Red
    # Define fallback logging function
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        Write-Host "[$Level] $Message" -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"White"})
    }
}

if (-not ('System.Windows.Forms.Form' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}
if (-not ('System.Drawing.Bitmap' -as [type])) {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}

function Get-ScreenResolution {
    [CmdletBinding()]
    param()
    
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        
        $baseWidth = 1920
        $baseHeight = 1080
        
        $scaleFactorX = $screenWidth / $baseWidth
        $scaleFactorY = $screenHeight / $baseHeight
        $scaleFactor = [Math]::Min($scaleFactorX, $scaleFactorY)
        $scaleFactor = [Math]::Max(1.0, [Math]::Min(2.0, $scaleFactor))
        
        return @{
            Width = $screenWidth
            Height = $screenHeight
            ScaleFactor = $scaleFactor
        }
    }
    catch {
        return @{
            Width = 1920
            Height = 1080
            ScaleFactor = 1.0
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

function Show-ImageSelectionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [string]$OrderNumber,
        
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo,
        
        [Parameter()]
        [array]$CustomerISOs = @()
    )
    
    try {
        Write-LogMessage "Starting image selection for customer: $CustomerName" "INFO"
        Write-LogMessage "Loading customer configuration for: $CustomerName" "INFO"
        
        # Load customer configuration with error handling
        $customerConfig = Get-CustomerImageConfig -CustomerName $CustomerName
        
        if (-not $customerConfig) {
            Write-LogMessage "CRITICAL: Failed to load customer configuration for $CustomerName" "ERROR"
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to load customer configuration for '$CustomerName'.`n`nCannot proceed with image selection without a valid configuration.`n`nPlease check the customer configuration file and try again.",
                "Configuration Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $null
        }
        
        Write-LogMessage "Customer configuration loaded successfully for: $CustomerName" "SUCCESS"
        
        # Import CustomerConfigManager for ISO functionality
        try {
            Import-Module "$PSScriptRoot\..\Core\CustomerConfigManager.psm1" -Force -ErrorAction SilentlyContinue
            $customerISOs = Get-CustomerISOs -CustomerName $CustomerName
            Write-LogMessage "Retrieved $($customerISOs.Count) customer ISOs" "INFO"
        } catch {
            Write-LogMessage "Error getting customer ISOs: $_" "WARNING"
            $customerISOs = @()
        }
        
        # Detect screen resolution and calculate scaling
        $screenInfo = Get-ScreenResolution
        $scaleX = $screenInfo.Width / 1280.0
        $scaleY = $screenInfo.Height / 800.0
        $scale = [Math]::Min($scaleX, $scaleY)
        $scale = [Math]::Min($scale, 1.5)
        $scale = [Math]::Max($scale, 0.7)

        # Scale font sizes based on resolution - ensure minimum values
        $baseFontSize = [Math]::Max(8, [int](9 * $scale))
        $titleFontSize = [Math]::Max(10, [int](14 * $scale))
        $headerFontSize = [Math]::Max(9, [int](11 * $scale))

        Write-LogMessage "Using aspect-ratio aware UI scale: $scale for screen $($screenInfo.Width)x$($screenInfo.Height)" "VERBOSE"

        # Create the base selection form with scaled dimensions - made resizable
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Select Image"
        $form.Size = New-Object System.Drawing.Size([int](900 * $scale), [int](750 * $scale))
        $form.MinimumSize = New-Object System.Drawing.Size([int](800 * $scale), [int](680 * $scale))
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "Sizable"
        $form.MaximizeBox = $true
        $form.MinimizeBox = $true
        
        # Add logo in top-left corner
        $logoPanel = New-Object System.Windows.Forms.Panel
        $logoPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
        $logoPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 80 $scale))
        $logoPanel.BackColor = [System.Drawing.Color]::Transparent
        $logoPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        
        try {
            $logoPath = "Y:\DeploymentModules\Assets\Logo\SHI.png"
            if (Test-Path $logoPath) {
                $logoPictureBox = New-Object System.Windows.Forms.PictureBox
                $logoPictureBox.Location = New-Object System.Drawing.Point(0, 0)
                $logoPictureBox.Size = New-Object System.Drawing.Size((Scale-UIElement 120 $scale), (Scale-UIElement 80 $scale))
                $logoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
                $logoPictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
                $logoPanel.Controls.Add($logoPictureBox)
                Write-LogMessage "Logo loaded successfully" "INFO"
            } else {
                Write-LogMessage "Logo file not found: $logoPath" "WARNING"
            }
        } catch {
            Write-LogMessage "Error loading logo: $_" "WARNING"
        }
        $form.Controls.Add($logoPanel)
        
        # Title label (adjusted for logo)
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Select Deployment Image for $CustomerName"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $titleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
        $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 140 $scale), (Scale-UIElement 20 $scale))
        $titleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 620 $scale), (Scale-UIElement 50 $scale))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $titleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($titleLabel)
        
        # Create tab control for image categories with scaled dimensions and anchoring
        $tabControl = New-Object System.Windows.Forms.TabControl
        $tabControl.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
        $tabControl.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 100 $scale))
        $tabControl.Size = New-Object System.Drawing.Size((Scale-UIElement 840 $scale), (Scale-UIElement 550 $scale))
        $tabControl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($tabControl)
        
        # Create tabs for customer-specific images, base images, and ISOs
        $customerTab = New-Object System.Windows.Forms.TabPage
        $customerTab.Text = "$CustomerName Images"
        $tabControl.Controls.Add($customerTab)
        
        $baseTab = New-Object System.Windows.Forms.TabPage
        $baseTab.Text = "Base Windows Images"
        $tabControl.Controls.Add($baseTab)
        
        # Add ISO tab if customer has ISOs
        $isoTab = $null
        if ($customerISOs.Count -gt 0) {
            $isoTab = New-Object System.Windows.Forms.TabPage
            $isoTab.Text = "$CustomerName ISOs"
            $tabControl.Controls.Add($isoTab)
        }
        
        Write-LogMessage "Customer config loaded successfully. CustomerImages count: $(if ($customerConfig.CustomerImages) { $customerConfig.CustomerImages.Count } else { 0 })" "INFO"
        
        # Create a single radio button group for ALL images (customer, base, and ISOs)
        $allImageGroup = New-Object System.Collections.ArrayList
        
        # --- NEW: Customer Images Two-Column Layout (WIM | FFU) ---
        # Remove old single scroll panel and create a parent panel for columns
        $customerImagesPanel = New-Object System.Windows.Forms.Panel
        $customerImagesPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
        $customerImagesPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 820 $scale), (Scale-UIElement 480 $scale))
        $customerImagesPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $customerTab.Controls.Add($customerImagesPanel)

        # WIM Images GroupBox (left)
        $wimGroupBox = New-Object System.Windows.Forms.GroupBox
        $wimGroupBox.Text = "WIM Images"
        $wimGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $wimGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 0 $scale), (Scale-UIElement 0 $scale))
        $wimGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 470 $scale))
        $wimGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
        $customerImagesPanel.Controls.Add($wimGroupBox)

        # FFU Images GroupBox (right)
        $ffuGroupBox = New-Object System.Windows.Forms.GroupBox
        $ffuGroupBox.Text = "FFU Images"
        $ffuGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $ffuGroupBox.Location = New-Object System.Drawing.Point((Scale-UIElement 410 $scale), (Scale-UIElement 0 $scale))
        $ffuGroupBox.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 470 $scale))
        $ffuGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
        $customerImagesPanel.Controls.Add($ffuGroupBox)

        # Scrollable panels inside each group box
        $wimScrollPanel = New-Object System.Windows.Forms.Panel
        $wimScrollPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 25 $scale))
        $wimScrollPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 430 $scale))
        $wimScrollPanel.AutoScroll = $true
        $wimScrollPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $wimGroupBox.Controls.Add($wimScrollPanel)

        $ffuScrollPanel = New-Object System.Windows.Forms.Panel
        $ffuScrollPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 25 $scale))
        $ffuScrollPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 430 $scale))
        $ffuScrollPanel.AutoScroll = $true
        $ffuScrollPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $ffuGroupBox.Controls.Add($ffuScrollPanel)

        # --- Populate WIM and FFU image lists from available customer images (case-insensitive, fallback to extension) ---
        $wimImages = New-Object System.Collections.ArrayList
        $ffuImages = New-Object System.Collections.ArrayList
        $customerAvailableImages = Get-CustomerAvailableImages -CustomerName $CustomerName
        Write-LogMessage ("DEBUG: Available customer images: " + ($customerAvailableImages | ConvertTo-Json -Compress)) "VERBOSE"
        foreach ($img in $customerAvailableImages) {
            # Debug: Log the image structure and active flag
            Write-LogMessage "DEBUG: Processing image $($img.ImageName) [$($img.ImageID)]" "VERBOSE"
            Write-LogMessage "DEBUG: Image type: $($img.GetType().Name)" "VERBOSE"
            Write-LogMessage "DEBUG: Image properties: $($img.PSObject.Properties.Name -join ', ')" "VERBOSE"
            Write-LogMessage "DEBUG: Active flag value: $($img.Active)" "VERBOSE"
            
            # Only show images if the active flag is present and true
            $isActive = $false
            if ($img -is [hashtable]) {
                if ($img.ContainsKey('Active')) {
                    $isActive = [bool]$img['Active']
                    Write-LogMessage "DEBUG: Hashtable Active check: $isActive" "VERBOSE"
                }
            } elseif ($img.PSObject -and $img.PSObject.Properties.Name -contains 'Active') {
                $isActive = [bool]$img.Active
                Write-LogMessage "DEBUG: PSObject Active check: $isActive" "VERBOSE"
            } else {
                # Try direct property access
                try {
                    if ($null -ne $img.Active) {
                        $isActive = [bool]$img.Active
                        Write-LogMessage "DEBUG: Direct property Active check: $isActive" "VERBOSE"
                    }
                } catch {
                    Write-LogMessage "DEBUG: No Active property found" "VERBOSE"
                }
            }
            
            if (-not $isActive) {
                Write-LogMessage "Skipping customer image (not active): $($img.ImageName) [$($img.ImageID)]" "INFO"
                continue
            }
            
            Write-LogMessage "Including customer image (active): $($img.ImageName) [$($img.ImageID)]" "INFO"
            $type = if ($img.Type) { $img.Type.ToUpper() } else { '' }
            $path = if ($img.Path) { $img.Path } else { '' }
            $ext = if ($path) { [System.IO.Path]::GetExtension($path).ToUpper() } else { '' }
            if ($type -eq 'FFU' -or $ext -eq '.FFU') {
                $null = $ffuImages.Add($img)
            } elseif ($type -eq 'WIM' -or $type -eq 'ESD' -or $ext -eq '.WIM' -or $ext -eq '.ESD') {
                $null = $wimImages.Add($img)
            }
        }
        
        # Populate WIM Images
        $wimY = 10
        if ($wimImages.Count -gt 0) {
            foreach ($imageProps in $wimImages) {
                $radioButton = New-Object System.Windows.Forms.RadioButton
                $radioButton.Text = "$($imageProps.ImageName) ($($imageProps.ImageID))"
                $radioButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
                $radioButton.Location = New-Object System.Drawing.Point(10, $wimY)
                $radioButton.Size = New-Object System.Drawing.Size(340, 20)
                $radioButton.Tag = $imageProps
                $radioButton.Add_CheckedChanged({
                    param($sender, $e)
                    if ($sender.Checked) {
                        foreach ($otherRadio in $allImageGroup) { if ($otherRadio -ne $sender) { $otherRadio.Checked = $false } }
                    }
                })
                $allImageGroup.Add($radioButton) | Out-Null
                $wimScrollPanel.Controls.Add($radioButton)
                $wimY += 25
                if ($imageProps.Description -and $imageProps.Description -ne "WIM Image") {
                    $descLabel = New-Object System.Windows.Forms.Label
                    $descLabel.Text = "    $($imageProps.Description)"
                    $descLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
                    $descLabel.ForeColor = [System.Drawing.Color]::FromArgb(128,128,128)
                    $descLabel.Location = New-Object System.Drawing.Point(30, $wimY)
                    $descLabel.Size = New-Object System.Drawing.Size(320, 15)
                    $wimScrollPanel.Controls.Add($descLabel)
                    $wimY += 20
                }
            }
        } else {
            $noWimLabel = New-Object System.Windows.Forms.Label
            $noWimLabel.Text = "    No WIM images available for this customer"
            $noWimLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $noWimLabel.ForeColor = [System.Drawing.Color]::FromArgb(128,128,128)
            $noWimLabel.Location = New-Object System.Drawing.Point(10, $wimY)
            $noWimLabel.Size = New-Object System.Drawing.Size(340, 20)
            $wimScrollPanel.Controls.Add($noWimLabel)
        }

        # Populate FFU Images
        $ffuY = 10
        if ($ffuImages.Count -gt 0) {
            foreach ($imageProps in $ffuImages) {
                $radioButton = New-Object System.Windows.Forms.RadioButton
                $radioButton.Text = "$($imageProps.ImageName) ($($imageProps.ImageID))"
                $radioButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
                $radioButton.Location = New-Object System.Drawing.Point(10, $ffuY)
                $radioButton.Size = New-Object System.Drawing.Size(340, 20)
                $radioButton.Tag = $imageProps
                $radioButton.Add_CheckedChanged({
                    param($sender, $e)
                    if ($sender.Checked) {
                        foreach ($otherRadio in $allImageGroup) { if ($otherRadio -ne $sender) { $otherRadio.Checked = $false } }
                    }
                })
                $allImageGroup.Add($radioButton) | Out-Null
                $ffuScrollPanel.Controls.Add($radioButton)
                $ffuY += 25
                if ($imageProps.Description -and $imageProps.Description -ne "FFU Image") {
                    $descLabel = New-Object System.Windows.Forms.Label
                    $descLabel.Text = "    $($imageProps.Description)"
                    $descLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
                    $descLabel.ForeColor = [System.Drawing.Color]::FromArgb(128,128,128)
                    $descLabel.Location = New-Object System.Drawing.Point(30, $ffuY)
                    $descLabel.Size = New-Object System.Drawing.Size(320, 15)
                    $ffuScrollPanel.Controls.Add($descLabel)
                    $ffuY += 20
                }
            }
        } else {
            $noFfuLabel = New-Object System.Windows.Forms.Label
            $noFfuLabel.Text = "    No FFU images available for this customer"
            $noFfuLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $noFfuLabel.ForeColor = [System.Drawing.Color]::FromArgb(128,128,128)
            $noFfuLabel.Location = New-Object System.Drawing.Point(10, $ffuY)
            $noFfuLabel.Size = New-Object System.Drawing.Size(340, 20)
            $ffuScrollPanel.Controls.Add($noFfuLabel)
        }

        # END: Customer Images Two-Column Layout

        # (Remove any old/duplicated code for single-column image display below this point)

        # Create base images layout with scaled dimensions and anchoring
        
        # Create title label with scaled dimensions - properly center it above both columns
        $baseTabTitleLabel = New-Object System.Windows.Forms.Label
        $baseTabTitleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 15 $scale))  # Align with the left panel edge
        $baseTabTitleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 810 $scale), (Scale-UIElement 25 $scale))  # Span across both panels (400 + 10 gap + 400)
        $baseTabTitleLabel.Text = "Select Windows Version and Build"
        $baseTabTitleLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $titleFontSize, [System.Drawing.FontStyle]::Bold)
        $baseTabTitleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $baseTabTitleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
        $baseTab.Controls.Add($baseTabTitleLabel)
        
        # Create Windows 10 column with scaled dimensions and anchoring - Move down to accommodate title
        $win10Panel = New-Object System.Windows.Forms.Panel
        $win10Panel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 45 $scale))
        $win10Panel.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 445 $scale))
        $win10Panel.BorderStyle = "FixedSingle"
        $win10Panel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
        $baseTab.Controls.Add($win10Panel)
        
        $win10Label = New-Object System.Windows.Forms.Label
        $win10Label.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
        $win10Label.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 25 $scale))
        $win10Label.Text = "Windows 10"
        $win10Label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $headerFontSize, [System.Drawing.FontStyle]::Bold)
        $win10Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $win10Label.BackColor = [System.Drawing.Color]::LightBlue
        $win10Label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $win10Panel.Controls.Add($win10Label)
        
        # Create Windows 11 column with scaled dimensions and anchoring - Move down to accommodate title
        $win11Panel = New-Object System.Windows.Forms.Panel
        $win11Panel.Location = New-Object System.Drawing.Point((Scale-UIElement 420 $scale), (Scale-UIElement 45 $scale))
        $win11Panel.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 445 $scale))
        $win11Panel.BorderStyle = "FixedSingle"
        $win11Panel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  # Reverted back to Left
        $baseTab.Controls.Add($win11Panel)
        
        $win11Label = New-Object System.Windows.Forms.Label
        $win11Label.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
        $win11Label.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 25 $scale))
        $win11Label.Text = "Windows 11"
        $win11Label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $headerFontSize, [System.Drawing.FontStyle]::Bold)
        $win11Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $win11Label.BackColor = [System.Drawing.Color]::LightGreen
        $win11Label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $win11Panel.Controls.Add($win11Label)
        
        # Get base images and organize by Windows version
        Write-LogMessage "Getting base Windows images..." "VERBOSE"
        $baseImages = Get-BaseWindowsImages -CustomerName $CustomerName -CustomerConfig $customerConfig
        Write-LogMessage "Received $($baseImages.Count) base images" "VERBOSE"
        
        $win10Images = New-Object System.Collections.ArrayList
        $win11Images = New-Object System.Collections.ArrayList
        
        foreach ($image in $baseImages) {
            if ($image.WindowsVersion -eq "10") {
                $null = $win10Images.Add($image)
            } elseif ($image.WindowsVersion -eq "11") {
                $null = $win11Images.Add($image)
            }
        }
        
        # Populate Windows 10 radio buttons
        $yPos10 = 45 + 30  # Start below the title with extra space
        $imageSpacing = [Math]::Max(20, [int](35 * $scale))  # More space between images, scales with UI
        foreach ($image in $win10Images) {
            try {
                Write-LogMessage "Processing Windows 10 image: $($image.ImageID)" "VERBOSE"
                # Skip if explicitly marked as inactive
                if ($image.PSObject.Properties.Name -contains "active" -and $image.active -eq $false) {
                    Write-LogMessage "Skipping inactive base image: $($image.ImageID)" "VERBOSE"
                    continue
                }
                $radioButton = New-Object System.Windows.Forms.RadioButton
                $radioButton.Location = New-Object System.Drawing.Point(10, $yPos10)
                $radioButton.Size = New-Object System.Drawing.Size(340, 20)
                $radioButton.Text = "$($image.BuildVersion) - $($image.DisplayName)"
                $radioButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
                $radioButton.Tag = $image
                $radioButton.Add_CheckedChanged({
                    param($sender, $e)
                    if ($sender.Checked) {
                        foreach ($otherRadio in $allImageGroup) {
                            if ($otherRadio -ne $sender) {
                                $otherRadio.Checked = $false
                            }
                        }
                    }
                })
                if ($image.PSObject.Properties.Name -contains "FileExists" -and $image.FileExists) {
                    $radioButton.ForeColor = [System.Drawing.Color]::Black
                } elseif (Test-Path $image.Path) {
                    $radioButton.ForeColor = [System.Drawing.Color]::Black
                } else {
                    $radioButton.ForeColor = [System.Drawing.Color]::Red
                    if (-not $radioButton.Text.Contains("(Not Available)")) {
                        $radioButton.Text += " (Not Available)"
                    }
                }
                $win10Panel.Controls.Add($radioButton)
                $allImageGroup.Add($radioButton) | Out-Null
                $yPos10 += $imageSpacing
                Write-LogMessage "Added the 10 image radio button: $($image.ImageID)" "VERBOSE"
            }
            catch {
                Write-LogMessage "Error adding Windows 10 image to list: $_" "WARNING"
            }
        }
        
        # Populate Windows 11 radio buttons
        $yPos11 = 45 + 30  # Start below the title with extra space
        $imageSpacing = [Math]::Max(20, [int](35 * $scale))  # More space between images, scales with UI
        foreach ($image in $win11Images) {
            try {
                Write-LogMessage "Processing Windows 11 image: $($image.ImageID)" "VERBOSE"
                # Skip if explicitly marked as inactive
                if ($image.PSObject.Properties.Name -contains "active" -and $image.active -eq $false) {
                    Write-LogMessage "Skipping inactive base image: $($image.ImageID)" "VERBOSE"
                    continue
                }
                $radioButton = New-Object System.Windows.Forms.RadioButton
                $radioButton.Location = New-Object System.Drawing.Point(10, $yPos11)
                $radioButton.Size = New-Object System.Drawing.Size(340, 20)
                $radioButton.Text = "$($image.BuildVersion) - $($image.DisplayName)"
                $radioButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
                $radioButton.Tag = $image
                $radioButton.Add_CheckedChanged({
                    param($sender, $e)
                    if ($sender.Checked) {
                        foreach ($otherRadio in $allImageGroup) {
                            if ($otherRadio -ne $sender) {
                                $otherRadio.Checked = $false
                            }
                        }
                    }
                })
                if ($image.PSObject.Properties.Name -contains "FileExists" -and $image.FileExists) {
                    $radioButton.ForeColor = [System.Drawing.Color]::Black
                } elseif (Test-Path $image.Path) {
                    $radioButton.ForeColor = [System.Drawing.Color]::Black
                } else {
                    $radioButton.ForeColor = [System.Drawing.Color]::Red
                    if (-not $radioButton.Text.Contains("(Not Available)")) {
                        $radioButton.Text += " (Not Available)"
                    }
                }
                $win11Panel.Controls.Add($radioButton)
                $allImageGroup.Add($radioButton) | Out-Null
                $yPos11 += $imageSpacing
                Write-LogMessage "Added Windows 11 image radio button: $($image.ImageID)" "VERBOSE"
            }
            catch {
                Write-LogMessage "Error adding Windows 11 image to list: $_" "WARNING"
            }
        }
        
        # Add "No images" labels if needed
        if ($win10Images.Count -eq 0) {
            $noWin10Label = New-Object System.Windows.Forms.Label
            $noWin10Label.Location = New-Object System.Drawing.Point(10, 45)
            $noWin10Label.Size = New-Object System.Drawing.Size(340, 40)
            $noWin10Label.Text = "No active Windows 10 images found."
            $noWin10Label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize, [System.Drawing.FontStyle]::Italic)
            $noWin10Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $win10Panel.Controls.Add($noWin10Label)
        }
        
        if ($win11Images.Count -eq 0) {
            $noWin11Label = New-Object System.Windows.Forms.Label
            $noWin11Label.Location = New-Object System.Drawing.Point(10, 45)
            $noWin11Label.Size = New-Object System.Drawing.Size(340, 40)
            $noWin11Label.Text = "No active Windows 11 images found."
            $noWin11Label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize, [System.Drawing.FontStyle]::Italic)
            $noWin11Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $win11Panel.Controls.Add($noWin11Label)
        }
        
        Write-LogMessage "Successfully created base images layout with $($win10Images.Count) Windows 10 and $($win11Images.Count) Windows 11 images" "INFO"
        
        # Add buttons at the bottom of the form with scaled dimensions and anchoring
        $selectButton = New-Object System.Windows.Forms.Button
        $selectButton.Location = New-Object System.Drawing.Point((Scale-UIElement 640 $scale), (Scale-UIElement 670 $scale))
        $selectButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $selectButton.Text = "Select"
        $selectButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
        $selectButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $selectButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($selectButton)
        
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 760 $scale), (Scale-UIElement 670 $scale))
        $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 30 $scale))
        $cancelButton.Text = "Cancel"
        $cancelButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $baseFontSize)
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
        $form.Controls.Add($cancelButton)
        
        $form.AcceptButton = $selectButton
        $form.CancelButton = $cancelButton
        
        # Add ISO tab content if ISOs are available with anchoring
        if ($isoTab -and $customerISOs.Count -gt 0) {
            Write-LogMessage "Creating ISO tab with $($customerISOs.Count) ISOs" "INFO"
            
            # Create scrollable panel for ISOs with anchoring
            $isoScrollPanel = New-Object System.Windows.Forms.Panel
            $isoScrollPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
            $isoScrollPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 820 $scale), (Scale-UIElement 480 $scale))
            $isoScrollPanel.AutoScroll = $true
            $isoScrollPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
            $isoTab.Controls.Add($isoScrollPanel)
            
            # Group ISOs by category
            $isoCategories = @{}
            foreach ($iso in $customerISOs) {
                $category = $iso.Category
                if (-not $isoCategories.ContainsKey($category)) {
                    $isoCategories[$category] = New-Object System.Collections.ArrayList
                }
                $null = $isoCategories[$category].Add($iso)
            }
            
            # Initialize Y position for ISOs
            $isoYPosition = 20
            
            # Create sections for each ISO category
            foreach ($categoryName in ($isoCategories.Keys | Sort-Object)) {
                $categoryISOs = $isoCategories[$categoryName]
                
                # Category header
                $categoryLabel = New-Object System.Windows.Forms.Label
                $categoryLabel.Text = "$categoryName ISOs ($($categoryISOs.Count))"
                $categoryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
                $categoryLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
                $categoryLabel.Location = New-Object System.Drawing.Point(20, $isoYPosition)
                $categoryLabel.Size = New-Object System.Drawing.Size(400, 25)
                $isoScrollPanel.Controls.Add($categoryLabel)
                $isoYPosition += 30
                
                # Add ISOs in this category
                foreach ($iso in $categoryISOs) {
                    # Create radio button for this ISO
                    $isoRadioButton = New-Object System.Windows.Forms.RadioButton
                    $isoRadioButton.Text = "$($iso.Name)"
                    $isoRadioButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
                    $isoRadioButton.Location = New-Object System.Drawing.Point(40, $isoYPosition)
                    $isoRadioButton.Size = New-Object System.Drawing.Size(500, 20)
                    
                    # Create ISO image properties for deployment
                    $isoImageProps = @{
                        ImageID = $iso.ID
                        ImageName = $iso.Name
                        Description = $iso.Description
                        Path = $iso.Path
                        Type = 'ISO'
                        Category = $iso.Category
                        Size = $iso.Size
                        Version = $iso.Version
                        Architecture = $iso.Architecture
                        Edition = $iso.Edition
                        DateModified = $iso.DateModified
                        SourceType = 'ISO'
                        RequiredUpdates = $true  # ISOs typically need updates
                        ApplyUnattend = $true
                        DriverInject = $true
                        IsISO = $true
                    }
                    
                    $isoRadioButton.Tag = $isoImageProps
                    
                    # Add event handler to clear ALL other radio buttons when this one is selected
                    $isoRadioButton.Add_CheckedChanged({
                        param($sender, $e)
                        if ($sender.Checked) {
                            # Clear all other radio buttons in the entire group
                            foreach ($otherRadio in $allImageGroup) {
                                if ($otherRadio -ne $sender) {
                                    $otherRadio.Checked = $false
                                }
                            }
                        }
                    })
                    
                    $allImageGroup.Add($isoRadioButton) | Out-Null
                    $isoScrollPanel.Controls.Add($isoRadioButton)
                    $isoYPosition += 25
                    
                    # Add description and details
                    $isoDetailsLabel = New-Object System.Windows.Forms.Label
                    $detailsText = "    Size: $($iso.Size)"
                    if ($iso.Version) { $detailsText += ", Version: $($iso.Version)" }
                    if ($iso.Architecture) { $detailsText += ", Arch: $($iso.Architecture)" }
                    if ($iso.Edition) { $detailsText += ", Edition: $($iso.Edition)" }
                    
                    $isoDetailsLabel.Text = $detailsText
                    $isoDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
                    $isoDetailsLabel.ForeColor = [System.Drawing.Color]::FromArgb(128,128,128)
                    $isoDetailsLabel.Location = New-Object System.Drawing.Point(60, $isoYPosition)
                    $isoDetailsLabel.Size = New-Object System.Drawing.Size(480, 15)
                    $isoScrollPanel.Controls.Add($isoDetailsLabel)
                    $isoYPosition += 20
                    
                    Write-LogMessage "Added ISO radio button: $($iso.Name) in category $categoryName" "INFO"
                }
                
                # Add spacing between categories
                $isoYPosition += 10
            }
            
            Write-LogMessage "Successfully created ISO tab with $($customerISOs.Count) ISOs in $($isoCategories.Count) categories" "INFO"
        }
        
        # Show the form and get the result
        $result = $form.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Write-LogMessage "Dialog OK - preparing selected image data" "INFO"
            
            # Find the selected radio button from all images
            $selectedRadio = $allImageGroup | Where-Object { $_.Checked }
            
            if ($selectedRadio) {
                $selectedImage = $selectedRadio.Tag
                
                # Validate that selectedImage has required properties
                if (-not $selectedImage -or -not $selectedImage.ContainsKey('ImageID')) {
                    Write-LogMessage "ERROR: Invalid image selection - missing required properties" "ERROR"
                    [System.Windows.Forms.MessageBox]::Show(
                        "Invalid image selection. Please select a valid image and try again.",
                        "Selection Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    return $null
                }
                
                # Immediately return for FFU images before any edition selection logic
                if ((($selectedImage.Type -and $selectedImage.Type.ToUpper() -eq 'FFU') -or ([System.IO.Path]::GetExtension($selectedImage.Path).ToUpper() -eq '.FFU'))) {
                    Write-LogMessage "Selected FFU image: $($selectedImage.ImageID) (no edition selection required)" "INFO"
                    return @{
                        ImageInfo = @{
                            Name = $selectedImage.ImageName
                            FullPath = $selectedImage.Path
                            ImageID = $selectedImage.ImageID
                            Type = $selectedImage.Type
                            Edition = $selectedImage.Edition
                            Description = $selectedImage.Description
                            OSInfo = $selectedImage.OSInfo
                            RequiredUpdates = [bool]$selectedImage.RequiredUpdates
                            ApplyUnattend = [bool]$selectedImage.ApplyUnattend
                            DriverInject = [bool]$selectedImage.DriverInject
                        }
                        CustomerName = $CustomerName
                        OrderNumber = $OrderNumber
                        DeviceInfo = $DeviceInfo
                    }
                }
                # Check if it's an ISO, customer image, or base image
                if ($selectedImage.ContainsKey('IsISO') -and $selectedImage['IsISO']) {
                    # ISO selected - handle ISO deployment
                    Write-LogMessage "Selected ISO: $($selectedImage.ImageID)" "INFO"
                    
                    # Import ISOManager to get image information from the ISO
                    try {
                        Import-Module "$PSScriptRoot\..\Core\ISOManager.psm1" -Force
                        Write-LogMessage "Getting image information from ISO: $($selectedImage.Path)" "INFO"
                        
                        # Get image information from the ISO and keep it mounted
                        $isoImageInfo = Get-ISOImageInfo -ISOPath $selectedImage.Path -KeepMounted
                        
                        if ($isoImageInfo -and $isoImageInfo.Count -gt 0) {
                            Write-LogMessage "Found $($isoImageInfo.Count) Windows editions in ISO" "INFO"
                            
                            # Show dynamic edition selection for ISO based on actual contents
                            $editionInfo = Show-DynamicEditionSelectionMenu -ImageInfo $isoImageInfo -ImageType "ISO"
                            
                            if ($editionInfo) {
                                # User selected an edition - ISO is already mounted from Get-ISOImageInfo
                                Write-LogMessage "User selected ISO edition: $($editionInfo.Name) (Index: $($editionInfo.Index))" "INFO"
                                
                                # Show deployment options dialog for ISOs
                                $deploymentOptions = Show-ISODeploymentOptionsDialog -ISOName $selectedImage.ImageName -EditionName $editionInfo.Name
                                
                                if ($deploymentOptions) {
                                    Write-LogMessage "User configured deployment options - Driver Injection: $($deploymentOptions.DriverInject), Updates: $($deploymentOptions.RequiredUpdates), Unattend: $($deploymentOptions.ApplyUnattend)" "INFO"
                                    
                                    # Find the selected image info from the original ISO scan
                                    $selectedImageInfo = $isoImageInfo | Where-Object { $_.ImageIndex -eq $editionInfo.Index }
                                    
                                    if (-not $selectedImageInfo) {
                                        $selectedImageInfo = $isoImageInfo[0]  # Fallback to first image
                                    }
                                    
                                    # Use the already mounted install.wim path
                                    $mountedInstallWimPath = $selectedImageInfo.InstallWimPath
                                    $mountedDriveLetter = $selectedImageInfo.MountedDrive
                                    
                                    Write-LogMessage "Using already mounted install.wim at: $mountedInstallWimPath" "SUCCESS"
                                    
                                    return @{
                                        ImageInfo = @{
                                            Name = "$($selectedImage.ImageName) - $($editionInfo.Name)"
                                            FullPath = $mountedInstallWimPath  # Use the mounted install.wim path
                                            ImageID = $selectedImage.ImageID
                                            Type = $selectedImage.Type
                                            ImageIndex = [int]$editionInfo.Index
                                            Edition = $editionInfo.Name
                                            Description = $selectedImage.Description
                                            Category = $selectedImage.Category
                                            Size = $selectedImage.Size
                                            Version = $selectedImage.Version
                                            Architecture = $selectedImage.Architecture
                                            RequiredUpdates = $deploymentOptions.RequiredUpdates
                                            ApplyUnattend = $deploymentOptions.ApplyUnattend
                                            DriverInject = $deploymentOptions.DriverInject
                                            SourceType = 'ISO'
                                            IsISO = $true
                                            # Keep track of ISO details for cleanup later
                                            ISOPath = $selectedImage.Path  # Original ISO path
                                            MountedDriveLetter = $mountedDriveLetter
                                            IsMounted = $true
                                            # Add Windows image information from the ISO
                                            WindowsVersion = $selectedImageInfo.ImageName
                                            WindowsBuild = $selectedImageInfo.ImageVersion
                                            InstallWimPath = $mountedInstallWimPath
                                        }
                                        CustomerName = $CustomerName
                                        OrderNumber = $OrderNumber
                                        DeviceInfo = $DeviceInfo
                                    }
                                } else {
                                    # User cancelled deployment options - dismount the ISO
                                    Write-LogMessage "User cancelled deployment options, dismounting ISO" "INFO"
                                    try {
                                        if ($isoImageInfo -and $isoImageInfo[0] -and $isoImageInfo[0].MountedDrive) {
                                            Dismount-ISOWithDiskpart -MountLetter $isoImageInfo[0].MountedDrive
                                        }
                                    } catch {
                                        Write-LogMessage "Warning: Failed to dismount ISO after cancellation: $_" "WARNING"
                                    }
                                    return $null
                                }
                            } else {
                                # User cancelled ISO edition selection - dismount the ISO
                                Write-LogMessage "User cancelled ISO edition selection, dismounting ISO" "INFO"
                                try {
                                    if ($isoImageInfo -and $isoImageInfo[0] -and $isoImageInfo[0].MountedDrive) {
                                        Dismount-ISOWithDiskpart -MountLetter $isoImageInfo[0].MountedDrive
                                    }
                                } catch {
                                    Write-LogMessage "Warning: Failed to dismount ISO after cancellation: $_" "WARNING"
                                }
                                return $null
                            }
                        } else {
                            Write-LogMessage "Failed to get image information from ISO" "ERROR"
                            [System.Windows.Forms.MessageBox]::Show(
                                "Failed to get image information from the selected ISO file. The ISO may be corrupted or not a valid Windows installation ISO.",
                                "ISO Error",
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Error
                            )
                            return $null
                        }
                    } catch {
                        Write-LogMessage "Error processing ISO: $_" "ERROR"
                        [System.Windows.Forms.MessageBox]::Show(
                            "Error processing ISO file: $_",
                            "ISO Error",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Error
                        )
                        return $null
                    }
                } elseif ($selectedImage.ContainsKey('Edition') -and $selectedImage['Edition'] -eq 'Custom Image') {
                    # Customer image selected - return with proper structure including config flags
                    Write-LogMessage "Selected custom image: $($selectedImage.ImageID)" "INFO"
                    Write-LogMessage "Custom image config - RequiredUpdates: $($selectedImage.RequiredUpdates), ApplyUnattend: $($selectedImage.ApplyUnattend)" "INFO"
                    
                    # Validate that the image has all required configuration
                    if (-not $selectedImage.ContainsKey('RequiredUpdates')) {
                        Write-LogMessage "WARNING: Custom image missing RequiredUpdates flag, defaulting to false" "WARNING"
                        $selectedImage.RequiredUpdates = $false
                    }
                    if (-not $selectedImage.ContainsKey('ApplyUnattend')) {
                        Write-LogMessage "WARNING: Custom image missing ApplyUnattend flag, defaulting to true" "WARNING"
                        $selectedImage.ApplyUnattend = $true
                    }
                    if (-not $selectedImage.ContainsKey('DriverInject')) {
                        Write-LogMessage "WARNING: Custom image missing DriverInject flag, defaulting to true" "WARNING"
                        $selectedImage.DriverInject = $true
                    }
                    
                    return @{
                        ImageInfo = @{
                            Name = $selectedImage.ImageName
                            FullPath = $selectedImage.Path
                            ImageID = $selectedImage.ImageID
                            Type = $selectedImage.Type
                            ImageIndex = $selectedImage.ImageIndex
                            Edition = $selectedImage.Edition
                            Description = $selectedImage.Description
                            OSInfo = $selectedImage.OSInfo
                            RequiredUpdates = [bool]$selectedImage.RequiredUpdates
                            ApplyUnattend = [bool]$selectedImage.ApplyUnattend
                            DriverInject = [bool]$selectedImage.DriverInject
                        }
                        CustomerName = $CustomerName
                        OrderNumber = $OrderNumber
                        DeviceInfo = $DeviceInfo
                    }
                } else {
                    # Base image selected - get actual editions from the ESD file
                    Write-LogMessage "Selected base image: $($selectedImage.ImageID)" "INFO"
                    
                    # Get actual image information from the ESD file
                    try {
                        Write-LogMessage "Getting image information from ESD: $($selectedImage.Path)" "INFO"
                        
                        # Get image info from the ESD file using DISM
                        $esdImageInfo = @()
                        
                        # Use DISM to get image information
                        $dismOutput = & dism /Get-WimInfo /WimFile:"$($selectedImage.Path)" 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            # Parse DISM output to extract image information
                            $currentImage = $null
                            
                            foreach ($line in $dismOutput) {
                                if ($line -match "Index : (\d+)") {
                                    if ($currentImage) {
                                        $esdImageInfo += $currentImage
                                    }
                                    $currentImage = @{
                                        ImageIndex = [int]$Matches[1]
                                        ImageName = ""
                                        ImageDescription = ""
                                        Architecture = ""
                                        ImageVersion = ""
                                    }
                                } elseif ($line -match "Name : (.+)" -and $currentImage) {
                                    $currentImage.ImageName = $Matches[1].Trim()
                                } elseif ($line -match "Description : (.+)" -and $currentImage) {
                                    $currentImage.ImageDescription = $Matches[1].Trim()
                                } elseif ($line -match "Architecture : (.+)" -and $currentImage) {
                                    $currentImage.Architecture = $Matches[1].Trim()
                                } elseif ($line -match "Version : (.+)" -and $currentImage) {
                                    $currentImage.ImageVersion = $Matches[1].Trim()
                                }
                            }
                            
                            # Add the last image
                            if ($currentImage) {
                                $esdImageInfo += $currentImage
                            }
                        }
                        
                        # If DISM parsing failed or returned no results, use default editions for dynamic menu
                        if ($esdImageInfo.Count -eq 0) {
                            Write-LogMessage "DISM parsing failed or no images found, using default ESD editions for dynamic menu" "WARNING"
                            $esdImageInfo = @(
                                @{
                                    ImageIndex = 4
                                    ImageName = "Windows Enterprise"
                                    ImageDescription = "Windows Enterprise"
                                    Architecture = "x64"
                                    ImageVersion = $selectedImage.BuildVersion
                                },
                                @{
                                    ImageIndex = 6
                                    ImageName = "Windows Pro"
                                    ImageDescription = "Windows Pro"
                                    Architecture = "x64"
                                    ImageVersion = $selectedImage.BuildVersion
                                }
                            )
                        }
                        
                        Write-LogMessage "Found $($esdImageInfo.Count) editions in ESD file (including defaults if needed)" "INFO"
                        
                        # Always show dynamic edition selection for ESD based on actual or default contents
                        $editionInfo = Show-DynamicEditionSelectionMenu -ImageInfo $esdImageInfo -ImageType "ESD"
                        
                        if ($editionInfo) {
                            # Get deployment settings from customer config
                            $deploymentSettings = @{
                                RequiredUpdates = $true
                                ApplyUnattend = $true
                                DriverInject = $true
                            }
                            
                            if ($customerConfig -and $customerConfig.ContainsKey('DeploymentSettings')) {
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultRequiredUpdates')) {
                                    $deploymentSettings.RequiredUpdates = [bool]$customerConfig.DeploymentSettings.DefaultRequiredUpdates
                                }
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultApplyUnattend')) {
                                    $deploymentSettings.ApplyUnattend = [bool]$customerConfig.DeploymentSettings.DefaultApplyUnattend
                                }
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultDriverInject')) {
                                    $deploymentSettings.DriverInject = [bool]$customerConfig.DeploymentSettings.DefaultDriverInject
                                }
                            }
                            
                            Write-LogMessage "Base image deployment settings - RequiredUpdates: $($deploymentSettings.RequiredUpdates), ApplyUnattend: $($deploymentSettings.ApplyUnattend)" "INFO"
                            
                            $finalImage = @{
                                ImageInfo = @{
                                    Name = "$($selectedImage.DisplayName) $($editionInfo.Name)"
                                    FullPath = $selectedImage.Path
                                    ImageID = $selectedImage.ImageID
                                    Type = "ESD"
                                    ImageIndex = [int]$editionInfo.Index
                                    Edition = $editionInfo.Name
                                    WindowsVersion = $selectedImage.WindowsVersion
                                    BuildVersion = $selectedImage.BuildVersion
                                    IsBaseImage = $true
                                    RequiredUpdates = $deploymentSettings.RequiredUpdates
                                    ApplyUnattend = $deploymentSettings.ApplyUnattend
                                    DriverInject = $deploymentSettings.DriverInject
                                }
                                CustomerName = $CustomerName
                                OrderNumber = $OrderNumber
                                DeviceInfo = $DeviceInfo
                            }
                            
                            Write-LogMessage "Selected base image: $($finalImage.ImageInfo.ImageID) - Edition: $($editionInfo.Name) (Index: $($editionInfo.Index)) - RequiredUpdates: $($finalImage.ImageInfo.RequiredUpdates), ApplyUnattend: $($finalImage.ImageInfo.ApplyUnattend)" "INFO"
                            return $finalImage
                        } else {
                            Write-LogMessage "User cancelled edition selection" "INFO"
                            return $null
                        }
                        
                    } catch {
                        Write-LogMessage "Error getting ESD image information: $_" "ERROR"
                        Write-LogMessage "Using default editions for dynamic selection menu" "WARNING"
                        
                        # Use default editions for dynamic menu instead of falling back to static
                        $defaultEsdImageInfo = @(
                            @{
                                ImageIndex = 4
                                ImageName = "Windows Enterprise"
                                ImageDescription = "Windows Enterprise"
                                Architecture = "x64"
                                ImageVersion = if ($selectedImage.BuildVersion) { $selectedImage.BuildVersion } else { "Unknown" }
                            },
                            @{
                                ImageIndex = 6
                                ImageName = "Windows Pro"
                                ImageDescription = "Windows Pro"
                                Architecture = "x64"
                                ImageVersion = if ($selectedImage.BuildVersion) { $selectedImage.BuildVersion } else { "Unknown" }
                            }
                        )
                        
                        # Show dynamic edition selection with default editions
                        $editionInfo = Show-DynamicEditionSelectionMenu -ImageInfo $defaultEsdImageInfo -ImageType "ESD"
                        
                        if ($editionInfo) {
                            # Get deployment settings from customer config
                            $deploymentSettings = @{
                                RequiredUpdates = $true
                                ApplyUnattend = $true
                                DriverInject = $true
                            }
                            
                            if ($customerConfig -and $customerConfig.ContainsKey('DeploymentSettings')) {
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultRequiredUpdates')) {
                                    $deploymentSettings.RequiredUpdates = [bool]$customerConfig.DeploymentSettings.DefaultRequiredUpdates
                                }
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultApplyUnattend')) {
                                    $deploymentSettings.ApplyUnattend = [bool]$customerConfig.DeploymentSettings.DefaultApplyUnattend
                                }
                                if ($customerConfig.DeploymentSettings.ContainsKey('DefaultDriverInject')) {
                                    $deploymentSettings.DriverInject = [bool]$customerConfig.DeploymentSettings.DefaultDriverInject
                                }
                            }
                            
                            $finalImage = @{
                                ImageInfo = @{
                                    Name = "$($selectedImage.DisplayName) $($editionInfo.Name)"
                                    FullPath = $selectedImage.Path
                                    ImageID = $selectedImage.ImageID
                                    Type = "ESD"
                                    ImageIndex = [int]$editionInfo.Index
                                    Edition = $editionInfo.Name
                                    WindowsVersion = $selectedImage.WindowsVersion
                                    BuildVersion = $selectedImage.BuildVersion
                                    IsBaseImage = $true
                                    RequiredUpdates = $deploymentSettings.RequiredUpdates
                                    ApplyUnattend = $deploymentSettings.ApplyUnattend
                                    DriverInject = $deploymentSettings.DriverInject
                                }
                                CustomerName = $CustomerName
                                OrderNumber = $OrderNumber
                                DeviceInfo = $DeviceInfo
                            }
                            
                            Write-LogMessage "Selected base image (with default editions): $($finalImage.ImageInfo.ImageID) - Edition: $($editionInfo.Name) (Index: $($editionInfo.Index)) - RequiredUpdates: $($finalImage.ImageInfo.RequiredUpdates), ApplyUnattend: $($finalImage.ImageInfo.ApplyUnattend)" "INFO"
                            return $finalImage
                        } else {
                            Write-LogMessage "User cancelled edition selection" "INFO"
                            return $null
                        }
                    }
                }
            } else {
                Write-LogMessage "ERROR: No image was selected" "ERROR"
                [System.Windows.Forms.MessageBox]::Show(
                    "Please select an image before proceeding.",
                    "No Selection",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return $null
            }
        } else {
            Write-LogMessage "User cancelled image selection" "INFO"
            return $null
        }
        
    } catch {
        Write-LogMessage "CRITICAL ERROR in image selection: $_" "ERROR"
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "A critical error occurred during image selection:`n`n$_`n`nPlease check the logs and try again.",
            "Critical Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $null
    }
}

function Apply-UnattendFileToWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory)]
        [string]$CustomerName
    )
    
    try {
        Write-LogMessage "Starting unattend file application..." "INFO"
        
        # Look for customer-specific unattend file first
        $customerUnattendPath = "Y:\DeploymentModules\Config\CustomerConfig\$CustomerName\Unattend.xml"
        $defaultUnattendPath = "Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Unattend.xml"
        
        if (Test-Path $customerUnattendPath) {
            Write-LogMessage "Using customer-specific unattend file: $customerUnattendPath" "INFO"
            $unattendPath = $customerUnattendPath
        } elseif (Test-Path $defaultUnattendPath) {
            Write-LogMessage "Using default unattend file: $defaultUnattendPath" "INFO"
            $unattendPath = $defaultUnattendPath
        } else {
            Write-LogMessage "No unattend file found for customer $CustomerName" "WARNING"
            return $false
        }
        
        # Mount the Windows image
        $mountResult = Mount-WindowsImage -ImagePath $WindowsDrive\install.wim -Index 1 -MountPath $WindowsDrive\Mount -ErrorAction Stop
        if (-not $mountResult) {
            Write-LogMessage "Failed to mount Windows image" "ERROR"
            return $false
        }
        
        # Apply the unattend file
        dism /Image:$WindowsDrive\Mount /Apply-Unattend:$unattendPath /LogPath:$WindowsDrive\dism.log
        
        # Unmount and commit changes
        Dismount-WindowsImage -MountPath $WindowsDrive\Mount -Commit -ErrorAction Stop
        
        Write-LogMessage "Unattend file applied successfully" "SUCCESS"
        return $true
    } catch {
        Write-LogMessage "Error applying unattend file: $_" "ERROR"
        return $false
    }
}

function Get-CustomerImageConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName
    )
    
    try {
        $configPath = "Y:\DeploymentModules\Config\CustomerConfig\$CustomerName\Config.json"
        
        if (-not (Test-Path $configPath)) {
            Write-LogMessage "Customer config file not found: $configPath" "WARNING"
            # Try default configuration
            $defaultConfigPath = "Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Default.json"
            if (Test-Path $defaultConfigPath) {
                Write-LogMessage "Using default configuration: $defaultConfigPath" "INFO"
                $configPath = $defaultConfigPath
            } else {
                Write-LogMessage "Default config file not found: $defaultConfigPath" "ERROR"
                return $null
            }
        }
        
        Write-LogMessage "Loading customer config from: $configPath" "VERBOSE"
        
        # Load the content from the file
        $configContent = Get-Content $configPath -Raw -ErrorAction Stop
        
        # Pre-process JSON to handle duplicate keys
        $cleanedContent = $configContent
        
        # Check for duplicate keys and clean them up
        if ($configContent -match '"BaseImages"\s*:' -and $configContent -match '"baseImages"\s*:') {
            Write-LogMessage "Found duplicate BaseImages/baseImages keys, cleaning up..." "WARNING"
            
            # Remove the duplicate "BaseImages" section (keep "baseImages")
            $cleanedContent = $configContent -replace '"BaseImages"\s*:\s*\{\s*\}\s*,?\s*', ''
        }
        
        # Convert from JSON without -AsHashtable for compatibility with older PowerShell versions
        $configObject = $cleanedContent | ConvertFrom-Json
        
        # Convert PSCustomObject to hashtable manually for older PowerShell compatibility
        $config = Convert-PSObjectToHashtable -InputObject $configObject
        
        if (-not $config) {
            Write-LogMessage "Failed to convert config object to hashtable" "ERROR"
            return $null
        }
        
        Write-LogMessage "Successfully loaded customer config for $CustomerName" "INFO"
        return $config
        
    } catch {
        Write-LogMessage "Failed to load customer config for $CustomerName`: $_" "ERROR"
        
        # Try to load default configuration as fallback
        try {
            $defaultConfigPath = "Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Default.json"
            if (Test-Path $defaultConfigPath) {
                Write-LogMessage "Attempting to load default configuration as fallback: $defaultConfigPath" "WARNING"
                $configContent = Get-Content $defaultConfigPath -Raw -ErrorAction Stop
                $configObject = $configContent | ConvertFrom-Json
                $config = Convert-PSObjectToHashtable -InputObject $configObject
                
                if ($config) {
                    Write-LogMessage "Successfully loaded default configuration as fallback" "INFO"
                    return $config
                }
            }
        } catch {
            Write-LogMessage "Failed to load default configuration fallback: $_" "WARNING"
        }
        
        # Provide more specific error messages
        if ($_.Exception.Message -match "duplicated keys") {
            Write-LogMessage "Configuration file contains duplicate keys. Please check and fix the JSON structure." "ERROR"
        } elseif ($_.Exception.Message -match "Invalid JSON") {
            Write-LogMessage "Configuration file contains invalid JSON. Please validate the JSON syntax." "ERROR"
        }
        
        return $null
    }
}

function Convert-PSObjectToHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )
    
    try {
        if ($InputObject -eq $null) {
            return $null
        }
        
        if ($InputObject -is [hashtable]) {
            return $InputObject
        }
        
        if ($InputObject -is [array]) {
            $array = @()
            foreach ($item in $InputObject) {
                $array += Convert-PSObjectToHashtable -InputObject $item
            }
            return $array
        }
        
        if ($InputObject -is [PSCustomObject]) {
            $hashtable = @{}
            
            $InputObject.PSObject.Properties | ForEach-Object {
                $key = $_.Name
                $value = $_.Value
                
                if ($value -is [PSCustomObject] -or $value -is [array]) {
                    $hashtable[$key] = Convert-PSObjectToHashtable -InputObject $value
                } else {
                    $hashtable[$key] = $value
                }
            }
            
            return $hashtable
        }
        
        # Return primitive types as-is
        return $InputObject
        
    } catch {
        Write-LogMessage "Error converting PSObject to hashtable: $_" "ERROR"
        return $InputObject
    }
}

function Get-CustomerAvailableImages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName
    )
    
    $availableImages = @()
    
    try {
        Write-LogMessage "Getting available images for customer: $CustomerName" "VERBOSE"
        
        # Get customer configuration first
        $customerConfig = Get-CustomerImageConfig -CustomerName $CustomerName
        
        # --- NEW: Check WIMImages section ---
        if ($customerConfig -and $customerConfig.ContainsKey('WIMImages')) {
            foreach ($imageKey in $customerConfig.WIMImages.Keys) {
                $image = $customerConfig.WIMImages[$imageKey]
                # Preserve the actual active flag from config (hashtable check)
                $activeFlag = if ($image.ContainsKey('active')) { 
                    [bool]$image.active 
                } else { 
                    $true  # Default to true if missing
                }
                Write-LogMessage "WIMImage ${imageKey}: active flag in config = $($image.active), using activeFlag = $activeFlag" "VERBOSE"
                $availableImages += @{
                    ImageID = if ($image.ImageID) { $image.ImageID } else { $imageKey }
                    ImageName = if ($image.ImageName) { $image.ImageName } else { $imageKey }
                    Description = if ($image.Description) { $image.Description } else { "WIM Image" }
                    Path = if ($image.FullPath) { $image.FullPath } else { $image.Path }
                    Type = 'WIM'
                    Active = $activeFlag
                    Edition = 'Custom Image'
                    RequiredUpdates = if ($image.ContainsKey('RequiredUpdates')) { [bool]$image.RequiredUpdates } else { $false }
                    ApplyUnattend = if ($image.ContainsKey('ApplyUnattend')) { [bool]$image.ApplyUnattend } else { $true }
                    DriverInject = if ($image.ContainsKey('DriverInject')) { [bool]$image.DriverInject } else { $true }
                }
            }
        }
        # --- NEW: Check FFUImages section ---
        if ($customerConfig -and $customerConfig.ContainsKey('FFUImages')) {
            foreach ($imageKey in $customerConfig.FFUImages.Keys) {
                $image = $customerConfig.FFUImages[$imageKey]
                # Preserve the actual active flag from config (hashtable check)
                $activeFlag = if ($image.ContainsKey('active')) { 
                    [bool]$image.active 
                } else { 
                    $true  # Default to true if missing
                }
                Write-LogMessage "FFUImage ${imageKey}: active flag in config = $($image.active), using activeFlag = $activeFlag" "VERBOSE"
                $availableImages += @{
                    ImageID = if ($image.ImageID) { $image.ImageID } else { $imageKey }
                    ImageName = if ($image.ImageName) { $image.ImageName } else { $imageKey }
                    Description = if ($image.Description) { $image.Description } else { "FFU Image" }
                    Path = if ($image.FullPath) { $image.FullPath } else { $image.Path }
                    Type = 'FFU'
                    Active = $activeFlag
                    Edition = 'Custom Image'
                    RequiredUpdates = if ($image.ContainsKey('RequiredUpdates')) { [bool]$image.RequiredUpdates } else { $false }
                    ApplyUnattend = if ($image.ContainsKey('ApplyUnattend')) { [bool]$image.ApplyUnattend } else { $true }
                    DriverInject = if ($image.ContainsKey('DriverInject')) { [bool]$image.DriverInject } else { $true }
                }
            }
        }
        # --- Legacy: Check CustomerImages section ---
        if ($customerConfig -and $customerConfig.ContainsKey('CustomerImages')) {
            foreach ($imageKey in $customerConfig.CustomerImages.Keys) {
                $image = $customerConfig.CustomerImages[$imageKey]
                # Preserve the actual active flag from config (hashtable check)
                $activeFlag = if ($image.ContainsKey('active')) { 
                    [bool]$image.active 
                } else { 
                    $true  # Default to true if missing
                }
                # --- Use CaptureMethod for type detection ---
                $imageType = 'WIM' # Default
                if ($image.ContainsKey('CaptureMethod')) {
                    if ($image.CaptureMethod -eq 'FFU') {
                        $imageType = 'FFU'
                    } elseif ($image.CaptureMethod -eq 'WIM' -or $image.CaptureMethod -eq 'ESD') {
                        $imageType = 'WIM'
                    }
                } elseif ($image.Type) {
                    $imageType = $image.Type
                }
                $availableImages += @{
                    ImageID = if ($image.ImageID) { $image.ImageID } else { $imageKey }
                    ImageName = if ($image.ImageName) { $image.ImageName } else { $imageKey }
                    Description = if ($image.Description) { $image.Description } else { "Customer Image" }
                    Path = if ($image.FullPath) { $image.FullPath } else { $image.Path }
                    Type = $imageType
                    Active = $activeFlag
                    Edition = 'Custom Image'
                    RequiredUpdates = if ($image.ContainsKey('RequiredUpdates')) { [bool]$image.RequiredUpdates } else { $false }
                    ApplyUnattend = if ($image.ContainsKey('ApplyUnattend')) { [bool]$image.ApplyUnattend } else { $true }
                    DriverInject = if ($image.ContainsKey('DriverInject')) { [bool]$image.DriverInject } else { $true }
                }
            }
        }
        # Also scan filesystem for customer images (WIM only)
        $customerImagePath = "Z:\CustomerImages\$CustomerName"
        if (Test-Path $customerImagePath) {
            $imageFiles = Get-ChildItem -Path $customerImagePath -Filter "*.wim" -Recurse -ErrorAction SilentlyContinue
            foreach ($imageFile in $imageFiles) {
                # Only add if not already in config
                $existingImage = $availableImages | Where-Object { $_.Path -eq $imageFile.FullName }
                if (-not $existingImage) {
                    $availableImages += @{
                        ImageID = [System.IO.Path]::GetFileNameWithoutExtension($imageFile.Name)
                        ImageName = [System.IO.Path]::GetFileNameWithoutExtension($imageFile.Name)
                        Description = "Discovered Customer Image"
                        Path = $imageFile.FullName
                        Type = "WIM" # Default for discovered images
                        Active = $true
                        Edition = 'Custom Image'
                        RequiredUpdates = $false  # Default for discovered images
                        ApplyUnattend = $true
                        DriverInject = $true
                    }
                }
            }
        }
        Write-LogMessage "Found $($availableImages.Count) available images for customer $CustomerName" "INFO"
        return $availableImages
    } catch {
        Write-LogMessage "Error getting customer available images: $_" "ERROR"
        return @()
    }
}

function Get-DefaultBaseImages {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Loading default base Windows images..." "VERBOSE"
        
        # Define hardcoded default images with proper structured paths
        $defaultImageDefinitions = @(
            @{
                ImageID = "WIN10_22H2_PRO"
                DisplayName = "Windows 10 Pro 22H2"
                WindowsVersion = "10"
                BuildVersion = "22H2"
                Path = "Z:\BaseImages\Windows\10\22H2\install.esd"
                Type = "ESD"
            },
            @{
                ImageID = "WIN10_21H2_PRO"
                DisplayName = "Windows 10 Pro 21H2"
                WindowsVersion = "10"
                BuildVersion = "21H2"
                Path = "Z:\BaseImages\Windows\10\21H2\install.esd"
                Type = "ESD"
            },
            @{
                ImageID = "WIN11_24H2_PRO"
                DisplayName = "Windows 11 Pro 24H2"
                WindowsVersion = "11"
                BuildVersion = "24H2"
                Path = "Z:\BaseImages\Windows\11\24H2\install.esd"
                Type = "ESD"
            },
            @{
                ImageID = "WIN11_23H2_PRO"
                DisplayName = "Windows 11 Pro 23H2"
                WindowsVersion = "11"
                BuildVersion = "23H2"
                Path = "Z:\BaseImages\Windows\11\23H2\install.esd"
                Type = "ESD"
            },
            @{
                ImageID = "WIN11_22H2_PRO"
                DisplayName = "Windows 11 Pro 22H2"
                WindowsVersion = "11"
                BuildVersion = "22H2"
                Path = "Z:\BaseImages\Windows\11\22H2\install.esd"
                Type = "ESD"
            },
            @{
                ImageID = "WIN11_21H2_PRO"
                DisplayName = "Windows 11 Pro 21H2"
                WindowsVersion = "11"
                BuildVersion = "21H2"
                Path = "Z:\BaseImages\Windows\11\21H2\install.esd"
                Type = "ESD"
            }
        )
        
        $availableImages = @()
        
        # Only include images that actually exist on the filesystem
        foreach ($imageDefinition in $defaultImageDefinitions) {
            $fileExists = Test-Path $imageDefinition.Path
            
            if ($fileExists) {
                try {
                    $fileInfo = Get-Item $imageDefinition.Path -ErrorAction SilentlyContinue
                    $image = @{
                        ImageID = $imageDefinition.ImageID
                        DisplayName = $imageDefinition.DisplayName
                        WindowsVersion = $imageDefinition.WindowsVersion
                        BuildVersion = $imageDefinition.BuildVersion
                        Path = $imageDefinition.Path
                        Type = $imageDefinition.Type
                        FileSize = if ($fileInfo) { [Math]::Round($fileInfo.Length / 1GB, 2) } else { 0 }
                        DateModified = if ($fileInfo) { $fileInfo.LastWriteTime } else { Get-Date }
                        FileExists = $true
                        active = $true
                    }
                    $availableImages += $image
                    Write-LogMessage "Found available default image: $($image.ImageID) at $($image.Path)" "VERBOSE"
                } catch {
                    Write-LogMessage "Error processing existing default image $($imageDefinition.ImageID): $_" "WARNING"
                }
            } else {
                Write-LogMessage "Default image not found on filesystem: $($imageDefinition.ImageID) at $($imageDefinition.Path)" "VERBOSE"
            }
        }
        
        Write-LogMessage "Returning $($availableImages.Count) available default base images (out of $($defaultImageDefinitions.Count) defined)" "INFO"
        return $availableImages
        
    } catch {
        Write-LogMessage "Error in Get-DefaultBaseImages: $_" "ERROR"
        return @()
    }
}

function Get-BaseWindowsImages {
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter()]
        [hashtable]$CustomerConfig = @{
        }
    )
    
    try {
        Write-LogMessage "Scanning base Windows images for customer: $CustomerName" "VERBOSE"
        $images = @()
        
        # Always scan the filesystem first to get what's actually available
        $filesystemImages = Get-FilesystemBaseImages
        Write-LogMessage "Found $($filesystemImages.Count) images on filesystem" "INFO"
        
        # Add filesystem images (these are guaranteed to exist)
        $images += $filesystemImages
        
        # Add default images that actually exist
        $defaultImages = Get-DefaultBaseImages
        Write-LogMessage "Found $($defaultImages.Count) available default base images" "INFO"
        
        # Only add defaults if not already found in filesystem
        foreach ($defaultImage in $defaultImages) {
            $existingImage = $images | Where-Object { $_.ImageID -eq $defaultImage.ImageID -or $_.Path -eq $defaultImage.Path }
            if (-not $existingImage) {
                $images += $defaultImage
                Write-LogMessage "Added available default base image: $($defaultImage.ImageID)" "VERBOSE"
            } else {
                Write-LogMessage "Default image already found in filesystem scan: $($defaultImage.ImageID)" "VERBOSE"
            }
        }
        
        # If customer has base images config, use it to filter and configure the images
        if ($CustomerConfig -and $CustomerConfig.ContainsKey('baseImages') -and $CustomerConfig.baseImages) {
            Write-LogMessage "Customer has baseImages configuration with $($CustomerConfig.baseImages.Count) entries" "VERBOSE"
            
            $configuredImages = @()
            
            # Process customer-configured base images
            foreach ($baseImageKey in $CustomerConfig.baseImages.Keys) {
                $baseImageConfig = $CustomerConfig.baseImages[$baseImageKey]
                
                # Skip inactive images
                if ($baseImageConfig.PSObject.Properties.Name -contains 'active' -and $baseImageConfig.active -eq $false) {
                    Write-LogMessage "Skipping inactive base image: $baseImageKey" "VERBOSE"
                    continue
                }
                
                # Look for matching existing image
                $matchingImage = $images | Where-Object { 
                    $_.ImageID -eq $baseImageKey -or 
                    $_.Path -eq $baseImageConfig.Path -or 
                    $_.DisplayName -eq $baseImageConfig.DisplayName 
                }
                
                if ($matchingImage) {
                    # Use existing image with config overrides
                    $image = $matchingImage.PSObject.Copy()
                    if ($baseImageConfig.DisplayName) { $image.DisplayName = $baseImageConfig.DisplayName }
                    if ($baseImageConfig.WindowsVersion) { $image.WindowsVersion = $baseImageConfig.WindowsVersion }
                    if ($baseImageConfig.BuildVersion) { $image.BuildVersion = $baseImageConfig.BuildVersion }
                    $configuredImages += $image
                    Write-LogMessage "Added configured base image: $($image.ImageID)" "VERBOSE"
                } else {
                    # Check if the configured path exists
                    $configPath = if ($baseImageConfig.Path) { $baseImageConfig.Path } else { "Z:\BaseImages\Windows\$baseImageKey.esd" }
                    
                    if (Test-Path $configPath) {
                        try {

                            $fileInfo = Get-Item $configPath
                            $image = @{
                                ImageID = $baseImageKey
                                DisplayName = if ($baseImageConfig.DisplayName) { $baseImageConfig.DisplayName } else { $baseImageKey }
                                WindowsVersion = if ($baseImageConfig.WindowsVersion) { $baseImageConfig.WindowsVersion } else { "Unknown" }
                                BuildVersion = if ($baseImageConfig.BuildVersion) { $baseImageConfig.BuildVersion } else { "Latest" }
                                Path = $configPath
                                Type = if ($baseImageConfig.Type) { $baseImageConfig.Type } else { "ESD" }
                                FileSize = [Math]::Round($fileInfo.Length / 1GB, 2)
                                DateModified = $fileInfo.LastWriteTime
                                FileExists = $true
                                active = $true
                            }
                            $configuredImages += $image
                            Write-LogMessage "Added config-only base image that exists: $($image.ImageID)" "VERBOSE"
                        } catch {
                            Write-LogMessage "Error processing config-only image file $configPath`: $_" "WARNING"
                        }
                    } else {
                        Write-LogMessage "Skipping config-only base image (file not found): $baseImageKey at $configPath" "VERBOSE"
                    }
                }
            }
            
            # Use configured images instead of all discovered images
            $images = $configuredImages
        }
        
        # Remove duplicates based on ImageID and Path
        $uniqueImages = @{
        }
        foreach ($image in $images) {
            $uniqueKey = "$($image.ImageID)_$($image.Path)"
            if (-not $uniqueImages.ContainsKey($uniqueKey)) {
                $uniqueImages[$uniqueKey] = $image
            }
        }
        $images = $uniqueImages.Values
        
        # Final filter - only return images that actually exist
        $finalImages = @()
        foreach ($image in $images) {
            if ($image.FileExists -and (Test-Path $image.Path)) {
                $finalImages += $image
                Write-LogMessage "Final image included: $($image.ImageID) | Version: $($image.WindowsVersion) | Display: $($image.DisplayName) | Path: $($image.Path)" "VERBOSE"
            } else {
                Write-LogMessage "Excluding image (file not found): $($image.ImageID) at $($image.Path)" "VERBOSE"
            }
        }
        
        Write-LogMessage "Final available image list: $($finalImages.Count) base images (excluded $($images.Count - $finalImages.Count) unavailable)" "INFO"
        
        # Log what we found by version for debugging
        $win10Count = ($finalImages | Where-Object { $_.WindowsVersion -eq "10" }).Count
        $win11Count = ($finalImages | Where-Object { $_.WindowsVersion -eq "11" }).Count
        $unknownCount = ($finalImages | Where-Object { $_.WindowsVersion -eq "Unknown" -or $_.WindowsVersion -eq $null }).Count
        
        Write-LogMessage "Available base images breakdown - Windows 10: $win10Count, Windows 11: $win11Count, Unknown: $unknownCount" "INFO"
        
        return $finalImages
        
    } catch {
        Write-LogMessage "Failed to get base Windows images: $_" "ERROR"
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return @()
    }
}

function Parse-BaseImageFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$FileType
    )
    try {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $fileInfo = Get-Item $FilePath -ErrorAction SilentlyContinue
        
        # Parse Windows version and build from filename - improved patterns
        $windowsVersion = "Unknown"
        $buildVersion = "Unknown"
        $displayName = $fileName
        
        # Check if this is a structured path (Z:\BaseImages\Windows\{version}\{build}\install.esd)
        if ($FilePath -match "\\BaseImages\\Windows\\(\d+)\\([^\\]+)\\") {
            $windowsVersion = $Matches[1]
            $buildVersion = $Matches[2]
            $displayName = "Windows $windowsVersion $buildVersion"
        }
        # Parse Windows 11 patterns from filename
        elseif ($fileName -match "(?i)win(?:dows)?_?11|w11|11h|11_") {
            $windowsVersion = "11"
            
            # Parse specific build versions for Windows 11
            if ($fileName -match "(?i)24h2|2024") {
                $buildVersion = "24H2"
                $displayName = "Windows 11 24H2"
            } elseif ($fileName -match "(?i)23h2|2023") {
                $buildVersion = "23H2"
                $displayName = "Windows 11 23H2"
            } elseif ($fileName -match "(?i)22h2|2022") {
                $buildVersion = "22H2"
                $displayName = "Windows 11 22H2"
            } elseif ($fileName -match "(?i)21h2") {
                $buildVersion = "21H2"
                $displayName = "Windows 11 21H2"
            } else {
                $buildVersion = "Latest"
                $displayName = "Windows 11"
            }
        }
        # Parse Windows 10 patterns from filename
        elseif ($fileName -match "(?i)win(?:dows)?_?10|w10|10h|10_") {
            $windowsVersion = "10"
            
            # Parse specific build versions for Windows 10
            if ($fileName -match "(?i)22h2|2022") {
                $buildVersion = "22H2"
                $displayName = "Windows 10 22H2"
            } elseif ($fileName -match "(?i)21h2") {
                $buildVersion = "21H2"
                $displayName = "Windows 10 21H2"
            } elseif ($fileName -match "(?i)21h1") {
                $buildVersion = "21H1"
                $displayName = "Windows 10 21H1"
            } elseif ($fileName -match "(?i)20h2") {
                $buildVersion = "20H2"
                $displayName = "Windows 10 20H2"
            } elseif ($fileName -match "(?i)2004") {
                $buildVersion = "2004"
                $displayName = "Windows 10 2004"
            } elseif ($fileName -match "(?i)1909") {
                $buildVersion = "1909"
                $displayName = "Windows 10 1909"
            } else {
                $buildVersion = "Latest"
                $displayName = "Windows 10"
            }
        }
        # Fallback - try to detect version from build numbers
        elseif ($fileName -match "(?i)22000|22621|22631|26100") {
            # These are Windows 11 build numbers
            $windowsVersion = "11"
            $buildVersion = "Latest"
            $displayName = "Windows 11"
        }
        elseif ($fileName -match "(?i)19041|19042|19043|19044|19045") {
            # These are Windows 10 build numbers
            $windowsVersion = "10"
            $buildVersion = "Latest"
            $displayName = "Windows 10"
        }
        
        # Check if file exists
        $fileExists = Test-Path $FilePath
        
        # Create image object
        $imageInfo = @{
            ImageID = $fileName
            DisplayName = $displayName
            WindowsVersion = $windowsVersion
            BuildVersion = $buildVersion
            Path = $FilePath
            Type = $FileType
            FileSize = if ($fileInfo) { [Math]::Round($fileInfo.Length / 1GB, 2) } else { 0 }
            DateModified = if ($fileInfo) { $fileInfo.LastWriteTime } else { Get-Date }
            FileExists = $fileExists
            active = $true
        }
        
        Write-LogMessage "Parsed image: $displayName ($windowsVersion $buildVersion) from $fileName - Exists: $fileExists" "VERBOSE"
        return $imageInfo
        
    } catch {
        Write-LogMessage "Error parsing base image from path $FilePath`: $_" "ERROR"
        return $null
    }
}

function Get-FilesystemBaseImages {
    [CmdletBinding()]
       param()
    
    try {
        $baseImagesPath = "Z:\BaseImages"
        $images = @()
        
        # Check if Z:\BaseImages exists
        if (-not (Test-Path $baseImagesPath)) {
            Write-LogMessage "Base images path not found: $baseImagesPath" "WARNING"
            return @()
        }
        
        # Look for Windows folder structure: Z:\BaseImages\Windows\{version}\{build}\
        $windowsPath = Join-Path $baseImagesPath "Windows"
        if (-not (Test-Path $windowsPath)) {
            Write-LogMessage "Windows base images path not found: $windowsPath" "WARNING"
            return @()
        }
        
        Write-LogMessage "Scanning Windows versions in: $windowsPath" "VERBOSE"
        
        # Get Windows version folders (10, 11, etc.)
        $versionFolders = Get-ChildItem -Path $windowsPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\d+$" }
        
        foreach ($versionFolder in $versionFolders) {
            Write-LogMessage "Scanning version folder: $($versionFolder.Name)" "VERBOSE"
            
            # Look for build folders within version folder
            $buildFolders = Get-ChildItem -Path $versionFolder.FullName -Directory -ErrorAction SilentlyContinue
            
            foreach ($buildFolder in $buildFolders) {
                Write-LogMessage "Scanning build folder: $($buildFolder.Name)" "VERBOSE"
                
                # Look for install.esd specifically in the build folder
                $installEsdPath = Join-Path $buildFolder.FullName "install.esd"
                
                if (Test-Path $installEsdPath) {
                    try {
                        $imageFile = Get-Item $installEsdPath
                        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($imageFile.Name)
                        $fileType = $imageFile.Extension.TrimStart('.').ToUpper()
                        
                        $image = @{
                            ImageID = "WIN$($versionFolder.Name)_$($buildFolder.Name)"
                            DisplayName = "Windows $($versionFolder.Name) $($buildFolder.Name)"
                            WindowsVersion = $versionFolder.Name
                            BuildVersion = $buildFolder.Name
                            Path = $imageFile.FullName
                            Type = $fileType
                            FileSize = [Math]::Round($imageFile.Length / 1GB, 2)
                            DateModified = $imageFile.LastWriteTime
                            FileExists = $true
                            active = $true
                        }
                        
                        $images += $image
                        Write-LogMessage "Found structured base image: $($image.ImageID) - Windows $($image.WindowsVersion) $($image.BuildVersion) at $($image.Path)" "VERBOSE"
                    }
                    catch {
                        Write-LogMessage "Error processing structured image file $installEsdPath`: $_" "WARNING"
                    }
                } else {
                    Write-LogMessage "install.esd not found in: $($buildFolder.FullName)" "VERBOSE"
                }
                
                # Also check for other image files in build folder as fallback
                $imageFiles = Get-ChildItem -Path $buildFolder.FullName -Include "*.esd", "*.wim", "*.iso" -ErrorAction SilentlyContinue
                
                foreach ($imageFile in $imageFiles) {
                    # Skip if we already processed install.esd
                    if ($imageFile.Name -eq "install.esd") {
                        continue
                    }
                    
                    try {
                        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($imageFile.Name)
                        $fileType = $imageFile.Extension.TrimStart('.').ToUpper()
                        
                        $image = @{
                            ImageID = "WIN$($versionFolder.Name)_$($buildFolder.Name)_$fileName"
                            DisplayName = "Windows $($versionFolder.Name) $($buildFolder.Name) ($fileName)"
                            WindowsVersion = $versionFolder.Name
                            BuildVersion = $buildFolder.Name
                            Path = $imageFile.FullName
                            Type = $fileType
                            FileSize = [Math]::Round($imageFile.Length / 1GB, 2)
                            DateModified = $imageFile.LastWriteTime
                            FileExists = $true
                            active = $true
                        }
                        
                        $images += $image
                        Write-LogMessage "Found additional structured base image: $($image.ImageID) - Windows $($image.WindowsVersion) $($image.BuildVersion)" "VERBOSE"
                    }
                    catch {
                        Write-LogMessage "Error processing structured image file $($imageFile.FullName): $_" "WARNING"
                    }
                }
            }
        }
        
        Write-LogMessage "Found $($images.Count) images on filesystem" "INFO"
        return $images
    }
    catch {
        Write-LogMessage "Failed to scan filesystem for base images: $_" "ERROR"
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return @()
    }
}

function Show-EditionSelectionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageType
    )
    
    # Apply scaling to the edition selection dialog
    $screenInfo = Get-ScreenResolution
    $scale = [Math]::Max(1.0, $screenInfo.ScaleFactor)
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Windows Edition Selection'
    $form.Size = New-Object System.Drawing.Size((Scale-UIElement 350 $scale), (Scale-UIElement 200 $scale))
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    
    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Select Windows Edition"
    $titleLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](10 * $scale)), [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 10 $scale), (Scale-UIElement 10 $scale))
    $titleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 320 $scale), (Scale-UIElement 25 $scale))
    $form.Controls.Add($titleLabel)
    
    # Info label for different image types
    $infoText = switch ($ImageType) {
        "ESD" { "For ESD files, specific image indices are required:" }
        "ISO" { "Select the Windows edition to deploy from this ISO:" }
        default { "Select the Windows edition:" }
    }
    
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = $infoText
    $infoLabel.Location = New-Object System.Drawing.Point(10, 35)
    $infoLabel.Size = New-Object System.Drawing.Size(320, 20)
    $form.Controls.Add($infoLabel)
    
    # Calculate panel Y position based on image type
    $panelY = 60
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(10, $panelY)
    $panel.Size = New-Object System.Drawing.Size(320, 80)
    
    $radioPro = New-Object System.Windows.Forms.RadioButton
    $radioEnt = New-Object System.Windows.Forms.RadioButton
    
    $radioPro.Location = New-Object System.Drawing.Point(10, 10)
    $radioPro.Size = New-Object System.Drawing.Size(300, 20)
    
    # Set appropriate indices based on image type
    switch ($ImageType) {
        "ESD" {
            $radioPro.Text = "Windows Pro (Index 6)"
            $radioPro.Tag = @{ Name = "Pro"; Index = 6 }
            $radioEnt.Text = "Windows Enterprise (Index 4)"
            $radioEnt.Tag = @{ Name = "Enterprise"; Index = 4 }
        }
        "ISO" {
            $radioPro.Text = "Windows Pro"
            $radioPro.Tag = @{ Name = "Pro"; Index = 1 }
            $radioEnt.Text = "Windows Enterprise"
            $radioEnt.Tag = @{ Name = "Enterprise"; Index = 2 }
        }
        default {
            $radioPro.Text = "Windows Pro"
            $radioPro.Tag = @{ Name = "Pro"; Index = 1 }
            $radioEnt.Text = "Windows Enterprise"
            $radioEnt.Tag = @{ Name = "Enterprise"; Index = 2 }
        }
    }
    
    $radioPro.Checked = $true
    
    $radioEnt.Location = New-Object System.Drawing.Point(10, 35)
    $radioEnt.Size = New-Object System.Drawing.Size(300, 20)
    
    $buttonContinue = New-Object System.Windows.Forms.Button
    $buttonContinue.Location = New-Object System.Drawing.Point(10, 65)
    $buttonContinue.Size = New-Object System.Drawing.Size(100, 25)
    $buttonContinue.Text = "Continue"
    $buttonContinue.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $buttonContinue.Add_Click({
        $form.Close()
    })
    
    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Location = New-Object System.Drawing.Point(220, 65)
    $buttonCancel.Size = New-Object System.Drawing.Size(100, 25)
    $buttonCancel.Text = "Cancel"
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttonCancel.Add_Click({
        $form.Close()
    })
    
    $panel.Controls.AddRange(@($radioPro, $radioEnt, $buttonContinue, $buttonCancel))
    $form.Controls.Add($panel)
    
    $form.AcceptButton = $buttonContinue
    $form.CancelButton = $buttonCancel
    
    $result = if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($radioPro.Checked) { $radioPro.Tag } else { $radioEnt.Tag }
    }
    else { $null }
    
    $form.Dispose()
    return $result
}

function Show-DynamicEditionSelectionMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ImageInfo,
        
        [Parameter(Mandatory)]
        [string]$ImageType
    )
    
    # --- Responsive scaling for edition selection dialog ---
    $screenInfo = Get-ScreenResolution
    $scaleX = $screenInfo.Width / 1280.0
    $scaleY = $screenInfo.Height / 800.0
    $scale = [Math]::Min($scaleX, $scaleY)
    $scale = [Math]::Min($scale, 1.5)
    $scale = [Math]::Max($scale, 0.7)

    $baseWidth = 600
    $baseHeight = 350
    $itemHeight = 45
    $additionalHeight = ($ImageInfo.Count * $itemHeight)
    $formHeight = [Math]::Max($baseHeight, $baseHeight + $additionalHeight)
    $formHeight = [Math]::Min($formHeight, 650)
    $formWidth = [int]($baseWidth * $scale)
    $formHeight = [int]($formHeight * $scale)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Windows Edition Selection'
    $form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $form.MinimumSize = New-Object System.Drawing.Size([int](400 * $scale), [int](300 * $scale))
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox = $true
    $form.MinimizeBox = $true

    # Update title based on image type
    $titleText = if ($ImageType -eq "ESD") { "Select Windows Edition from ESD" } else { "Select Windows Edition from $ImageType" }

    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $titleText
    $titleLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(10, [int](12 * $scale)), [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point([int](15 * $scale), [int](15 * $scale))
    $titleLabel.Size = New-Object System.Drawing.Size([int](($formWidth-30)), [int](25 * $scale))
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $titleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($titleLabel)

    # Info label
    $infoText = "Found $($ImageInfo.Count) Windows editions in this $ImageType. Select the edition to deploy:"

    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = $infoText
    $infoLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](10 * $scale)))
    $infoLabel.Location = New-Object System.Drawing.Point([int](15 * $scale), [int](45 * $scale))
    $infoLabel.Size = New-Object System.Drawing.Size([int]($formWidth-30), [int](20 * $scale))
    $infoLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $infoLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($infoLabel)

    # Create scrollable panel for radio buttons
    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location = New-Object System.Drawing.Point([int](15 * $scale), [int](75 * $scale))
    $scrollPanel.Size = New-Object System.Drawing.Size([int]($formWidth-30), [int]($formHeight - (75 * $scale) - (70 * $scale)))
    $scrollPanel.AutoScroll = $true
    $scrollPanel.BorderStyle = "FixedSingle"
    $scrollPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($scrollPanel)
    
    # Create radio buttons for each edition
    $radioButtons = @()
    $yPosition = 10
    $radioWidth = [int](($formWidth-70) * 0.95)
    $detailsWidth = $radioWidth - 20

    foreach ($image in $ImageInfo) {
        $radioButton = New-Object System.Windows.Forms.RadioButton
        $radioButton.Location = New-Object System.Drawing.Point([int](10 * $scale), $yPosition)
        $radioButton.Size = New-Object System.Drawing.Size($radioWidth, [int](20 * $scale))
        $editionText = if ($image.ImageName) { $image.ImageName } else { "Windows Edition" }
        if ($image.ImageDescription -and $image.ImageDescription -ne $image.ImageName) {
            $editionText = $image.ImageDescription
        }
        $radioButton.Text = $editionText
        $radioButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $radioButton.Tag = @{
            Name = $editionText
            Index = $image.ImageIndex
            Description = $image.ImageDescription
            Architecture = $image.Architecture
            Version = $image.ImageVersion
        }
        if ($radioButtons.Count -eq 0) {
            $radioButton.Checked = $true
        }
        $radioButtons += $radioButton
        $scrollPanel.Controls.Add($radioButton)
        $yPosition += [int](25 * $scale)
        $detailsLabel = New-Object System.Windows.Forms.Label
        $detailsText = "    Index: $($image.ImageIndex)"
        if ($image.Architecture) { $detailsText += "  |  Architecture: $($image.Architecture)" }
        if ($image.ImageVersion) { $detailsText += "  |  Version: $($image.ImageVersion)" }
        $detailsLabel.Text = $detailsText
        $detailsLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](8 * $scale)))
        $detailsLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
        $detailsLabel.Location = New-Object System.Drawing.Point([int](30 * $scale), $yPosition)
        $detailsLabel.Size = New-Object System.Drawing.Size($detailsWidth, [int](15 * $scale))
        $scrollPanel.Controls.Add($detailsLabel)
        $yPosition += [int](20 * $scale)
    }

    # Create a group box to contain the radio buttons (for visual grouping)
    $groupBox = New-Object System.Windows.Forms.GroupBox
    $groupBox.Text = "Available Editions"
    $groupBox.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(9, [int](10 * $scale)), [System.Drawing.FontStyle]::Bold)
    $groupBox.Location = $scrollPanel.Location
    $groupBox.Size = $scrollPanel.Size
    $groupBox.Anchor = $scrollPanel.Anchor
    $form.Controls.Remove($scrollPanel)
    $groupBox.Controls.Add($scrollPanel)
    $form.Controls.Add($groupBox)

    # Create buttons panel anchored below the group box
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Height = [int](50 * $scale)
    $buttonPanel.Width = $formWidth - 30
    $buttonPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $buttonPanel.Location = New-Object System.Drawing.Point([int]$groupBox.Location.X, ([int]$groupBox.Location.Y + [int]$groupBox.Height + [int](10 * $scale)))

    # Select button
    $selectButton = New-Object System.Windows.Forms.Button
    $selectButton.Size = New-Object System.Drawing.Size([int](100 * $scale), [int](35 * $scale))
    $selectButton.Text = "Select"
    $selectButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
    $selectButton.BackColor = [System.Drawing.Color]::LightGreen
    $selectButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $selectButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
    $selectButton.Add_Click({ $form.Close() })
    $buttonPanel.Controls.Add($selectButton)

    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Size = New-Object System.Drawing.Size([int](100 * $scale), [int](35 * $scale))
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](9 * $scale)))
    $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
    $cancelButton.Add_Click({ $form.Close() })
    $buttonPanel.Controls.Add($cancelButton)

    $form.Controls.Add($buttonPanel)
    $form.AcceptButton = $selectButton
    $form.CancelButton = $cancelButton

    # Responsive: adjust layout on resize
    $form.Add_Resize({
        $formWidthNow = $form.ClientSize.Width
        $formHeightNow = $form.ClientSize.Height
        $titleLabel.Width = $formWidthNow - [int](30 * $scale)
        $infoLabel.Width = $formWidthNow - [int](30 * $scale)
        $groupBox.Width = $formWidthNow - [int](30 * $scale)
        $groupBox.Height = $formHeightNow - $buttonPanel.Height - $groupBox.Location.Y - [int](20 * $scale)
        $scrollPanel.Width = $groupBox.Width - [int](10 * $scale)
        $scrollPanel.Height = $groupBox.Height - [int](30 * $scale)
        $buttonPanel.Width = $formWidthNow - [int](30 * $scale)
        $buttonPanel.Location = New-Object System.Drawing.Point([int]$groupBox.Location.X, ([int]$groupBox.Location.Y + [int]$groupBox.Height + [int](10 * $scale)))
        $selectButton.Location = New-Object System.Drawing.Point([int](($buttonPanel.Width/2) - (110 * $scale)), [int](10 * $scale))
        $cancelButton.Location = New-Object System.Drawing.Point([int](($buttonPanel.Width/2) + (10 * $scale)), [int](10 * $scale))
    })

    $result = if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedRadio = $radioButtons | Where-Object { $_.Checked }
        if ($selectedRadio) {
            $selectedRadio.Tag
        } else {
            $radioButtons[0].Tag
        }
    } else {
        Write-LogMessage "User cancelled edition selection" "INFO"
        $null
    }

    $form.Dispose()
    return $result
}

function Show-ISODeploymentOptionsDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOName,
        
        [Parameter(Mandatory)]
        [string]$EditionName
    )
    
    # Apply scaling to the deployment options dialog
    $screenInfo = Get-ScreenResolution
    $scale = [Math]::Max(1.0, $screenInfo.ScaleFactor)
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ISO Deployment Options'
    $form.Size = New-Object System.Drawing.Size((Scale-UIElement 500 $scale), (Scale-UIElement 350 $scale))
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    
    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Configure Deployment Options"
    $titleLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(12, [int](14 * $scale)), [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 15 $scale))
    $titleLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 460 $scale), (Scale-UIElement 25 $scale))
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($titleLabel)
    
    # Info label
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "ISO: $ISOName - $EditionName`n`nSelect which deployment features to enable:"
    $infoLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](10 * $scale)))
    $infoLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 45 $scale))
    $infoLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 460 $scale), (Scale-UIElement 40 $scale))
    $infoLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($infoLabel)
    
    # Create options panel
    $optionsPanel = New-Object System.Windows.Forms.Panel
    $optionsPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 95 $scale))
    $optionsPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 460 $scale), (Scale-UIElement 150 $scale))
    $optionsPanel.BorderStyle = "FixedSingle"
    $form.Controls.Add($optionsPanel)
    
    # Driver Injection checkbox
    $driverInjectCheckBox = New-Object System.Windows.Forms.CheckBox
    $driverInjectCheckBox.Text = "Driver Injection"
    $driverInjectCheckBox.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(10, [int](11 * $scale)), [System.Drawing.FontStyle]::Bold)
    $driverInjectCheckBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 20 $scale))
    $driverInjectCheckBox.Size = New-Object System.Drawing.Size((Scale-UIElement 200 $scale), (Scale-UIElement 25 $scale))
    $driverInjectCheckBox.Checked = $true  # Default to enabled
    $optionsPanel.Controls.Add($driverInjectCheckBox)
    
    $driverInjectDescLabel = New-Object System.Windows.Forms.Label
    $driverInjectDescLabel.Text = "Automatically inject device-specific drivers during deployment"
    $driverInjectDescLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)))
    $driverInjectDescLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
    $driverInjectDescLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 40 $scale), (Scale-UIElement 45 $scale))
    $driverInjectDescLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 15 $scale))
    $optionsPanel.Controls.Add($driverInjectDescLabel)
    
    # Updates Installation checkbox
    $updatesCheckBox = New-Object System.Windows.Forms.CheckBox
    $updatesCheckBox.Text = "Windows Updates Installation"
    $updatesCheckBox.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(10, [int](11 * $scale)), [System.Drawing.FontStyle]::Bold)
    $updatesCheckBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 70 $scale))
    $updatesCheckBox.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), (Scale-UIElement 25 $scale))
    $updatesCheckBox.Checked = $true  # Default to enabled
    $optionsPanel.Controls.Add($updatesCheckBox)
    
    $updatesDescLabel = New-Object System.Windows.Forms.Label
    $updatesDescLabel.Text = "Download and install Windows Updates after deployment"
    $updatesDescLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)))
    $updatesDescLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
    $updatesDescLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 40 $scale), (Scale-UIElement 95 $scale))
    $updatesDescLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 15 $scale))
    $optionsPanel.Controls.Add($updatesDescLabel)
    
    # Unattend Application checkbox
    $unattendCheckBox = New-Object System.Windows.Forms.CheckBox
    $unattendCheckBox.Text = "Unattend File Application"
    $unattendCheckBox.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(10, [int](11 * $scale)), [System.Drawing.FontStyle]::Bold)
    $unattendCheckBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 120 $scale))
    $unattendCheckBox.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), (Scale-UIElement 25 $scale))
    $unattendCheckBox.Checked = $true  # Default to enabled
    $optionsPanel.Controls.Add($unattendCheckBox)
    
    $unattendDescLabel = New-Object System.Windows.Forms.Label
    $unattendDescLabel.Text = "Apply customer-specific unattend.xml configuration"
    $unattendDescLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)))
    $unattendDescLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,0,139)
    $unattendDescLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 40 $scale), (Scale-UIElement 145 $scale))
    $unattendDescLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 380 $scale), (Scale-UIElement 15 $scale))
    $optionsPanel.Controls.Add($unattendDescLabel)
    
    # Create buttons panel
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 260 $scale))
    $buttonPanel.Size = New-Object System.Drawing.Size((Scale-UIElement 460 $scale), (Scale-UIElement 50 $scale))
    $form.Controls.Add($buttonPanel)
    
    # Continue button
    $continueButton = New-Object System.Windows.Forms.Button
    $continueButton.Location = New-Object System.Drawing.Point((Scale-UIElement 250 $scale), (Scale-UIElement 10 $scale))
    $continueButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
    $continueButton.Text = "Continue"
    $continueButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](10 * $scale)), [System.Drawing.FontStyle]::Bold)
    $continueButton.BackColor = [System.Drawing.Color]::LightGreen
    $continueButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $continueButton.Add_Click({
        $form.Close()
    })
    
    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 360 $scale), (Scale-UIElement 10 $scale))
    $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 100 $scale), (Scale-UIElement 35 $scale))
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(9, [int](10 * $scale)))
    $cancelButton.BackColor = [System.Drawing.Color]::LightCoral
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Add_Click({
        $form.Close()
    })
    
    $buttonPanel.Controls.Add($continueButton)
    $buttonPanel.Controls.Add($cancelButton)
    
    # Set as default buttons
    $form.AcceptButton = $continueButton
    $form.CancelButton = $cancelButton
    
    $result = if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-LogMessage "User selected deployment options - Driver Injection: $($driverInjectCheckBox.Checked), Updates: $($updatesCheckBox.Checked), Unattend: $($unattendCheckBox.Checked)" "INFO"
        @{
            DriverInject = $driverInjectCheckBox.Checked
            RequiredUpdates = $updatesCheckBox.Checked
            ApplyUnattend = $unattendCheckBox.Checked
        }
    } else { 
        Write-LogMessage "User cancelled deployment options dialog" "INFO"
        $null 
    }
    
    $form.Dispose()
    return $result
}

# Export only functions with approved verbs
Export-ModuleMember -Function Show-ImageSelectionMenu, Get-CustomerImageConfig, Convert-PSObjectToHashtable, Get-CustomerAvailableImages, Get-DefaultBaseImages, Get-BaseWindowsImages, Get-FilesystemBaseImages, Show-EditionSelectionMenu, Show-DynamicEditionSelectionMenu, Show-ISODeploymentOptionsDialog
