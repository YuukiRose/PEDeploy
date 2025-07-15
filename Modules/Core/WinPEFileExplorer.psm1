# WinPE File Explorer Module
# Provides a lightweight file explorer interface for WinPE environments

# Import required modules
try {
    Import-Module "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import Logging module: $_" -ForegroundColor Red
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        Write-Host "[$Level] $Message" -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"White"})
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
            Width = 1024
            Height = 768
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

function Show-WinPEFileExplorer {
    [CmdletBinding()]
    param(
        [string]$StartPath = "C:\"
    )
    
    try {
        Write-LogMessage "Starting WinPE File Explorer" "INFO"
        
        # Get screen resolution and scaling
        $screenInfo = Get-ScreenResolution
        $scale = $screenInfo.ScaleFactor
        
        # Scale font sizes
        $baseFontSize = 9
        $titleFontSize = 12
        $buttonFontSize = 9
        
        $scaledBaseFontSize = [Math]::Max(8, [int]($baseFontSize * $scale))
        $scaledTitleFontSize = [Math]::Max(10, [int]($titleFontSize * $scale))
        $scaledButtonFontSize = [Math]::Max(8, [int]($buttonFontSize * $scale))
        
        # Create main form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "WinPE File Explorer"
        $form.Size = New-Object System.Drawing.Size((Scale-UIElement 900 $scale), (Scale-UIElement 700 $scale))
        $form.StartPosition = "CenterScreen"
        $form.MinimizeBox = $true
        $form.MaximizeBox = $true
        $form.FormBorderStyle = "Sizable"
        
        # Create menu bar
        $menuStrip = New-Object System.Windows.Forms.MenuStrip
        $menuStrip.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        
        # File menu
        $fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $fileMenu.Text = "File"
        
        $newFolderMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $newFolderMenuItem.Text = "New Folder"
        $newFolderMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::N
        
        $deleteMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $deleteMenuItem.Text = "Delete"
        $deleteMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::Delete
        
        $propertiesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $propertiesMenuItem.Text = "Properties"
        $propertiesMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::Alt -bor [System.Windows.Forms.Keys]::Enter
        
        $separator1 = New-Object System.Windows.Forms.ToolStripSeparator
        
        $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitMenuItem.Text = "Exit"
        $exitMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::Alt -bor [System.Windows.Forms.Keys]::F4
        
        $fileMenu.DropDownItems.AddRange(@($newFolderMenuItem, $deleteMenuItem, $propertiesMenuItem, $separator1, $exitMenuItem))
        
        # View menu
        $viewMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $viewMenu.Text = "View"
        
        $refreshMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $refreshMenuItem.Text = "Refresh"
        $refreshMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F5
        
        $viewMenu.DropDownItems.Add($refreshMenuItem) | Out-Null
        
        # Tools menu
        $toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $toolsMenu.Text = "Tools"
        
        $openCmdMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $openCmdMenuItem.Text = "Open Command Prompt Here"
        
        $openPowerShellMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $openPowerShellMenuItem.Text = "Open PowerShell Here"
        
        $toolsMenu.DropDownItems.AddRange(@($openCmdMenuItem, $openPowerShellMenuItem))
        
        $menuStrip.Items.AddRange(@($fileMenu, $viewMenu, $toolsMenu))
        $form.MainMenuStrip = $menuStrip
        $form.Controls.Add($menuStrip)
        
        # Create toolbar
        $toolStrip = New-Object System.Windows.Forms.ToolStrip
        $toolStrip.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        
        $backButton = New-Object System.Windows.Forms.ToolStripButton
        $backButton.Text = "Back"
        $backButton.DisplayStyle = [System.Windows.Forms.ToolStripItemDisplayStyle]::Text
        
        $upButton = New-Object System.Windows.Forms.ToolStripButton
        $upButton.Text = "Up"
        $upButton.DisplayStyle = [System.Windows.Forms.ToolStripItemDisplayStyle]::Text
        
        $separator2 = New-Object System.Windows.Forms.ToolStripSeparator
        
        $addressLabel = New-Object System.Windows.Forms.ToolStripLabel
        $addressLabel.Text = "Address:"
        
        $addressTextBox = New-Object System.Windows.Forms.ToolStripTextBox
        $addressTextBox.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 25 $scale))
        
        $goButton = New-Object System.Windows.Forms.ToolStripButton
        $goButton.Text = "Go"
        $goButton.DisplayStyle = [System.Windows.Forms.ToolStripItemDisplayStyle]::Text
        
        $toolStrip.Items.AddRange(@($backButton, $upButton, $separator2, $addressLabel, $addressTextBox, $goButton))
        $form.Controls.Add($toolStrip)
        
        # Create split container - adjusted to prevent toolbar clipping
        $splitContainer = New-Object System.Windows.Forms.SplitContainer
        $splitContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
        $splitContainer.SplitterDistance = Scale-UIElement 50 $scale  # Base 50 pixels scaled by screen size
        $splitContainer.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        
        # Set anchor to prevent toolbar overlap
        $splitContainer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $splitContainer.Location = New-Object System.Drawing.Point(0, (Scale-UIElement 75 $scale))  # Start below menu and toolbar
        $splitContainer.Size = New-Object System.Drawing.Size((Scale-UIElement 900 $scale), (Scale-UIElement 600 $scale))  # Adjust height

        # Left panel - Drive tree
        $driveTreeView = New-Object System.Windows.Forms.TreeView
        $driveTreeView.Dock = [System.Windows.Forms.DockStyle]::Fill
        $driveTreeView.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        $driveTreeView.ShowLines = $true
        $driveTreeView.ShowPlusMinus = $true
        $driveTreeView.ShowRootLines = $true
        
        $splitContainer.Panel1.Controls.Add($driveTreeView)
        
        # Right panel - File list
        $fileListView = New-Object System.Windows.Forms.ListView
        $fileListView.Dock = [System.Windows.Forms.DockStyle]::Fill
        $fileListView.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        $fileListView.View = [System.Windows.Forms.View]::Details
        $fileListView.FullRowSelect = $true
        $fileListView.GridLines = $true
        $fileListView.MultiSelect = $true
        
        # Add columns
        $fileListView.Columns.Add("Name", (Scale-UIElement 300 $scale)) | Out-Null
        $fileListView.Columns.Add("Type", (Scale-UIElement 100 $scale)) | Out-Null
        $fileListView.Columns.Add("Size", (Scale-UIElement 100 $scale)) | Out-Null
        $fileListView.Columns.Add("Modified", (Scale-UIElement 150 $scale)) | Out-Null
        
        # Create context menu for file list
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $contextMenu.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        
        # Open with Notepad
        $openNotepadMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $openNotepadMenuItem.Text = "Open with Notepad"
        
        # Open with default application
        $openDefaultMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $openDefaultMenuItem.Text = "Open"
        
        # Properties
        $contextPropertiesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $contextPropertiesMenuItem.Text = "Properties"
        
        # Separator
        $contextSeparator = New-Object System.Windows.Forms.ToolStripSeparator
        
        # New Folder
        $contextNewFolderMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $contextNewFolderMenuItem.Text = "New Folder"
        
        # Delete
        $contextDeleteMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $contextDeleteMenuItem.Text = "Delete"
        
        $contextMenu.Items.AddRange(@($openDefaultMenuItem, $openNotepadMenuItem, $contextSeparator, $contextNewFolderMenuItem, $contextDeleteMenuItem, $contextSeparator, $contextPropertiesMenuItem))
        $fileListView.ContextMenuStrip = $contextMenu
        
        $splitContainer.Panel2.Controls.Add($fileListView)
        $form.Controls.Add($splitContainer)
        
        # Status bar
        $statusStrip = New-Object System.Windows.Forms.StatusStrip
        $statusStrip.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", $scaledBaseFontSize)
        
        $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
        $statusLabel.Text = "Ready"
        $statusLabel.Spring = $true
        
        $itemCountLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
        $itemCountLabel.Text = "0 items"
        
        $statusStrip.Items.AddRange(@($statusLabel, $itemCountLabel))
        $form.Controls.Add($statusStrip)
        
        # Variables for navigation
        $script:currentPath = $StartPath
        $script:navigationHistory = New-Object System.Collections.ArrayList
        $script:historyIndex = -1
        
        # Populate drives in tree view
        function Populate-DriveTree {
            try {
                $driveTreeView.Nodes.Clear()
                
                # Add "This PC" root node
                $computerNode = New-Object System.Windows.Forms.TreeNode
                $computerNode.Text = "This PC"
                $computerNode.Tag = "Computer"
                $driveTreeView.Nodes.Add($computerNode) | Out-Null
                
                # Get all drives
                $drives = Get-PSDrive -PSProvider FileSystem | Sort-Object Name
                foreach ($drive in $drives) {
                    try {
                        $driveNode = New-Object System.Windows.Forms.TreeNode
                        $driveNode.Text = "$($drive.Name): ($($drive.Description))"
                        $driveNode.Tag = "$($drive.Name):\"
                        
                        # Add dummy node for expansion
                        $dummyNode = New-Object System.Windows.Forms.TreeNode
                        $dummyNode.Text = "Loading..."
                        $driveNode.Nodes.Add($dummyNode) | Out-Null
                        
                        $computerNode.Nodes.Add($driveNode) | Out-Null
                    } catch {
                        Write-LogMessage "Error adding drive $($drive.Name): $_" "WARNING"
                    }
                }
                
                $computerNode.Expand()
            } catch {
                Write-LogMessage "Error populating drive tree: $_" "ERROR"
            }
        }
        
        # Populate file list
        function Populate-FileList {
            param([string]$Path)
            
            try {
                $fileListView.Items.Clear()
                $statusLabel.Text = "Loading..."
                
                if (-not (Test-Path $Path)) {
                    $statusLabel.Text = "Path not found: $Path"
                    return
                }
                
                $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
                $itemCount = 0
                
                foreach ($item in $items) {
                    try {
                        $listViewItem = New-Object System.Windows.Forms.ListViewItem
                        $listViewItem.Text = $item.Name
                        $listViewItem.Tag = $item.FullName
                        
                        if ($item.PSIsContainer) {
                            $listViewItem.SubItems.Add("Folder") | Out-Null
                            $listViewItem.SubItems.Add("") | Out-Null
                        } else {
                            $extension = [System.IO.Path]::GetExtension($item.Name)
                            if ($extension) {
                                $listViewItem.SubItems.Add("$($extension.ToUpper()) File") | Out-Null
                            } else {
                                $listViewItem.SubItems.Add("File") | Out-Null
                            }
                            
                            if ($item.Length -lt 1KB) {
                                $listViewItem.SubItems.Add("$($item.Length) bytes") | Out-Null
                            } elseif ($item.Length -lt 1MB) {
                                $listViewItem.SubItems.Add("$([Math]::Round($item.Length / 1KB, 1)) KB") | Out-Null
                            } elseif ($item.Length -lt 1GB) {
                                $listViewItem.SubItems.Add("$([Math]::Round($item.Length / 1MB, 1)) MB") | Out-Null
                            } else {
                                $listViewItem.SubItems.Add("$([Math]::Round($item.Length / 1GB, 2)) GB") | Out-Null
                            }
                        }
                        
                        $listViewItem.SubItems.Add($item.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) | Out-Null
                        $fileListView.Items.Add($listViewItem) | Out-Null
                        $itemCount++
                    } catch {
                        Write-LogMessage "Error processing item $($item.Name): $_" "WARNING"
                    }
                }
                
                $itemCountLabel.Text = "$itemCount items"
                $statusLabel.Text = "Ready"
                $addressTextBox.Text = $Path
                $script:currentPath = $Path
                
            } catch {
                $statusLabel.Text = "Error loading path: $_"
                Write-LogMessage "Error populating file list for ${Path}: $_" "ERROR"
            }
        }
        
        # Navigate to path
        function Navigate-ToPath {
            param([string]$Path)
            
            if (Test-Path $Path) {
                # Add to history
                if ($script:historyIndex -eq -1 -or $script:navigationHistory[$script:historyIndex] -ne $Path) {
                    # Remove any forward history
                    for ($i = $script:navigationHistory.Count - 1; $i -gt $script:historyIndex; $i--) {
                        $script:navigationHistory.RemoveAt($i)
                    }
                    
                    $script:navigationHistory.Add($Path) | Out-Null
                    $script:historyIndex = $script:navigationHistory.Count - 1
                    
                    # Limit history size
                    if ($script:navigationHistory.Count -gt 50) {
                        $script:navigationHistory.RemoveAt(0)
                        $script:historyIndex--
                    }
                }
                
                Populate-FileList -Path $Path
                $backButton.Enabled = $script:historyIndex -gt 0
            }
        }
        
        # Event handlers
        
        # Back button
        $backButton.Add_Click({
            if ($script:historyIndex -gt 0) {
                $script:historyIndex--
                $previousPath = $script:navigationHistory[$script:historyIndex]
                Populate-FileList -Path $previousPath
                $backButton.Enabled = $script:historyIndex -gt 0
                Write-LogMessage "Navigated back to: $previousPath" "VERBOSE"
            }
        })
        
        # Up button
        $upButton.Add_Click({
            if ($script:currentPath) {
                $parentPath = Split-Path $script:currentPath -Parent
                if ($parentPath -and (Test-Path $parentPath)) {
                    Navigate-ToPath -Path $parentPath
                    Write-LogMessage "Navigated up to: $parentPath" "VERBOSE"
                }
            }
        })
        
        # Go button
        $goButton.Add_Click({
            $targetPath = $addressTextBox.Text
            if ($targetPath -and (Test-Path $targetPath)) {
                Navigate-ToPath -Path $targetPath
                Write-LogMessage "Navigated to address: $targetPath" "VERBOSE"
            } else {
                $statusLabel.Text = "Invalid path: $targetPath"
            }
        })
        
        # Address textbox enter key
        $addressTextBox.Add_KeyDown({
            param($sender, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                $goButton.PerformClick()
            }
        })
        
        # Tree view node expansion
        $driveTreeView.Add_BeforeExpand({
            param($sender, $e)
            
            $node = $e.Node
            if ($node.Nodes.Count -eq 1 -and $node.Nodes[0].Text -eq "Loading...") {
                $node.Nodes.Clear()
                
                try {
                    $path = $node.Tag
                    if ($path -and $path -ne "Computer") {
                        $subDirs = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
                        foreach ($subDir in $subDirs) {
                            $subNode = New-Object System.Windows.Forms.TreeNode
                            $subNode.Text = $subDir.Name
                            $subNode.Tag = $subDir.FullName
                            
                            # Check if subfolder has subdirectories
                            try {
                                $hasSubDirs = Get-ChildItem -Path $subDir.FullName -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
                                if ($hasSubDirs) {
                                    $dummyNode = New-Object System.Windows.Forms.TreeNode
                                    $dummyNode.Text = "Loading..."
                                    $subNode.Nodes.Add($dummyNode) | Out-Null
                                }
                            } catch {
                                # Ignore access errors
                            }
                            
                            $node.Nodes.Add($subNode) | Out-Null
                        }
                    }
                } catch {
                    Write-LogMessage "Error expanding node: $_" "WARNING"
                }
            }
        })
        
        # Tree view selection
        $driveTreeView.Add_AfterSelect({
            param($sender, $e)
            
            $selectedNode = $e.Node
            if ($selectedNode.Tag -and $selectedNode.Tag -ne "Computer") {
                Navigate-ToPath -Path $selectedNode.Tag
            }
        })
        
        # File list double-click
        $fileListView.Add_DoubleClick({
            if ($fileListView.SelectedItems.Count -eq 1) {
                $selectedItem = $fileListView.SelectedItems[0]
                $path = $selectedItem.Tag
                
                if (Test-Path $path -PathType Container) {
                    Navigate-ToPath -Path $path
                } else {
                    # Try to open file with default application
                    try {
                        Start-Process -FilePath $path -ErrorAction Stop
                    } catch {
                        $statusLabel.Text = "Cannot open file: $_"
                    }
                }
            }
        })
        
        # Context menu events
        $openDefaultMenuItem.Add_Click({
            if ($fileListView.SelectedItems.Count -eq 1) {
                $selectedItem = $fileListView.SelectedItems[0]
                $path = $selectedItem.Tag
                
                if (Test-Path $path -PathType Container) {
                    Navigate-ToPath -Path $path
                } else {
                    try {
                        Start-Process -FilePath $path -ErrorAction Stop
                    } catch {
                        $statusLabel.Text = "Cannot open file: $_"
                    }
                }
            }
        })
        
        $openNotepadMenuItem.Add_Click({
            if ($fileListView.SelectedItems.Count -eq 1) {
                $selectedItem = $fileListView.SelectedItems[0]
                $path = $selectedItem.Tag
                
                if (-not (Test-Path $path -PathType Container)) {
                    try {
                        # Check if notepad.exe exists
                        $notepadPath = Get-Command notepad.exe -ErrorAction SilentlyContinue
                        if ($notepadPath) {
                            Start-Process -FilePath "notepad.exe" -ArgumentList "`"$path`"" -ErrorAction Stop
                        } else {
                            $statusLabel.Text = "Notepad not found"
                        }
                    } catch {
                        $statusLabel.Text = "Cannot open file in Notepad: $_"
                    }
                }
            }
        })
        
        $contextNewFolderMenuItem.Add_Click({
            $newFolderMenuItem.PerformClick()
        })
        
        $contextDeleteMenuItem.Add_Click({
            $deleteMenuItem.PerformClick()
        })
        
        $contextPropertiesMenuItem.Add_Click({
            $propertiesMenuItem.PerformClick()
        })
        
        # Context menu opening event to enable/disable items based on selection
        $contextMenu.Add_Opening({
            param($sender, $e)
            
            $hasSelection = $fileListView.SelectedItems.Count -gt 0
            $singleFileSelected = $fileListView.SelectedItems.Count -eq 1 -and $fileListView.SelectedItems[0].Tag -and -not (Test-Path $fileListView.SelectedItems[0].Tag -PathType Container)
            $singleItemSelected = $fileListView.SelectedItems.Count -eq 1
            
            $openDefaultMenuItem.Enabled = $singleItemSelected
            $openNotepadMenuItem.Enabled = $singleFileSelected
            $contextDeleteMenuItem.Enabled = $hasSelection
            $contextPropertiesMenuItem.Enabled = $singleItemSelected
        })

        # Menu events
        $newFolderMenuItem.Add_Click({
            if ($script:currentPath) {
                Write-LogMessage "New folder menu clicked for path: $script:currentPath" "INFO"
                $folderName = Show-InputDialog -Title "New Folder" -Prompt "Enter folder name:" -DefaultValue "New Folder"
                if ($folderName) {
                    try {
                        # Ensure we have a clean string for the folder name
                        $cleanFolderName = $folderName.ToString().Trim()
                        $cleanCurrentPath = $script:currentPath.ToString().Trim()
                        
                        # Use string concatenation instead of Join-Path to avoid array issues
                        $newPath = if ($cleanCurrentPath.EndsWith('\')) {
                            "$cleanCurrentPath$cleanFolderName"
                        } else {
                            "$cleanCurrentPath\$cleanFolderName"
                        }
                        
                        Write-LogMessage "Creating new folder: $newPath" "INFO"
                        New-Item -Path $newPath -ItemType Directory -ErrorAction Stop
                        Write-LogMessage "Folder created successfully: $newPath" "SUCCESS"
                        
                        # Refresh the file list to show the new folder
                        Start-Sleep -Milliseconds 500  # Brief pause to ensure folder creation is complete
                        Populate-FileList -Path $script:currentPath
                        $statusLabel.Text = "Folder created: $cleanFolderName"
                    } catch {
                        Write-LogMessage "Error creating folder: $_" "ERROR"
                        $statusLabel.Text = "Error creating folder: $_"
                        [System.Windows.Forms.MessageBox]::Show("Error creating folder: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                } else {
                    Write-LogMessage "New folder creation cancelled or empty name provided" "INFO"
                }
            } else {
                Write-LogMessage "Cannot create folder: current path is null or empty" "WARNING"
                $statusLabel.Text = "Cannot create folder: no current path"
            }
        })
        
        $deleteMenuItem.Add_Click({
            if ($fileListView.SelectedItems.Count -gt 0) {
                $items = $fileListView.SelectedItems
                $message = if ($items.Count -eq 1) {
                    "Delete '$($items[0].Text)'?"
                } else {
                    "Delete $($items.Count) selected items?"
                }
                
                $result = [System.Windows.Forms.MessageBox]::Show($message, "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    foreach ($item in $items) {
                        try {
                            Remove-Item -Path $item.Tag -Recurse -Force -ErrorAction Stop
                        } catch {
                            $statusLabel.Text = "Error deleting $($item.Text): $_"
                        }
                    }
                    Populate-FileList -Path $script:currentPath
                }
            }
        })
        
        $refreshMenuItem.Add_Click({
            if ($script:currentPath) {
                Populate-FileList -Path $script:currentPath
            }
            Populate-DriveTree
        })
        
        $openCmdMenuItem.Add_Click({
            if ($script:currentPath) {
                try {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/k cd /d `"$script:currentPath`"" -ErrorAction Stop
                } catch {
                    $statusLabel.Text = "Error opening command prompt: $_"
                }
            }
        })
        
        $openPowerShellMenuItem.Add_Click({
            if ($script:currentPath) {
                try {
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "Set-Location -Path '$script:currentPath'" -ErrorAction Stop
                } catch {
                    $statusLabel.Text = "Error opening PowerShell: $_"
                }
            }
        })
        
        $exitMenuItem.Add_Click({
            $form.Close()
        })
        
        # Initialize
        Populate-DriveTree
        Navigate-ToPath -Path $StartPath
        
        # Show form
        $result = $form.ShowDialog()
        $form.Dispose()
        
        return $result
        
    } catch {
        Write-LogMessage "Error in WinPE File Explorer: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: $_", "WinPE File Explorer Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-InputDialog {
    [CmdletBinding()]
    param(
        [string]$Title = "Input",
        [string]$Prompt = "Enter value:",
        [string]$DefaultValue = ""
    )
    
    try {
        # Get scaling for the dialog
        $screenInfo = Get-ScreenResolution
        $scale = $screenInfo.ScaleFactor
        
        # Create input dialog
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = $Title
        $inputForm.Size = New-Object System.Drawing.Size((Scale-UIElement 350 $scale), (Scale-UIElement 150 $scale))
        $inputForm.StartPosition = "CenterParent"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false
        
        # Create prompt label
        $promptLabel = New-Object System.Windows.Forms.Label
        $promptLabel.Text = $Prompt
        $promptLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 20 $scale))
        $promptLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 300 $scale), (Scale-UIElement 20 $scale))
        $inputForm.Controls.Add($promptLabel)
        
        # Create text input
        $inputTextBox = New-Object System.Windows.Forms.TextBox
        $inputTextBox.Text = $DefaultValue
        $inputTextBox.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), (Scale-UIElement 45 $scale))
        $inputTextBox.Size = New-Object System.Drawing.Size((Scale-UIElement 300 $scale), (Scale-UIElement 25 $scale))
        $inputForm.Controls.Add($inputTextBox)
        
        # Create OK button
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point((Scale-UIElement 170 $scale), (Scale-UIElement 80 $scale))
        $okButton.Size = New-Object System.Drawing.Size((Scale-UIElement 70 $scale), (Scale-UIElement 25 $scale))
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $inputForm.Controls.Add($okButton)
        
        # Create Cancel button
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Location = New-Object System.Drawing.Point((Scale-UIElement 250 $scale), (Scale-UIElement 80 $scale))
        $cancelButton.Size = New-Object System.Drawing.Size((Scale-UIElement 70 $scale), (Scale-UIElement 25 $scale))
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $inputForm.Controls.Add($cancelButton)
        
        # Set default buttons
        $inputForm.AcceptButton = $okButton
        $inputForm.CancelButton = $cancelButton
        
        # Focus and select text
        $inputForm.Add_Shown({
            $inputTextBox.Focus()
            $inputTextBox.SelectAll()
        })
        
        # Show dialog
        $result = $inputForm.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($inputTextBox.Text)) {
            # Ensure we return a proper string, not an array
            $returnValue = [string]$inputTextBox.Text.Trim()
            Write-LogMessage "Input dialog returning: '$returnValue'" "VERBOSE"
            return $returnValue
        }
        
        Write-LogMessage "Input dialog cancelled or empty" "VERBOSE"
        return $null
    }
    catch {
        Write-LogMessage "Error in input dialog: $_" "ERROR"
        return $null
    }
    finally {
        if ($inputForm) {
            $inputForm.Dispose()
        }
    }
}

function Show-PropertiesDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        # Get scaling for the dialog
        $screenInfo = Get-ScreenResolution
        $scale = $screenInfo.ScaleFactor
        
        # Get item information
        if (-not (Test-Path $Path)) {
            [System.Windows.Forms.MessageBox]::Show("Path not found: $Path", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        
        $item = Get-Item $Path -ErrorAction SilentlyContinue
        if (-not $item) {
            [System.Windows.Forms.MessageBox]::Show("Cannot access item: $Path", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        
        # Create properties dialog
        $propsForm = New-Object System.Windows.Forms.Form
        $propsForm.Text = "Properties - $($item.Name)"
        $propsForm.Size = New-Object System.Drawing.Size((Scale-UIElement 400 $scale), (Scale-UIElement 500 $scale))
        $propsForm.StartPosition = "CenterParent"
        $propsForm.FormBorderStyle = "FixedDialog"
        $propsForm.MaximizeBox = $false
        $propsForm.MinimizeBox = $false
        
        # Create tab control for different property pages
        $tabControl = New-Object System.Windows.Forms.TabControl
        $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
        $tabControl.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)))
        
        # General tab
        $generalTab = New-Object System.Windows.Forms.TabPage
        $generalTab.Text = "General"
        
        # Create property labels and values
        $yPos = 20
        $labelHeight = Scale-UIElement 20 $scale
        $spacing = Scale-UIElement 25 $scale
        
        # Name
        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = "Name:"
        $nameLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $nameLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $nameLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($nameLabel)
        
        $nameValueLabel = New-Object System.Windows.Forms.Label
        $nameValueLabel.Text = $item.Name
        $nameValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $nameValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
        $generalTab.Controls.Add($nameValueLabel)
        
        $yPos += $spacing
        
        # Type
        $typeLabel = New-Object System.Windows.Forms.Label
        $typeLabel.Text = "Type:"
        $typeLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $typeLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $typeLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($typeLabel)
        
        $typeValue = if ($item.PSIsContainer) { "Folder" } else { "File" }
        if (-not $item.PSIsContainer -and $item.Extension) {
            $typeValue += " ($($item.Extension.ToUpper()))"
        }
        
        $typeValueLabel = New-Object System.Windows.Forms.Label
        $typeValueLabel.Text = $typeValue
        $typeValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $typeValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
        $generalTab.Controls.Add($typeValueLabel)
        
        $yPos += $spacing
        
        # Location
        $locationLabel = New-Object System.Windows.Forms.Label
        $locationLabel.Text = "Location:"
        $locationLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $locationLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $locationLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($locationLabel)
        
        $locationValueLabel = New-Object System.Windows.Forms.Label
        $locationValueLabel.Text = Split-Path $item.FullName -Parent
        $locationValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $locationValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight * 2)
        $generalTab.Controls.Add($locationValueLabel)
        
        $yPos += $spacing * 2
        
        # Size (for files)
        if (-not $item.PSIsContainer) {
            $sizeLabel = New-Object System.Windows.Forms.Label
            $sizeLabel.Text = "Size:"
            $sizeLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
            $sizeLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
            $sizeLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
            $generalTab.Controls.Add($sizeLabel)
            
            $sizeBytes = $item.Length
            $sizeText = "$sizeBytes bytes"
            if ($sizeBytes -gt 1GB) {
                $sizeText += " ($([Math]::Round($sizeBytes / 1GB, 2)) GB)"
            } elseif ($sizeBytes -gt 1MB) {
                $sizeText += " ($([Math]::Round($sizeBytes / 1MB, 2)) MB)"
            } elseif ($sizeBytes -gt 1KB) {
                $sizeText += " ($([Math]::Round($sizeBytes / 1KB, 1)) KB)"
            }
            
            $sizeValueLabel = New-Object System.Windows.Forms.Label
            $sizeValueLabel.Text = $sizeText
            $sizeValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
            $sizeValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
            $generalTab.Controls.Add($sizeValueLabel)
            
            $yPos += $spacing
        } else {
            # For folders, show item count
            try {
                $childItems = Get-ChildItem $Path -ErrorAction SilentlyContinue
                $itemCount = $childItems.Count
                $folderCount = ($childItems | Where-Object { $_.PSIsContainer }).Count
                $fileCount = $itemCount - $folderCount
                
                $contentsLabel = New-Object System.Windows.Forms.Label
                $contentsLabel.Text = "Contains:"
                $contentsLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
                $contentsLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
                $contentsLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
                $generalTab.Controls.Add($contentsLabel)
                
                $contentsText = "$fileCount file(s), $folderCount folder(s)"
                $contentsValueLabel = New-Object System.Windows.Forms.Label
                $contentsValueLabel.Text = $contentsText
                $contentsValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
                $contentsValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
                $generalTab.Controls.Add($contentsValueLabel)
                
                $yPos += $spacing
            } catch {
                # Ignore errors counting items
            }
        }
        
        # Created
        $createdLabel = New-Object System.Windows.Forms.Label
        $createdLabel.Text = "Created:"
        $createdLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $createdLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $createdLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($createdLabel)
        
        $createdValueLabel = New-Object System.Windows.Forms.Label
        $createdValueLabel.Text = $item.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
        $createdValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $createdValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
        $generalTab.Controls.Add($createdValueLabel)
        
        $yPos += $spacing
        
        # Modified
        $modifiedLabel = New-Object System.Windows.Forms.Label
        $modifiedLabel.Text = "Modified:"
        $modifiedLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $modifiedLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $modifiedLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($modifiedLabel)
        
        $modifiedValueLabel = New-Object System.Windows.Forms.Label
        $modifiedValueLabel.Text = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $modifiedValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $modifiedValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
        $generalTab.Controls.Add($modifiedValueLabel)
        
        $yPos += $spacing
        
        # Accessed
        $accessedLabel = New-Object System.Windows.Forms.Label
        $accessedLabel.Text = "Accessed:"
        $accessedLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $accessedLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $accessedLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($accessedLabel)
        
        $accessedValueLabel = New-Object System.Windows.Forms.Label
        $accessedValueLabel.Text = $item.LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss")
        $accessedValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $accessedValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight)
        $generalTab.Controls.Add($accessedValueLabel)
        
        $yPos += $spacing
        
        # Attributes
        $attributesLabel = New-Object System.Windows.Forms.Label
        $attributesLabel.Text = "Attributes:"
        $attributesLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", [Math]::Max(8, [int](9 * $scale)), [System.Drawing.FontStyle]::Bold)
        $attributesLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 20 $scale), $yPos)
        $attributesLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 80 $scale), $labelHeight)
        $generalTab.Controls.Add($attributesLabel)
        
        $attributesText = $item.Attributes.ToString() -replace ", ", "`n"
        $attributesValueLabel = New-Object System.Windows.Forms.Label
        $attributesValueLabel.Text = $attributesText
        $attributesValueLabel.Location = New-Object System.Drawing.Point((Scale-UIElement 110 $scale), $yPos)
        $attributesValueLabel.Size = New-Object System.Drawing.Size((Scale-UIElement 250 $scale), $labelHeight * 3)
        $generalTab.Controls.Add($attributesValueLabel)
        
        # Add general tab to tab control
        $tabControl.TabPages.Add($generalTab)
        
        # Add tab control to form
        $propsForm.Controls.Add($tabControl)
        
        # Add OK button
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point((Scale-UIElement 160 $scale), (Scale-UIElement 420 $scale))
        $okButton.Size = New-Object System.Drawing.Size((Scale-UIElement 75 $scale), (Scale-UIElement 30 $scale))
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $okButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
        $propsForm.Controls.Add($okButton)
        
        $propsForm.AcceptButton = $okButton
        
        # Show dialog
        $propsForm.ShowDialog() | Out-Null
        $propsForm.Dispose()
        
    } catch {
        Write-LogMessage "Error showing properties dialog: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error showing properties: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Export-ModuleMember -Function Show-WinPEFileExplorer
