# Import required modules
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import Logging module in DriverHarvesting: $_" -ForegroundColor Red
    # Provide fallback logging function
    function Write-LogMessage {
        param([string]$Message, [string]$Level = "INFO")
        Write-Host "[$Level] $Message" -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}elseif($Level -eq "SUCCESS"){"Green"}else{"White"})
    }
}

function Clean-DeviceName {
    param(
        [string]$Name
    )
    
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "Unknown"
    }
    
    # Replace spaces with underscores and remove all punctuation except underscores, periods, and hyphens
    $cleaned = $Name -replace '\s+', '_'  # Replace one or more spaces with single underscore
    $cleaned = $cleaned -replace '[^\w\-\.]', ''  # Remove all characters except word chars, hyphens, and periods
    $cleaned = $cleaned -replace '_+', '_'  # Replace multiple underscores with single underscore
    $cleaned = $cleaned.Trim('_')  # Remove leading/trailing underscores
    
    return $cleaned
}

function Export-SystemDrivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo,
        
        [Parameter()]
        [ValidateSet("Auto", "Live", "Offline", "Drive")]
        [string]$SourceType = "Auto"
    )
    
    try {
        Write-LogMessage "=== Starting Driver Export ===" "INFO"
        Write-LogMessage "Output Path: $OutputPath" "INFO"
        Write-LogMessage "Source Type: $SourceType" "INFO"
        Write-LogMessage "Device: $($DeviceInfo.Manufacturer) $($DeviceInfo.Model)" "INFO"
        

        # Create output directory
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created output directory: $OutputPath" "INFO"
        }
        
        # Create metadata file
        $metadataPath = Join-Path $OutputPath "DeviceInfo.json"
        $DeviceInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Force
        Write-LogMessage "Saved device metadata to: $metadataPath" "INFO"
        
        # Create logs directory
        $logDirectory = Join-Path $OutputPath "Logs"
        if (-not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        
        $driverLogPath = Join-Path $logDirectory "DriverExport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        "Driver Export Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content $driverLogPath
        "Device: $($DeviceInfo.Manufacturer) $($DeviceInfo.Model)" | Add-Content $driverLogPath
        "Serial Number: $($DeviceInfo.SerialNumber)" | Add-Content $driverLogPath
        "------------------------------------------------------" | Add-Content $driverLogPath
        
        # Determine source type automatically if requested
        if ($SourceType -eq "Auto") {
            $SourceType = Determine-OptimalSourceType -DeviceInfo $DeviceInfo -LogPath $driverLogPath
            Write-LogMessage "Auto-determined source type: $SourceType" "INFO"
        }
        
        # Export drivers based on source type
        $driverCount = 0
        
        switch ($SourceType) {
            "Live" {
                Write-LogMessage "Exporting drivers from live system..." "INFO"
                $driverCount = Export-LiveSystemDrivers -OutputPath $OutputPath -LogPath $driverLogPath
            }
            "Offline" {
                Write-LogMessage "Exporting drivers from offline system..." "INFO"
                $driverCount = Export-OfflineSystemDrivers -OutputPath $OutputPath -LogPath $driverLogPath -DeviceInfo $DeviceInfo
            }
            "Drive" {
                Write-LogMessage "Exporting drivers from specific drive..." "INFO"
                $driverCount = Export-DriveDrivers -OutputPath $OutputPath -LogPath $driverLogPath
            }
        }
        
        # Create summary report
        Create-DriverSummary -OutputPath $OutputPath -DriverCount $driverCount -DeviceInfo $DeviceInfo
        
        Write-LogMessage "Driver export completed successfully" "SUCCESS"
        Write-LogMessage "Exported $driverCount driver packages" "INFO"
        
        return @{
            Success = $true
            DriverCount = $driverCount
            OutputPath = $OutputPath
            LogPath = $driverLogPath
            SourceType = $SourceType
        }
    }
    catch {
        Write-LogMessage "Driver export failed: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
            Error = $_
        }
    }
}

function Determine-OptimalSourceType {
    param(
        [hashtable]$DeviceInfo,
        [string]$LogPath
    )
    
    try {
        # Check if drivers exist in V: drive structure
        $deviceMake = Clean-DeviceName -Name $DeviceInfo.Manufacturer
        $deviceModel = Clean-DeviceName -Name $DeviceInfo.Model
        $vDrivePath = "V:\$deviceMake\$deviceModel"
        
        "Checking for existing drivers at: $vDrivePath" | Add-Content $LogPath
        
        # Check if V: drive is available first
        if (Test-Path "V:\") {
            if (Test-Path $vDrivePath) {
                $driverFiles = Get-ChildItem -Path $vDrivePath -Recurse -Include "*.inf", "*.sys", "*.cat" -ErrorAction SilentlyContinue
                if ($driverFiles.Count -gt 0) {
                    "Found $($driverFiles.Count) driver files in V: drive structure. Using Live export." | Add-Content $LogPath
                    Write-LogMessage "Device drivers found in V:\$deviceMake\$deviceModel - using Live export" "INFO"
                    return "Live"
                }
            }
        } else {
            "V: drive not available - skipping V: drive check" | Add-Content $LogPath
            Write-LogMessage "V: drive not available for driver check" "WARNING"
        }
        
        "No drivers found in V: drive structure. Checking for Windows partitions..." | Add-Content $LogPath
        Write-LogMessage "Device drivers not found in V:\$deviceMake\$deviceModel - checking for offline harvest" "INFO"
        
        # Check all physical drives for Windows partitions
        $windowsPartitions = Find-AllWindowsPartitions
        
        if ($windowsPartitions.Count -gt 0) {
            "Found $($windowsPartitions.Count) Windows partition(s). Using Offline export." | Add-Content $LogPath
            foreach ($partition in $windowsPartitions) {
                "Windows partition found: $($partition.DriveLetter) ($($partition.WindowsVersion))" | Add-Content $LogPath
            }
            Write-LogMessage "Found Windows partitions on system - using Offline export" "INFO"
            return "Offline"
        }
        
        "No Windows partitions found. Falling back to Live export." | Add-Content $LogPath
        Write-LogMessage "No Windows partitions found - falling back to Live export" "WARNING"
        return "Live"
    }
    catch {
        "Error determining optimal source type: $_" | Add-Content $LogPath
        Write-LogMessage "Error determining source type, defaulting to Live: $_" "WARNING"
        return "Live"
    }
}

function Export-DriveDrivers {
    param(
        [string]$OutputPath,
        [string]$LogPath
    )
    
    try {
        "Starting drive-specific driver export..." | Add-Content $LogPath
        Write-LogMessage "Export-DriveDrivers function called but not fully implemented" "WARNING"
        
        # This is a placeholder - could be enhanced to select specific drives
        # For now, fall back to live system export
        return Export-LiveSystemDrivers -OutputPath $OutputPath -LogPath $LogPath
    }
    catch {
        "Error in drive-specific export: $_" | Add-Content $LogPath
        throw
    }
}

function Export-LiveSystemDrivers {
    param(
        [string]$OutputPath,
        [string]$LogPath
    )
    
    try {
        "Starting live system driver export..." | Add-Content $LogPath
        Write-LogMessage "Exporting drivers from live system using DISM..." "INFO"
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            "Created output directory: $OutputPath" | Add-Content $LogPath
            Write-LogMessage "Created output directory: $OutputPath" "INFO"
        }
        
        # Use DISM to export drivers from running system directly to target path
        $dismCommand = "dism.exe /online /export-driver /destination:`"$OutputPath`""
        "Executing DISM command: $dismCommand" | Add-Content $LogPath
        Write-LogMessage "DISM command: $dismCommand" "VERBOSE"
        
        $dismOutput = & dism.exe /online /export-driver /destination:"$OutputPath" 2>&1
        
        "DISM exit code: $LASTEXITCODE" | Add-Content $LogPath
        Write-LogMessage "DISM exit code: $LASTEXITCODE" "INFO"
        
        # Log all DISM output for debugging
        if ($dismOutput) {
            "DISM output:" | Add-Content $LogPath
            foreach ($line in $dismOutput) {
                "  $line" | Add-Content $LogPath
                Write-LogMessage "[DISM] $line" "VERBOSE"
            }
        }
        
        if ($LASTEXITCODE -eq 0) {
            "Live system driver export completed successfully" | Add-Content $LogPath
            
            # Count exported drivers
            $driverFolders = Get-ChildItem -Path $OutputPath -Directory -ErrorAction SilentlyContinue | Where-Object { 
                $_.Name -ne "Logs" -and $_.Name -ne "Device_Drivers" 
            }
            $driverCount = $driverFolders.Count
            
            "Found $driverCount driver folders after export" | Add-Content $LogPath
            Write-LogMessage "Exported $driverCount driver packages from live system" "INFO"
            
            # List the driver folders for debugging
            if ($driverFolders) {
                "Driver folders found:" | Add-Content $LogPath
                foreach ($folder in $driverFolders) {
                    "  - $($folder.Name)" | Add-Content $LogPath
                    Write-LogMessage "Driver folder: $($folder.Name)" "VERBOSE"
                }
            } else {
                "No driver folders found in output directory" | Add-Content $LogPath
                Write-LogMessage "WARNING: No driver folders found after export" "WARNING"
            }
            
            return $driverCount
        } else {
            $errorMsg = "DISM export failed with exit code $LASTEXITCODE"
            "ERROR: $errorMsg" | Add-Content $LogPath
            Write-LogMessage $errorMsg "ERROR"
            throw "$errorMsg. Output: $($dismOutput -join "`n")"
        }
    }
    catch {
        $errorMsg = "Error exporting live system drivers: $_"
        $errorMsg | Add-Content $LogPath
        Write-LogMessage $errorMsg "ERROR"
        throw
    }
}

function Export-OfflineSystemDrivers {
    param(
        [string]$OutputPath,
        [string]$LogPath,
        [hashtable]$DeviceInfo
    )
    
    try {
        "Starting offline system driver export..." | Add-Content $LogPath
        Write-LogMessage "Exporting drivers from offline Windows installations..." "INFO"
        
        # Find all Windows partitions
        $windowsPartitions = Find-AllWindowsPartitions
        
        "Found $($windowsPartitions.Count) Windows partitions for offline export" | Add-Content $LogPath
        Write-LogMessage "Found $($windowsPartitions.Count) Windows partitions for offline export" "INFO"
        
        if ($windowsPartitions.Count -eq 0) {
            $errorMsg = "No Windows partitions found for offline driver export"
            $errorMsg | Add-Content $LogPath
            Write-LogMessage $errorMsg "WARNING"
            throw $errorMsg
        }
        
        $totalDriversExported = 0
        
        # Create output directory structure if using V: drive directly
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            "Created output directory: $OutputPath" | Add-Content $LogPath
            Write-LogMessage "Created output directory: $OutputPath" "INFO"
        }
        
        foreach ($partition in $windowsPartitions) {
            try {
                $partitionMsg = "Processing Windows partition: $($partition.DriveLetter) ($($partition.WindowsVersion))"
                $partitionMsg | Add-Content $LogPath
                Write-LogMessage $partitionMsg "INFO"
                
                # Create subfolder for this partition within the main output path
                $partitionOutputPath = Join-Path $OutputPath "Device_Drivers"
                if (-not (Test-Path $partitionOutputPath)) {
                    New-Item -Path $partitionOutputPath -ItemType Directory -Force | Out-Null
                    "Created partition output directory: $partitionOutputPath" | Add-Content $LogPath
                }
                
                # Use DISM to export drivers from this partition directly to V: drive
                $dismCommand = "dism.exe /image:`"$($partition.DriveLetter)\`" /export-driver /destination:`"$partitionOutputPath`""
                "Executing DISM command: $dismCommand" | Add-Content $LogPath
                Write-LogMessage "DISM command: $dismCommand" "VERBOSE"
                
                $dismOutput = & dism.exe /image:"$($partition.DriveLetter)\" /export-driver /destination:"$partitionOutputPath" 2>&1
                
                "DISM exit code for $($partition.DriveLetter): $LASTEXITCODE" | Add-Content $LogPath
                Write-LogMessage "DISM exit code for $($partition.DriveLetter): $LASTEXITCODE" "INFO"
                
                # Log DISM output for debugging
                if ($dismOutput) {
                    "DISM output for $($partition.DriveLetter):" | Add-Content $LogPath
                    foreach ($line in $dismOutput) {
                        "  $line" | Add-Content $LogPath
                        Write-LogMessage "[DISM-$($partition.DriveLetter)] $line" "VERBOSE"
                    }
                }
                
                if ($LASTEXITCODE -eq 0) {
                    "Successfully exported drivers from $($partition.DriveLetter)" | Add-Content $LogPath
                    
                    # Count exported drivers for this partition
                    $driverFolders = Get-ChildItem -Path $partitionOutputPath -Directory -ErrorAction SilentlyContinue
                    $partitionDriverCount = $driverFolders.Count
                    $totalDriversExported += $partitionDriverCount
                    
                    "Exported $partitionDriverCount driver packages from $($partition.DriveLetter)" | Add-Content $LogPath
                    Write-LogMessage "Exported $partitionDriverCount drivers from $($partition.DriveLetter)" "INFO"
                    
                    # List driver folders for debugging
                    if ($driverFolders) {
                        "Driver folders from $($partition.DriveLetter):" | Add-Content $LogPath
                        foreach ($folder in $driverFolders) {
                            "  - $($folder.Name)" | Add-Content $LogPath
                        }
                    }
                    
                    # Create partition summary
                    $partitionSummary = @{
                        DriveLetter = $partition.DriveLetter
                        WindowsVersion = $partition.WindowsVersion
                        DriverCount = $partitionDriverCount
                        ExportPath = $partitionOutputPath
                        DeviceInfo = $DeviceInfo
                        ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    }
                    
                    $summaryPath = Join-Path $partitionOutputPath "PartitionInfo.json"
                    $partitionSummary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Force
                    
                } else {
                    $failMsg = "Failed to export drivers from $($partition.DriveLetter): $($dismOutput -join "`n")"
                    $failMsg | Add-Content $LogPath
                    Write-LogMessage "Failed to export drivers from $($partition.DriveLetter)" "WARNING"
                }
            }
            catch {
                $errorMsg = "Error processing partition $($partition.DriveLetter): $_"
                $errorMsg | Add-Content $LogPath
                Write-LogMessage $errorMsg "WARNING"
            }
        }
        
        "Total drivers exported from all partitions: $totalDriversExported" | Add-Content $LogPath
        Write-LogMessage "Total drivers exported from all partitions: $totalDriversExported" "INFO"
        
        # Create harvest metadata directly in the V: drive location
        if ($totalDriversExported -gt 0 -and $OutputPath -like "V:\*") {
            try {
                $repoMetadata = @{
                    DeviceInfo = $DeviceInfo
                    HarvestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    SourceType = "Offline"
                    DriverCount = $totalDriversExported
                    WindowsPartitions = $windowsPartitions | ForEach-Object { "$($_.DriveLetter) ($($_.WindowsVersion))" }
                    ExportMethod = "Direct to V: drive"
                }
                
                $metadataPath = Join-Path $OutputPath "DriverHarvestInfo.json"
                $repoMetadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Force
                
                "Created harvest metadata at: $metadataPath" | Add-Content $LogPath
                Write-LogMessage "Created harvest metadata at: $metadataPath" "INFO"
            } catch {
                "Failed to create harvest metadata: $_" | Add-Content $LogPath
                Write-LogMessage "Failed to create harvest metadata: $_" "WARNING"
            }
        }
        
        return $totalDriversExported
    }
    catch {
        $errorMsg = "Error in offline driver export: $_"
        $errorMsg | Add-Content $LogPath
        Write-LogMessage $errorMsg "ERROR"
        throw
    }
}

function Find-AllWindowsPartitions {
    try {
        $windowsPartitions = @()
        
        # Get all physical disks
        $physicalDisks = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.MediaType -like "*fixed*" }
        
        Write-LogMessage "Scanning $($physicalDisks.Count) physical disk(s) for Windows partitions..." "INFO"
        
        # Check all logical disks but exclude WinPE and system drives
        $excludedDrives = @('V', 'W', 'X', 'Y', 'Z')  # Exclude system drives from driver harvesting
        
        Write-LogMessage "Excluded drives for driver harvesting: $($excludedDrives -join ', ')" "INFO"
        
        $allLogicalDisks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        Write-LogMessage "Found $($allLogicalDisks.Count) fixed logical disks" "INFO"
        
        $candidateDisks = $allLogicalDisks | Where-Object { 
            $_.DeviceID.Substring(0,1) -notin $excludedDrives 
        }
        Write-LogMessage "Found $($candidateDisks.Count) candidate disks after exclusions" "INFO"
        
        foreach ($disk in $candidateDisks) {
            $driveLetter = $disk.DeviceID
            $windowsPath = Join-Path $driveLetter "Windows"
            
            Write-LogMessage "Checking drive $driveLetter for Windows installation..." "VERBOSE"
            
            if (Test-Path $windowsPath) {
                $systemPath = Join-Path $windowsPath "System32"
                $bootPath = Join-Path $windowsPath "Boot"
                
                Write-LogMessage "Found Windows folder on $driveLetter, checking System32 and Boot..." "VERBOSE"
                
                if ((Test-Path $systemPath) -and (Test-Path $bootPath)) {
                    Write-LogMessage "Found System32 and Boot folders on $driveLetter" "VERBOSE"
                    
                    # Additional check to ensure this is not a WinPE installation
                    $winpeIndicators = @(
                        "$windowsPath\System32\startnet.cmd",
                        "$windowsPath\System32\wpeinit.exe",
                        "$windowsPath\System32\winpeshl.exe"
                    )
                    
                    $isWinPE = $false
                    foreach ($indicator in $winpeIndicators) {
                        if (Test-Path $indicator) {
                            $isWinPE = $true
                            Write-LogMessage "Drive $driveLetter appears to be WinPE (found $indicator) - skipping for driver harvest" "INFO"
                            break
                        }
                    }
                    
                    if ($isWinPE) {
                        continue  # Skip WinPE installations
                    }
                    
                    # Try to determine Windows version
                    $windowsVersion = "Unknown"
                    $versionPath = Join-Path $systemPath "kernel32.dll"
                    
                    if (Test-Path $versionPath) {
                        try {
                            $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($versionPath)
                            if ($fileVersion.ProductMajorPart -eq 10) {
                                # Check build number to distinguish Windows 10 vs 11
                                if ($fileVersion.ProductBuildPart -ge 22000) {
                                    $windowsVersion = "Windows 11"
                                } else {
                                    $windowsVersion = "Windows 10"
                                }
                            } elseif ($fileVersion.ProductMajorPart -eq 6) {
                                if ($fileVersion.ProductMinorPart -eq 3) {
                                    $windowsVersion = "Windows 8.1"
                                } elseif ($fileVersion.ProductMinorPart -eq 1) {
                                    $windowsVersion = "Windows 7"
                                }
                            }
                        } catch {
                            $windowsVersion = "Windows (version detection failed)"
                            Write-LogMessage "Failed to detect Windows version on $driveLetter" "VERBOSE"
                        }
                    }
                    
                    $partitionInfo = @{
                        DriveLetter = $driveLetter
                        WindowsPath = $windowsPath
                        SystemPath = $systemPath
                        WindowsVersion = $windowsVersion
                        Size = [math]::Round($disk.Size / 1GB, 2)
                        FreeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
                    }
                    
                    $windowsPartitions += $partitionInfo
                    Write-LogMessage "Found valid Windows partition for driver harvest: $driveLetter ($windowsVersion, $($partitionInfo.Size)GB)" "INFO"
                } else {
                    Write-LogMessage "Drive $driveLetter has Windows folder but missing System32 or Boot" "VERBOSE"
                }
            } else {
                Write-LogMessage "No Windows folder found on $driveLetter" "VERBOSE"
            }
        }
        
        Write-LogMessage "Found $($windowsPartitions.Count) valid Windows partitions for driver harvesting (excluded system drives: $($excludedDrives -join ', '))" "INFO"
        return $windowsPartitions
    }
    catch {
        Write-LogMessage "Error scanning for Windows partitions: $_" "ERROR"
        return @()
    }
}

function Create-DriverSummary {
    param(
        [string]$OutputPath,
        [int]$DriverCount,
        [hashtable]$DeviceInfo
    )
    
    try {
        $summaryPath = Join-Path $OutputPath "DriverSummary.txt"
        
        $summary = @"
Driver Export Summary
====================

Export Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Device Information:
- Manufacturer: $($DeviceInfo.Manufacturer)
- Model: $($DeviceInfo.Model)
- Serial Number: $($DeviceInfo.SerialNumber)
- Memory: $($DeviceInfo.MemoryTotal)

Export Results:
- Total Driver Packages: $DriverCount
- Output Location: $OutputPath

Instructions:
1. These drivers are specific to the hardware configuration they were exported from
2. For deployment, copy the entire folder to your driver repository
3. Use DISM or deployment tools to inject these drivers during Windows installation

Note: Only use these drivers on identical hardware models for best compatibility.
"@
        
        $summary | Set-Content -Path $summaryPath -Force
        Write-LogMessage "Created driver summary at: $summaryPath" "INFO"
    }
    catch {
        Write-LogMessage "Failed to create driver summary: $_" "WARNING"
    }
}

Export-ModuleMember -Function Export-SystemDrivers, Find-AllWindowsPartitions, Clean-DeviceName
function Create-DriverSummary {
    param(
        [string]$OutputPath,
        [int]$DriverCount,
        [hashtable]$DeviceInfo
    )
    
    try {
        $summaryPath = Join-Path $OutputPath "DriverSummary.txt"
        
        $summary = @"
Driver Export Summary
====================

Export Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Device Information:
- Manufacturer: $($DeviceInfo.Manufacturer)
- Model: $($DeviceInfo.Model)
- Serial Number: $($DeviceInfo.SerialNumber)
- Memory: $($DeviceInfo.MemoryTotal)

Export Results:
- Total Driver Packages: $DriverCount
- Output Location: $OutputPath

Instructions:
1. These drivers are specific to the hardware configuration they were exported from
2. For deployment, copy the entire folder to your driver repository
3. Use DISM or deployment tools to inject these drivers during Windows installation

Note: Only use these drivers on identical hardware models for best compatibility.
"@
        
        $summary | Set-Content -Path $summaryPath -Force
        Write-LogMessage "Created driver summary at: $summaryPath" "INFO"
    }
    catch {
        Write-LogMessage "Failed to create driver summary: $_" "WARNING"
    }
}

Export-ModuleMember -Function Export-SystemDrivers, Find-WindowsPartition, Find-AllWindowsPartitions, Clean-DeviceName
