# Import required modules
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
    Import-Module "$PSScriptRoot\..\Core\DeviceInformation.psm1" -Force -ErrorAction Stop
    Import-Module "$PSScriptRoot\ImageMenu.psm1" -Force -ErrorAction Stop
    Import-Module "$PSScriptRoot\..\Core\CatMode.psm1" -Force -ErrorAction SilentlyContinue
    Import-Module "$PSScriptRoot\..\Core\CustomerConfigManager.psm1" -Force -ErrorAction SilentlyContinue
    Import-Module "$PSScriptRoot\ImageCaptureMenu.psm1" -Force -ErrorAction SilentlyContinue
    Write-LogMessage "DeploymentMenu: Required modules imported successfully" "INFO"
} catch {
    Write-Host "Failed to import required modules: $_" -ForegroundColor Red
    throw "Required modules not found"
}


function Update-DeploymentProgress {
    param(
        [int]$PercentComplete,
        [string]$Status
    )

    # Defensive: Only update if controls are initialized, are the right type, and not disposed
    try {
        if (
            $script:progressBar -is [System.Windows.Forms.ProgressBar] -and
            $script:progressLabel -is [System.Windows.Forms.Label] -and
            $script:progressBar -ne $null -and
            $script:progressLabel -ne $null -and
            -not $script:progressBar.IsDisposed -and
            -not $script:progressLabel.IsDisposed
        ) {
            if ($script:progressBar.InvokeRequired) {
                $script:progressBar.BeginInvoke([Action]{
                    try {
                        if ($script:progressBar -is [System.Windows.Forms.ProgressBar] -and -not $script:progressBar.IsDisposed) {
                            $script:progressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
                        }
                    } catch {}
                }) | Out-Null
            } else {
                $script:progressBar.Value = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
            }

            if ($script:progressLabel.InvokeRequired) {
                $script:progressLabel.BeginInvoke([Action]{
                    try {
                        if ($script:progressLabel -is [System.Windows.Forms.Label] -and -not $script:progressLabel.IsDisposed) {
                            $script:progressLabel.Text = $Status
                            $script:progressLabel.Refresh()
                        }
                    } catch {}
                }) | Out-Null
            } else {
                $script:progressLabel.Text = $Status
                $script:progressLabel.Refresh()
            }

            if ($script:progressBar.InvokeRequired) {
                $script:progressBar.BeginInvoke([Action]{
                    try {
                        if ($script:progressBar -is [System.Windows.Forms.ProgressBar] -and -not $script:progressBar.IsDisposed) {
                            $script:progressBar.Refresh()
                        }
                    } catch {}
                }) | Out-Null
            } else {
                $script:progressBar.Refresh()
            }
        }
    } catch {
        # Silently handle any UI update errors
    }
    
    # Update Cat Mode if enabled (check both local and global flags)
    if ($script:catModeEnabled -or $global:catModeEnabled) {
        try {
            if (Get-Command Update-CatModeProgress -ErrorAction SilentlyContinue) {
                Update-CatModeProgress -PercentComplete $PercentComplete -Status $Status
            } else {
                # Try to import the module if command not found
                Import-Module "$PSScriptRoot\..\Core\CatMode.psm1" -Force -ErrorAction SilentlyContinue
                if (Get-Command Update-CatModeProgress -ErrorAction SilentlyContinue) {
                    Update-CatModeProgress -PercentComplete $PercentComplete -Status $Status
                }
            }
        } catch {
            Write-LogMessage "Cat Mode update error (non-critical): $_" "WARNING"
        }
    }
    
    Write-LogMessage "Progress: [$PercentComplete%] $Status" "INFO"
}

function Get-CustomerList {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Getting customer list..." "VERBOSE"
        
        $customerConfigPath = "Y:\DeploymentModules\Config\CustomerConfig"
        
        if (-not (Test-Path $customerConfigPath)) {
            Write-LogMessage "Customer config directory not found: $customerConfigPath" "WARNING"
            return @()
        }
        
        $customerDirs = Get-ChildItem -Path $customerConfigPath -Directory -ErrorAction SilentlyContinue
        
        if (-not $customerDirs) {
            Write-LogMessage "No customer directories found in: $customerConfigPath" "WARNING"
            return @()
        }
        
        $customers = @()
        foreach ($dir in $customerDirs) {
            # Skip directories that don't look like customer names
            if ($dir.Name -eq "DEFAULTIMAGECONFIG" -or $dir.Name -like ".*") {
                continue
            }
            
            # Check if the directory has a Config.json file
            $configFile = Join-Path $dir.FullName "Config.json"
            if (Test-Path $configFile) {
                $customers += $dir.Name
                Write-LogMessage "Found customer: $($dir.Name)" "VERBOSE"
            } else {
                Write-LogMessage "Customer directory missing Config.json: $($dir.Name)" "WARNING"
            }
        }
        
        Write-LogMessage "Found $($customers.Count) customers" "INFO"
        return $customers | Sort-Object
        
    } catch {
        Write-LogMessage "Error getting customer list: $_" "ERROR"
        return @()
    }
}

# Add entries to GUI log textbox
function Add-LogEntry {
    param([string]$Message)
    try {
        if (
            $script:logTextBox -is [System.Windows.Forms.TextBox] -and
            $script:logTextBox -ne $null -and
            -not $script:logTextBox.IsDisposed
        ) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $entry = "[$timestamp] $Message"
            if (-not $script:AllLogLines) { $script:AllLogLines = @() }
            $script:AllLogLines += $entry
            # Use global debug/verbose value if available, else local
            $showVerbose = $false
            if ($global:ShowVerboseLogs -ne $null) {
                $showVerbose = $global:ShowVerboseLogs
            } elseif ($script:ShowVerboseLogs -ne $null) {
                $showVerbose = $script:ShowVerboseLogs
            }
            $linesToShow = $script:AllLogLines | Where-Object { $showVerbose -or ($_ -notmatch '\[VERB\]') }
            if ($script:logTextBox.InvokeRequired) {
                $script:logTextBox.BeginInvoke([Action]{
                    try {
                        $script:logTextBox.Lines = $linesToShow
                        $script:logTextBox.SelectionStart = $script:logTextBox.Text.Length
                        $script:logTextBox.ScrollToCaret()
                    } catch {}
                }) | Out-Null
            } else {
                $script:logTextBox.Lines = $linesToShow
                $script:logTextBox.SelectionStart = $script:logTextBox.Text.Length
                $script:logTextBox.ScrollToCaret()
            }
        }
    } catch {
        # Silently handle threading or disposal issues
    }
}

# Enable or disable buttons based on state
function Update-DeploymentButtons {
    if ($script:selectedCustomer -and $script:orderNumber -and $script:deviceInfo) {
        $selectImageButton.Enabled = $true
        if ($script:selectedImage) { $startDeploymentButton.Enabled = $true }
    } else {
        $selectImageButton.Enabled = $false
        $startDeploymentButton.Enabled = $false
    }
}

function Sync-SystemTimeWithServer {
    try {
        $configPath = "X:\\Windows\\System32\\Deploy\\Modules\\Config\\ServerConfig\\server-config.json"
        $serverIP = $null
        $fallbackIPs = @("172.16.10.3", "172.20.11.23")
        if (Test-Path $configPath) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                $serverIP = $config.serverIP
                if (-not $serverIP) { $serverIP = $fallbackIPs[0] }
            } catch { $serverIP = $fallbackIPs[0] }
        } else {
            $serverIP = $fallbackIPs[0]
        }
        if (-not (Test-Connection -ComputerName $serverIP -Count 1 -Quiet)) {
            $serverIP = $fallbackIPs[1]
        }
        $netTimeCmd = "net time \\$serverIP"
        $netTimeOutput = cmd.exe /c $netTimeCmd
        Write-Host "[TimeSync] net time output:\n$netTimeOutput" -ForegroundColor Cyan
        Write-LogMessage "[TimeSync] net time output: $netTimeOutput" "VERBOSE"
        if ($LASTEXITCODE -ne 0 -or $netTimeOutput -match 'error' -or $netTimeOutput -match 'could not') {
            throw "Failed to get time from server ($serverIP): $netTimeOutput"
        }
        $serverTime = $null
        $localMatch = [regex]::Match($netTimeOutput, 'Local time.*?is\s+\d{1,2}/\d{1,2}/\d{4}\s+([0-9:]{1,8}\s*[AP]M)')
        if ($localMatch.Success) {
            $serverTime = $localMatch.Groups[1].Value
            Write-Host "[TimeSync] Parsed Local time: $serverTime" -ForegroundColor Cyan
            Write-LogMessage "[TimeSync] Parsed Local time: $serverTime" "VERBOSE"
        } else {
            $currentMatch = [regex]::Match($netTimeOutput, 'Current time at \\.+ is\s+\d{1,2}/\d{1,2}/\d{4}\s+([0-9:]{1,8}\s*[AP]M)')
            if ($currentMatch.Success) {
                $serverTime = $currentMatch.Groups[1].Value
                Write-Host "[TimeSync] Parsed Current time: $serverTime" -ForegroundColor Cyan
                Write-LogMessage "[TimeSync] Parsed Current time: $serverTime" "VERBOSE"
            } else {
                $theCurrentMatch = [regex]::Match($netTimeOutput, 'The current time is: \d{1,2}/\d{1,2}/\d{4}\s+([0-9:]{1,8}\s*[AP]M)')
                if ($theCurrentMatch.Success) {
                    $serverTime = $theCurrentMatch.Groups[1].Value
                    Write-Host "[TimeSync] Parsed The current time: $serverTime" -ForegroundColor Cyan
                    Write-LogMessage "[TimeSync] Parsed The current time: $serverTime" "VERBOSE"
                }
            }
        }
        if (-not $serverTime) {
            throw "Could not parse server time from output: $netTimeOutput"
        }
        $serverTime24 = $null
        try {
            $serverTime = $serverTime.Trim()
            $dt = [DateTime]::Parse($serverTime)
            if ($dt) {
                $serverTime24 = $dt.ToString("HH:mm:ss")
            } else {
                $serverTime24 = $serverTime
            }
        } catch {
            $serverTime24 = $serverTime
        }
        Write-Host "[TimeSync] Final time string for time command: $serverTime24" -ForegroundColor Cyan
        Write-LogMessage "[TimeSync] Final time string for time command: $serverTime24" "VERBOSE"
        if ($serverTime24 -match '([0-9]{2}:[0-9]{2}(:[0-9]{2})?)') {
            $serverTime24 = $matches[1]
        }
        $setTimeCmd = "time $serverTime24"
        $setTimeOutput = cmd.exe /c $setTimeCmd
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "System time set to $serverTime24 from server $serverIP. Raw: $serverTime Output: $netTimeOutput" "INFO"
        } else {
            throw "Failed to set system time: $setTimeOutput"
        }
    } catch {
        Write-LogMessage "Time sync failed: $_" 'WARNING'
    }
}


function Show-DeploymentMenu {
    [CmdletBinding()]
    param()
    
    try {
        Sync-SystemTimeWithServer
        Write-LogMessage "Starting deployment menu..." "INFO"

        # Start the Windows Time service (w32time) on form load using 'net start'
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = "/c net start w32time"
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $output = $proc.StandardOutput.ReadToEnd()
            $error = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            Write-LogMessage "w32time service start output: $output $error" "INFO"
        } catch {
            Write-LogMessage "Could not start w32time service: $_" "WARNING"
        }

        # Initialize script-level variables
        $script:selectedCustomer = $null
        $script:selectedImage = $null
        $script:orderNumber = $null
        $script:deviceInfo = $null
        $script:progressBar = $null
        $script:progressLabel = $null
        $script:logTextBox = $null
        $script:catModeEnabled = $false
        $script:customersLoaded = $false

        # Stop any existing timers from previous instances
        try {
            Get-Variable -Name "*timer*" -Scope Script -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Value -and $_.Value.GetType().Name -eq "Timer") {
                    $_.Value.Stop()
                    $_.Value.Dispose()
                }
            }
        } catch {
            # Silently handle any timer cleanup errors
        }
        
        # Create main form - made resizable
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Windows Deployment Tool"
$form.Size = New-Object System.Drawing.Size(900, 700)  # Increased default size
# Set a larger minimum size to reduce clipping at smallest window
$form.MinimumSize = New-Object System.Drawing.Size(1000, 750)
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "Sizable"  # Changed from FixedDialog to Sizable
        $form.MaximizeBox = $true  # Enable maximize
        $form.MinimizeBox = $true  # Enable minimize
        $form.BackColor = [System.Drawing.Color]::FromArgb(234,247,255)
        
        # 1. MenuStrip (toolbar menu) at the very top - add first
        $menuStrip = New-Object System.Windows.Forms.MenuStrip
        $menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $menuStrip.Dock = [System.Windows.Forms.DockStyle]::Top  # Ensure proper docking
        
        # System Menu
        $systemMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $systemMenu.Text = "&System"
        # System menu: Restart, Shutdown
        $rebootMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $rebootMenuItem.Text = "&Restart"
        $rebootMenuItem.Add_Click({
            $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to restart the system?", "Restart System", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Restart-Computer -Force
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not restart system: $_", "Restart Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        })
        $shutdownMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $shutdownMenuItem.Text = "&Shutdown"
        $shutdownMenuItem.Add_Click({
            $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to shutdown the system?", "Shutdown System", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Stop-Computer -Force
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not shutdown system: $_", "Shutdown Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        })
        $systemMenu.DropDownItems.Clear()
        $systemMenu.DropDownItems.AddRange(@($rebootMenuItem, $shutdownMenuItem))
        
        # Imaging Menu
        $imagingMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $imagingMenu.Text = "&Imaging"
        $captureImageMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $captureImageMenuItem.Text = "&Capture Image"
        $captureImageMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F3
        $captureImageMenuItem.Add_Click({
            try {
                Import-Module "$PSScriptRoot\ImageCaptureMenu.psm1" -Force
                Show-ImageCaptureMenu
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error launching Image Capture: $_", "Image Capture Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $browseImagesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $browseImagesMenuItem.Text = "&Browse Images"
        $browseImagesMenuItem.Add_Click({
            try {
                $imagePath = "Z:\\CustomerImages"
                if (Test-Path $imagePath) {
                    Import-Module "$PSScriptRoot\..\Core\WinPEFileExplorer.psm1" -Force
                    Show-WinPEFileExplorer -StartPath $imagePath
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Images directory not found: $imagePath", "Browse Images", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error opening images directory: $_", "Browse Images Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $imagingMenu.DropDownItems.AddRange(@($captureImageMenuItem, (New-Object System.Windows.Forms.ToolStripSeparator), $browseImagesMenuItem))
        
        # Tools Menu
        $toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $toolsMenu.Text = "&Tools"
        # Device Information (F2)
        $deviceInfoMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $deviceInfoMenuItem.Text = "Device Information"
        $deviceInfoMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F2
        $deviceInfoMenuItem.Add_Click({
            try {
                Import-Module "$PSScriptRoot\..\Core\DeviceInformation.psm1" -Force
                $deviceInfo = Get-DeviceInformation
                Show-DeviceInformationDialog -DeviceInfo $deviceInfo
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error displaying device information: $_", "Device Information Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $toolsMenu.DropDownItems.Add($deviceInfoMenuItem)
        $toolsMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        # Disk Management
        $diskManagementMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $diskManagementMenuItem.Text = "Disk Management"
        $diskManagementMenuItem.Add_Click({
            try {
                Import-Module "$PSScriptRoot\..\Core\DiskManagement.psm1" -Force
                Show-DiskManagement
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error launching WinPE Disk Management: $_", "Disk Management Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $toolsMenu.DropDownItems.Add($diskManagementMenuItem)
        # Manage Customers
        $manageCustomersMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $manageCustomersMenuItem.Text = "Manage Customers"
        $manageCustomersMenuItem.Add_Click({
            try {
                $customerConfigPath = "Y:\\DeploymentModules\\Config\\CustomerConfig"
                if (Test-Path $customerConfigPath) {
                    Import-Module "$PSScriptRoot\..\Core\WinPEFileExplorer.psm1" -Force
                    Show-WinPEFileExplorer -StartPath $customerConfigPath
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Customer configuration directory not found: $customerConfigPath", "Manage Customers", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error opening customer configuration: $_", "Manage Customers Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $toolsMenu.DropDownItems.Add($manageCustomersMenuItem)
        # Customer Config Reload (F5)
        $toolsMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $reloadCustomerConfigMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $reloadCustomerConfigMenuItem.Text = "Customer Config Reload"
        $reloadCustomerConfigMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F5
        $reloadCustomerConfigMenuItem.ToolTipText = "Reload the customer list from disk."
        $reloadCustomerConfigMenuItem.Add_Click({
            try {
                $customerComboBox.Items.Clear()
                $customers = Get-CustomerList
                foreach ($customer in $customers) {
                    $customerComboBox.Items.Add($customer) | Out-Null
                }
                $script:customersLoaded = $true
                Add-LogEntry "Customer list reloaded."
            } catch {
                Write-LogMessage "Error reloading customer list: $_" "ERROR"
                Add-LogEntry "Error reloading customer list: $_"
            }
        })
        $toolsMenu.DropDownItems.Add($reloadCustomerConfigMenuItem)
        $toolsMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        # Cat Mode Toggle (single entry)
        $catModeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $catModeMenuItem.Text = "Cat Mode"
        $catModeMenuItem.CheckOnClick = $true
        $catModeMenuItem.Checked = $script:catModeEnabled
        $catModeMenuItem.ToolTipText = "Toggle Cat Mode (fun animated progress bar)"
        $catModeMenuItem.Add_Click({
            $script:catModeEnabled = $catModeMenuItem.Checked
            $global:catModeEnabled = $catModeMenuItem.Checked
            if ($catModeMenuItem.Checked) {
                try {
                    if (-not (Get-Command Start-CatMode -ErrorAction SilentlyContinue)) {
                        Import-Module "$PSScriptRoot\..\Core\CatMode.psm1" -Force
                    }
                    if (Get-Command Start-CatMode -ErrorAction SilentlyContinue) {
                        Start-CatMode
                        Add-LogEntry "Cat Mode enabled!"
                        Write-LogMessage "Cat Mode enabled from menu" "INFO"
                    }
                } catch {
                    Write-LogMessage "Error enabling Cat Mode: $_" "WARNING"
                }
            } else {
                try {
                    if (Get-Command Stop-CatMode -ErrorAction SilentlyContinue) {
                        Stop-CatMode
                        Add-LogEntry "Cat Mode disabled."
                        Write-LogMessage "Cat Mode disabled from menu" "INFO"
                    }
                } catch {
                    Write-LogMessage "Error disabling Cat Mode: $_" "WARNING"
                }
            }
        })
        $toolsMenu.DropDownItems.Add($catModeMenuItem)
        # Network Drive Status
        $networkDrivesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $networkDrivesMenuItem.Text = "Network Drive Status"
        $networkDrivesMenuItem.Add_Click({ Show-NetworkDrivesStatus })
        $toolsMenu.DropDownItems.Add($networkDrivesMenuItem)
        
        # View Menu
        $viewMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $viewMenu.Text = "&View"
        $fileExplorerMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $fileExplorerMenuItem.Text = "File Explorer"
        $fileExplorerMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F6
        $fileExplorerMenuItem.Add_Click({
            try {
                Import-Module "$PSScriptRoot\..\Core\WinPEFileExplorer.psm1" -Force
                Show-WinPEFileExplorer
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error launching File Explorer: $_", "File Explorer Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $logsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $logsMenuItem.Text = "Deployment Logs"
        $logsMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F4
        $logsMenuItem.Add_Click({
            try {
                $logsPath = "W:\\Logs"
                if (-not (Test-Path $logsPath)) {
                    $logsPath = "C:\\Logs"
                }
                Import-Module "$PSScriptRoot\..\Core\WinPEFileExplorer.psm1" -Force -ErrorAction Stop
                Show-WinPEFileExplorer -StartPath $logsPath
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Unable to open WinPE File Explorer for logs: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        $viewMenu.DropDownItems.Add($fileExplorerMenuItem)
        $viewMenu.DropDownItems.Add($logsMenuItem)
        $viewMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $debugMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $debugMenuItem.Text = "Debug (Show Verbose Logs)"
        $debugMenuItem.CheckOnClick = $true
        $debugMenuItem.Checked = $false
        $script:ShowVerboseLogs = $false
        $debugMenuItem.Add_Click({
            $script:ShowVerboseLogs = $debugMenuItem.Checked
            $global:ShowVerboseLogs = $debugMenuItem.Checked
            if ($script:AllLogLines -and $script:logTextBox) {
                $showVerbose = $false
                if ($global:ShowVerboseLogs -ne $null) {
                    $showVerbose = $global:ShowVerboseLogs
                } elseif ($script:ShowVerboseLogs -ne $null) {
                    $showVerbose = $script:ShowVerboseLogs
                }
                $linesToShow = $script:AllLogLines | Where-Object { $showVerbose -or ($_ -notmatch '\[VERB\]') }
                $script:logTextBox.Lines = $linesToShow
                $script:logTextBox.SelectionStart = $script:logTextBox.Text.Length
                $script:logTextBox.ScrollToCaret()
            }
        })
        $viewMenu.DropDownItems.Add($debugMenuItem)
        $viewMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $aboutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $aboutMenuItem.Text = "About"
        $aboutMenuItem.Add_Click({ Show-AboutDialog })
        $viewMenu.DropDownItems.Add($aboutMenuItem)
        # Wait Menu (Games)
        $waitMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $waitMenu.Text = "Wait"



        # Use absolute path to the wait folder relative to deployment root
        $deploymentRoot = Split-Path -Parent $PSScriptRoot
        $waitFolder = Join-Path $deploymentRoot 'wait'

        $minesweeperMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $minesweeperMenuItem.Text = "MineSweeper"
        $minesweeperMenuItem.Add_Click({
            try {
                $deploymentRoot = Split-Path -Parent $PSScriptRoot
                $waitFolder = Join-Path $deploymentRoot 'wait'
                $gamePath = Join-Path $waitFolder 'MineSweeper.ps1'
                if (Test-Path $gamePath) {
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$gamePath`"" -WindowStyle Hidden
                } else {
                    [System.Windows.Forms.MessageBox]::Show("MineSweeper.ps1 not found in wait folder: $gamePath", "Game Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error launching MineSweeper: $_", "Game Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })

        $snakeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $snakeMenuItem.Text = "Snake"
        $snakeMenuItem.Add_Click({
            try {
                $deploymentRoot = Split-Path -Parent $PSScriptRoot
                $waitFolder = Join-Path $deploymentRoot 'wait'
                $gamePath = Join-Path $waitFolder 'Snake.ps1'
                if (Test-Path $gamePath) {
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$gamePath`"" -WindowStyle Hidden
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Snake.ps1 not found in wait folder: $gamePath", "Game Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error launching Snake: $_", "Game Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })

        $waitMenu.DropDownItems.Add($minesweeperMenuItem)
        $waitMenu.DropDownItems.Add($snakeMenuItem)

        $menuStrip.Items.AddRange(@($systemMenu, $toolsMenu, $imagingMenu, $viewMenu, $waitMenu))
        
        # Add menu strip to form
        $form.MainMenuStrip = $menuStrip
        $form.Controls.Add($menuStrip)
        $form.Controls.SetChildIndex($menuStrip, 0)

        # 2. TableLayoutPanel for main content (now with 2 rows)
        $mainTable = New-Object System.Windows.Forms.TableLayoutPanel
        $mainTable.Dock = 'Fill'
        $mainTable.ColumnCount = 2
        $mainTable.RowCount = 2
        $mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
        $mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 100))) # Header row
        $mainTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) # Main content row
        $mainTable.Padding = '0,0,0,0'
        $mainTable.Margin = '0,0,0,0'
        $mainTable.BackColor = [System.Drawing.Color]::Transparent

        # --- HEADER CELL (row 0, col 0): logo and title in a panel ---
        $headerCellPanel = New-Object System.Windows.Forms.Panel
        $headerCellPanel.Dock = 'Fill'
        $headerCellPanel.BackColor = [System.Drawing.Color]::Transparent

        # Logo (left, fixed width)
        $logoPictureBox = New-Object System.Windows.Forms.PictureBox
        $logoPictureBox.Size = New-Object System.Drawing.Size(120, 80)
        $logoPictureBox.Location = New-Object System.Drawing.Point(10, 10)
        $logoPictureBox.BackColor = [System.Drawing.Color]::Transparent
        $logoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        try {
            $logoPath = "Y:\\DeploymentModules\\Assets\\Logo\\SHI.png"
            if (Test-Path $logoPath) {
                $logoPictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
            }
        } catch {}
        $headerCellPanel.Controls.Add($logoPictureBox)

        # Title label (right of logo)
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Windows Network Deployment Tool"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::DarkBlue
        $titleLabel.AutoSize = $false
        $titleLabel.Height = 80
        $titleLabel.Width = 700
        $titleLabel.Location = New-Object System.Drawing.Point(140, 30)
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $headerCellPanel.Controls.Add($titleLabel)

        $mainTable.Controls.Add($headerCellPanel, 0, 0)
        $mainTable.SetColumnSpan($headerCellPanel, 2) # Span both columns for header

        # --- MAIN CONTENT ROW (row 1) ---
        # Left FlowLayoutPanel (vertical)
        $leftFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $leftFlow.Dock = 'Fill'
        $leftFlow.FlowDirection = 'TopDown'
        $leftFlow.WrapContents = $false
        $leftFlow.AutoScroll = $true
        $leftFlow.Padding = '0,0,0,0'
        $leftFlow.BackColor = [System.Drawing.Color]::Transparent

        # Right FlowLayoutPanel (vertical)
        $rightFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $rightFlow.Dock = 'Fill'
        $rightFlow.FlowDirection = 'TopDown'
        $rightFlow.WrapContents = $false
        $rightFlow.AutoScroll = $true
        $rightFlow.Padding = '0,0,0,0'
        $rightFlow.BackColor = [System.Drawing.Color]::Transparent

        # --- LEFT COLUMN CONTENTS ---
        # Customer selection group
        $customerGroupBox = New-Object System.Windows.Forms.GroupBox
        $customerGroupBox.Text = "Customer Selection"
        $customerGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $customerGroupBox.Size = New-Object System.Drawing.Size(360, 80)
        $customerGroupBox.Margin = '10,0,10,0'
        $customerComboBox = New-Object System.Windows.Forms.ComboBox
        $customerComboBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $customerComboBox.Location = New-Object System.Drawing.Point(15, 25)
        $customerComboBox.Size = New-Object System.Drawing.Size(250, 25)
        $customerComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $customerGroupBox.Controls.Add($customerComboBox)
        $addCustomerButton = New-Object System.Windows.Forms.Button
        $addCustomerButton.Text = "Add New"
        $addCustomerButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $addCustomerButton.Location = New-Object System.Drawing.Point(275, 24)
        $addCustomerButton.Size = New-Object System.Drawing.Size(70, 27)
        $addCustomerButton.BackColor = [System.Drawing.Color]::FromArgb(211,211,211)
        $customerGroupBox.Controls.Add($addCustomerButton)
        $leftFlow.Controls.Add($customerGroupBox)
        # Load customers (only once)
        if (-not $script:customersLoaded) {
            $customers = Get-CustomerList
            foreach ($customer in $customers) {
                $customerComboBox.Items.Add($customer) | Out-Null
            }
            $script:customersLoaded = $true
        }

        # Order number group
        $orderGroupBox = New-Object System.Windows.Forms.GroupBox
        $orderGroupBox.Text = "Order Number"
        $orderGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $orderGroupBox.Size = New-Object System.Drawing.Size(360, 60)
        $orderGroupBox.Margin = '10,0,10,0'
        $orderTextBox = New-Object System.Windows.Forms.TextBox
        $orderTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $orderTextBox.Location = New-Object System.Drawing.Point(15, 25)
        $orderTextBox.Size = New-Object System.Drawing.Size(330, 25)
        $orderGroupBox.Controls.Add($orderTextBox)
        $leftFlow.Controls.Add($orderGroupBox)

        # Device information group
        $deviceGroupBox = New-Object System.Windows.Forms.GroupBox
        $deviceGroupBox.Text = "Device Information"
        $deviceGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $deviceGroupBox.Size = New-Object System.Drawing.Size(360, 80)
        $deviceGroupBox.Margin = '10,0,10,0'
        $deviceLabel = New-Object System.Windows.Forms.Label
        $deviceLabel.Text = "Gathering device information..."
        $deviceLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $deviceLabel.ForeColor = [System.Drawing.Color]::Blue
        $deviceLabel.Location = New-Object System.Drawing.Point(15, 25)
        $deviceLabel.Size = New-Object System.Drawing.Size(330, 45)
        $deviceGroupBox.Controls.Add($deviceLabel)
        $leftFlow.Controls.Add($deviceGroupBox)

        # Image selection button
        $selectImageButton = New-Object System.Windows.Forms.Button
        $selectImageButton.Text = "Select Image"
        $selectImageButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $selectImageButton.Size = New-Object System.Drawing.Size(360, 50)
        $selectImageButton.BackColor = [System.Drawing.Color]::FromArgb(173,216,230)
        $selectImageButton.Enabled = $false
        $selectImageButton.Margin = '10,0,10,0'
        $leftFlow.Controls.Add($selectImageButton)

        # --- RIGHT COLUMN CONTENTS ---
        # Add spacing panel at the top
        $gapPanelTop = New-Object System.Windows.Forms.Panel
        $gapPanelTop.Height = 20
        $gapPanelTop.Width = 10
        $gapPanelTop.BackColor = [System.Drawing.Color]::Transparent
        $rightFlow.Controls.Add($gapPanelTop)

        # Start deployment button
        $startDeploymentButton = New-Object System.Windows.Forms.Button
        $startDeploymentButton.Text = "Start Deployment"
        $startDeploymentButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $startDeploymentButton.Size = New-Object System.Drawing.Size(340, 60)
        $startDeploymentButton.BackColor = [System.Drawing.Color]::FromArgb(144,238,144)
        $startDeploymentButton.Enabled = $false
        $startDeploymentButton.Margin = '10,10,10,0'
        $rightFlow.Controls.Add($startDeploymentButton)

        # Cancel deployment button
        $cancelDeploymentButton = New-Object System.Windows.Forms.Button
        $cancelDeploymentButton.Text = "Cancel Deployment"
        $cancelDeploymentButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $cancelDeploymentButton.Size = New-Object System.Drawing.Size(340, 40)
        $cancelDeploymentButton.BackColor = [System.Drawing.Color]::FromArgb(240,128,128)
        $cancelDeploymentButton.Enabled = $false
        $cancelDeploymentButton.Margin = '10,0,10,0'
        $rightFlow.Controls.Add($cancelDeploymentButton)

        # Add gap before progress bar
        $gapPanelBeforeProgress = New-Object System.Windows.Forms.Panel
        $gapPanelBeforeProgress.Height = 20
        $gapPanelBeforeProgress.Width = 10
        $gapPanelBeforeProgress.BackColor = [System.Drawing.Color]::Transparent
        $rightFlow.Controls.Add($gapPanelBeforeProgress)

        # Progress bar and label (ensure they are created here)
        $script:progressBar = New-Object System.Windows.Forms.ProgressBar
        $script:progressBar.Size = New-Object System.Drawing.Size(340, 25)
        $script:progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $script:progressBar.Minimum = 0
        $script:progressBar.Maximum = 100
        $script:progressBar.Value = 0
        $script:progressBar.Margin = '10,0,10,0'
        $rightFlow.Controls.Add($script:progressBar)

        $script:progressLabel = New-Object System.Windows.Forms.Label
        $script:progressLabel.Text = "Ready for deployment"
        $script:progressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $script:progressLabel.Size = New-Object System.Drawing.Size(340, 20)
        $script:progressLabel.Margin = '10,0,10,0'
        $rightFlow.Controls.Add($script:progressLabel)

        # Add gap after progress bar
        $gapPanelAfterProgress = New-Object System.Windows.Forms.Panel
        $gapPanelAfterProgress.Height = 20
        $gapPanelAfterProgress.Width = 10
        $gapPanelAfterProgress.BackColor = [System.Drawing.Color]::Transparent
        $rightFlow.Controls.Add($gapPanelAfterProgress)

        # Deployment log group (with logTextBox inside)
        $logGroupBox = New-Object System.Windows.Forms.GroupBox
        $logGroupBox.Text = "Deployment Log"
        $logGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $logGroupBox.Size = New-Object System.Drawing.Size(340, 280)
        $logGroupBox.Margin = '10,0,10,0'
        $script:logTextBox = New-Object System.Windows.Forms.TextBox
        $script:logTextBox.Font = New-Object System.Drawing.Font("Consolas", 8)
        $script:logTextBox.Size = New-Object System.Drawing.Size(310, 240)
        $script:logTextBox.Multiline = $true
        $script:logTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $script:logTextBox.ReadOnly = $true
        $script:logTextBox.BackColor = [System.Drawing.Color]::FromArgb(0,0,0)
        $script:logTextBox.ForeColor = [System.Drawing.Color]::LimeGreen
        $script:logTextBox.Location = New-Object System.Drawing.Point(15, 25)
        $logGroupBox.Controls.Add($script:logTextBox)
        $rightFlow.Controls.Add($logGroupBox)

        # Add gap after log group
        $gapPanelAfterLog = New-Object System.Windows.Forms.Panel
        $gapPanelAfterLog.Height = 20
        $gapPanelAfterLog.Width = 10
        $gapPanelAfterLog.BackColor = [System.Drawing.Color]::Transparent
        $rightFlow.Controls.Add($gapPanelAfterLog)

        $mainTable.Controls.Add($leftFlow, 0, 1)
        $mainTable.Controls.Add($rightFlow, 1, 1)

        # Add the main table to the form (below header)
        $form.Controls.Add($mainTable)

        # Guarantee MenuStrip is at the top (z-order)
        $form.Controls.SetChildIndex($menuStrip, 0)
        $form.Controls.SetChildIndex($mainTable, 1)

        # --- Responsive scaling on resize (excluding logo and title) ---
        $originalFormSize = $form.Size
        # $originalLogoSize = $logoPictureBox.Size  # No longer used
        # $originalTitleFont = $titleLabel.Font      # No longer used
        # $originalTitleLocation = $titleLabel.Location
        # $originalTitleWidth = $titleLabel.Width

        # Store original sizes/fonts for main controls
        $originalCustomerGroupSize = $customerGroupBox.Size
        $originalCustomerGroupFont = $customerGroupBox.Font
        $originalOrderGroupSize = $orderGroupBox.Size
        $originalOrderGroupFont = $orderGroupBox.Font
        $originalDeviceGroupSize = $deviceGroupBox.Size
        $originalDeviceGroupFont = $deviceGroupBox.Font
        $originalSelectImageButtonSize = $selectImageButton.Size
        $originalSelectImageButtonFont = $selectImageButton.Font
        $originalStartDeploymentButtonSize = $startDeploymentButton.Size
        $originalStartDeploymentButtonFont = $startDeploymentButton.Font
        $originalCancelDeploymentButtonSize = $cancelDeploymentButton.Size
        $originalCancelDeploymentButtonFont = $cancelDeploymentButton.Font
        $originalProgressBarSize = $script:progressBar.Size
        $originalProgressLabelFont = $script:progressLabel.Font
        $originalLogGroupBoxSize = $logGroupBox.Size
        $originalLogGroupBoxFont = $logGroupBox.Font
        $originalLogTextBoxSize = $script:logTextBox.Size
        $originalLogTextBoxFont = $script:logTextBox.Font

        $form.Add_Resize({
            $scaleX = $form.Width / $originalFormSize.Width
            $scaleY = $form.Height / $originalFormSize.Height

            # Aspect ratio aware scaling: use the smaller scale factor to avoid clipping on square-ish screens
            $scale = [Math]::Min($scaleX, $scaleY)

            # Optionally, limit the maximum scale to avoid excessive growth on ultra-wide or tall screens
            $scale = [Math]::Min($scale, 1.5)
            $scale = [Math]::Max($scale, 0.7)

            # Do NOT scale logo or title

            # Scale group boxes and their fonts
            $customerGroupBox.Size = New-Object System.Drawing.Size([int]($originalCustomerGroupSize.Width * $scale), [int]($originalCustomerGroupSize.Height * $scale))
            $customerGroupBox.Font = New-Object System.Drawing.Font($originalCustomerGroupFont.FontFamily, [Math]::Max(8, [int]($originalCustomerGroupFont.Size * $scale)), $originalCustomerGroupFont.Style)
            $orderGroupBox.Size = New-Object System.Drawing.Size([int]($originalOrderGroupSize.Width * $scale), [int]($originalOrderGroupSize.Height * $scale))
            $orderGroupBox.Font = New-Object System.Drawing.Font($originalOrderGroupFont.FontFamily, [Math]::Max(8, [int]($originalOrderGroupFont.Size * $scale)), $originalOrderGroupFont.Style)
            $deviceGroupBox.Size = New-Object System.Drawing.Size([int]($originalDeviceGroupSize.Width * $scale), [int]($originalDeviceGroupSize.Height * $scale))
            $deviceGroupBox.Font = New-Object System.Drawing.Font($originalDeviceGroupFont.FontFamily, [Math]::Max(8, [int]($originalDeviceGroupFont.Size * $scale)), $originalDeviceGroupFont.Style)

            # Scale buttons and their fonts
            $selectImageButton.Size = New-Object System.Drawing.Size([int]($originalSelectImageButtonSize.Width * $scale), [int]($originalSelectImageButtonSize.Height * $scale))
            $selectImageButton.Font = New-Object System.Drawing.Font($originalSelectImageButtonFont.FontFamily, [Math]::Max(8, [int]($originalSelectImageButtonFont.Size * $scale)), $originalSelectImageButtonFont.Style)
            $startDeploymentButton.Size = New-Object System.Drawing.Size([int]($originalStartDeploymentButtonSize.Width * $scale), [int]($originalStartDeploymentButtonSize.Height * $scale))
            $startDeploymentButton.Font = New-Object System.Drawing.Font($originalStartDeploymentButtonFont.FontFamily, [Math]::Max(8, [int]($originalStartDeploymentButtonFont.Size * $scale)), $originalStartDeploymentButtonFont.Style)
            $cancelDeploymentButton.Size = New-Object System.Drawing.Size([int]($originalCancelDeploymentButtonSize.Width * $scale), [int]($originalCancelDeploymentButtonSize.Height * $scale))
            $cancelDeploymentButton.Font = New-Object System.Drawing.Font($originalCancelDeploymentButtonFont.FontFamily, [Math]::Max(8, [int]($originalCancelDeploymentButtonFont.Size * $scale)), $originalCancelDeploymentButtonFont.Style)

            # Scale progress bar and label
            $script:progressBar.Size = New-Object System.Drawing.Size([int]($originalProgressBarSize.Width * $scale), [int]($originalProgressBarSize.Height * $scale))
            $script:progressLabel.Font = New-Object System.Drawing.Font($originalProgressLabelFont.FontFamily, [Math]::Max(8, [int]($originalProgressLabelFont.Size * $scale)), $originalProgressLabelFont.Style)

            # Scale deployment log group and textbox
            $logGroupBox.Size = New-Object System.Drawing.Size([int]($originalLogGroupBoxSize.Width * $scale), [int]($originalLogGroupBoxSize.Height * $scale))
            $logGroupBox.Font = New-Object System.Drawing.Font($originalLogGroupBoxFont.FontFamily, [Math]::Max(8, [int]($originalLogGroupBoxFont.Size * $scale)), $originalLogGroupBoxFont.Style)
            $script:logTextBox.Size = New-Object System.Drawing.Size([int]($originalLogTextBoxSize.Width * $scale), [int]($originalLogTextBoxSize.Height * $scale))
            $script:logTextBox.Font = New-Object System.Drawing.Font($originalLogTextBoxFont.FontFamily, [Math]::Max(8, [int]($originalLogTextBoxFont.Size * $scale)), $originalLogTextBoxFont.Style)
        })

        # --- Add toolbar label for system time ---
        $timeLabel = New-Object System.Windows.Forms.ToolStripLabel
        $timeLabel.Name = "toolStripTimeLabel"
        $timeLabel.Alignment = "Right"
        $timeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $timeLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray
        $timeLabel.Text = (Get-Date).ToString("HH:mm:ss")
        $menuStrip.Items.Add($timeLabel)

        # Timer to update the time label every second
        $script:systemTimeTimer = New-Object System.Windows.Forms.Timer
        $script:systemTimeTimer.Interval = 1000
        $script:systemTimeTimer.Add_Tick({
            try {
                if ($timeLabel -and $timeLabel -is [System.Windows.Forms.ToolStripLabel]) {
                    $timeLabel.Text = (Get-Date).ToString("HH:mm:ss")
                }
            } catch {}
        })
        $script:systemTimeTimer.Start()

        # Add comprehensive form close handler to clean up timers
        $form.Add_FormClosing({
            try {
                if ($script:systemTimeTimer) {
                    $script:systemTimeTimer.Stop()
                    $script:systemTimeTimer.Dispose()
                    Remove-Variable -Name systemTimeTimer -Scope Script -ErrorAction SilentlyContinue
                }
                Stop-AllRunningTimers
            } catch {
                # Silently handle timer cleanup errors
            }
        })

        # Add form disposed handler
        $form.Add_Disposed({
            try {
                if ($script:systemTimeTimer) {
                    $script:systemTimeTimer.Stop()
                    $script:systemTimeTimer.Dispose()
                    Remove-Variable -Name systemTimeTimer -Scope Script -ErrorAction SilentlyContinue
                }
                Stop-AllRunningTimers
            } catch {
                # Silently handle timer cleanup errors
            }
        })

        # Add resize handler to reposition timeLabel top-right (optional, for aesthetics)
        $form.Add_Resize({
            # Reposition timeLabel top-right in the menu strip
            if ($timeLabel -and $menuStrip.Items.Contains($timeLabel)) {
                $timeLabel.Alignment = "Right"
            }
        })

        # Event handlers
        
        # Customer selection
        $customerComboBox.Add_SelectedIndexChanged({
            if ($customerComboBox.SelectedItem) {
                $script:selectedCustomer = $customerComboBox.SelectedItem.ToString()
                Write-LogMessage "Customer selected: $script:selectedCustomer" "INFO"
                Add-LogEntry "Customer selected: $script:selectedCustomer"
                
                # Auto-refresh customer ISOs when customer is selected
                try {
                    Add-LogEntry "Refreshing ISO list for customer..."
                    $isoCount = Refresh-CustomerISOs -CustomerName $script:selectedCustomer
                    Add-LogEntry "Found $isoCount ISO(s) for customer $script:selectedCustomer"
                    
                    # Debug: Show ISO details
                    if ($isoCount -gt 0) {
                        $customerISOs = Get-CustomerISOs -CustomerName $script:selectedCustomer
                        Write-LogMessage "DEBUG: Retrieved $($customerISOs.Count) ISOs for display" "INFO"
                        foreach ($iso in $customerISOs) {
                            Write-LogMessage "DEBUG: ISO - Name: $($iso.Name), Category: $($iso.Category), Path: $($iso.Path)" "VERBOSE"
                        }
                    }
                } catch {
                    Write-LogMessage "Error refreshing customer ISOs: $_" "WARNING"
                    Add-LogEntry "Warning: Could not refresh ISO list for customer"
                }
                
                Update-DeploymentButtons
            }
        })
        
        # Add customer button
        $addCustomerButton.Add_Click({
            try {
                # Defensive: Check if Show-NewCustomerDialog exists before calling
                if (Get-Command Show-NewCustomerDialog -ErrorAction SilentlyContinue) {
                    $newCustomer = Show-NewCustomerDialog
                } else {
                    [System.Windows.Forms.MessageBox]::Show("The function Show-NewCustomerDialog is not available in this environment.", "Function Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
                if ($newCustomer) {
                    # Create customer directory and minimal Config.json
                    $customerDir = Join-Path 'Y:\DeploymentModules\Config\CustomerConfig' $newCustomer
                    if (-not (Test-Path $customerDir)) {
                        New-Item -Path $customerDir -ItemType Directory -Force | Out-Null
                    }
                    $configFile = Join-Path $customerDir 'Config.json'
                    if (-not (Test-Path $configFile)) {
                        $defaultConfig = @{ CustomerName = $newCustomer; Description = "" } | ConvertTo-Json -Depth 3
                        $defaultConfig | Out-File -FilePath $configFile -Encoding UTF8 -Force
                    }
                    $customerComboBox.Items.Add($newCustomer)
                    $customerComboBox.SelectedItem = $newCustomer
                    Add-LogEntry "New customer added: $newCustomer"
                }
            } catch {
                Write-LogMessage "Error adding new customer: $_" "ERROR"
                Add-LogEntry "Error adding customer: $_"
            }
        })
        
        # Order number input
        $orderTextBox.Add_TextChanged({
            $script:orderNumber = $orderTextBox.Text.Trim()
            Update-DeploymentButtons
        })
        
        # Select image button
        $selectImageButton.Add_Click({
            try {
                if ([string]::IsNullOrWhiteSpace($script:selectedCustomer)) {
                    [System.Windows.Forms.MessageBox]::Show("Please select a customer first.", "Missing Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                
                Add-LogEntry "Opening image selection..."
                
                # Get customer ISOs to pass to ImageMenu
                $customerISOs = @()
                try {
                    $customerISOs = Get-CustomerISOs -CustomerName $script:selectedCustomer
                    Write-LogMessage "Passing $($customerISOs.Count) customer ISOs to ImageMenu" "INFO"
                } catch {
                    Write-LogMessage "Error getting customer ISOs for ImageMenu: $_" "WARNING"
                }
                
                $imageSelection = Show-ImageSelectionMenu -CustomerName $script:selectedCustomer -OrderNumber $script:orderNumber -DeviceInfo $script:deviceInfo -CustomerISOs $customerISOs
                
                if ($imageSelection) {
                    $script:selectedImage = $imageSelection
                    Add-LogEntry "Image selected: $($imageSelection.ImageInfo.Name)"
                    Update-DeploymentButtons
                } else {
                    Add-LogEntry "Image selection cancelled"
                }
            } catch {
                Write-LogMessage "Error in image selection: $_" "ERROR"
                Add-LogEntry "Error selecting image: $_"
            }
        })
        
        # Start deployment button
        $startDeploymentButton.Add_Click({
            try {
                Add-LogEntry "Starting deployment..."

                # Confirmation
                $confirmMessage = @"
Ready to deploy:

Customer: $($script:selectedCustomer)
Order: $($script:orderNumber)
Image: $($script:selectedImage.ImageInfo.Name)
Device: $($script:deviceInfo.Manufacturer) $($script:deviceInfo.Model)

This will format the hard drive and install Windows.
Are you sure you want to continue?
"@
                $confirmResult = [System.Windows.Forms.MessageBox]::Show($confirmMessage, "Confirm Deployment", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

                if ($confirmResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $startDeploymentFunc = Get-Command Start-DeploymentProcess -ErrorAction SilentlyContinue
                    if ($startDeploymentFunc) {
                        Start-DeploymentProcess
                    } elseif (Get-Command Start-WindowsDeployment -ErrorAction SilentlyContinue) {
                        $params = @{
                            ImagePath    = $script:selectedImage.ImageInfo.FullPath
                            CustomerName = $script:selectedCustomer
                            OrderNumber  = $script:orderNumber
                            DeviceInfo   = $script:deviceInfo
                            ImageIndex   = $script:selectedImage.ImageInfo.ImageIndex
                            ImageConfig  = $script:selectedImage.ImageInfo
                            # Add other parameters as needed
                        }
                        $result = Start-WindowsDeployment @params
                        if ($result -and $result.Success) {
                            Show-CountdownAndReboot
                        }
                    } else {
                        [System.Windows.Forms.MessageBox]::Show(
                            "No deployment function (Start-DeploymentProcess or Start-WindowsDeployment) is available in this environment.",
                            "Function Not Found",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Error
                        )
                        Add-LogEntry "No deployment function found."
                    }
                } else {
                    Add-LogEntry "Deployment cancelled by user"
                }
            } catch {
                Write-LogMessage "Error starting deployment: $_" "ERROR"
                Add-LogEntry "Error starting deployment: $_"
            }
        })
        
        # Cancel deployment button
        $cancelDeploymentButton.Add_Click({
            Add-LogEntry "Deployment cancelled by user"
            # Add cancellation logic here
        })
        
        # Initialize device information
        try {
            Write-LogMessage "Gathering initial device information..." "INFO"
            $script:deviceInfo = Get-DeviceBasicInfo
            
            if ($script:deviceInfo -and $script:deviceInfo.Manufacturer -and $script:deviceInfo.Model -and $script:deviceInfo.SerialNumber) {
                $deviceLabel.Text = "Device: $($script:deviceInfo.Manufacturer) $($script:deviceInfo.Model)`nSerial: $($script:deviceInfo.SerialNumber)"
                $deviceLabel.ForeColor = [System.Drawing.Color]::Green
                Add-LogEntry "Device detected: $($script:deviceInfo.Manufacturer) $($script:deviceInfo.Model)"
            } else {
                $deviceLabel.Text = "Device: Information incomplete or unavailable"
                $deviceLabel.ForeColor = [System.Drawing.Color]::Orange
                Add-LogEntry "Device information incomplete"
                
                # Create minimal device info
                $script:deviceInfo = @{
                    Manufacturer = "Unknown"
                    Model = "Unknown"
                    SerialNumber = "Unknown-$(Get-Date -Format 'yyyyMMddHHmmss')"
                }
            }
        } catch {
            Write-LogMessage "Failed to gather device information: $_" "ERROR"
            $deviceLabel.Text = "Device: Error gathering information"
            $deviceLabel.ForeColor = [System.Drawing.Color]::Red
            Add-LogEntry "Device information error: $_"
            
            # Create minimal device info for error case
            $script:deviceInfo = @{
                Manufacturer = "Unknown"
                Model = "Unknown"
                SerialNumber = "Error-$(Get-Date -Format 'yyyyMMddHHmmss')"
            }
        }
    } catch {
        Write-LogMessage "Error in Show-DeploymentMenu: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred while initializing the deployment menu: $_", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    
    # Display the form
    Write-LogMessage "Showing deployment menu form" "INFO"
    $result = $form.ShowDialog()
    try { $form.Dispose() } catch {}
    Exit
}

function Start-DeploymentProcess {
    try {
        Add-LogEntry "Preparing deployment parameters..."
        
        # Disable start button, enable cancel
        $startDeploymentButton.Enabled = $false
        $cancelDeploymentButton.Enabled = $true
        
        # Start Cat Mode if enabled (this will run in background)
        if ($script:catModeEnabled) {
            try {
                Write-LogMessage "Cat Mode is enabled, attempting to start..." "INFO"
                Add-LogEntry "Starting Cat Mode..."
                
                # Ensure assemblies are loaded first
                if (-not ('System.Windows.Forms.Form' -as [type])) {
                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                    Write-LogMessage "Loaded System.Windows.Forms assembly" "VERBOSE"
                }
                if (-not ('System.Drawing.Bitmap' -as [type])) {
                    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
                    Write-LogMessage "Loaded System.Drawing assembly" "VERBOSE"
                }
                
                # Ensure Cat Mode module is loaded
                if (-not (Get-Command Start-CatMode -ErrorAction SilentlyContinue)) {
                    Write-LogMessage "Cat Mode module not loaded, importing..." "INFO"
                    Import-Module "$PSScriptRoot\..\Core\CatMode.psm1" -Force
                    Add-LogEntry "Imported Cat Mode module"
                }
                
                # Check if the command is now available
                if (Get-Command Start-CatMode -ErrorAction SilentlyContinue) {
                    Write-LogMessage "Starting Cat Mode..." "INFO"
                    Start-CatMode
                    $global:catModeEnabled = $true
                    Add-LogEntry "Cat Mode activated for deployment!"
                    Write-Host "CAT: Successfully started Cat Mode" -ForegroundColor Green
                    
                    # Give it a moment to initialize
                    Start-Sleep -Milliseconds 1000
                    
                    # Test with initial progress update
                    Update-DeploymentProgress -PercentComplete 1 -Status "Cat Mode initialized, starting deployment..."
                    
                } else {
                    Write-LogMessage "Start-CatMode command not found after module import" "WARNING"
                    Add-LogEntry "Cat Mode command not available"
                    $script:catModeEnabled = $false
                }
            } catch {
                Write-LogMessage "Failed to start Cat Mode: $_" "WARNING"
                Add-LogEntry "Cat Mode failed to start: $_"
                $script:catModeEnabled = $false
            }
        } else {
            Write-LogMessage "Cat Mode is not enabled" "INFO"
        }
        
        # Import WindowsInstaller module
        Import-Module "$PSScriptRoot\..\Deployment\WindowsInstaller.psm1" -Force
        
        # Prepare deployment parameters
        $deploymentParams = @{
            ImagePath = $script:selectedImage.ImageInfo.FullPath
            CustomerName = $script:selectedCustomer
            OrderNumber = $script:orderNumber
            DeviceInfo = $script:deviceInfo
            UseDisk0 = $true
            ImageIndex = if ($script:selectedImage.ImageInfo.ImageIndex) { $script:selectedImage.ImageInfo.ImageIndex } else { 1 }
            ImageConfig = $script:selectedImage.ImageInfo
        }
        
        Add-LogEntry "Starting Windows deployment..."
        
        # The deployment will now run without blocking the cat mode animation
        $deploymentResult = Start-WindowsDeployment @deploymentParams
        
        if ($deploymentResult.Success) {
            Update-DeploymentProgress -PercentComplete 100 -Status "Deployment completed successfully!"
            Add-LogEntry "Deployment completed successfully!"
            Add-LogEntry "Duration: $($deploymentResult.Duration) seconds"
            
            # Stop Cat Mode if it was running
            if ($script:catModeEnabled -or $global:catModeEnabled) {
                try {
                    if (Get-Command Stop-CatMode -ErrorAction SilentlyContinue) {
                        Stop-CatMode
                        Add-LogEntry "Cat Mode stopped"
                    }
                } catch {
                    Write-LogMessage "Error stopping Cat Mode: $_" "WARNING"
                }
            }
            
            Show-CountdownAndReboot
            
        } else {
            Update-DeploymentProgress -PercentComplete 0 -Status "Deployment failed"
            Add-LogEntry "Deployment failed: $($deploymentResult.Message)"
            
            # Stop Cat Mode on failure
            if ($script:catModeEnabled -or $global:catModeEnabled) {
                try {
                    if (Get-Command Stop-CatMode -ErrorAction SilentlyContinue) {
                        Stop-CatMode
                    }
                } catch {
                    Write-LogMessage "Error stopping Cat Mode after failure: $_" "WARNING"
                }
            }
            
            [System.Windows.Forms.MessageBox]::Show("Deployment failed: $($deploymentResult.Message)", "Deployment Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        
    } catch {
        Write-LogMessage "Error during deployment: $_" "ERROR"
        Add-LogEntry "Deployment error: $_"
        Update-DeploymentProgress -PercentComplete 0 -Status "Deployment error"
        
        # Stop Cat Mode on error
        if ($script:catModeEnabled -or $global:catModeEnabled) {
            try {
                if (Get-Command Stop-CatMode -ErrorAction SilentlyContinue) {
                    Stop-CatMode
                }
            } catch {
                Write-LogMessage "Error stopping Cat Mode after error: $_" "WARNING"
            }
        }
        
        [System.Windows.Forms.MessageBox]::Show("Deployment error: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        # Re-enable start button, disable cancel
        $startDeploymentButton.Enabled = $true
        $cancelDeploymentButton.Enabled = $false
        
        # Ensure global cat mode is disabled
        $global:catModeEnabled = $false
    }
}

function Get-ScreenResolution {
    [CmdletBinding()]
    param()
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        return @{ Width = $screenWidth; Height = $screenHeight }
    } catch {
        return @{ Width = 1024; Height = 768 }
    }
}

function Show-CountdownAndReboot {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Starting countdown to reboot..." "INFO"
        Add-LogEntry "Starting 10 second countdown to reboot..."
        
        # Get screen resolution for full screen display
        $screenInfo = Get-ScreenResolution
        $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
        $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
        
        # Calculate scaled font sizes based on screen resolution
        $baseTitleFontSize = [Math]::Max(24, [int](48 * ($screenWidth / 1920)))
        $baseSubtitleFontSize = [Math]::Max(14, [int](24 * ($screenWidth / 1920)))
        $baseCountdownFontSize = [Math]::Max(60, [int](120 * ($screenWidth / 1920)))
        $baseButtonFontSize = [Math]::Max(9, [int](12 * ($screenWidth / 1920)))
        
        # Create full screen countdown form
        $countdownForm = New-Object System.Windows.Forms.Form
        $countdownForm.Text = "Deployment Complete - Rebooting"
        $countdownForm.Size = New-Object System.Drawing.Size($screenWidth, $screenHeight)
        $countdownForm.StartPosition = "Manual"
        $countdownForm.Location = New-Object System.Drawing.Point(0, 0)
        $countdownForm.FormBorderStyle = "None"
        $countdownForm.WindowState = "Maximized"
        $countdownForm.TopMost = $true
        $countdownForm.BackColor = [System.Drawing.Color]::Black
        
        # Main title label with proper scaling and positioning
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "DEPLOYMENT COMPLETED SUCCESSFULLY"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $baseTitleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = [System.Drawing.Color]::LimeGreen
        $titleLabel.Location = New-Object System.Drawing.Point(0, [int]($screenHeight * 0.2))
        $titleLabel.Size = New-Object System.Drawing.Size($screenWidth, [int]($baseTitleFontSize * 1.5))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $titleLabel.AutoSize = $false
        $countdownForm.Controls.Add($titleLabel)
        
        # Reboot message label with proper scaling
        $rebootLabel = New-Object System.Windows.Forms.Label
        $rebootLabel.Text = "System will reboot automatically"
        $rebootLabel.Font = New-Object System.Drawing.Font("Segoe UI", $baseSubtitleFontSize, [System.Drawing.FontStyle]::Regular)
        $rebootLabel.ForeColor = [System.Drawing.Color]::White
        $rebootLabel.Location = New-Object System.Drawing.Point(0, [int]($screenHeight * 0.35))
        $rebootLabel.Size = New-Object System.Drawing.Size($screenWidth, [int]($baseSubtitleFontSize * 1.5))
        $rebootLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $rebootLabel.AutoSize = $false
        $countdownForm.Controls.Add($rebootLabel)
        
        # Countdown number label with proper scaling
        $countdownLabel = New-Object System.Windows.Forms.Label
        $countdownLabel.Text = "10"
        $countdownLabel.Font = New-Object System.Drawing.Font("Segoe UI", $baseCountdownFontSize, [System.Drawing.FontStyle]::Bold)
        $countdownLabel.ForeColor = [System.Drawing.Color]::Yellow
        $countdownLabel.Location = New-Object System.Drawing.Point(0, [int]($screenHeight * 0.45))
        $countdownLabel.Size = New-Object System.Drawing.Size($screenWidth, [int]($baseCountdownFontSize * 1.5))
        $countdownLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $countdownLabel.AutoSize = $false
        $countdownForm.Controls.Add($countdownLabel)
        
        # Cancel button (small, bottom right) with scaling
        $cancelRebootButton = New-Object System.Windows.Forms.Button
        $cancelRebootButton.Text = "Cancel Reboot"
        $cancelRebootButton.Font = New-Object System.Drawing.Font("Segoe UI", $baseButtonFontSize)
        $cancelRebootButton.Location = New-Object System.Drawing.Point([int]($screenWidth - 220), [int]($screenHeight - 100))
        $cancelRebootButton.Size = New-Object System.Drawing.Size(200, [int]($baseButtonFontSize * 3))
        $cancelRebootButton.BackColor = [System.Drawing.Color]::Red
        $cancelRebootButton.ForeColor = [System.Drawing.Color]::White
        $countdownForm.Controls.Add($cancelRebootButton)
        
        # Initialize countdown value - moved outside of timer scope
        $script:countdownValue = 10
        
        # Timer for countdown
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000  # 1 second
        
        # Timer tick event - fixed variable scope issue
        $timer.Add_Tick({
            $script:countdownValue--
            $countdownLabel.Text = $script:countdownValue.ToString()
            
            # Change color as countdown progresses
            if ($script:countdownValue -le 3) {
                $countdownLabel.ForeColor = [System.Drawing.Color]::Red
            } elseif ($script:countdownValue -le 5) {
                $countdownLabel.ForeColor = [System.Drawing.Color]::Orange
            }
            
            Write-LogMessage "Countdown: $script:countdownValue seconds to reboot" "INFO"
            Add-LogEntry "Rebooting in $script:countdownValue seconds..."
            
            if ($script:countdownValue -le 0) {
                $timer.Stop()
                $countdownForm.Close()
                
                # Execute reboot
                Write-LogMessage "Countdown complete - initiating system reboot" "INFO"
                Add-LogEntry "Countdown complete - rebooting system now!"
                
                try {
                    # Use shutdown command for immediate reboot
                    Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "0", "/f" -NoNewWindow -Wait
                } catch {
                    Write-LogMessage "Error initiating reboot via shutdown.exe: $_" "ERROR"
                    try {
                        # Fallback to Restart-Computer
                        Restart-Computer -Force
                    } catch {
                        Write-LogMessage "Error initiating reboot via Restart-Computer: $_" "ERROR"
                        [System.Windows.Forms.MessageBox]::Show("Could not initiate automatic reboot. Please restart manually.", "Reboot Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    }
                }
            }
        })
        
        # Cancel button event
        $cancelRebootButton.Add_Click({
            $timer.Stop()
            $countdownForm.Close()
            Write-LogMessage "Automatic reboot cancelled by user" "INFO"
            Add-LogEntry "Automatic reboot cancelled by user"
            [System.Windows.Forms.MessageBox]::Show("Automatic reboot cancelled. You may restart manually when ready.", "Reboot Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        })
        
        # ESC key to cancel
        $countdownForm.Add_KeyDown({
            param($sender, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $timer.Stop()
                $countdownForm.Close()
                Write-LogMessage "Automatic reboot cancelled by ESC key" "INFO"
                Add-LogEntry "Automatic reboot cancelled by ESC key"
                [System.Windows.Forms.MessageBox]::Show("Automatic reboot cancelled. You may restart manually when ready.", "Reboot Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        })
        
        # Make form focusable for key events
        $countdownForm.KeyPreview = $true
        
        # Start the timer and show the form
        $timer.Start()
        $countdownForm.ShowDialog()
        $countdownForm.Dispose()
        
    } catch {
        Write-LogMessage "Error in countdown and reboot function: $_" "ERROR"
        Add-LogEntry "Error in countdown: $_"
        [System.Windows.Forms.MessageBox]::Show("Error displaying countdown. System will not reboot automatically.", "Countdown Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-DeviceInformationDialog {
    param([hashtable]$DeviceInfo = $null)
    
    try {
        if (-not $DeviceInfo) {
            Import-Module "$PSScriptRoot\..\Core\DeviceInformation.psm1" -Force
            $DeviceInfo = Get-DeviceInformation
        }
        
        # Use the existing device information dialog from ImageCaptureMenu
        Import-Module "$PSScriptRoot\ImageCaptureMenu.psm1" -Force
        
        # Call the device information dialog function
        & (Get-Module ImageCaptureMenu) { Show-DeviceInformationDialog }
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error displaying device information: $_", "Device Information Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-NetworkDrivesStatus {
    try {
        $screenInfo = Get-ScreenResolution
        $screenWidth = $screenInfo.Width
        $screenHeight = $screenInfo.Height
        $scale = [Math]::Min([Math]::Max($screenWidth / 1920, 1.0), 2.0)

        $formWidth = [int](600 * $scale)
        $formHeight = [int](400 * $scale)
        $headerFontSize = [Math]::Max(10, [int](12 * $scale))
        $listFontSize = [Math]::Max(8, [int](9 * $scale))
        $buttonFontSize = [Math]::Max(8, [int](10 * $scale))

        $statusForm = New-Object System.Windows.Forms.Form
        $statusForm.Text = "Network Drives Status"
        $statusForm.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
        $statusForm.StartPosition = "CenterParent"
        $statusForm.FormBorderStyle = "Sizable"
        $statusForm.MaximizeBox = $false
        $statusForm.MinimizeBox = $false

        $listView = New-Object System.Windows.Forms.ListView
        $listView.Dock = [System.Windows.Forms.DockStyle]::Fill
        $listView.View = [System.Windows.Forms.View]::Details
        $listView.FullRowSelect = $true
        $listView.GridLines = $true
        $listView.Font = New-Object System.Drawing.Font("Segoe UI", $listFontSize)

        # Add columns
        $listView.Columns.Add("Drive", [int](80 * $scale)) | Out-Null
        $listView.Columns.Add("Path", [int](300 * $scale)) | Out-Null
        $listView.Columns.Add("Status", [int](100 * $scale)) | Out-Null
        $listView.Columns.Add("Free Space", [int](100 * $scale)) | Out-Null

        # Read server IP from config
        $serverConfigPath = "X:\\Windows\\System32\\Deploy\\Modules\\Config\\ServerConfig\\server-config.json"
        $serverIP = ""
        $fallbackIPs = @("172.16.10.3", "172.20.11.23")
        if (Test-Path $serverConfigPath) {
            try {
                $serverConfig = Get-Content $serverConfigPath -Raw | ConvertFrom-Json
                $serverIP = $serverConfig.serverIP
                if ([string]::IsNullOrWhiteSpace($serverIP)) {
                    $serverIP = $fallbackIPs[0]
                }
            } catch {
                $serverIP = $fallbackIPs[0]
            }
        } else {
            $serverIP = $fallbackIPs[0]
        }
        # If first fallback fails, try the second
        if (-not (Test-Connection -ComputerName $serverIP -Count 1 -Quiet)) {
            $serverIP = $fallbackIPs[1]
        }

        # Check network drives
        $networkDrives = @(
            @{ Letter = "W:"; Path = "\\$serverIP\Logs" },
            @{ Letter = "Y:"; Path = "\\$serverIP\Deploy" },
            @{ Letter = "Z:"; Path = "\\$serverIP\Images" },
            @{ Letter = "V:"; Path = "\\$serverIP\Drivers" }
        )

        foreach ($drive in $networkDrives) {
            $item = New-Object System.Windows.Forms.ListViewItem($drive.Letter)
            $item.SubItems.Add($drive.Path) | Out-Null
            if (Test-Path $drive.Letter) {
                $item.SubItems.Add("Connected") | Out-Null
                try {
                    $free = Get-PSDrive -Name $drive.Letter.TrimEnd(':') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Free
                    if ($free) {
                        $item.SubItems.Add(( [math]::Round($free/1GB,2).ToString() + ' GB')) | Out-Null
                    } else {
                        $item.SubItems.Add('N/A') | Out-Null
                    }
                } catch { $item.SubItems.Add('N/A') | Out-Null }
            } else {
                $item.SubItems.Add("Not Connected") | Out-Null
                $item.SubItems.Add('N/A') | Out-Null
            }
            $listView.Items.Add($item) | Out-Null
        }

        $statusForm.Controls.Add($listView)

        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Font = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize)
        $okButton.Size = New-Object System.Drawing.Size([int](75 * $scale), [int](30 * $scale))
        $okButton.Location = New-Object System.Drawing.Point([int](($formWidth - 75 * $scale) / 2), [int](($formHeight - 50 * $scale)))
        $okButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $statusForm.Controls.Add($okButton)
        $statusForm.AcceptButton = $okButton

        $statusForm.ShowDialog() | Out-Null
        $statusForm.Dispose()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error checking network drives: $_", "Network Drives Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-AboutDialog {
    try {
        $screenInfo = Get-ScreenResolution
        $screenWidth = $screenInfo.Width
        $screenHeight = $screenInfo.Height
        $scale = [Math]::Min([Math]::Max($screenWidth / 1920, 1.0), 2.0)

        $formWidth = [int](450 * $scale)
        $formHeight = [int](300 * $scale)
        $titleFontSize = [Math]::Max(12, [int](14 * $scale))
        $versionFontSize = [Math]::Max(8, [int](10 * $scale))
        $descFontSize = [Math]::Max(8, [int](9 * $scale))
        $buttonFontSize = [Math]::Max(8, [int](10 * $scale))

        $aboutForm = New-Object System.Windows.Forms.Form
        $aboutForm.Text = "About Windows Deployment Tool"
        $aboutForm.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
        $aboutForm.StartPosition = "CenterParent"
        $aboutForm.FormBorderStyle = "Sizable"
        $aboutForm.MaximizeBox = $false
        $aboutForm.MinimizeBox = $false

        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "Windows Network Deployment Tool"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", $titleFontSize, [System.Drawing.FontStyle]::Bold)
        $titleLabel.Location = New-Object System.Drawing.Point([int](20 * $scale), [int](20 * $scale))
        $titleLabel.Size = New-Object System.Drawing.Size([int](400 * $scale), [int](30 * $scale))
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $titleLabel.AutoSize = $false
        $aboutForm.Controls.Add($titleLabel)

        $versionLabel = New-Object System.Windows.Forms.Label
        $versionLabel.Text = "Version 5.2.1"
        $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", $versionFontSize)
        $versionLabel.Location = New-Object System.Drawing.Point([int](20 * $scale), [int](60 * $scale))
        $versionLabel.Size = New-Object System.Drawing.Size([int](400 * $scale), [int](20 * $scale))
        $versionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $aboutForm.Controls.Add($versionLabel)

        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = @"
Network-based Windows deployment and imaging tool.
Created By Rose Webb

Features:
- Automated Windows deployment
- Custom image capture
- Customer-specific configurations
- Driver injection
- Windows Update integration
- Comprehensive logging

Built with PowerShell
"@
        $descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", $descFontSize)
        $descriptionLabel.Location = New-Object System.Drawing.Point([int](20 * $scale), [int](100 * $scale))
        $descriptionLabel.Size = New-Object System.Drawing.Size([int](400 * $scale), [int](120 * $scale))
        $aboutForm.Controls.Add($descriptionLabel)

        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Font = New-Object System.Drawing.Font("Segoe UI", $buttonFontSize)
        $okButton.Location = New-Object System.Drawing.Point([int](($formWidth - 75 * $scale) / 2), [int](230 * $scale))
        $okButton.Size = New-Object System.Drawing.Size([int](75 * $scale), [int](30 * $scale))
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $aboutForm.Controls.Add($okButton)

        $aboutForm.AcceptButton = $okButton
        $aboutForm.ShowDialog() | Out-Null
        $aboutForm.Dispose()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error displaying about dialog: $_", "About Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}
# Export module functions
Export-ModuleMember -Function Show-DeploymentMenu, Update-DeploymentProgress, Get-CustomerList, Add-LogEntry, Update-DeploymentButtons