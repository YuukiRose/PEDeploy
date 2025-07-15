# Set images root at the top of the script
$ImagesRoot = "Z:\"

# Import only the local logging module
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import local Logging module: $_" -ForegroundColor Red
    throw "Required local Logging module not found"
}

# Import DriverHarvesting module for Clean-DeviceName function
try {
    Import-Module "$PSScriptRoot\..\Drivers\DriverHarvesting.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import DriverHarvesting module: $_" -ForegroundColor Red
    throw "Required DriverHarvesting module not found"
}

# Define Update-DeploymentProgress function if not available
if (-not (Get-Command Update-DeploymentProgress -ErrorAction SilentlyContinue)) {
    function Update-DeploymentProgress {
        param(
            [int]$PercentComplete,
            [string]$Status
        )
        Write-Host "[$PercentComplete%] $Status" -ForegroundColor Cyan
        if (Get-Command Write-LogMessage -ErrorAction SilentlyContinue) {
            Write-LogMessage "Progress: [$PercentComplete%] $Status" "INFO"
        }
    }
}

function Start-WindowsDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [string]$OrderNumber,
        
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo,
        
        [Parameter()]
        [bool]$UseDisk0 = $true,
        
        [Parameter()]
        [string]$TargetDrive = $null,
        
        [Parameter()]
        [int]$ImageIndex = 1,
        
        [Parameter()]
        [hashtable]$ImageConfig = @{}
    )
    
    try {
        # FORCE MINIMUM EXECUTION TIME TO DETECT FAKE OPERATIONS
        $deploymentStartTime = Get-Date
        
        # Start logging using the local system
        $serial = $null
        if ($DeviceInfo.ContainsKey("SerialNumber")) {
            $serial = $DeviceInfo.SerialNumber
        } elseif ($DeviceInfo.ContainsKey("Serial")) {
            $serial = $DeviceInfo.Serial
        }
        if (-not $serial) { $serial = "UnknownSerial" }
        
        # Use local logging initialization
        $logResult = Initialize-DeploymentLogging -CustomerName $CustomerName -OrderNumber $OrderNumber -SerialNumber $serial
        if (-not $logResult) {
            throw "CRITICAL: Failed to initialize logging system"
        }

        Write-LogMessage "=== Starting Windows Deployment ===" "INFO"
        Write-LogMessage "Image: $ImagePath" "INFO"
        Write-LogMessage "Customer: $CustomerName" "INFO"
        Write-LogMessage "Order: $OrderNumber" "INFO"
        Write-LogMessage "Device: $($DeviceInfo.Manufacturer) $($DeviceInfo.Model)" "INFO"
        Write-LogMessage "Serial: $serial" "INFO"
        
        # Check if this is an ISO deployment
        $isISO = $ImageConfig.ContainsKey('IsISO') -and $ImageConfig.IsISO
        $mountedISOInfo = $null
        $actualImagePath = $ImagePath
        
        if ($isISO) {
            Write-LogMessage "ISO deployment detected - mounting ISO first" "INFO"
            try {
                Import-Module "$PSScriptRoot\..\Core\ISOManager.psm1" -Force
                $mountedISOInfo = Mount-ISOForDeployment -ISOPath $ImagePath
                $actualImagePath = $mountedISOInfo.InstallWimPath
                Write-LogMessage "ISO mounted successfully. Using install.wim at: $actualImagePath" "SUCCESS"
            } catch {
                throw "CRITICAL: Failed to mount ISO for deployment: $_"
            }
        }
        
        # CRITICAL: Add explicit checks for required tools
        Write-LogMessage "Verifying deployment environment..." "INFO"
        
        # Check for diskpart
        $diskpartPath = Get-Command diskpart.exe -ErrorAction SilentlyContinue
        if (-not $diskpartPath) {
            throw "CRITICAL: diskpart.exe not found - cannot partition disks"
        }
        Write-LogMessage "Found diskpart.exe at: $($diskpartPath.Source)" "INFO"
        
        # Check for DISM
        $dismPath = Get-Command dism.exe -ErrorAction SilentlyContinue
        if (-not $dismPath) {
            throw "CRITICAL: dism.exe not found - cannot apply images"
        }
        Write-LogMessage "Found dism.exe at: $($dismPath.Source)" "INFO"
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 5 -Status "Validating image file..."
        
        # CRITICAL: Validate image file exists with detailed error
        Write-LogMessage "Validating image file: $actualImagePath" "INFO"
        if (-not (Test-Path $actualImagePath)) {
            throw "CRITICAL: Image file not found: $actualImagePath"
        }
        
        # Determine image type (WIM/ESD vs FFU) with robust detection
        $isFFU = $false
        $imageType = $null
        if ($ImageConfig.ContainsKey('Type')) {
            $imageType = $ImageConfig.Type.ToString().ToLower()
        }
        if ($actualImagePath -match '\\.[Ff][Ff][Uu]$' -or $imageType -eq 'ffu') {
            $isFFU = $true
            Write-LogMessage "FFU image detected: $actualImagePath (Type: $imageType)" "INFO"
        }
        else {
            Write-LogMessage "Non-FFU image detected: $actualImagePath (Type: $imageType)" "INFO"
        }

        if (-not $isFFU) {
            # Get image information with detailed validation (WIM/ESD only)
            Write-LogMessage "Getting image information..." "INFO"
            $imageInfo = Get-WindowsImageInfo -ImagePath $actualImagePath
            if (-not $imageInfo) {
                throw "CRITICAL: Failed to get image information from $actualImagePath"
            }
            Write-LogMessage "Image contains $($imageInfo.ImageCount) image(s)" "INFO"
            # Validate ImageIndex
            if ($ImageIndex -gt $imageInfo.ImageCount) {
                throw "CRITICAL: Requested image index $ImageIndex does not exist (image has $($imageInfo.ImageCount) indices)"
            }
        }
        else {
            # For FFU, skip image info and index validation
            Write-LogMessage "Skipping image info and index validation for FFU image." "INFO"
        }
        
        Write-LogMessage "Checking for device-specific drivers..." "INFO"
        $driverPath = Get-DriverPath -DeviceInfo $DeviceInfo
        $harvestedDriverPath = $null
        $driversAvailable = $false
        
        if ($driverPath -and (Test-Path $driverPath)) {
            Write-LogMessage "Found device-specific drivers at: $driverPath" "INFO"
            $driversAvailable = $true
        } else {
            Write-LogMessage "No device-specific drivers found for $($DeviceInfo.Manufacturer) $($DeviceInfo.Model)" "INFO"
            
            # Try to harvest drivers from existing Windows installation BEFORE formatting
            Write-LogMessage "Attempting to harvest drivers from existing Windows installation before disk formatting..." "INFO"
            $harvestResult = Get-DriversFromDisk0 -DeviceInfo $DeviceInfo
            
            if ($harvestResult.Success) {
                Write-LogMessage "Successfully harvested drivers: $($harvestResult.Message)" "SUCCESS"
                $harvestedDriverPath = $harvestResult.DriverPath
                $driversAvailable = $true
            } else {
                Write-LogMessage "Driver harvesting result: $($harvestResult.Message)" "INFO"
            }
        }
        
        if ($driversAvailable) {
            Write-LogMessage "Drivers are available for installation after Windows deployment" "SUCCESS"
        } else {
            Write-LogMessage "No drivers found - device will use generic Windows drivers" "WARNING"
        }
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 20 -Status "Preparing target disk..."
        
        # FORCE DISK INITIALIZATION TO TAKE TIME
        $diskStartTime = Get-Date
        Write-LogMessage "Starting disk initialization at $diskStartTime" "INFO"
        
        # Initialize disk if requested
        if ($UseDisk0) {
            $diskResult = Initialize-Disk0ForWindows
            
            $diskEndTime = Get-Date
            $diskDuration = ($diskEndTime - $diskStartTime).TotalSeconds
            Write-LogMessage "Disk initialization took $diskDuration seconds" "INFO"
            
            # CRITICAL: If disk formatting took less than 10 seconds, it probably failed
            if ($diskDuration -lt 10) {
                Write-LogMessage "WARNING: Disk initialization completed suspiciously fast ($diskDuration seconds)" "WARNING"
            }
            
            if (-not $diskResult.Success) {
                throw "CRITICAL: Failed to prepare disk: $($diskResult.Message)"
            }
            $windowsDrive = $diskResult.WindowsDrive
            $systemDrive = $diskResult.SystemDrive
            
            # FORCE VERIFICATION OF DISK OPERATIONS
            Write-LogMessage "CRITICAL VERIFICATION: Checking if drives actually exist..." "INFO"
            if (-not (Test-Path "$windowsDrive\")) {
                throw "CRITICAL: Windows drive $windowsDrive does not exist after disk initialization"
            }
            if (-not (Test-Path "$systemDrive\")) {
                throw "CRITICAL: System drive $systemDrive does not exist after disk initialization"
            }
            
            # Test write access immediately
            try {
                $testFile = "$windowsDrive\deployment_test_$(Get-Random).tmp"
                "test" | Out-File -FilePath $testFile -ErrorAction Stop
                Remove-Item $testFile -Force -ErrorAction Stop
                Write-LogMessage "Verified write access to $windowsDrive" "INFO"
            } catch {
                throw "CRITICAL: Cannot write to $windowsDrive after disk initialization: $_"
            }
        } else {
            $windowsDrive = $TargetDrive
            $systemDrive = $TargetDrive
        }
        
        Write-LogMessage "Target drives - Windows: $windowsDrive, System: $systemDrive" "INFO"
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 40 -Status "Applying Windows image..."
        # FORCE IMAGE APPLICATION TO TAKE TIME
        $imageStartTime = Get-Date
        Write-LogMessage "Starting image application at $imageStartTime" "INFO"

        if ($isFFU) {
            $applyResult = Install-WindowsFromFFU -ImagePath $actualImagePath -TargetDrive $windowsDrive
            # For FFU images, skip driver installation, updates, unattend, and boot config
            Write-LogMessage "FFU deployment: Skipping driver installation, Windows updates, unattend file, and boot configuration." "INFO"
            # Explicitly skip all post-deployment steps for FFU
            return $applyResult
        } else {
            $applyResult = Install-WindowsFromWim -ImagePath $actualImagePath -ImageIndex $ImageIndex -TargetDrive $windowsDrive
        }

        $imageEndTime = Get-Date
        $imageDuration = ($imageEndTime - $imageStartTime).TotalSeconds
        Write-LogMessage "Image application took $imageDuration seconds" "INFO"
        
        # CRITICAL: If image application took less than 30 seconds, it probably failed
        if ($imageDuration -lt 30) {
            Write-LogMessage "CRITICAL WARNING: Image application completed suspiciously fast ($imageDuration seconds)" "ERROR"
            Write-LogMessage "A real Windows image deployment should take several minutes" "ERROR"
        }
        
        if (-not $applyResult.Success) {
            throw "CRITICAL: Failed to apply Windows image: $($applyResult.Message)"
        }
        
        if (-not $isFFU) {
            # FORCE VERIFICATION OF IMAGE APPLICATION
            Write-LogMessage "CRITICAL VERIFICATION: Checking if Windows was actually deployed..." "INFO"
            $windowsDir = "$windowsDrive\Windows"
            if (-not (Test-Path $windowsDir)) {
                throw "CRITICAL: Windows directory not found at $windowsDir after image application"
            }
            $system32Dir = "$windowsDir\System32"
            if (-not (Test-Path $system32Dir)) {
                throw "CRITICAL: System32 directory not found at $system32Dir after image application"
            }
            # Check for critical Windows files
            $criticalFiles = @(
                "$system32Dir\ntoskrnl.exe",
                "$system32Dir\kernel32.dll",
                "$system32Dir\winload.efi"
            )
            $missingFiles = @()
            foreach ($file in $criticalFiles) {
                if (-not (Test-Path $file)) {
                    $missingFiles += $file
                }
            }
            if ($missingFiles.Count -gt 0) {
                throw "CRITICAL: Missing critical Windows files after deployment: $($missingFiles -join ', ')"
            }
            Write-LogMessage "Verified critical Windows files are present" "INFO"
        }
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 70 -Status "Installing drivers..."
        
        # Install drivers using previously identified sources
        $driversInstalled = $false
        
        if ($driverPath -and (Test-Path $driverPath)) {
            Write-LogMessage "Installing device-specific drivers from: $driverPath" "INFO"
            $driverResult = Install-DriversToWindows -WindowsDrive $windowsDrive -DriverPath $driverPath
            if ($driverResult.Success) {
                Write-LogMessage "Device-specific drivers installed successfully" "SUCCESS"
                $driversInstalled = $true
            } else {
                Write-LogMessage "Device-specific driver installation failed: $($driverResult.Message)" "WARNING"
            }
        } elseif ($harvestedDriverPath -and (Test-Path $harvestedDriverPath)) {
            Write-LogMessage "Installing harvested drivers from: $harvestedDriverPath" "INFO"
            $driverResult = Install-DriversToWindows -WindowsDrive $windowsDrive -DriverPath $harvestedDriverPath
            if ($driverResult.Success) {
                Write-LogMessage "Harvested drivers installed successfully" "SUCCESS"
                $driversInstalled = $true
            } else {
                Write-LogMessage "Harvested driver installation failed: $($driverResult.Message)" "WARNING"
            }
        }
        
        if (-not $driversInstalled) {
            Write-LogMessage "No drivers were installed - device may use generic Windows drivers" "WARNING"
        }
        
        # Check if Windows updates should be installed
        $shouldInstallUpdates = $false
        if ($ImageConfig.ContainsKey('RequiredUpdates')) {
            $shouldInstallUpdates = [bool]$ImageConfig.RequiredUpdates
            Write-LogMessage "RequiredUpdates flag found in image config: $shouldInstallUpdates" "INFO"
        } else {
            Write-LogMessage "RequiredUpdates flag not found in image config, defaulting to false" "INFO"
        }
        
        if ($shouldInstallUpdates) {
            # Update progress
            Update-DeploymentProgress -PercentComplete 80 -Status "Installing Windows updates..."
            
            # Install Windows updates if available
            $updateResult = Install-WindowsUpdatesToWindows -WindowsDrive $windowsDrive -ImagePath $ImagePath
            if ($updateResult.Success) {
                Write-LogMessage "Windows updates installed successfully: $($updateResult.Message)" "SUCCESS"
            } else {
                Write-LogMessage "Windows updates installation completed with warnings: $($updateResult.Message)" "WARNING"
            }
        } else {
            Write-LogMessage "Skipping Windows updates installation (RequiredUpdates = false)" "INFO"
            Update-DeploymentProgress -PercentComplete 80 -Status "Skipping Windows updates (not required)..."
        }
        
# --- BEGIN: Apply Unattend.xml from image root or fallback to default ---
$imageRoot = Join-Path $ImagesRoot "CustomerImages"
$imageID = Split-Path (Split-Path $actualImagePath -Parent) -Leaf
$customerImageRootUnattend = Join-Path (Join-Path $imageRoot $CustomerName) (Join-Path $imageID 'Unattend.xml')
$defaultUnattendPath = 'Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Unattend.xml'
$unattendToApply = $null
if (Test-Path $customerImageRootUnattend) {
    Write-LogMessage "Found Unattend.xml in image root: $customerImageRootUnattend. Will use this unattend file." "INFO"
    $unattendToApply = $customerImageRootUnattend
} elseif (Test-Path $defaultUnattendPath) {
    Write-LogMessage "No Unattend.xml in image root. Using default unattend: $defaultUnattendPath" "INFO"
    $unattendToApply = $defaultUnattendPath
} else {
    Write-LogMessage "No unattend file found in image root or default location. Skipping unattend application." "WARNING"
}
if ($unattendToApply) {
    $unattendResult = Set-UnattendFileToWindows -WindowsDrive $windowsDrive -CustomerName $CustomerName -UnattendSourcePath $unattendToApply
    if ($unattendResult.Success) {
        Write-LogMessage "Unattend file applied successfully: $($unattendResult.Message)" "SUCCESS"
    } else {
        Write-LogMessage "Unattend file application completed with warnings: $($unattendResult.Message)" "WARNING"
    }
}
# --- END: Apply Unattend.xml logic ---
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 90 -Status "Configuring boot environment..."
        
        # Configure boot
        $bootResult = Set-WindowsBoot -WindowsDrive $windowsDrive -SystemDrive $systemDrive
        if (-not $bootResult.Success) {
            throw "CRITICAL: Failed to configure boot: $($bootResult.Message)"
        }
        
        # --- BEGIN: Copy Additional Scripts if present ---
        $scriptsSource = Join-Path (Split-Path $actualImagePath -Parent) "Scripts"
        $scriptsTarget = Join-Path $windowsDrive "Scripts"
        $additionalTasksPresent = $false
        if (Test-Path $scriptsSource) {
            Write-LogMessage "Found additional scripts at $scriptsSource. Copying to $scriptsTarget..." "INFO"
            try {
                if (-not (Test-Path $scriptsTarget)) {
                    New-Item -Path $scriptsTarget -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path (Join-Path $scriptsSource '*') -Destination $scriptsTarget -Recurse -Force
                Write-LogMessage "Copied additional scripts to $scriptsTarget" "SUCCESS"
                $additionalTasksPresent = $true
            } catch {
                Write-LogMessage "Failed to copy additional scripts: $_" "ERROR"
            }
        } else {
            Write-LogMessage "No additional scripts found at $scriptsSource" "INFO"
        }
        # --- END: Copy Additional Scripts ---

        
        # FINAL VERIFICATION
        $deploymentEndTime = Get-Date
        $totalDuration = ($deploymentEndTime - $deploymentStartTime).TotalSeconds
        Write-LogMessage "Total deployment time: $totalDuration seconds" "INFO"
        
        # CRITICAL: If total deployment took less than 60 seconds, something is wrong
        if ($totalDuration -lt 60) {
            throw "CRITICAL: Deployment completed suspiciously fast ($totalDuration seconds). Real deployments take several minutes."
        }
        
        # Update progress
        Update-DeploymentProgress -PercentComplete 100 -Status "Deployment completed successfully"
        Write-LogMessage "=== Windows Deployment Completed Successfully ===" "SUCCESS"
        
        return @{
            Success = $true
            Message = "Windows deployment completed successfully"
            WindowsDrive = $windowsDrive
            SystemDrive = $systemDrive
            Duration = $totalDuration
        }
    }
    catch {
        Write-LogMessage "DEPLOYMENT FAILED: $_" "ERROR"
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Update-DeploymentProgress -PercentComplete 0 -Status "Deployment failed: $($_.Exception.Message)"
        
        return @{
            Success = $false
            Message = $_.Exception.Message
            Error = $_
        }
    }
    finally {
        # Only dismount ISO if deployment failed - successful deployments will reboot and clean up automatically
        if ($isISO -and $mountedISOInfo) {
            # We need to determine if deployment was successful
            # Since we're in finally block, we can't easily access the return value
            # Instead, check if we made it through the main deployment without exceptions
            
            try {
                # Check if we have a valid result by looking at the last progress message
                # But since successful deployments will reboot immediately, we shouldn't get here on success
                
                # The fact that we're in this finally block after a successful deployment 
                # means the system is about to reboot, so we should NOT dismount
                
                # Only dismount if we can detect this was actually a failure
                $shouldDismount = $false
                
                # Check if there was an exception by looking for error indicators
                if ($Error.Count -gt 0) {
                    $lastError = $Error[0]
                    if ($lastError.Exception.Message -and $lastError.Exception.Message -like "*CRITICAL*") {
                        $shouldDismount = $true
                        Write-LogMessage "Deployment failed - will dismount ISO" "INFO"
                    }
                }
                
                # Additional check: if we're still in WinPE and haven't rebooted, 
                # it might indicate a failure
                if ($shouldDismount) {
                    Write-LogMessage "Dismounting ISO after failed deployment..." "INFO"
                    Dismount-ISOAfterDeployment -ISOPath $ImagePath
                } else {
                    Write-LogMessage "Deployment appears successful - ISO will be cleaned up on reboot" "INFO"
                }
                
            } catch {
                Write-LogMessage "Warning: Error in finally block ISO handling: $_" "WARNING"
            }
        }
    }
}

function Initialize-Disk0ForWindows {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Initializing Disk 0 for Windows installation..." "INFO"
        
        # Quick disk existence check first
        $listDiskScriptPath = "$env:TEMP\quick_disk_check_$(Get-Random).txt"
        "list disk`r`nexit" | Out-File -FilePath $listDiskScriptPath -Encoding ASCII -Force
        
        try {
            $diskListOutput = & diskpart.exe /s $listDiskScriptPath 2>&1
            Remove-Item $listDiskScriptPath -Force -ErrorAction SilentlyContinue
            
            $diskLines = $diskListOutput | Where-Object { $_ -match "Disk\s+\d+" }
            if ($diskLines.Count -eq 0) {
                throw "No physical disks found in system"
            }
            
            Write-LogMessage "Found $($diskLines.Count) physical disk(s)" "INFO"
            foreach ($diskLine in $diskLines) {
                Write-LogMessage "  $diskLine" "INFO"
            }
            
            # Find Disk 0 or first available disk
            $diskNumber = 0
            $targetDiskFound = $diskLines | Where-Object { $_ -match "Disk\s+0\s+" }
            if (-not $targetDiskFound) {
                Write-LogMessage "Disk 0 not found, using first available disk..." "WARNING"
                $firstDisk = $diskLines[0]
                if ($firstDisk -match "Disk\s+(\d+)\s+") {
                    $diskNumber = [int]$Matches[1]
                    Write-LogMessage "Using Disk $diskNumber instead of Disk 0" "INFO"
                } else {
                    throw "No valid disks found"
                }
            }
            
        } catch {
            throw "Failed to check available disks: $_"
        }
        
        Write-LogMessage "Using Disk $diskNumber for deployment" "INFO"
        
        # Create disk configuration
        $diskConfig = @{
            DiskNumber = $diskNumber
            UseEntireDisk = $true
            WindowsPartitionLabel = "Windows"
            SystemPartitionLabel = "System"
            RecoveryPartitionLabel = "Recovery"
        }
        
        # Import and call the Initialize-SystemDisk function with timeout protection
        try {
            Import-Module "$PSScriptRoot\Initialize-SystemDisk.psm1" -Force
        } catch {
            throw "Failed to import Initialize-SystemDisk module: $_"
        }
        
        Write-LogMessage "Starting disk initialization with timeout protection..." "INFO"
        $initStartTime = Get-Date
        
        # Add timeout protection for the entire disk initialization
        $initJob = Start-Job -ScriptBlock {
            param($diskConfig, $modulePath)
            Import-Module $modulePath -Force
            Initialize-SystemDisk -DiskConfig $diskConfig
        } -ArgumentList $diskConfig, "$PSScriptRoot\Initialize-SystemDisk.psm1"
        
        # Wait for completion with timeout (max 10 minutes for full disk initialization)
        $timeoutMinutes = 10
        $completed = Wait-Job $initJob -Timeout ($timeoutMinutes * 60)
        
        if ($completed) {
            $diskResult = Receive-Job $initJob
            Remove-Job $initJob -Force
        } else {
            Write-LogMessage "Disk initialization timed out after $timeoutMinutes minutes" "ERROR"
            Stop-Job $initJob -ErrorAction SilentlyContinue
            Remove-Job $initJob -Force -ErrorAction SilentlyContinue
            throw "Disk initialization timed out after $timeoutMinutes minutes"
        }
        
        $initEndTime = Get-Date
        $initDuration = ($initEndTime - $initStartTime).TotalSeconds
        Write-LogMessage "Disk initialization completed in $initDuration seconds" "INFO"
        
        if (-not $diskResult.Success) {
            $errorMsg = if ($diskResult.Error) { $diskResult.Error } else { $diskResult.Message }
            throw "Initialize-SystemDisk failed: $errorMsg"
        }
        
        # Verify the drives actually exist
        $systemDrive = $diskResult.SystemDrive
        $windowsDrive = $diskResult.WindowsDrive
        
        Write-LogMessage "Verifying created drives: System=$systemDrive, Windows=$windowsDrive" "INFO"
        
        if (-not (Test-Path "$systemDrive\")) {
            throw "System drive $systemDrive was not created or is not accessible"
        }
        
        if (-not (Test-Path "$windowsDrive\")) {
            throw "Windows drive $windowsDrive was not created or is not accessible"
        }
        
        Write-LogMessage "Disk initialization completed successfully" "SUCCESS"
        
        return @{
            Success = $true
            WindowsDrive = $diskResult.WindowsDrive
            SystemDrive = $diskResult.SystemDrive
            RecoveryDrive = $diskResult.RecoveryDrive
            DiskNumber = $diskResult.DiskNumber
            Duration = $initDuration
        }
    }
    catch {
        Write-LogMessage "Failed to initialize disk: $_" "ERROR"
        
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Get-WindowsImageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath
    )
    
    try {
        # For direct image paths (including mounted ISO install.wim), use the path as-is
        if ($ImagePath -match "^[A-Za-z]:\\" -or $ImagePath -like "*install.wim" -or $ImagePath -like "*install.esd") {
            $imageFullPath = $ImagePath
        } else {
            # Legacy path resolution for relative paths
            if ($ImagePath -like "*BaseImages*") {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\BaseImages\Windows" $ImagePath } else { $ImagePath }
            } elseif ($ImagePath -like "*CustomerImages*") {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\CustomerImages" $ImagePath } else { $ImagePath }
            } else {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\BaseImages\Windows" $ImagePath } else { $ImagePath }
            }
        }
        
        Write-LogMessage "Getting image info from: $imageFullPath" "VERBOSE"
        
        $dismOutput = & dism.exe /Get-WimInfo /WimFile:"$imageFullPath" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "DISM failed to get image info"
        }
        
        # Parse output to get image count
        $imageCount = 0
        foreach ($line in $dismOutput) {
            if ($line -match "Index\s*:\s*(\d+)") {
                $imageCount = [Math]::Max($imageCount, [int]$matches[1])
            }
        }
        
        return @{
            ImageCount = $imageCount
            Output = $dismOutput
        }
    }
    catch {
        Write-LogMessage "Failed to get image info: $_" "ERROR"
        return $null
    }
}

function Install-WindowsFromWim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        
        [Parameter(Mandatory)]
        [int]$ImageIndex,
        
        [Parameter(Mandatory)]
        [string]$TargetDrive
    )
    
    try {
        Write-LogMessage "Applying Windows image from $ImagePath (index: $ImageIndex) to $TargetDrive" "INFO"
        
        # For direct image paths (including mounted ISO install.wim), use the path as-is
        if ($ImagePath -match "^[A-Za-z]:\\" -or $ImagePath -like "*install.wim" -or $ImagePath -like "*install.esd") {
            $imageFullPath = $ImagePath
        } else {
            # Legacy path resolution for relative paths
            if ($ImagePath -like "*BaseImages*") {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\BaseImages\Windows" $ImagePath } else { $ImagePath }
            } elseif ($ImagePath -like "*CustomerImages*") {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\CustomerImages" $ImagePath } else { $ImagePath }
            } else {
                $imageFullPath = if ($ImagePath -notmatch '^[A-Za-z]:\\') { Join-Path "$ImagesRoot\BaseImages\Windows" $ImagePath } else { $ImagePath }
            }
        }

        Write-LogMessage "Resolved image path: $imageFullPath" "INFO"

        # Ensure DISM is available
        $dismPath = (Get-Command dism.exe -ErrorAction SilentlyContinue).Source
        if (-not $dismPath) {
            Write-LogMessage "DISM.exe not found in PATH" "ERROR"
            throw "DISM.exe not found in PATH"
        }

        # Format target drive
        $formattedDrive = $TargetDrive.TrimEnd('\')
        if (-not $formattedDrive.EndsWith(':')) {
            $formattedDrive = $formattedDrive + ":"
        }
        
        Write-LogMessage "Formatted target drive: $formattedDrive" "INFO"
        
        # Verify paths exist
        if (-not (Test-Path $imageFullPath)) {
            Write-LogMessage "Image file not found: $imageFullPath" "ERROR"
            throw "Image file not found: $imageFullPath"
        }
        
        if (-not (Test-Path "$formattedDrive\")) {
            Write-LogMessage "Target drive not accessible: $formattedDrive" "ERROR"
            throw "Target drive not accessible: $formattedDrive"
        }
        
        Write-LogMessage "Both image file and target drive verified" "INFO"
        Write-LogMessage "Starting DISM image application..." "INFO"
        
        # Build DISM command
        $dismArgs = @(
            "/Apply-Image"
            "/ImageFile:$imageFullPath"
            "/Index:$ImageIndex"
            "/ApplyDir:$formattedDrive\"
        )
        
        $dismCommand = "$dismPath $($dismArgs -join ' ')"
        Write-LogMessage "DISM command: $dismCommand" "INFO"
        
        # Execute DISM and capture all output
        $dismStartTime = Get-Date
        Write-LogMessage "Starting DISM execution at $dismStartTime" "INFO"
        
        $dismOutput = & $dismPath $dismArgs 2>&1
        $dismEndTime = Get-Date
        $dismDuration = ($dismEndTime - $dismStartTime).TotalSeconds
        
        Write-LogMessage "DISM execution completed in $dismDuration seconds" "INFO"
        Write-LogMessage "DISM exit code: $LASTEXITCODE" "INFO"
        
        # Log ALL DISM output
        if ($dismOutput) {
            Write-LogMessage "DISM output ($($dismOutput.Count) lines):" "INFO"
            foreach ($line in $dismOutput) {
                Write-LogMessage "[DISM] $line" "VERBOSE"
            }
        } else {
            Write-LogMessage "DISM produced no output" "WARNING"
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "DISM apply failed with exit code $LASTEXITCODE" "ERROR"
            throw "DISM apply failed with exit code $LASTEXITCODE. Output: $($dismOutput -join "`n")"
        }
        
        # Check if DISM actually did something by looking for progress indicators
        $progressFound = $dismOutput | Where-Object { $_ -match "progress|applying|extracting|copying" }
        if (-not $progressFound) {
            Write-LogMessage "WARNING: No progress indicators found in DISM output" "WARNING"
        }
        
        # Wait for file system to settle
        Write-LogMessage "Waiting for file system to settle..." "INFO"
        Start-Sleep -Seconds 5
        
        # Verify Windows directory exists
        $windowsPath = "$formattedDrive\Windows"
        Write-LogMessage "Checking for Windows directory at: $windowsPath" "INFO"
        
        if (-not (Test-Path $windowsPath)) {
            # List what's actually in the target drive
            $driveContents = Get-ChildItem "$formattedDrive\" -ErrorAction SilentlyContinue | Select-Object Name, Length
            $contentsString = ($driveContents | ForEach-Object { "$($_.Name) ($($_.Length) bytes)" }) -join ", "
            Write-LogMessage "Target drive contents: $contentsString" "ERROR"
            Write-LogMessage "Windows directory not found after image application: $windowsPath" "ERROR"
            throw "Windows directory not found after image application: $windowsPath"
        }
        
        $system32Path = "$windowsPath\System32"
        if (-not (Test-Path $system32Path)) {
            Write-LogMessage "System32 directory not found: $system32Path" "ERROR"
            throw "System32 directory not found: $system32Path"
        }
        
        # Additional verification - check for key Windows files
        $keyFiles = @(
            "$windowsPath\System32\ntoskrnl.exe",
            "$windowsPath\System32\kernel32.dll",
            "$windowsPath\System32\config\SYSTEM"
        )
        
        foreach ($keyFile in $keyFiles) {
            if (-not (Test-Path $keyFile)) {
                Write-LogMessage "Key Windows file missing: $keyFile" "WARNING"
            } else {
                Write-LogMessage "Verified key file: $keyFile" "INFO"
            }
        }
        
        Write-LogMessage "Windows image applied successfully to $formattedDrive" "SUCCESS"
        
        return @{
            Success = $true
            TargetDrive = $formattedDrive
            WindowsPath = $windowsPath
        }
    }
    catch {
        Write-LogMessage "Failed to apply Windows image: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Install-WindowsFromFFU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        [Parameter(Mandatory)]
        [string]$TargetDrive
    )
    try {
        Write-LogMessage "Applying FFU image from $ImagePath to $TargetDrive" "INFO"
        # Format target drive (should be a physical drive, e.g., \\.\PhysicalDrive0)
        $physicalDrive = $TargetDrive
        $resolved = $false
        # If TargetDrive is a drive letter, resolve to physical drive
        if ($TargetDrive -match '^[A-Za-z]:') {
            try {
                $partition = Get-Partition -DriveLetter $TargetDrive[0] -ErrorAction Stop
                $disk = $partition | Get-Disk -ErrorAction Stop | Select-Object -First 1
                if ($disk) {
                    $physicalDrive = "\\.\PhysicalDrive$($disk.Number)"
                    Write-LogMessage "Auto-resolved $TargetDrive to physical drive $physicalDrive for FFU deployment" "INFO"
                    $resolved = $true
                }
            } catch {
                Write-LogMessage "Could not auto-resolve $TargetDrive to a physical disk. Will prompt user." "WARNING"
                $resolved = $false
            }
        }
        if (-not $resolved) {
            # Enumerate all disks using Get-PSDrive/Get-Partition/Get-Disk for robust info
            $diskInfoList = @()
            $driveLetters = (Get-PSDrive -PSProvider FileSystem).Name | Where-Object { $_ -match '^[a-zA-Z]$' }
            foreach ($letter in $driveLetters) {
                try {
                    $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
                    $disk = $part | Get-Disk -ErrorAction Stop
                    foreach ($d in $disk) {
                        $diskInfoList += [PSCustomObject]@{
                            DriveLetter = $letter
                            DiskNumber = $d.Number
                            FriendlyName = $d.FriendlyName
                            SizeGB = [math]::Round($d.Size/1GB,2)
                        }
                    }
                } catch {}
            }
            # Fallback: If no drive letters found, enumerate all disks
            if ($diskInfoList.Count -eq 0) {
                $allDisks = Get-Disk | Where-Object { $_.PartitionStyle -ne 'RAW' }
                foreach ($d in $allDisks) {
                    $diskInfoList += [PSCustomObject]@{
                        DriveLetter = ''
                        DiskNumber = $d.Number
                        FriendlyName = $d.FriendlyName
                        SizeGB = [math]::Round($d.Size/1GB,2)
                    }
                }
            }
            if ($diskInfoList.Count -eq 0) {
                throw "No physical disks found for FFU deployment."
            }
            Write-Host "Available disks for FFU deployment:" -ForegroundColor Yellow
            $diskInfoList | ForEach-Object {
                $dl = if ($_.DriveLetter) { "[$($_.DriveLetter)]" } else { '' }
                Write-Host ("[{0}] {1} {2} - {3} GB" -f $_.DiskNumber, $dl, $_.FriendlyName, $_.SizeGB) -ForegroundColor Cyan
            }
            # Auto-select if only one disk
            if ($diskInfoList.Count -eq 1) {
                $selectedDisk = $diskInfoList[0]
                Write-Host ("Only one disk found. Auto-selecting Disk {0} {1} - {2} GB" -f $selectedDisk.DiskNumber, $selectedDisk.FriendlyName, $selectedDisk.SizeGB) -ForegroundColor Green
            } else {
                $selectedDisk = $null
                while ($null -eq $selectedDisk) {
                    $userInput = Read-Host "Enter the Disk Number to deploy the FFU image to"
                    $match = $diskInfoList | Where-Object { $_.DiskNumber -eq [int]$userInput }
                    if ($match) {
                        $selectedDisk = $match
                      } else {
                        Write-Host "Invalid selection. Please enter a valid Disk Number from the list above." -ForegroundColor Red
                      }
                  }
            }
            $physicalDrive = "\\.\PhysicalDrive$($selectedDisk.DiskNumber)"
            Write-LogMessage "User selected physical drive $physicalDrive for FFU deployment" "INFO"
        }
        # Ensure DISM is available
        $dismPath = (Get-Command dism.exe -ErrorAction SilentlyContinue).Source
        if (-not $dismPath) {
            Write-LogMessage "DISM.exe not found in PATH" "ERROR"
            throw "DISM.exe not found in PATH"
        }
        # Build DISM command for FFU
        $dismArgs = @(
            "/Apply-FFU"
            "/ImageFile:$ImagePath"
            "/ApplyDrive:$physicalDrive"
        )
        $dismCommand = "$dismPath $($dismArgs -join ' ')"
        Write-LogMessage "DISM FFU command: $dismCommand" "INFO"
        $dismStartTime = Get-Date
        $dismOutput = & $dismPath $dismArgs 2>&1
        $dismEndTime = Get-Date
        $dismDuration = ($dismEndTime - $dismStartTime).TotalSeconds
        Write-LogMessage "DISM FFU execution completed in $dismDuration seconds" "INFO"
        Write-LogMessage "DISM exit code: $LASTEXITCODE" "INFO"
        if ($dismOutput) {
            foreach ($line in $dismOutput) {
                Write-LogMessage "[DISM-FFU] $line" "VERBOSE"
            }
        }
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "DISM FFU apply failed with exit code $LASTEXITCODE" "ERROR"
            throw "DISM FFU apply failed with exit code $LASTEXITCODE. Output: $($dismOutput -join '`n')"
        }
        Write-LogMessage "FFU image applied successfully to $physicalDrive" "SUCCESS"
        return @{ Success = $true; TargetDrive = $physicalDrive }
    } catch {
        Write-LogMessage "Failed to apply FFU image: $_" "ERROR"
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Get-DriverPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo
    )
    
    $deviceMake = Clean-DeviceName -Name $DeviceInfo.Manufacturer
    $deviceModel = Clean-DeviceName -Name $DeviceInfo.Model
    
    $driverPaths = @(
        "V:\$deviceMake\$deviceModel"
    )
    
    foreach ($path in $driverPaths) {
        if (Test-Path $path) {
            Write-LogMessage "Found driver path: $path" "INFO"
            return $path
        }
    }
    
    Write-LogMessage "No driver path found for $deviceMake\$deviceModel" "WARNING"
    return $null
}

function Install-DriversToWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory)]
        [string]$DriverPath
    )
    
    try {
        Write-LogMessage "Installing drivers from $DriverPath to $WindowsDrive" "INFO"
        
        # Verify driver path exists
        if (-not (Test-Path $DriverPath)) {
            Write-LogMessage "Driver path does not exist: $DriverPath" "ERROR"
            return @{
                Success = $false
                Message = "Driver path does not exist: $DriverPath"
            }
        }
        
        # Count .inf files in driver path
        $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
        Write-LogMessage "Found $($infFiles.Count) .inf files in driver path" "INFO"
        
        if ($infFiles.Count -eq 0) {
            Write-LogMessage "No .inf files found in driver path" "WARNING"
            return @{
                Success = $false
                Message = "No .inf files found in driver path"
            }
        }
        
        $formattedDrive = $WindowsDrive.TrimEnd('\').TrimEnd(':') + ":"
        
        # Verify Windows installation exists
        if (-not (Test-Path "$formattedDrive\Windows\System32")) {
            Write-LogMessage "Windows installation not found at $formattedDrive" "ERROR"
            return @{
                Success = $false
                Message = "Windows installation not found at $formattedDrive"
            }
        }
        
        Write-LogMessage "Starting DISM driver installation..." "INFO"
        $dismStartTime = Get-Date
        
        # Build DISM command properly
        $dismArgs = @(
            "/Image:$formattedDrive"
            "/Add-Driver"
            "/Driver:$DriverPath"
            "/Recurse"
        )
        
        $dismCommand = "dism.exe $($dismArgs -join ' ')"
        Write-LogMessage "DISM driver command: $dismCommand" "INFO"
        
        $dismOutput = & dism.exe $dismArgs 2>&1
        
        $dismEndTime = Get-Date
        $dismDuration = ($dismEndTime - $dismStartTime).TotalSeconds
        Write-LogMessage "DISM driver installation completed in $dismDuration seconds" "INFO"
        Write-LogMessage "DISM exit code: $LASTEXITCODE" "INFO"
        
        # Log driver installation output
        if ($dismOutput) {
            foreach ($line in $dismOutput) {
                Write-LogMessage "[DISM-Driver] $line" "VERBOSE"
            }
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "Drivers installed successfully" "SUCCESS"
            return @{ Success = $true }
        } else {
            Write-LogMessage "DISM driver installation failed with exit code $LASTEXITCODE" "ERROR"
            throw "DISM driver installation failed: $($dismOutput -join "`n")"
        }
    }
    catch {
        Write-LogMessage "Failed to install drivers: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Set-WindowsBoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory)]
        [string]$SystemDrive
    )
    
    try {
        Write-LogMessage "Configuring Windows boot..." "INFO"
        
        # Ensure proper drive formatting with colons
        $formattedWindowsDrive = $WindowsDrive.TrimEnd('\').TrimEnd(':') + ":"
        $formattedSystemDrive = $SystemDrive.TrimEnd('\').TrimEnd(':') + ":"
        
        Write-LogMessage "Formatted drives - Windows: $formattedWindowsDrive, System: $formattedSystemDrive" "INFO"
        
        $bcdbootPath = "$formattedWindowsDrive\Windows\System32\bcdboot.exe"
        
        # Verify bcdboot exists
        if (-not (Test-Path $bcdbootPath)) {
            Write-LogMessage "BCDBoot not found at: $bcdbootPath" "ERROR"
            throw "BCDBoot not found at: $bcdbootPath"
        }
        
        Write-LogMessage "Found BCDBoot at: $bcdbootPath" "INFO"
        
        $bcdbootArgs = @(
            "$formattedWindowsDrive\Windows"
            "/s"
            "$formattedSystemDrive"
            "/f"
            "UEFI"
        )
        
        $bcdbootCommand = "$bcdbootPath $($bcdbootArgs -join ' ')"
        Write-LogMessage "BCDBoot command: $bcdbootCommand" "INFO"
        
        $bcdbootStartTime = Get-Date
        $output = & $bcdbootPath $bcdbootArgs 2>&1
        $bcdbootEndTime = Get-Date
        $bcdbootDuration = ($bcdbootEndTime - $bcdbootStartTime).TotalSeconds
        
        Write-LogMessage "BCDBoot completed in $bcdbootDuration seconds" "INFO"
        Write-LogMessage "BCDBoot exit code: $LASTEXITCODE" "INFO"
        
        if ($output) {
            foreach ($line in $output) {
                Write-LogMessage "[BCDBoot] $line" "INFO"
            }
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "BCDBoot failed with exit code $LASTEXITCODE" "ERROR"
            throw "BCDBoot failed: $($output -join "`n")"
        }
        
        # Verify boot files were created
        $bootFiles = @(
            "$formattedSystemDrive\EFI\Microsoft\Boot\bootmgfw.efi",
            "$formattedSystemDrive\EFI\Boot\bootx64.efi"
        )
        
        foreach ($bootFile in $bootFiles) {
            if (Test-Path $bootFile) {
                Write-LogMessage "Verified boot file: $bootFile" "INFO"
            } else {
                Write-LogMessage "Boot file not found: $bootFile" "WARNING"
            }
        }
        
        Write-LogMessage "Boot configuration completed successfully" "SUCCESS"
        
        return @{ Success = $true }
    }
    catch {
        Write-LogMessage "Failed to configure boot: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Install-WindowsUpdatesToWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory)]
        [string]$ImagePath
    )
    
    try {
        Write-LogMessage "Starting Windows updates installation..." "INFO"
        
        $hotfixesPath = "Y:\DeploymentHotfixes"
        
        # Verify hotfixes root path exists
        if (-not (Test-Path $hotfixesPath)) {
            Write-LogMessage "Hotfixes root path does not exist: $hotfixesPath" "WARNING"
            return @{
                Success = $true
                Message = "No hotfixes directory found - skipping updates"
                UpdatesInstalled = 0
            }
        }
        
        # Determine Windows version and build from image metadata (ImageConfig)
        $windowsVersion = $null
        $windowsBuild = $null
        if ($ImageConfig -and $ImageConfig.ContainsKey('WindowsVersion')) {
            $windowsVersion = $ImageConfig.WindowsVersion
        }
        if ($ImageConfig -and $ImageConfig.ContainsKey('WindowsBuild')) {
            $windowsBuild = $ImageConfig.WindowsBuild
        }
        Write-LogMessage "Detected Windows version from image metadata: Version=$windowsVersion, Build=$windowsBuild" "INFO"
        
        if (-not $windowsVersion) {
            Write-LogMessage "Could not determine Windows version from image metadata" "WARNING"
            return @{
                Success = $true
                Message = "Could not determine Windows version - skipping targeted updates"
                UpdatesInstalled = 0
            }
        }
        
        # Look for version and build-specific hotfix folders in priority order
        $versionPaths = @()
        
        # First priority: Specific version and build (e.g., Windows11\24H2)
        if ($windowsBuild) {
            $versionPaths += "$hotfixesPath\Windows$windowsVersion\$windowsBuild"
        }
        
        # Second priority: Version folder (e.g., Windows11)
        $versionPaths += "$hotfixesPath\Windows$windowsVersion"
        
        # Third priority: Short version format (e.g., Win11)
        $versionPaths += "$hotfixesPath\Win$windowsVersion"
        
        # Fourth priority: Just the version number (e.g., 11)
        $versionPaths += "$hotfixesPath\$windowsVersion"
        
        # Last priority: Root folder
        $versionPaths += $hotfixesPath
        
        Write-LogMessage "Searching for updates in paths: $($versionPaths -join ', ')" "INFO"
        
        $cabFiles = @()
        $foundPaths = @()
        
        foreach ($versionPath in $versionPaths) {
            if (Test-Path $versionPath) {
                Write-LogMessage "Scanning for CAB files in: $versionPath" "INFO"
                $foundCabs = Get-ChildItem -Path $versionPath -Filter "*.cab" -Recurse -ErrorAction SilentlyContinue
                
                foreach ($cab in $foundCabs) {
                    # Skip if already added (in case of overlapping paths)
                    if ($cabFiles | Where-Object { $_.FullName -eq $cab.FullName }) {
                        continue
                    }
                    
                    $cabFiles += $cab
                    Write-LogMessage "Found update: $($cab.Name) ($([Math]::Round($cab.Length / 1MB, 2)) MB) in $versionPath" "INFO"
                }
                
                if ($foundCabs.Count -gt 0) {
                    $foundPaths += $versionPath
                }
            } else {
                Write-LogMessage "Path does not exist: $versionPath" "VERBOSE"
            }
        }
        
        if ($cabFiles.Count -eq 0) {
            Write-LogMessage "No CAB update files found for Windows $windowsVersion" "INFO"
            return @{
                Success = $true
                Message = "No updates found for Windows $windowsVersion"
                UpdatesInstalled = 0
            }
        }
        
        Write-LogMessage "Found $($cabFiles.Count) update files for Windows $windowsVersion from paths: $($foundPaths -join ', ')" "INFO"
        $totalSize = [Math]::Round(($cabFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        Write-LogMessage "Total updates size: $totalSize MB" "INFO"
        
        # Format target drive path
        $formattedDrive = $WindowsDrive.TrimEnd('\').TrimEnd(':') + ":"
        
        # Verify Windows installation exists
        if (-not (Test-Path "$formattedDrive\Windows\System32")) {
            Write-LogMessage "Windows installation not found at $formattedDrive" "ERROR"
            return @{
                Success = $false
                Message = "Windows installation not found at $formattedDrive"
                UpdatesInstalled = 0
            }
        }
        
        Write-LogMessage "Starting DISM updates installation to $formattedDrive..." "INFO"
        $updatesStartTime = Get-Date
        
        $successfulUpdates = 0
        $failedUpdates = 0
        $skippedUpdates = 0
        
        # Install updates one by one for better error tracking and progress
        $updateCount = 0
        foreach ($cabFile in $cabFiles) {
            $updateCount++
            try {
                Write-LogMessage "Installing update $updateCount of $($cabFiles.Count): $($cabFile.Name)" "INFO"
                
                # Update progress during update installation
                $updateProgress = 80 + ([int](($updateCount / $cabFiles.Count) * 10))
                Update-DeploymentProgress -PercentComplete $updateProgress -Status "Installing update $updateCount of $($cabFiles.Count): $($cabFile.Name)"
                
                $dismArgs = @(
                    "/Image:$formattedDrive"
                    "/Add-Package"
                    "/PackagePath:$($cabFile.FullName)"
                    "/LogPath:$env:TEMP\dism_update_$($cabFile.BaseName).log"
                    "/Quiet"
                )
                
                Write-LogMessage "DISM update command: dism.exe $($dismArgs -join ' ')" "VERBOSE"
                
                $updateStartTime = Get-Date
                $dismOutput = & dism.exe $dismArgs 2>&1
                $updateEndTime = Get-Date
                $updateDuration = ($updateEndTime - $updateStartTime).TotalSeconds
                
                Write-LogMessage "Update $($cabFile.Name) processed in $updateDuration seconds" "INFO"
                Write-LogMessage "DISM exit code: $LASTEXITCODE" "VERBOSE"
                
                # Log DISM output for this update (but only errors and important info)
                if ($dismOutput) {
                    $importantLines = $dismOutput | Where-Object { 
                        $_ -match "error|fail|success|complete|progress" -or 
                        $_ -match "package|operation" 
                    }
                    foreach ($line in $importantLines) {
                        Write-LogMessage "[DISM-Update-$($cabFile.BaseName)] $line" "VERBOSE"
                    }
                }
                
                # Handle different DISM exit codes
                if ($LASTEXITCODE -eq 0) {
                    $successfulUpdates++
                    Write-LogMessage "Successfully installed update: $($cabFile.Name)" "SUCCESS"
                } elseif ($LASTEXITCODE -eq 0x800f081e) {
                    # Package not applicable to this image
                    $skippedUpdates++
                    Write-LogMessage "Update not applicable to this Windows version: $($cabFile.Name)" "INFO"
                } elseif ($LASTEXITCODE -eq 0x800f0823) {
                    # Package already installed
                    $skippedUpdates++
                    Write-LogMessage "Update already installed: $($cabFile.Name)" "INFO"
                } elseif ($LASTEXITCODE -eq 0x800f0922) {
                    # Reboot required (but we're offline, so this is OK)
                    $successfulUpdates++
                    Write-LogMessage "Update installed successfully (reboot required): $($cabFile.Name)" "SUCCESS"
                } else {
                    $failedUpdates++
                    Write-LogMessage "Failed to install update $($cabFile.Name) with exit code 0x$($LASTEXITCODE.ToString('X8'))" "WARNING"
                    
                    # Log detailed error if available
                    $errorLines = $dismOutput | Where-Object { $_ -match "error|fail" }
                    if ($errorLines) {
                        foreach ($errorLine in $errorLines) {
                            Write-LogMessage "[DISM-ERROR] $errorLine" "WARNING"
                        }
                    }
                }
                
            } catch {
                $failedUpdates++
                Write-LogMessage "Exception installing update $($cabFile.Name): $_" "ERROR"
            }
        }
        
        $updatesEndTime = Get-Date
        $totalUpdateDuration = ($updatesEndTime - $updatesStartTime).TotalSeconds
        Write-LogMessage "Updates installation completed in $([Math]::Round($totalUpdateDuration / 60, 2)) minutes" "INFO"
        Write-LogMessage "Updates summary: $successfulUpdates successful, $skippedUpdates skipped, $failedUpdates failed" "INFO"
        
        # Cleanup DISM image to reduce size and free up space
        try {
            Write-LogMessage "Performing component store cleanup to reduce image size..." "INFO"
            Update-DeploymentProgress -PercentComplete 89 -Status "Cleaning up component store..."
            
            $cleanupArgs = @(
                "/Image:$formattedDrive"
                "/Cleanup-Image"
                "/StartComponentCleanup"
                "/ResetBase"
                "/Quiet"
            )
            
            $cleanupStartTime = Get-Date
            $cleanupOutput = & dism.exe $cleanupArgs 2>&1
            $cleanupEndTime = Get-Date
            $cleanupDuration = ($cleanupEndTime - $cleanupStartTime).TotalSeconds
            
            Write-LogMessage "Component cleanup completed in $([Math]::Round($cleanupDuration / 60, 2)) minutes" "INFO"
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Component store cleanup completed successfully" "SUCCESS"
            } else {
                Write-LogMessage "Component store cleanup failed with exit code 0x$($LASTEXITCODE.ToString('X8'))" "WARNING"
                # Log cleanup errors but don't fail the deployment
                $cleanupErrors = $cleanupOutput | Where-Object { $_ -match "error|fail" }
                foreach ($cleanupError in $cleanupErrors) {
                    Write-LogMessage "[CLEANUP-ERROR] $cleanupError" "WARNING"
                }
            }
            
        } catch {
            Write-LogMessage "Exception during component cleanup: $_" "WARNING"
        }
        
        # Generate summary message
        $resultMessage = if ($failedUpdates -eq 0) {
            if ($skippedUpdates -gt 0) {
                "$successfulUpdates updates installed, $skippedUpdates skipped (not applicable)"
            } else {
                "All $successfulUpdates updates installed successfully"
            }
        } else {
            "$successfulUpdates updates installed, $skippedUpdates skipped, $failedUpdates failed"
        }
        
        Write-LogMessage "Windows updates installation completed: $resultMessage" "SUCCESS"
        
        return @{
            Success = $true
            Message = $resultMessage
            UpdatesInstalled = $successfulUpdates
            UpdatesSkipped = $skippedUpdates
            UpdatesFailed = $failedUpdates
            TotalSize = $totalSize
            Duration = $totalUpdateDuration
            CleanupPerformed = $true
        }
    }
    catch {
        Write-LogMessage "Failed to install Windows updates: $_" "ERROR"
            return @{
                Success = $false
                Message = $_.Exception.Message
                UpdatesInstalled = 0
            }
        }
    }

function Set-UnattendFileToWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [string]$UnattendSourcePath
    )
    
    try {
        Write-LogMessage "Starting unattend file application..." "INFO"
        
        # Format target drive path
        $formattedDrive = $WindowsDrive.TrimEnd('\').TrimEnd(':') + ":"
        
        # Verify Windows installation exists
        if (-not (Test-Path "$formattedDrive\Windows\System32")) {
            Write-LogMessage "Windows installation not found at $formattedDrive" "ERROR"
            return @{
                Success = $false
                Message = "Windows installation not found at $formattedDrive"
            }
        }
        
        # Look for customer-specific unattend file first
        $customerUnattendPath = "Y:\DeploymentModules\Config\CustomerConfig\$CustomerName\$ImageID\Unattend.xml"
        $defaultUnattendPath = "Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Unattend.xml"
        
        $unattendSourcePath = $null
        
        if (Test-Path $customerUnattendPath) {
            $unattendSourcePath = $customerUnattendPath
            Write-LogMessage "Using customer-specific unattend file: $customerUnattendPath" "INFO"
        } elseif (Test-Path $defaultUnattendPath) {
            $unattendSourcePath = $defaultUnattendPath
            Write-LogMessage "Using default unattend file: $defaultUnattendPath" "INFO"
        } else {
            Write-LogMessage "No unattend file found (checked customer-specific and default locations)" "WARNING"
            return @{
                Success = $true
                Message = "No unattend file found - skipping unattend application"
            }
        }
        
        # Target path for unattend file in Windows installation
        $targetUnattendPath = "$formattedDrive\Windows\Panther\unattend.xml"
        $pantherPath = "$formattedDrive\Windows\Panther"
        
        # Create Panther directory if it doesn't exist
        if (-not (Test-Path $pantherPath)) {
            try {
                New-Item -Path $pantherPath -ItemType Directory -Force | Out-Null
                Write-LogMessage "Created Panther directory: $pantherPath" "INFO"
            } catch {
                Write-LogMessage "Failed to create Panther directory: $_" "ERROR"
                return @{
                    Success = $false
                    Message = "Failed to create Panther directory: $_"
                }
            }
        }
        
        # Copy unattend file to target location
        try {
            Copy-Item -Path $unattendSourcePath -Destination $targetUnattendPath -Force
            Write-LogMessage "Copied unattend file from $unattendSourcePath to $targetUnattendPath" "INFO"
        } catch {
            Write-LogMessage "Failed to copy unattend file: $_" "ERROR"
            return @{
                Success = $false
                Message = "Failed to copy unattend file: $_"
            }
        }
        
        # Verify the file was copied
        if (-not (Test-Path $targetUnattendPath)) {
            Write-LogMessage "Unattend file not found at target location after copy" "ERROR"
            return @{
                Success = $false
                Message = "Unattend file not found at target location after copy"
            }
        }
        
        # Apply unattend file using DISM
        Write-LogMessage "Applying unattend file using DISM..." "INFO"
        $dismStartTime = Get-Date
        
        $dismArgs = @(
            "/Image:$formattedDrive\\"
            "/Apply-Unattend:$targetUnattendPath"
            "/LogPath:$env:TEMP\dism_unattend.log"
        )
        
        Write-LogMessage "DISM unattend command: dism.exe $($dismArgs -join ' ')" "VERBOSE"
        
        $dismOutput = & dism.exe $dismArgs 2>&1
        $dismEndTime = Get-Date
        $dismDuration = ($dismEndTime - $dismStartTime).TotalSeconds
        
        Write-LogMessage "DISM unattend application completed in $dismDuration seconds" "INFO"
        Write-LogMessage "DISM exit code: $LASTEXITCODE" "VERBOSE"
        
        # Log DISM output
        if ($dismOutput) {
            foreach ($line in $dismOutput) {
                Write-LogMessage "[DISM-Unattend] $line" "VERBOSE"
            }
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "Unattend file applied successfully" "SUCCESS"
            
            # Get file size for reporting
            $fileInfo = Get-Item $targetUnattendPath
            $fileSizeKB = [Math]::Round($fileInfo.Length / 1KB, 2)
            
            return @{
                Success = $true
                Message = "Unattend file applied successfully ($fileSizeKB KB)"
                SourcePath = $unattendSourcePath
                TargetPath = $targetUnattendPath
                Duration = $dismDuration
            }
        } else {
            Write-LogMessage "DISM unattend application failed with exit code $LASTEXITCODE" "WARNING"
            
            # Check for specific error patterns
            $errorMessage = "DISM unattend application failed"
            if ($dismOutput -match "not valid|invalid|malformed") {
                $errorMessage += " - Invalid unattend file format"
            } elseif ($dismOutput -match "access denied|permission") {
                $errorMessage += " - Access denied"
            }
            
            return @{
                Success = $false
                Message = "$errorMessage (exit code $LASTEXITCODE)"
                SourcePath = $unattendSourcePath
                DismOutput = $dismOutput -join "`n"
            }
        }
        
    } catch {
        Write-LogMessage "Exception during unattend file application: $_" "ERROR"
        return @{
            Success = $false
            Message = "Exception during unattend file application: $($_.Exception.Message)"
        }
    }
}

function Get-DriversFromDisk0 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo
    )
    
    try {
        Write-LogMessage "Starting driver harvesting from existing Windows installation on disk 0..." "INFO"
        
        # First, check if disk 0 has any Windows partitions
        $existingWindowsPartitions = Find-ExistingWindowsPartitions
        
        if ($existingWindowsPartitions.Count -eq 0) {
            Write-LogMessage "No existing Windows partitions found on disk 0 - skipping driver harvest" "INFO"
            return @{
                Success = $false
                Message = "No existing Windows partitions found"
            }
        }
        
        Write-LogMessage "Found $($existingWindowsPartitions.Count) existing Windows partition(s)" "INFO"
        
        # Create output path directly on V: drive instead of temp
        $deviceMake = Clean-DeviceName -Name $DeviceInfo.Manufacturer
        $deviceModel = Clean-DeviceName -Name $DeviceInfo.Model
        $vDriveDriverPath = "V:\$deviceMake\$deviceModel"
        
               
        # Check if V: drive is available
        if (-not (Test-Path "V:\")) {
            Write-LogMessage "V: drive not available - cannot save harvested drivers to repository" "WARNING"
            # Fall back to temporary path for immediate use only
            $outputPath = "$env:TEMP\HarvestedDrivers_$(Get-Random)"
            $useVDrive = $false
        } else {
            $outputPath = $vDriveDriverPath
            $useVDrive = $true
            Write-LogMessage "Will harvest drivers directly to V: drive at: $outputPath" "INFO"
        }
        
        $harvestedDrivers = 0
        
        try {
            # Create output directory
            if (-not (Test-Path $outputPath)) {
                New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
                Write-LogMessage "Created driver harvest directory: $outputPath" "INFO"
            }
            
            foreach ($windowsPartition in $existingWindowsPartitions) {
                Write-LogMessage "Harvesting drivers from: $windowsPartition" "INFO"
                try {
                    # Create subfolder for this partition
                    $partitionOutputPath = Join-Path $outputPath "AutoHarvest_$($windowsPartition.Replace(':', ''))"
                    if (-not (Test-Path $partitionOutputPath)) {
                        New-Item -Path $partitionOutputPath -ItemType Directory -Force | Out-Null
                    }
                    
                    # Use DISM to export drivers from the existing Windows installation directly to V: drive
                    $dismArgs = @(
                        "/Image:$windowsPartition"
                        "/Export-Driver"
                        "/Destination:$partitionOutputPath"
                    )
                    
                    Write-LogMessage "DISM export command: dism.exe $($dismArgs -join ' ')" "VERBOSE"
                    
                    $exportStartTime = Get-Date
                    $dismOutput = & dism.exe $dismArgs 2>&1
                    $exportEndTime = Get-Date
                    $exportDuration = ($exportEndTime - $exportStartTime).TotalSeconds
                    
                    Write-LogMessage "Driver export completed in $exportDuration seconds" "INFO"
                    Write-LogMessage "DISM exit code: $LASTEXITCODE" "VERBOSE"
                    
                    # Log important DISM output
                    if ($dismOutput) {
                        $importantLines = $dismOutput | Where-Object { 
                            $_ -match "exported|driver|error|success|complete" 
                        }
                        foreach ($line in $importantLines) {
                            Write-LogMessage "[DISM-Export] $line" "VERBOSE"
                        }
                    }
                    
                    if ($LASTEXITCODE -eq 0) {
                        # Count exported drivers
                        $exportedInfFiles = Get-ChildItem -Path $partitionOutputPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
                        $driverCount = $exportedInfFiles.Count
                        Write-LogMessage "Successfully exported $driverCount driver packages from $windowsPartition" "SUCCESS"
                        $harvestedDrivers += $driverCount
                        
                        # If we got drivers from this partition, we can stop looking
                        if ($driverCount -gt 0) {
                            break
                        }
                    } else {
                        Write-LogMessage "Failed to export drivers from $windowsPartition (exit code: $LASTEXITCODE)" "WARNING"
                        # Continue to next partition
                        continue
                    }
                    
                } catch {
                    Write-LogMessage "Exception exporting drivers from $windowsPartition`: $_" "WARNING"
                    continue
                }
            }
            
            if ($harvestedDrivers -eq 0) {
                Write-LogMessage "No drivers were harvested from existing Windows installations" "INFO"
                return @{
                    Success = $false
                    Message = "No drivers found in existing Windows installations"
                }
            }
            
            Write-LogMessage "Total harvested drivers: $harvestedDrivers" "INFO"
            
            # Create harvest metadata directly in V: drive if using V: drive
            if ($useVDrive -and $harvestedDrivers -gt 0) {
                try {
                    $harvestMetadata = @{
                        DeviceInfo = $DeviceInfo
                        HarvestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        SourceType = "Auto-Harvest"
                        DriverCount = $harvestedDrivers
                        SourcePartitions = $existingWindowsPartitions -join ", "
                        ExportMethod = "Direct to V: drive (auto)"
                    }
                    
                    $metadataPath = Join-Path $outputPath "AutoDriverHarvestInfo.json"
                    $harvestMetadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Force
                    Write-LogMessage "Created auto-harvest metadata at: $metadataPath" "INFO"
                } catch {
                    Write-LogMessage "Failed to create auto-harvest metadata: $_" "WARNING"
                }
            }
            
            return @{
                Success = $true
                Message = "Harvested $harvestedDrivers driver packages"
                DriversHarvested = $harvestedDrivers
                SourcePartitions = $existingWindowsPartitions -join ", "
                DriverPath = $outputPath
            }
        } catch {
            # Clean up temporary directory on error if using temp path
            if (-not $useVDrive -and (Test-Path $outputPath)) {
                try {
                    Remove-Item -Path $outputPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    # Ignore cleanup errors
                }
            }
            throw
        }
    } catch {
        Write-LogMessage "Exception during driver harvesting: $_" "ERROR"
        return @{
            Success = $false
            Message = "Exception during driver harvesting: $($_.Exception.Message)"
        }
    }
}

function Find-ExistingWindowsPartitions {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Scanning for existing Windows partitions for driver harvesting..." "INFO"
        
        # Get all drive letters and check for Windows installations
        $existingPartitions = @()
        
        # Get all drives except the system drives
        $excludedDrives = @('V', 'W', 'X', 'Y', 'Z')  # Exclude all system drives from driver harvesting
        $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { 
            $_.Name -notin $excludedDrives -and $_.Name.Length -eq 1 
        }
        
        foreach ($drive in $allDrives) {
            $driveLetter = $drive.Name + ":"
            $windowsPath = "$driveLetter\Windows"
            $system32Path = "$windowsPath\System32"
            
            Write-LogMessage "Checking drive $driveLetter for Windows installation (excluding system drives: $($excludedDrives -join ', '))" "VERBOSE"
            
            if ((Test-Path $windowsPath) -and (Test-Path $system32Path)) {
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
                        Write-LogMessage "Drive $driveLetter appears to be WinPE - skipping for driver harvest" "INFO"
                        break
                    }
                }
                
                if ($isWinPE) {

                    continue  # Skip WinPE installations
                }
                
                # Additional verification - check for key Windows files
                $keyFiles = @(
                    "$system32Path\ntoskrnl.exe",
                    "$system32Path\kernel32.dll"
                )
                
                $validWindows = $true
                foreach ($keyFile in $keyFiles) {
                    if (-not (Test-Path $keyFile)) {
                        $validWindows = $false
                        break
                    }
                }
                
                if ($validWindows) {
                    Write-LogMessage "Found valid Windows installation for driver harvest on drive $driveLetter" "INFO"
                    $existingPartitions += $driveLetter
                } else {
                    Write-LogMessage "Drive $driveLetter has Windows folder but missing key files" "VERBOSE"
                }
            }
        }
        
        Write-LogMessage "Found $($existingPartitions.Count) existing Windows installations for driver harvesting: $($existingPartitions -join ', ') (excluded system drives: $($excludedDrives -join ', '))" "INFO"
        return $existingPartitions
        
    } catch {
        Write-LogMessage "Error scanning for existing Windows partitions: $_" "WARNING"
        return @()
    }
}

function Save-HarvestedDrivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$TargetPath,
        
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo
    )
    
    try {
        # Check if we should save drivers (only if V: drive is writable)
        if (-not (Test-Path "V:")) {
            Write-LogMessage "V: drive not available - cannot save harvested drivers" "VERBOSE"
            return $false
        }
        # Create target directory if it doesn't exist
        $targetDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $targetDir)) {
            try {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                Write-LogMessage "Created driver directory: $targetDir" "INFO"
            } catch {
                Write-LogMessage "Failed to create driver directory: $_" "WARNING"
                return $false
            }
        }
        
        # Copy harvested drivers to permanent location
        try {
            Copy-Item -Path "$SourcePath\*" -Destination $TargetPath -Recurse -Force
            
            # Count saved drivers
            $savedInfFiles = Get-ChildItem -Path $TargetPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            Write-LogMessage "Saved $($savedInfFiles.Count) driver packages for future use" "SUCCESS"
            
            # Create a metadata file using cleaned device names
            $deviceMake = Clean-DeviceName -Name $DeviceInfo.Manufacturer
            $deviceModel = Clean-DeviceName -Name $DeviceInfo.Model
            $metadataPath = "$TargetPath\HarvestInfo.txt"
            $metadata = @"
Harvested Drivers Information
=============================
Device: $($DeviceInfo.Manufacturer) $($DeviceInfo.Model)
Cleaned Path: $deviceMake\$deviceModel
Serial: $($DeviceInfo.SerialNumber)
Harvest Date: $(Get-Date)
Driver Count: $($savedInfFiles.Count)
Source: Existing Windows installation on disk 0
"@
            $metadata | Out-File -FilePath $metadataPath -Encoding UTF8
            
            return $true
            
        } catch {
            Write-LogMessage "Failed to save harvested drivers: $_" "WARNING"
            return $false
        }
        
    } catch {
        Write-LogMessage "Exception saving harvested drivers: $_" "WARNING"
        return $false
    }
}

Export-ModuleMember -Function Start-WindowsDeployment, Get-WindowsImageInfo, Initialize-Disk0ForWindows, Install-WindowsFromWim, Get-DriverPath, Install-DriversToWindows, Set-WindowsBoot, Install-WindowsUpdatesToWindows, Set-UnattendFileToWindows, Get-DriversFromDisk0, Find-ExistingWindowsPartitions, Save-HarvestedDrivers
