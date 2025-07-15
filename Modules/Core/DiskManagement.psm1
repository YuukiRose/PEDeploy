# WinPE Disk Management Module
# Provides disk management functionality for WinPE environments where diskmgmt.msc is not available

# Import required modules
try {
    Import-Module "$PSScriptRoot\Logging.psm1" -Force -ErrorAction SilentlyContinue
} catch {
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        Write-Host "[$Level] $Message" -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"White"})
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-DiskManagement {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Starting WinPE Disk Management interface..." "INFO"
        
        # Get screen resolution for scaling
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        $scale = [Math]::Max(1.0, [Math]::Min(2.0, $screenWidth / 1920))
        
        # Create main form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "WinPE Disk Management"
        $form.Size = New-Object System.Drawing.Size([int](1000 * $scale), [int](700 * $scale))
        $form.StartPosition = "CenterScreen"
        $form.MinimizeBox = $true
        $form.MaximizeBox = $true
        $form.FormBorderStyle = "Sizable"
        
        # Create menu bar
        $menuStrip = New-Object System.Windows.Forms.MenuStrip
        
        # Action menu
        $actionMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $actionMenu.Text = "&Action"
        
        $refreshMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $refreshMenuItem.Text = "&Refresh"
        $refreshMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::F5
        
        $rescanMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $rescanMenuItem.Text = "Rescan &Disks"
        
        $separator1 = New-Object System.Windows.Forms.ToolStripSeparator
        
        $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $exitMenuItem.Text = "E&xit"
        $exitMenuItem.ShortcutKeys = [System.Windows.Forms.Keys]::Alt -bor [System.Windows.Forms.Keys]::F4
        
        $actionMenu.DropDownItems.AddRange(@($refreshMenuItem, $rescanMenuItem, $separator1, $exitMenuItem))
        
        # View menu
        $viewMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $viewMenu.Text = "&View"
        
        $topMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $topMenuItem.Text = "&Top"
        $topMenuItem.Checked = $true
        
        $bottomMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $bottomMenuItem.Text = "&Bottom"
        
        $viewMenu.DropDownItems.AddRange(@($topMenuItem, $bottomMenuItem))
        
        # Help menu
        $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $helpMenu.Text = "&Help"
        
        $aboutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $aboutMenuItem.Text = "&About"
        
        $helpMenu.DropDownItems.Add($aboutMenuItem) | Out-Null
        
        $menuStrip.Items.AddRange(@($actionMenu, $viewMenu, $helpMenu))
        $form.MainMenuStrip = $menuStrip
        $form.Controls.Add($menuStrip)
        
        # Create main split container
        $mainSplitter = New-Object System.Windows.Forms.SplitContainer
        $mainSplitter.Dock = [System.Windows.Forms.DockStyle]::Fill
        $mainSplitter.Orientation = [System.Windows.Forms.Orientation]::Horizontal
        $mainSplitter.SplitterDistance = [int](200 * $scale)
        
        # Top panel - Disk list
        $diskGroupBox = New-Object System.Windows.Forms.GroupBox
        $diskGroupBox.Text = "Physical Disks"
        $diskGroupBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        
        $diskListView = New-Object System.Windows.Forms.ListView
        $diskListView.Dock = [System.Windows.Forms.DockStyle]::Fill
        $diskListView.View = [System.Windows.Forms.View]::Details
        $diskListView.FullRowSelect = $true
        $diskListView.GridLines = $true
        $diskListView.MultiSelect = $false
        
        # Add disk columns
        $diskListView.Columns.Add("Disk", [int](60 * $scale)) | Out-Null
        $diskListView.Columns.Add("Status", [int](80 * $scale)) | Out-Null
        $diskListView.Columns.Add("Size", [int](80 * $scale)) | Out-Null
        $diskListView.Columns.Add("Free Space", [int](80 * $scale)) | Out-Null
        $diskListView.Columns.Add("Dyn", [int](40 * $scale)) | Out-Null
        $diskListView.Columns.Add("GPT", [int](40 * $scale)) | Out-Null
        $diskListView.Columns.Add("Interface", [int](80 * $scale)) | Out-Null
        $diskListView.Columns.Add("Path", [int](300 * $scale)) | Out-Null
        
        $diskGroupBox.Controls.Add($diskListView)
        $mainSplitter.Panel1.Controls.Add($diskGroupBox)
        
        # Bottom panel - Volume/Partition list
        $volumeGroupBox = New-Object System.Windows.Forms.GroupBox
        $volumeGroupBox.Text = "Volumes and Partitions"
        $volumeGroupBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        
        $volumeListView = New-Object System.Windows.Forms.ListView
        $volumeListView.Dock = [System.Windows.Forms.DockStyle]::Fill
        $volumeListView.View = [System.Windows.Forms.View]::Details
        $volumeListView.FullRowSelect = $true
        $volumeListView.GridLines = $true
        $volumeListView.MultiSelect = $false
        
        # Add volume columns
        $volumeListView.Columns.Add("Volume", [int](60 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Layout", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Type", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("File System", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Status", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Capacity", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Free Space", [int](80 * $scale)) | Out-Null
        $volumeListView.Columns.Add("% Free", [int](60 * $scale)) | Out-Null
        $volumeListView.Columns.Add("Label", [int](100 * $scale)) | Out-Null
        
        $volumeGroupBox.Controls.Add($volumeListView)
        $mainSplitter.Panel2.Controls.Add($volumeGroupBox)
        
        $form.Controls.Add($mainSplitter)
        
        # Status bar
        $statusStrip = New-Object System.Windows.Forms.StatusStrip
        $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
        $statusLabel.Text = "Ready"
        $statusLabel.Spring = $true
        $statusStrip.Items.Add($statusLabel) | Out-Null
        $form.Controls.Add($statusStrip)
        
        # Context menu for disks
        $diskContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        $initializeDiskMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $initializeDiskMenuItem.Text = "Initialize Disk..."
        
        $convertToGPTMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $convertToGPTMenuItem.Text = "Convert to GPT Disk..."
        
        $convertToMBRMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $convertToMBRMenuItem.Text = "Convert to MBR Disk..."
        
        $cleanDiskMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $cleanDiskMenuItem.Text = "Clean Disk..."
        
        $diskSeparator1 = New-Object System.Windows.Forms.ToolStripSeparator
        
        $diskPropertiesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $diskPropertiesMenuItem.Text = "Properties"
        
        $diskContextMenu.Items.AddRange(@($initializeDiskMenuItem, $convertToGPTMenuItem, $convertToMBRMenuItem, $cleanDiskMenuItem, $diskSeparator1, $diskPropertiesMenuItem))
        $diskListView.ContextMenuStrip = $diskContextMenu
        
        # Context menu for volumes
        $volumeContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        $newPartitionMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $newPartitionMenuItem.Text = "New Simple Volume..."
        
        $deleteVolumeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $deleteVolumeMenuItem.Text = "Delete Volume..."
        
        $formatVolumeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $formatVolumeMenuItem.Text = "Format..."
        
        $assignLetterMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $assignLetterMenuItem.Text = "Change Drive Letter..."
        
        $volumeSeparator1 = New-Object System.Windows.Forms.ToolStripSeparator
        
        $volumePropertiesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $volumePropertiesMenuItem.Text = "Properties"
        
        $volumeContextMenu.Items.AddRange(@($newPartitionMenuItem, $deleteVolumeMenuItem, $formatVolumeMenuItem, $assignLetterMenuItem, $volumeSeparator1, $volumePropertiesMenuItem))
        $volumeListView.ContextMenuStrip = $volumeContextMenu
        
        # Event handlers
        $refreshMenuItem.Add_Click({
            Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
        })
        
        $rescanMenuItem.Add_Click({
            Rescan-Disks -StatusLabel $statusLabel
            Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
        })
        
        $exitMenuItem.Add_Click({
            $form.Close()
        })
        
        $aboutMenuItem.Add_Click({
            Show-AboutDiskManagement
        })
        
        $diskListView.Add_SelectedIndexChanged({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Refresh-VolumeData -VolumeListView $volumeListView -DiskNumber $diskNumber -StatusLabel $statusLabel
            }
        })
        
        # Disk context menu events
        $initializeDiskMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Initialize-SelectedDisk -DiskNumber $diskNumber -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $convertToGPTMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Convert-DiskToGPT -DiskNumber $diskNumber -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $convertToMBRMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Convert-DiskToMBR -DiskNumber $diskNumber -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $cleanDiskMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Clean-SelectedDisk -DiskNumber $diskNumber -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $diskPropertiesMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                Show-DiskProperties -DiskNumber $diskNumber
            }
        })
        
        # Volume context menu events
        $newPartitionMenuItem.Add_Click({
            if ($diskListView.SelectedItems.Count -gt 0) {
                $selectedDisk = $diskListView.SelectedItems[0]
                $diskNumber = [int]$selectedDisk.Text.Replace("Disk ", "")
                New-SimpleVolume -DiskNumber $diskNumber -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $deleteVolumeMenuItem.Add_Click({
            if ($volumeListView.SelectedItems.Count -gt 0) {
                $selectedVolume = $volumeListView.SelectedItems[0]
                $volumeLetter = $selectedVolume.Text
                Delete-SelectedVolume -VolumeLetter $volumeLetter -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $formatVolumeMenuItem.Add_Click({
            if ($volumeListView.SelectedItems.Count -gt 0) {
                $selectedVolume = $volumeListView.SelectedItems[0]
                $volumeLetter = $selectedVolume.Text
                Format-SelectedVolume -VolumeLetter $volumeLetter -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $assignLetterMenuItem.Add_Click({
            if ($volumeListView.SelectedItems.Count -gt 0) {
                $selectedVolume = $volumeListView.SelectedItems[0]
                $volumeLetter = $selectedVolume.Text
                Change-DriveLetter -VolumeLetter $volumeLetter -StatusLabel $statusLabel
                Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
            }
        })
        
        $volumePropertiesMenuItem.Add_Click({
            if ($volumeListView.SelectedItems.Count -gt 0) {
                $selectedVolume = $volumeListView.SelectedItems[0]
                $volumeLetter = $selectedVolume.Text
                Show-VolumeProperties -VolumeLetter $volumeLetter
            }
        })
        
        # Initial data load
        Refresh-DiskData -DiskListView $diskListView -VolumeListView $volumeListView -StatusLabel $statusLabel
        
        # Show form
        $result = $form.ShowDialog()
        $form.Dispose()
        
        return $result
        
    } catch {
        Write-LogMessage "Error in WinPE Disk Management: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: $_", "Disk Management Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Refresh-DiskData {
    param(
        [System.Windows.Forms.ListView]$DiskListView,
        [System.Windows.Forms.ListView]$VolumeListView,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $StatusLabel.Text = "Refreshing disk data..."
        $DiskListView.Items.Clear()
        $VolumeListView.Items.Clear()
        
        # Get disk information using diskpart
        $diskInfo = Get-DiskInformation
        
        foreach ($disk in $diskInfo) {
            $item = New-Object System.Windows.Forms.ListViewItem("Disk $($disk.Number)")
            $item.SubItems.Add($disk.Status) | Out-Null
            $item.SubItems.Add($disk.Size) | Out-Null
            $item.SubItems.Add($disk.FreeSpace) | Out-Null
            $item.SubItems.Add($disk.Dynamic) | Out-Null
            $item.SubItems.Add($disk.GPT) | Out-Null
            $item.SubItems.Add($disk.Interface) | Out-Null
            $item.SubItems.Add($disk.Path) | Out-Null
            
            # Color coding
            if ($disk.Status -eq "Online") {
                $item.ForeColor = [System.Drawing.Color]::Black
            } elseif ($disk.Status -eq "Offline") {
                $item.ForeColor = [System.Drawing.Color]::Red
            } else {
                $item.ForeColor = [System.Drawing.Color]::Orange
            }
            
            $DiskListView.Items.Add($item) | Out-Null
        }
        
        # Get volume information
        $volumeInfo = Get-VolumeInformation
        
        foreach ($volume in $volumeInfo) {
            $item = New-Object System.Windows.Forms.ListViewItem($volume.Letter)
            $item.SubItems.Add($volume.Layout) | Out-Null
            $item.SubItems.Add($volume.Type) | Out-Null
            $item.SubItems.Add($volume.FileSystem) | Out-Null
            $item.SubItems.Add($volume.Status) | Out-Null
            $item.SubItems.Add($volume.Capacity) | Out-Null
            $item.SubItems.Add($volume.FreeSpace) | Out-Null
            $item.SubItems.Add($volume.PercentFree) | Out-Null
            $item.SubItems.Add($volume.Label) | Out-Null
            
            # Color coding
            if ($volume.Status -eq "Healthy") {
                $item.ForeColor = [System.Drawing.Color]::Black
            } else {
                $item.ForeColor = [System.Drawing.Color]::Red
            }
            
            $VolumeListView.Items.Add($item) | Out-Null
        }
        
        $StatusLabel.Text = "Ready - Found $($diskInfo.Count) disks, $($volumeInfo.Count) volumes"
        
    } catch {
        $StatusLabel.Text = "Error refreshing disk data: $_"
        Write-LogMessage "Error refreshing disk data: $_" "ERROR"
    }
}

function Refresh-VolumeData {
    param(
        [System.Windows.Forms.ListView]$VolumeListView,
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $StatusLabel.Text = "Loading partitions for Disk $DiskNumber..."
        $VolumeListView.Items.Clear()
        
        # Get partition information for selected disk
        $partitionInfo = Get-PartitionInformation -DiskNumber $DiskNumber
        
        foreach ($partition in $partitionInfo) {
            $item = New-Object System.Windows.Forms.ListViewItem($partition.Letter)
            $item.SubItems.Add($partition.Layout) | Out-Null
            $item.SubItems.Add($partition.Type) | Out-Null
            $item.SubItems.Add($partition.FileSystem) | Out-Null
            $item.SubItems.Add($partition.Status) | Out-Null
            $item.SubItems.Add($partition.Capacity) | Out-Null
            $item.SubItems.Add($partition.FreeSpace) | Out-Null
            $item.SubItems.Add($partition.PercentFree) | Out-Null
            $item.SubItems.Add($partition.Label) | Out-Null
            
            $VolumeListView.Items.Add($item) | Out-Null
        }
        
        $StatusLabel.Text = "Ready - Showing $($partitionInfo.Count) partitions for Disk $DiskNumber"
        
    } catch {
        $StatusLabel.Text = "Error loading partition data: $_"
        Write-LogMessage "Error loading partition data: $_" "ERROR"
    }
}

function Get-DiskInformation {
    [CmdletBinding()
    ]
    param()
    
    try {
        Write-LogMessage "Getting disk information via diskpart..." "VERBOSE"
        
        # Create diskpart script to list disks
        $diskpartScript = @"
list disk
exit
"@
        
        $scriptPath = "$env:TEMP\list_disks_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        # Execute diskpart
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        $diskInfo = @()
        
        foreach ($line in $diskpartOutput) {
            if ($line -match "Disk\s+(\d+)\s+(\w+)\s+(\d+\s+\w+)\s+(\d+\s+\w+|\d+\s+\w+)\s*(.*)") {
                $diskNumber = [int]$Matches[1]
                $status = $Matches[2]
                $size = $Matches[3]
                $freeSpace = $Matches[4]
                $info = if ($Matches[5]) { $Matches[5] } else { "" }
                
                # Get more detailed info for this disk
                $detailScript = @"
select disk $diskNumber
detail disk
exit
"@
                
                $detailScriptPath = "$env:TEMP\detail_disk_$diskNumber`_$(Get-Random).txt"
                $detailScript | Out-File -FilePath $detailScriptPath -Encoding ASCII -Force
                
                $detailOutput = & diskpart.exe /s $detailScriptPath 2>&1
                Remove-Item $detailScriptPath -Force -ErrorAction SilentlyContinue
                
                # Parse detail output
                $isDynamic = ($detailOutput | Where-Object { $_ -match "Dynamic" }) -ne $null
                $isGPT = ($detailOutput | Where-Object { $_ -match "GPT" }) -ne $null
                $interface = "Unknown"
                $path = ""
                
                foreach ($detailLine in $detailOutput) {
                    if ($detailLine -match "Type\s*:\s*(.+)") {
                        $interface = $Matches[1].Trim()
                    }
                    if ($detailLine -match "Device ID\s*:\s*(.+)") {
                        $path = $Matches[1].Trim()
                    }
                }
                
                $diskInfo += @{
                    Number = $diskNumber
                    Status = $status
                    Size = $size
                    FreeSpace = $freeSpace
                    Dynamic = if ($isDynamic) { "Yes" } else { "No" }
                    GPT = if ($isGPT) { "Yes" } else { "No" }
                    Interface = $interface
                    Path = $path
                }
            }
        }
        
        Write-LogMessage "Found $($diskInfo.Count) disks" "INFO"
        return $diskInfo
        
    } catch {
        Write-LogMessage "Error getting disk information: $_" "ERROR"
        return @()
    }
}

function Get-VolumeInformation {
    [CmdletBinding()
    ]
    param()
    
    try {
        Write-LogMessage "Getting volume information..." "VERBOSE"
        
        # Use Get-Volume if available, otherwise use diskpart
        $volumeInfo = @()
        
        try {
            # Try PowerShell cmdlets first
            $volumes = Get-Volume -ErrorAction SilentlyContinue
            
            foreach ($volume in $volumes) {
                $letter = if ($volume.DriveLetter) { "$($volume.DriveLetter):" } else { "No Letter" }
                $sizeGB = if ($volume.Size) { [Math]::Round($volume.Size / 1GB, 2) } else { 0 }
                $freeGB = if ($volume.SizeRemaining) { [Math]::Round($volume.SizeRemaining / 1GB, 2) } else { 0 }
                $percentFree = if ($volume.Size -gt 0) { [Math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1) } else { 0 }
                
                $volumeInfo += @{
                    Letter = $letter
                    Layout = "Simple"
                    Type = "Basic"
                    FileSystem = if ($volume.FileSystem) { $volume.FileSystem } else { "Unknown" }
                    Status = if ($volume.HealthStatus) { $volume.HealthStatus } else { "Unknown" }
                    Capacity = "$sizeGB GB"
                    FreeSpace = "$freeGB GB"
                    PercentFree = "$percentFree%"
                    Label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "" }
                }
            }
        } catch {
            Write-LogMessage "PowerShell cmdlets not available, using diskpart..." "VERBOSE"
            
            # Fallback to diskpart
            $diskpartScript = @"
list volume
exit
"@
            
            $scriptPath = "$env:TEMP\list_volumes_$(Get-Random).txt"
            $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
            
            $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
            Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
            
            foreach ($line in $diskpartOutput) {
                if ($line -match "Volume\s+\d+\s+(\w*)\s+([A-Z]|\-)\s+([^\s]+)\s+([^\s]+)\s+(\d+\s+\w+)\s+([^\s]+)\s*(.*)") {
                    $volumeInfo += @{
                        Letter = if ($Matches[2] -ne "-") { "$($Matches[2]):" } else { "No Letter" }
                        Layout = "Simple"
                        Type = "Basic"
                        FileSystem = $Matches[4]
                        Status = $Matches[6]
                        Capacity = $Matches[5]
                        FreeSpace = "Unknown"
                        PercentFree = "Unknown"
                        Label = if ($Matches[1]) { $Matches[1] } else { "" }
                    }
                }
            }
        }
        
        Write-LogMessage "Found $($volumeInfo.Count) volumes" "INFO"
        return $volumeInfo
        
    } catch {
        Write-LogMessage "Error getting volume information: $_" "ERROR"
        return @()
    }
}

function Get-PartitionInformation {
    [CmdletBinding()
    ]
    param(
        [Parameter(Mandatory)]
        [int]$DiskNumber
    )
    
    try {
        Write-LogMessage "Getting partition information for Disk $DiskNumber..." "VERBOSE"
        
        $diskpartScript = @"
select disk $DiskNumber
list partition
exit
"@
        
        $scriptPath = "$env:TEMP\list_partitions_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        $partitionInfo = @()
        
        foreach ($line in $diskpartOutput) {
            if ($line -match "Partition\s+(\d+)\s+([^\s]+)\s+(\d+\s+\w+)\s+(\d+\s+\w+)") {
                $partitionNumber = [int]$Matches[1]
                $type = $Matches[2]
                $size = $Matches[3]
                $offset = $Matches[4]
                
                # Try to get more details about this partition
                $letter = "No Letter"
                $fileSystem = "Unknown"
                $label = ""
                
                # Check if this partition has a drive letter
                try {
                    $volumeScript = @"
select disk $DiskNumber
select partition $partitionNumber
detail partition
exit
"@
                    
                    $volumeScriptPath = "$env:TEMP\detail_partition_$DiskNumber`_$partitionNumber`_$(Get-Random).txt"
                    $volumeScript | Out-File -FilePath $volumeScriptPath -Encoding ASCII -Force
                    
                    $volumeOutput = & diskpart.exe /s $volumeScriptPath 2>&1
                    Remove-Item $volumeScriptPath -Force -ErrorAction SilentlyContinue
                    
                    foreach ($volumeLine in $volumeOutput) {
                        if ($volumeLine -match "Volume\s+\d+\s+([A-Z])\s") {
                            $letter = "$($Matches[1]):"
                        }
                    }
                } catch {
                    # Ignore errors
                }
                
                $partitionInfo += @{
                    Letter = $letter
                    Layout = "Simple"
                    Type = $type
                    FileSystem = $fileSystem
                    Status = "Healthy"
                    Capacity = $size
                    FreeSpace = "Unknown"
                    PercentFree = "Unknown"
                    Label = $label
                }
            }
        }
        
        Write-LogMessage "Found $($partitionInfo.Count) partitions on Disk $DiskNumber" "INFO"
        return $partitionInfo
        
    } catch {
        Write-LogMessage "Error getting partition information: $_" "ERROR"
        return @()
    }
}

function Rescan-Disks {
    param(
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $StatusLabel.Text = "Rescanning disks..."
        
        $diskpartScript = @"
rescan
exit
"@
        
        $scriptPath = "$env:TEMP\rescan_disks_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Disk rescan completed" "INFO"
        $StatusLabel.Text = "Disk rescan completed"
        
        # Wait a moment for the rescan to settle
        Start-Sleep -Seconds 2
        
    } catch {
        Write-LogMessage "Error rescanning disks: $_" "ERROR"
        $StatusLabel.Text = "Error rescanning disks: $_"
    }
}

function Initialize-SelectedDisk {
    param(
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will initialize Disk $DiskNumber and erase all data. Continue?",
            "Initialize Disk",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Initializing Disk $DiskNumber..."
        
        $diskpartScript = @"
select disk $DiskNumber
clean
convert gpt
exit
"@
        
        $scriptPath = "$env:TEMP\init_disk_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Disk $DiskNumber initialized" "SUCCESS"
        $StatusLabel.Text = "Disk $DiskNumber initialized successfully"
        
    } catch {
        Write-LogMessage "Error initializing disk: $_" "ERROR"
        $StatusLabel.Text = "Error initializing disk: $_"
        [System.Windows.Forms.MessageBox]::Show("Error initializing disk: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Convert-DiskToGPT {
    param(
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will convert Disk $DiskNumber to GPT and erase all data. Continue?",
            "Convert to GPT",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Converting Disk $DiskNumber to GPT..."
        
        $diskpartScript = @"
select disk $DiskNumber
clean
convert gpt
exit
"@
        
        $scriptPath = "$env:TEMP\convert_gpt_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Disk $DiskNumber converted to GPT" "SUCCESS"
        $StatusLabel.Text = "Disk $DiskNumber converted to GPT successfully"
        
    } catch {
        Write-LogMessage "Error converting disk to GPT: $_" "ERROR"
        $StatusLabel.Text = "Error converting disk to GPT: $_"
        [System.Windows.Forms.MessageBox]::Show("Error converting disk: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Convert-DiskToMBR {
    param(
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will convert Disk $DiskNumber to MBR and erase all data. Continue?",
            "Convert to MBR",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Converting Disk $DiskNumber to MBR..."
        
        $diskpartScript = @"
select disk $DiskNumber
clean
convert mbr
exit
"@
        
        $scriptPath = "$env:TEMP\convert_mbr_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Disk $DiskNumber converted to MBR" "SUCCESS"
        $StatusLabel.Text = "Disk $DiskNumber converted to MBR successfully"
        
    } catch {
        Write-LogMessage "Error converting disk to MBR: $_" "ERROR"
        $StatusLabel.Text = "Error converting disk to MBR: $_"
        [System.Windows.Forms.MessageBox]::Show("Error converting disk: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Clean-SelectedDisk {
    param(
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will clean Disk $DiskNumber and erase ALL data. This action cannot be undone. Continue?",
            "Clean Disk",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Cleaning Disk $DiskNumber..."
        
        $diskpartScript = @"
select disk $DiskNumber
clean
exit
"@
        
        $scriptPath = "$env:TEMP\clean_disk_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Disk $DiskNumber cleaned" "SUCCESS"
        $StatusLabel.Text = "Disk $DiskNumber cleaned successfully"
        
    } catch {
        Write-LogMessage "Error cleaning disk: $_" "ERROR"
        $StatusLabel.Text = "Error cleaning disk: $_"
        [System.Windows.Forms.MessageBox]::Show("Error cleaning disk: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function New-SimpleVolume {
    param(
        [int]$DiskNumber,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        # Show dialog to get volume size and drive letter
        $volumeDialog = New-Object System.Windows.Forms.Form
        $volumeDialog.Text = "Create Simple Volume"
        $volumeDialog.Size = New-Object System.Drawing.Size(400, 200)
        $volumeDialog.StartPosition = "CenterParent"
        $volumeDialog.FormBorderStyle = "FixedDialog"
        $volumeDialog.MaximizeBox = $false
        $volumeDialog.MinimizeBox = $false
        
        $sizeLabel = New-Object System.Windows.Forms.Label
        $sizeLabel.Text = "Size (MB):"
        $sizeLabel.Location = New-Object System.Drawing.Point(20, 30)
        $sizeLabel.Size = New-Object System.Drawing.Size(80, 20)
        $volumeDialog.Controls.Add($sizeLabel)
        
        $sizeTextBox = New-Object System.Windows.Forms.TextBox
        $sizeTextBox.Text = "1024"
        $sizeTextBox.Location = New-Object System.Drawing.Point(110, 30)
        $sizeTextBox.Size = New-Object System.Drawing.Size(100, 20)
        $volumeDialog.Controls.Add($sizeTextBox)
        
        $letterLabel = New-Object System.Windows.Forms.Label
        $letterLabel.Text = "Drive Letter:"
        $letterLabel.Location = New-Object System.Drawing.Point(20, 60)
        $letterLabel.Size = New-Object System.Drawing.Size(80, 20)
        $volumeDialog.Controls.Add($letterLabel)
        
        $letterComboBox = New-Object System.Windows.Forms.ComboBox
        $letterComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        
        # Add available drive letters
        $usedLetters = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
        for ($i = 68; $i -le 90; $i++) {  # D through Z
            $letter = [char]$i
            if ($letter -notin $usedLetters) {
                $letterComboBox.Items.Add($letter) | Out-Null
            }
        }
        
        if ($letterComboBox.Items.Count -gt 0) {
            $letterComboBox.SelectedIndex = 0
        }
        
        $letterComboBox.Location = New-Object System.Drawing.Point(110, 60)
        $letterComboBox.Size = New-Object System.Drawing.Size(50, 20)
        $volumeDialog.Controls.Add($letterComboBox)
        
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(200, 120)
        $okButton.Size = New-Object System.Drawing.Size(75, 25)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $volumeDialog.Controls.Add($okButton)
        
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Location = New-Object System.Drawing.Point(285, 120)
        $cancelButton.Size = New-Object System.Drawing.Size(75, 25)
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $volumeDialog.Controls.Add($cancelButton)
        
        $volumeDialog.AcceptButton = $okButton
        $volumeDialog.CancelButton = $cancelButton
        
        $result = $volumeDialog.ShowDialog()
        $volumeDialog.Dispose()
        
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $size = $sizeTextBox.Text
        $driveLetter = $letterComboBox.SelectedItem
        
        if (-not $size -or -not $driveLetter) {
            [System.Windows.Forms.MessageBox]::Show("Please enter size and select drive letter", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $StatusLabel.Text = "Creating volume on Disk $DiskNumber..."
        
        $diskpartScript = @"
select disk $DiskNumber
create partition primary size=$size
format quick fs=ntfs
assign letter=$driveLetter
exit
"@
        
        $scriptPath = "$env:TEMP\create_volume_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Volume ${driveLetter}: created on Disk $DiskNumber" "SUCCESS"
        $StatusLabel.Text = "Volume ${driveLetter}: created successfully"
        
    } catch {
        Write-LogMessage "Error creating volume: $_" "ERROR"
        $StatusLabel.Text = "Error creating volume: $_"
        [System.Windows.Forms.MessageBox]::Show("Error creating volume: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Delete-SelectedVolume {
    param(
        [string]$VolumeLetter,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        if ($VolumeLetter -eq "No Letter") {
            [System.Windows.Forms.MessageBox]::Show("Cannot delete volume without drive letter", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will delete volume $VolumeLetter and erase all data. Continue?",
            "Delete Volume",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Deleting volume $VolumeLetter..."
        
        $diskpartScript = @"
select volume $($VolumeLetter.Replace(':', ''))
delete volume
exit
"@
        
        $scriptPath = "$env:TEMP\delete_volume_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Volume $VolumeLetter deleted" "SUCCESS"
        $StatusLabel.Text = "Volume $VolumeLetter deleted successfully"
        
    } catch {
        Write-LogMessage "Error deleting volume: $_" "ERROR"
        $StatusLabel.Text = "Error deleting volume: $_"
        [System.Windows.Forms.MessageBox]::Show("Error deleting volume: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Format-SelectedVolume {
    param(
        [string]$VolumeLetter,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        if ($VolumeLetter -eq "No Letter") {
            [System.Windows.Forms.MessageBox]::Show("Cannot format volume without drive letter", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            "This will format volume $VolumeLetter and erase all data. Continue?",
            "Format Volume",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $StatusLabel.Text = "Formatting volume $VolumeLetter..."
        
        $diskpartScript = @"
select volume $($VolumeLetter.Replace(':', ''))
format quick fs=ntfs
exit
"@
        
        $scriptPath = "$env:TEMP\format_volume_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Volume $VolumeLetter formatted" "SUCCESS"
        $StatusLabel.Text = "Volume $VolumeLetter formatted successfully"
        
    } catch {
        Write-LogMessage "Error formatting volume: $_" "ERROR"
        $StatusLabel.Text = "Error formatting volume: $_"
        [System.Windows.Forms.MessageBox]::Show("Error formatting volume: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Change-DriveLetter {
    param(
        [string]$VolumeLetter,
        [System.Windows.Forms.ToolStripStatusLabel]$StatusLabel
    )
    
    try {
        # Show dialog to select new drive letter
        $letterDialog = New-Object System.Windows.Forms.Form
        $letterDialog.Text = "Change Drive Letter"
        $letterDialog.Size = New-Object System.Drawing.Size(300, 150)
        $letterDialog.StartPosition = "CenterParent"
        $letterDialog.FormBorderStyle = "FixedDialog"
        $letterDialog.MaximizeBox = $false
        $letterDialog.MinimizeBox = $false
        
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "New Drive Letter:"
        $label.Location = New-Object System.Drawing.Point(20, 30)
        $label.Size = New-Object System.Drawing.Size(100, 20)
        $letterDialog.Controls.Add($label)
        
        $letterComboBox = New-Object System.Windows.Forms.ComboBox
        $letterComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        
        # Add available drive letters
        $usedLetters = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
        for ($i = 68; $i -le 90; $i++) {  # D through Z
            $letter = [char]$i
            if ($letter -notin $usedLetters) {
                $letterComboBox.Items.Add($letter) | Out-Null
            }
        }
        
        if ($letterComboBox.Items.Count -gt 0) {
            $letterComboBox.SelectedIndex = 0
        }
        
        $letterComboBox.Location = New-Object System.Drawing.Point(130, 30)
        $letterComboBox.Size = New-Object System.Drawing.Size(50, 20)
        $letterDialog.Controls.Add($letterComboBox)
        
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(120, 70)
        $okButton.Size = New-Object System.Drawing.Size(75, 25)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $letterDialog.Controls.Add($okButton)
        
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Text = "Cancel"
        $cancelButton.Location = New-Object System.Drawing.Point(205, 70)
        $cancelButton.Size = New-Object System.Drawing.Size(75, 25)
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $letterDialog.Controls.Add($cancelButton)
        
        $letterDialog.AcceptButton = $okButton
        $letterDialog.CancelButton = $cancelButton
        
        $result = $letterDialog.ShowDialog()
        $letterDialog.Dispose()
        
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        
        $newLetter = $letterComboBox.SelectedItem
        
        if (-not $newLetter) {
            [System.Windows.Forms.MessageBox]::Show("Please select a drive letter", "Invalid Input", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $StatusLabel.Text = "Changing drive letter..."
        
        $diskpartScript = @"
select volume $($VolumeLetter.Replace(':', ''))
assign letter=$newLetter
exit
"@
        
        $scriptPath = "$env:TEMP\change_letter_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        Write-LogMessage "Drive letter changed from $VolumeLetter to ${newLetter}:" "SUCCESS"
        $StatusLabel.Text = "Drive letter changed successfully"
        
    } catch {
        Write-LogMessage "Error changing drive letter: $_" "ERROR"
        $StatusLabel.Text = "Error changing drive letter: $_"
        [System.Windows.Forms.MessageBox]::Show("Error changing drive letter: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-DiskProperties {
    param([int]$DiskNumber)
    
    try {
        # Get detailed disk information
        $diskpartScript = @"
select disk $DiskNumber
detail disk
exit
"@
        
        $scriptPath = "$env:TEMP\disk_properties_$DiskNumber`_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        $properties = $diskpartOutput -join "`r`n"
        
        # Show properties dialog
        $propsForm = New-Object System.Windows.Forms.Form
        $propsForm.Text = "Disk $DiskNumber Properties"
        $propsForm.Size = New-Object System.Drawing.Size(600, 400)
        $propsForm.StartPosition = "CenterParent"
        
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Text = $properties
        $textBox.Multiline = $true
        $textBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
        $textBox.ReadOnly = $true
        $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
        
        $propsForm.Controls.Add($textBox)
        $propsForm.ShowDialog() | Out-Null
        $propsForm.Dispose()
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error showing disk properties: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-VolumeProperties {
    param([string]$VolumeLetter)
    
    try {
        if ($VolumeLetter -eq "No Letter") {
            [System.Windows.Forms.MessageBox]::Show("Cannot show properties for volume without drive letter", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # Get detailed volume information
        $diskpartScript = @"
select volume $($VolumeLetter.Replace(':', ''))
detail volume
exit
"@
        
        $scriptPath = "$env:TEMP\volume_properties_$(Get-Random).txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        
        $diskpartOutput = & diskpart.exe /s $scriptPath 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        $properties = $diskpartOutput -join "`r`n"
        
        # Show properties dialog
        $propsForm = New-Object System.Windows.Forms.Form
        $propsForm.Text = "Volume $VolumeLetter Properties"
        $propsForm.Size = New-Object System.Drawing.Size(600, 400)
        $propsForm.StartPosition = "CenterParent"
        
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Text = $properties
        $textBox.Multiline = $true
        $textBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
        $textBox.ReadOnly = $true
        $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
        
        $propsForm.Controls.Add($textBox)
        $propsForm.ShowDialog() | Out-Null
        $propsForm.Dispose()
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error showing volume properties: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Show-AboutDiskManagement {
    try {
        $aboutForm = New-Object System.Windows.Forms.Form
        $aboutForm.Text = "About WinPE Disk Management"
        $aboutForm.Size = New-Object System.Drawing.Size(450, 300)
        $aboutForm.StartPosition = "CenterParent"
        $aboutForm.FormBorderStyle = "FixedDialog"
        $aboutForm.MaximizeBox = $false
        $aboutForm.MinimizeBox = $false
        
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = "WinPE Disk Management"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
        $titleLabel.Size = New-Object System.Drawing.Size(400, 30)
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $aboutForm.Controls.Add($titleLabel)
        
        $versionLabel = New-Object System.Windows.Forms.Label
        $versionLabel.Text = "Version 1.0"
        $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $versionLabel.Location = New-Object System.Drawing.Point(20, 60)
        $versionLabel.Size = New-Object System.Drawing.Size(400, 20)
        $versionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $aboutForm.Controls.Add($versionLabel)
        
        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = @"
Disk management tool for WinPE environments.

Features:
• View disk and volume information
• Initialize and partition disks
• Create and delete volumes
• Format volumes
• Change drive letters
• Convert between GPT and MBR

Built with PowerShell and Windows Forms
"@
        $descriptionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $descriptionLabel.Location = New-Object System.Drawing.Point(20, 100)
        $descriptionLabel.Size = New-Object System.Drawing.Size(400, 120)
        $aboutForm.Controls.Add($descriptionLabel)
        
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(175, 230)
        $okButton.Size = New-Object System.Drawing.Size(75, 30)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $aboutForm.Controls.Add($okButton)
        
        $aboutForm.AcceptButton = $okButton
        $aboutForm.ShowDialog() | Out-Null
        $aboutForm.Dispose()
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error displaying about dialog: $_", "About Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Export-ModuleMember -Function Show-DiskManagement
