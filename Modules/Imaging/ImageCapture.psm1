# Import required modules
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to import Logging module: $_" -ForegroundColor Red
    throw "Required Logging module not found"
}

# Script-level variable for progress callback
$Script:CaptureProgressCallback = $null

function Set-CaptureProgressCallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Callback
    )
    
    $Script:CaptureProgressCallback = $Callback
}

function Invoke-ImageCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageName,
        
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [string]$ImageID,
        
        [Parameter()]
        [string]$Description = "Captured Windows Image",
        
        [Parameter()]
        [string]$SourceDrive = "C:",
        
        [Parameter()]
        [ValidateSet("max", "fast", "none")]
        [string]$Compression = "max",
        
        [Parameter()]
        [switch]$Verify,
        
        [Parameter()]
        [switch]$CheckIntegrity,
        
        [Parameter()]
        [ValidateSet("WIM", "FFU")]
        [string]$CaptureMethod = "WIM"
    )
    
    try {
        Write-LogMessage "=== Starting Network Boot Image Capture ===" "INFO"
        
        # Update progress callback
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 5 "Initializing capture..."
        }
        
        # Validate source drive
        if (-not (Test-Path $SourceDrive)) {
            throw "Source drive not found: $SourceDrive"
        }
        
        # Check for Windows directory
        $windowsPath = Join-Path $SourceDrive "Windows"
        if (-not (Test-Path $windowsPath)) {
            throw "Windows directory not found on source drive: $SourceDrive"
        }
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 10 "Checking disk space and resolving conflicts..."
        }
        
        # Check available disk space on Z: drive
        $zDrive = "Z:\"
        if (Test-Path $zDrive) {
            try {
                $zDriveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "Z:" }
                if ($zDriveInfo) {
                    $freeSpaceGB = [Math]::Round($zDriveInfo.FreeSpace / 1GB, 2)
                    $totalSpaceGB = [Math]::Round($zDriveInfo.Size / 1GB, 2)
                    Write-LogMessage "Z: drive space - Free: $freeSpaceGB GB, Total: $totalSpaceGB GB" "INFO"
                    
                    # Estimate source drive size for space calculation
                    $sourceDriveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $SourceDrive }
                    if ($sourceDriveInfo) {
                        $usedSpaceGB = [Math]::Round(($sourceDriveInfo.Size - $sourceDriveInfo.FreeSpace) / 1GB, 2)
                        Write-LogMessage "Source drive ($SourceDrive) used space: $usedSpaceGB GB" "INFO"
                        
                        # Estimate compressed size based on compression type
                        $estimatedSizeGB = switch ($Compression) {
                            "max" { $usedSpaceGB * 0.4 }    # Maximum compression ~60% reduction
                            "fast" { $usedSpaceGB * 0.6 }   # Fast compression ~40% reduction
                            "none" { $usedSpaceGB * 0.9 }   # No compression ~10% overhead
                        }
                        
                        Write-LogMessage "Estimated capture size with $Compression compression: $([Math]::Round($estimatedSizeGB, 2)) GB" "INFO"
                        
                        if ($freeSpaceGB -lt ($estimatedSizeGB + 5)) { # Add 5GB buffer
                            throw "Insufficient disk space on Z: drive. Required: ~$([Math]::Round($estimatedSizeGB + 5, 2)) GB, Available: $freeSpaceGB GB"
                        }
                    }
                } else {
                    Write-LogMessage "Could not get Z: drive information" "WARNING"
                }
            } catch {
                Write-LogMessage "Error checking Z: drive space: $_" "WARNING"
            }
        } else {
            throw "Z: drive not accessible for image storage"
        }
        
        # Check for and handle problematic files that cause conflicts
        $windowsPath = Join-Path $SourceDrive "Windows"
        $problematicFiles = @(
            "$windowsPath\System32\Recovery\Winre.wim",
            "$windowsPath\System32\config\*.sav",
            "$windowsPath\System32\config\*.LOG*",
            "$windowsPath\Temp\*",
            "$windowsPath\SoftwareDistribution\Download\*"
        )
        
        Write-LogMessage "Checking for problematic files that may cause capture conflicts..." "INFO"
        $conflictCount = 0
        foreach ($pattern in $problematicFiles) {
            try {
                $files = Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue
                if ($files) {
                    $conflictCount += $files.Count
                    Write-LogMessage "Found $($files.Count) files matching pattern: $pattern" "WARNING"
                }
            } catch {
                # Ignore errors for patterns that don't match
            }
        }
        
        if ($conflictCount -gt 0) {
            Write-LogMessage "Found $conflictCount potentially problematic files. These may cause capture conflicts." "WARNING"
            Write-LogMessage "Consider cleaning temporary files and Windows Update cache before capture." "WARNING"
        }

        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 15 "Creating output directories..."
        }
        
        # Create customer image directory structure
        $customerImageBase = "Z:\CustomerImages\$CustomerName"
        $imageDirectory = "$customerImageBase\$ImageID"
        
        if (-not (Test-Path $customerImageBase)) {
            New-Item -Path $customerImageBase -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created customer directory: $customerImageBase" "INFO"
        }
        
        if (-not (Test-Path $imageDirectory)) {
            New-Item -Path $imageDirectory -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created image directory: $imageDirectory" "INFO"
        }
        
        # Set output filename and extension based on method
        $outputFileName = "$ImageID." + $(if ($CaptureMethod -eq 'FFU') { 'ffu' } else { 'wim' })
        $outputPath = Join-Path $imageDirectory $outputFileName

        # For FFU, resolve the physical drive from the logical drive letter
        $ffuPhysicalDrive = $null
        if ($CaptureMethod -eq 'FFU') {
            try {
                # Remove trailing colon if present
                $logicalDrive = $SourceDrive.TrimEnd(':')
                $partition = Get-Partition -DriveLetter $logicalDrive -ErrorAction Stop
                $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
                $ffuPhysicalDrive = "\\.\PhysicalDrive$($disk.Number)"
                Write-LogMessage "Resolved FFU physical drive: $ffuPhysicalDrive from logical drive: ${SourceDrive}" "INFO"
            } catch {
                throw "Failed to resolve physical drive for FFU capture from logical drive ${SourceDrive}: $_"
            }
        }

        # Create logs directory
        $logDirectory = Join-Path $imageDirectory "Logs"
        if (-not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        
        # Create temp directory for capture process files
        $tempDirectory = Join-Path $imageDirectory "Temp"
        if (-not (Test-Path $tempDirectory)) {
            New-Item -Path $tempDirectory -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created temp directory: $tempDirectory" "INFO"
        }
        
        $logFile = Join-Path $logDirectory "ImageCapture_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 20 "Getting Windows information..."
        }
        
        # Get offline Windows information
        Write-LogMessage "Collecting Windows information from captured system..." "INFO"
        $osInfo = Get-OfflineWindowsInfo -WindowsPath $windowsPath
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 25 "Starting DISM capture process..."
        }
        
        # Build DISM command based on capture method
        if ($CaptureMethod -eq "FFU") {
            $dismArgs = @(
                "/Capture-FFU",
                "/ImageFile:`"$outputPath`"",
                "/CaptureDrive:$ffuPhysicalDrive",
                "/Name:`"$ImageName`"",
                "/Description:`"$Description`"",
                "/LogPath:`"$logFile`""
            )
            if ($CheckIntegrity) {
                $dismArgs += "/CheckIntegrity"
            }
            # No exclusions for FFU
        } else {
            # WIM logic (default)
            $dismArgs = @(
                "/Capture-Image",
                "/ImageFile:`"$outputPath`"",
                "/CaptureDir:$SourceDrive",
                "/Name:`"$ImageName`"",
                "/Description:`"$Description`"",
                "/Compress:$Compression",
                "/LogPath:`"$logFile`"",
                "/Verify"
            )
            # Create WimScript.ini file for exclusions (DISM's preferred method)
            $wimScriptFile = Join-Path $tempDirectory "WimScript.ini"
            $wimScriptContent = @"
[ExclusionList]
ntuser.dat
ntuser.dat.log
ntuser.ini
hiberfil.sys
pagefile.sys
swapfile.sys
"`$RECYCLE.BIN"
"System Volume Information"
Windows\CSC
Windows\Temp
Windows\SoftwareDistribution\Download
Windows\System32\config\*.sav
Windows\System32\config\*.LOG*
Windows\System32\Recovery\Winre.wim
Users\*\AppData\Local\Temp
Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files
ProgramData\Microsoft\Windows\WER
"@
            # Write WimScript.ini file
            $wimScriptContent | Out-File -FilePath $wimScriptFile -Encoding UTF8 -Force
            Write-LogMessage "Created WimScript.ini file: $wimScriptFile" "INFO"
            $dismArgs += "/ConfigFile:`"$wimScriptFile`""
            if ($CheckIntegrity) {
                $dismArgs += "/CheckIntegrity"
            }
        }
        
        Write-LogMessage "Executing enhanced DISM capture command..." "INFO"
        Write-LogMessage "Command: dism.exe $($dismArgs -join ' ')" "VERBOSE"
        
        # Log exclusions being used
        Write-LogMessage "WimScript.ini exclusions:" "INFO"
        $wimScriptLines = $wimScriptContent -split "`n"
        foreach ($line in $wimScriptLines) {
            if ($line -and $line -notmatch "^\[" -and $line.Trim()) {
                Write-LogMessage "  - $($line.Trim())" "VERBOSE"
            }
        }
        
        # Execute DISM capture with enhanced error handling
        $captureStartTime = Get-Date
        $dismResult = Start-DismCaptureWithProgress -DismArgs $dismArgs -LogFile $logFile -SourceDrive $SourceDrive -TempDirectory $tempDirectory
        $captureEndTime = Get-Date
        $captureDuration = ($captureEndTime - $captureStartTime).TotalMinutes
        
        if (-not $dismResult.Success) {
            # Check for specific error codes and provide helpful messages
            $errorMessage = $dismResult.Message
            if ($dismResult.ErrorOutput -match "0x80070070") {
                $errorMessage = "Insufficient disk space during capture. This is likely a temp directory space issue, not Z: drive space."
            } elseif ($dismResult.ErrorOutput -match "0x80070050") {
                $errorMessage = "File conflicts detected. The source system may have active processes or locked files. Try running sysprep again or reboot to WinPE."
            } elseif ($dismResult.ErrorOutput -match "Winre.wim") {
                $errorMessage = "Windows Recovery Environment (WinRE) conflicts detected. Try excluding the Recovery folder or running capture from WinPE."
            }
            
            throw "DISM capture failed: $errorMessage"
        }
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 90 "Verifying captured image..."
        }
        
        # Verify output file exists
        if (-not (Test-Path $outputPath)) {
            throw "Output WIM file was not created: $outputPath"
        }
        
        # Get file size
        $fileInfo = Get-Item $outputPath
        $fileSizeGB = [Math]::Round($fileInfo.Length / 1GB, 2)
        
        Write-LogMessage "Image captured successfully" "SUCCESS"
        Write-LogMessage "Output file: $outputPath" "INFO"
        Write-LogMessage "File size: $fileSizeGB GB" "INFO"
        Write-LogMessage "Capture duration: $([Math]::Round($captureDuration, 1)) minutes" "INFO"
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 95 "Creating metadata and updating configuration..."
        }
        
        # Create comprehensive metadata file
        $metadata = @{
            ImageInfo = @{
                ImageID = $ImageID
                ImageName = $ImageName
                Description = $Description
                CaptureMethod = $CaptureMethod
                Compression = if ($CaptureMethod -eq 'WIM') { $Compression } else { $null }
                RequiresDrivers = $false # Set as needed
                SysprepGeneralized = $sysprepContent -match "Sysprep_Generalize_Complete"
                FullPath = $outputPath
            }
            FileInfo = @{
                FileSizeGB = $fileSizeGB
            }
            OSInfo = $osInfo
            CaptureLog = @{
                CaptureDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            NetworkBootInfo = @{
                ReadyForDeployment = $true
                SysprepGeneralized = ($sysprepContent -match "Sysprep_Generalize_Complete")
                RequiresDrivers = $true
                Notes = "Image captured from generalized Windows installation ready for network deployment"
            }
        }
        
        $metadataPath = Join-Path $imageDirectory "ImageMetadata.json"
        $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Force
        Write-LogMessage "Created metadata file: $metadataPath" "INFO"
        
        # Update customer configuration
        # Ensure CaptureMethod is always present in metadata for config update
        if (-not $metadata.ImageInfo.ContainsKey('CaptureMethod')) {
            $metadata.ImageInfo.CaptureMethod = $CaptureMethod
        }
        $configUpdateResult = Update-CustomerConfig -CustomerName $CustomerName -ImageID $ImageID -ImageName $ImageName -ImagePath $outputPath -Metadata $metadata
        
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 100 "Image capture completed successfully!"
        }
        
        # Create README file
        $readmePath = Join-Path $imageDirectory "README.txt"
        $readmeContent = @"
Network Boot Windows Image
==========================

Customer: $CustomerName
Image ID: $ImageID
Image Name: $ImageName
Description: $Description

Capture Information:
- Source Drive: $SourceDrive
- Capture Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- Capture Duration: $([Math]::Round($captureDuration, 1)) minutes
- Compression: $Compression
- File Size: $fileSizeGB GB
- Sysprep Status: $(if ($sysprepContent -match "Sysprep_Generalize_Complete") { "Generalized" } else { "Unknown" })

OS Information:
- Product Name: $($osInfo.ProductName)
- Build Number: $($osInfo.BuildNumber)
- Edition: $($osInfo.Edition)
- Architecture: $($osInfo.Architecture)

Files Created:
- $outputFileName (Main WIM image file)
- ImageMetadata.json (Comprehensive metadata)
- Logs\ImageCapture_*.log (DISM capture log)

Deployment Notes:
- This image is ready for network boot deployment
- The source system was sysprepped and generalized
- Image has been added to customer configuration for deployment selection
- Use Windows Deployment Tool to deploy this image

Network Path: \\server\CustomerImages\$CustomerName\$ImageID\$outputFileName
Relative Path: CustomerImages\$CustomerName\$ImageID\$outputFileName
"@
        $readmeContent | Set-Content -Path $readmePath -Force
        
        # Cleanup temp directory after successful capture
        if ($dismResult.Success) {
            try {
                Write-LogMessage "Cleaning up temporary files..." "INFO"
                Remove-Item $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Temporary files cleaned up successfully" "INFO"
            } catch {
                Write-LogMessage "Warning: Could not clean up temp directory: $_" "WARNING"
            }
        } else {
            Write-LogMessage "Keeping temp directory for troubleshooting: $tempDirectory" "INFO"
        }
        
        return @{
            Success = $true
            ImagePath = $outputPath
            ImageID = $ImageID
            CustomerName = $CustomerName
            ImageSize = "$fileSizeGB GB"
            CaptureDuration = "$([Math]::Round($captureDuration, 1)) minutes"
            MetadataPath = $metadataPath
            LogPath = $logFile
            ConfigUpdated = $configUpdateResult.Success
        }
    }
    catch {
        Write-LogMessage "Network boot image capture failed: $_" "ERROR"
        if ($Script:CaptureProgressCallback) {
            & $Script:CaptureProgressCallback 0 "Capture failed: $($_.Exception.Message)"
        }
        return @{
            Success = $false
            Message = $_.Exception.Message
            Error = $_
        }
    }
}

function Start-DismCaptureWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$DismArgs,
        
        [Parameter(Mandatory)]
        [string]$LogFile,
        
        [Parameter()]
        [string]$SourceDrive = "C:",
        
        [Parameter()]
        [string]$TempDirectory = $env:TEMP
    )
    
    try {
        # Check for existing partial WIM file and clean it up
        $wimFilePath = ($DismArgs | Where-Object { $_ -match "/ImageFile:" }) -replace "/ImageFile:", "" -replace '"', ''
        if (Test-Path $wimFilePath) {
            Write-LogMessage "Removing existing partial WIM file: $wimFilePath" "INFO"
            try {
                Remove-Item $wimFilePath -Force -ErrorAction Stop
            } catch {
                Write-LogMessage "Warning: Could not remove existing WIM file: $_" "WARNING"
            }
        }
        
        # CRITICAL: Create a large temp directory on Z: drive for DISM operations
        $dismTempDir = Join-Path $TempDirectory "DismTemp_$(Get-Random)"
        if (-not (Test-Path $dismTempDir)) {
            New-Item -Path $dismTempDir -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created DISM temp directory: $dismTempDir" "INFO"
        }
        
        # Set environment variables to force DISM to use our temp directory
        $originalTemp = $env:TEMP
        $originalTmp = $env:TMP
        $originalScratchDir = $env:DISM_SCRATCH_DIR
        
        $env:TEMP = $dismTempDir
        $env:TMP = $dismTempDir
        $env:DISM_SCRATCH_DIR = $dismTempDir
        
        Write-LogMessage "Set DISM temp directories to: $dismTempDir" "INFO"
        
        # Add explicit scratch directory to DISM args
        $dismArgs += "/ScratchDir:`"$dismTempDir`""
        
        # Pre-flight checks for common issues
        Write-LogMessage "Performing pre-flight checks..." "INFO"
        
        # Check temp directory space
        $tempDrive = $dismTempDir.Substring(0, 2)
        $tempDriveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $tempDrive }
        if ($tempDriveInfo) {
            $tempFreeSpaceGB = [Math]::Round($tempDriveInfo.FreeSpace / 1GB, 2)
            Write-LogMessage "Temp drive ($tempDrive) free space: $tempFreeSpaceGB GB" "INFO"
            
            if ($tempFreeSpaceGB -lt 10) {
                throw "Insufficient space on temp drive $tempDrive. Available: $tempFreeSpaceGB GB, Recommended: 10+ GB"
            }
        }
        
        # Check if source drive is accessible
        if (-not (Test-Path "$SourceDrive\")) {
            throw "Source drive $SourceDrive is not accessible"
        }
        
        # Check if Windows directory exists
        if (-not (Test-Path "$SourceDrive\Windows")) {
            throw "Windows directory not found on source drive $SourceDrive"
        }
        
        # Clean up any existing temp files that might interfere
        Write-LogMessage "Cleaning existing temp files..." "INFO"
        try {
            Get-ChildItem -Path "X:\WINDOWS\SystemTemp" -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -match "dism|wim|cab" } |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } catch {
            Write-LogMessage "Could not clean X:\WINDOWS\SystemTemp: $_" "WARNING"
        }
        
        # Check for running services that might lock files
        $problematicServices = @("wuauserv", "bits", "cryptsvc", "msiserver")
        foreach ($service in $problematicServices) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq "Running") {
                    Write-LogMessage "Warning: Service $service is running and may cause file locks" "WARNING"
                }
            } catch {
                # Service doesn't exist, ignore
            }
        }
        
        # Start DISM process with better error capture using temp directory
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = "dism.exe"
        $processStartInfo.Arguments = $DismArgs -join " "
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        $processStartInfo.CreateNoWindow = $true
        
        # Set environment variables for the process
        $processStartInfo.EnvironmentVariables["TEMP"] = $dismTempDir
        $processStartInfo.EnvironmentVariables["TMP"] = $dismTempDir
        $processStartInfo.EnvironmentVariables["DISM_SCRATCH_DIR"] = $dismTempDir
        
        $dismProcess = New-Object System.Diagnostics.Process
        $dismProcess.StartInfo = $processStartInfo
        
        # Use temp directory for output capture files
        $outputCaptureFile = Join-Path $TempDirectory "dism_output_$(Get-Random).txt"
        $errorCaptureFile = Join-Path $TempDirectory "dism_error_$(Get-Random).txt"
        
        # Create output/error collectors
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder
        
        # Event handlers for output
        $outputAction = {
            if ($EventArgs.Data) {
                $outputBuilder.AppendLine($EventArgs.Data)
                # Also write to temp file for analysis
                try {
                    Add-Content -Path $outputCaptureFile -Value $EventArgs.Data -ErrorAction SilentlyContinue
                } catch { }
                Write-LogMessage "[DISM-Output] $($EventArgs.Data)" "VERBOSE"
            }
        }
        
        $errorAction = {
            if ($EventArgs.Data) {
                $errorBuilder.AppendLine($EventArgs.Data)
                # Also write to temp file for analysis
                try {
                    Add-Content -Path $errorCaptureFile -Value $EventArgs.Data -ErrorAction SilentlyContinue
                } catch { }
                Write-LogMessage "[DISM-Error] $($EventArgs.Data)" "ERROR"
            }
        }
        
        Register-ObjectEvent -InputObject $dismProcess -EventName OutputDataReceived -Action $outputAction | Out-Null
        Register-ObjectEvent -InputObject $dismProcess -EventName ErrorDataReceived -Action $errorAction | Out-Null
        
        Write-LogMessage "Starting DISM capture process with custom temp directory..." "INFO"
        Write-LogMessage "DISM command: dism.exe $($dismArgs -join ' ')" "INFO"
        $progressStartTime = Get-Date
        
        try {
            $dismProcess.Start()
            $dismProcess.BeginOutputReadLine()
            $dismProcess.BeginErrorReadLine()
            
            $lastProgressUpdate = Get-Date
            $currentProgress = 25
            
            # Enhanced progress monitoring with temp directory size checking
            while (-not $dismProcess.HasExited) {
                Start-Sleep -Seconds 3
                
                $currentTime = Get-Date
                $elapsedMinutes = ($currentTime - $progressStartTime).TotalMinutes
                
                # Check temp directory usage periodically
                if (($currentTime - $lastProgressUpdate).TotalSeconds -ge 30) {
                    try {
                        $tempUsage = (Get-ChildItem -Path $dismTempDir -Recurse -ErrorAction SilentlyContinue | 
                                     Measure-Object -Property Length -Sum).Sum / 1GB
                        Write-LogMessage "Temp directory usage: $([Math]::Round($tempUsage, 2)) GB" "INFO"
                    } catch {
                        Write-LogMessage "Could not check temp directory usage" "WARNING"
                    }
                }
                
                # Better progress estimation based on typical capture patterns
                if ($elapsedMinutes -lt 2) {
                    $estimatedProgress = 25 + ($elapsedMinutes / 2) * 15  # 25-40% in first 2 minutes
                } elseif ($elapsedMinutes -lt 10) {
                    $estimatedProgress = 40 + (($elapsedMinutes - 2) / 8) * 35  # 40-75% in next 8 minutes
                } elseif ($elapsedMinutes -lt 20) {
                    $estimatedProgress = 75 + (($elapsedMinutes - 10) / 10) * 15  # 75-90% in next 10 minutes
                } else {
                    $estimatedProgress = 90  # Cap at 90% until completion
                }
                
                $estimatedProgress = [Math]::Min(90, [Math]::Max($currentProgress, $estimatedProgress))
                
                # Update progress every 5 seconds
                if (($currentTime - $lastProgressUpdate).TotalSeconds -ge 5) {
                    if ($Script:CaptureProgressCallback) {
                        & $Script:CaptureProgressCallback $estimatedProgress "Capturing image... ($([Math]::Round($elapsedMinutes, 1)) minutes elapsed)"
                    }
                    $lastProgressUpdate = $currentTime
                    $currentProgress = $estimatedProgress
                }
                
                # Enhanced timeout checking with warnings
                if ($elapsedMinutes -gt 30) {
                    Write-LogMessage "DISM capture has been running for over 30 minutes - this may indicate an issue" "WARNING"
                }
                if ($elapsedMinutes -gt 60) {
                    Write-LogMessage "DISM capture has been running for over 1 hour - consider canceling if stuck" "WARNING"
                }
                if ($elapsedMinutes -gt 120) {
                    Write-LogMessage "DISM capture has been running for over 2 hours - likely stuck, terminating" "ERROR"
                    try {
                        $dismProcess.Kill()
                        throw "DISM capture timeout after 2 hours"
                    } catch {
                        throw "DISM capture timeout and could not terminate process"
                    }
                }
            }
            
            # Wait for process to complete and clean up events
            $dismProcess.WaitForExit()
            $exitCode = $dismProcess.ExitCode
            
        } finally {
            # Always restore environment variables
            $env:TEMP = $originalTemp
            $env:TMP = $originalTmp
            if ($originalScratchDir) {
                $env:DISM_SCRATCH_DIR = $originalScratchDir
            } else {
                Remove-Item env:DISM_SCRATCH_DIR -ErrorAction SilentlyContinue
            }
            
            # Clean up temp directory
            try {
                if (Test-Path $dismTempDir) {
                    Write-LogMessage "Cleaning up DISM temp directory: $dismTempDir" "INFO"
                    Remove-Item $dismTempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-LogMessage "Could not clean up DISM temp directory: $_" "WARNING"
            }
        }
        
        # Clean up event handlers
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $dismProcess } | Unregister-Event
        
        # Get final output
        $output = $outputBuilder.ToString()
        $errorOutput = $errorBuilder.ToString()
        
        # Save final output to temp files for analysis
        try {
            $output | Out-File -FilePath $outputCaptureFile -Append -ErrorAction SilentlyContinue
            $errorOutput | Out-File -FilePath $errorCaptureFile -Append -ErrorAction SilentlyContinue
            Write-LogMessage "DISM output saved to: $outputCaptureFile" "VERBOSE"
            Write-LogMessage "DISM errors saved to: $errorCaptureFile" "VERBOSE"
        } catch {
            Write-LogMessage "Could not save DISM output to temp files: $_" "WARNING"
        }
        
        $totalDuration = ($currentTime - $progressStartTime).TotalMinutes
        Write-LogMessage "DISM capture completed in $([Math]::Round($totalDuration, 1)) minutes with exit code $exitCode" "INFO"
        
        # Enhanced error analysis
        if ($exitCode -ne 0) {
            $errorAnalysis = "DISM failed with exit code $exitCode"
            
            if ($errorOutput -match "0x80070070") {
                $errorAnalysis += " - Insufficient disk space"
            } elseif ($errorOutput -match "0x80070050") {
                $errorAnalysis += " - File exists/access denied (may be file locks)"
            } elseif ($errorOutput -match "0x80070005") {
                $errorAnalysis += " - Access denied (check permissions)"
            } elseif ($errorOutput -match "Winre\.wim") {
                $errorAnalysis += " - Windows Recovery Environment conflict"
            }
            
            return @{
                Success = $false
                ExitCode = $exitCode
                Output = $output
                ErrorOutput = $errorOutput
                Message = $errorAnalysis
            }
        }
        
        return @{
            Success = $true
            ExitCode = $exitCode
            Output = $output
            Duration = $totalDuration
        }
        
    } catch {
        Write-LogMessage "Error running DISM capture: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
            Error = $_
        }
    }
}

function Update-CustomerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        [Parameter(Mandatory)]
        [string]$ImageID,
        [Parameter(Mandatory)]
        [string]$ImageName,
        [Parameter(Mandatory)]
        [string]$ImagePath,
        [Parameter(Mandatory)]
        $Metadata
    )
    try {
        # Load config
        $configPath = "Y:\DeploymentModules\Config\CustomerConfig\$CustomerName\Config.json"
        if (-not (Test-Path $configPath)) {
            throw "Config file not found: $configPath"
        }
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $isFFU = $Metadata.ImageInfo.CaptureMethod -eq 'FFU'
        $section = if ($isFFU) { 'FFUImages' } else { 'WIMImages' }
        if (-not $config.PSObject.Properties.Name -contains $section) {
            $config | Add-Member -MemberType NoteProperty -Name $section -Value @{} -Force
        }
        # Ensure section is a hashtable
        $imagesSection = $config.$section
        if ($imagesSection -isnot [hashtable]) {
            $imagesSection = @{
            }
            # Copy existing entries if any
            foreach ($prop in $config.$section.PSObject.Properties) {
                $imagesSection[$prop.Name] = $prop.Value
            }
        }
        # Add or update image entry with comprehensive information
        $imageInfo = $Metadata.ImageInfo
        
        # Ensure Active flag is always set to true for newly captured images (with proper casing)
        $imageInfo['active'] = $true  # Use lowercase 'active' to match config standard
        
        # Ensure all required capture method specific properties are present
        if (-not $imageInfo.ContainsKey('RequiredUpdates')) {
            $imageInfo['RequiredUpdates'] = $false  # Default for captured images
        }
        if (-not $imageInfo.ContainsKey('ApplyUnattend')) {
            $imageInfo['ApplyUnattend'] = $true   # Default for captured images
        }
        if (-not $imageInfo.ContainsKey('DriverInject')) {
            $imageInfo['DriverInject'] = $true    # Default for captured images
        }
        
        # Ensure capture method specific fields are present
        if (-not $imageInfo.ContainsKey('CaptureMethod')) {
            $imageInfo['CaptureMethod'] = if ($isFFU) { 'FFU' } else { 'WIM' }
        }
        if (-not $imageInfo.ContainsKey('Compression') -and -not $isFFU) {
            $imageInfo['Compression'] = $Metadata.ImageInfo.Compression -or 'max'
        }
        if (-not $imageInfo.ContainsKey('SysprepGeneralized')) {
            $imageInfo['SysprepGeneralized'] = $Metadata.ImageInfo.SysprepGeneralized -or $false
        }
        if (-not $imageInfo.ContainsKey('RequiresDrivers')) {
            $imageInfo['RequiresDrivers'] = $Metadata.ImageInfo.RequiresDrivers -or $false
        }
        
        $imagesSection[$ImageID] = $imageInfo
        $config.$section = $imagesSection
        # Remove from old section if present
        $oldSection = if ($isFFU) { 'WIMImages' } else { 'FFUImages' }
        if ($config.PSObject.Properties.Name -contains $oldSection) {
            $oldSectionObj = $config.$oldSection
            if ($oldSectionObj -isnot [hashtable]) {
                $tmp = @{
                }
                foreach ($prop in $oldSectionObj.PSObject.Properties) {
                    $tmp[$prop.Name] = $prop.Value
                }
                $oldSectionObj = $tmp
            }
            if ($oldSectionObj.ContainsKey($ImageID)) {
                $oldSectionObj.Remove($ImageID)
                $config.$oldSection = $oldSectionObj
            }
        }
        # Save config
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force
        return @{ Success = $true }
    } catch {
        Write-LogMessage "Failed to update customer config: $_" "ERROR"
        return @{ Success = $false; Message = $_ }
    }
}

function Get-OfflineWindowsInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath
    )
    
    try {
        Write-LogMessage "Getting offline Windows information from: $WindowsPath" "VERBOSE"
        
        $metadata = @{
            OSVersion = "Unknown"
            BuildNumber = "Unknown"
            Edition = "Unknown"
            ProductName = "Unknown"
            InstallDate = "Unknown"
            RegisteredOwner = "Unknown"
            Architecture = "Unknown"
            InstallationType = "Unknown"
            DisplayVersion = "Unknown"
        }
        
        # Check if we can access offline Windows files
        $systemPath = Join-Path $WindowsPath "System32"
        if (-not (Test-Path $systemPath)) {
            Write-LogMessage "Cannot access System32 folder" "WARNING"
            return $metadata
        }
        
        # Detect architecture
        $wow64Path = Join-Path $systemPath "wow64.dll"
        if (Test-Path $wow64Path) {
            $metadata.Architecture = "x64"
        } else {
            $metadata.Architecture = "x86"
        }
        
        # Try to extract version from file properties
        $versionDll = Join-Path $systemPath "kernel32.dll"
        if (Test-Path $versionDll) {
            try {
                $versionInfo = (Get-Item $versionDll).VersionInfo
                $metadata.OSVersion = $versionInfo.ProductVersion
                $metadata.BuildNumber = $versionInfo.FileBuildPart
                Write-LogMessage "Found Windows build $($metadata.BuildNumber)" "INFO"
            } catch {
                Write-LogMessage "Failed to read version from kernel32.dll" "WARNING"
            }
        }
        
        # Try to read from SOFTWARE registry hive
        $softwareHive = Join-Path $WindowsPath "System32\config\SOFTWARE"
        if (Test-Path $softwareHive) {
            try {
                # Load the registry hive temporarily
                $tempKeyName = "TempSoftware_$(Get-Random)"
                $tempKey = "HKLM:\$tempKeyName"
                
                $null = reg load "HKLM\$tempKeyName" "`"$softwareHive`"" 2>&1
                
                $winVerKey = "$tempKey\Microsoft\Windows NT\CurrentVersion"
                if (Test-Path $winVerKey) {
                    $winVer = Get-ItemProperty -Path $winVerKey -ErrorAction SilentlyContinue
                    
                    if ($winVer) {
                        if ($winVer.ProductName) { $metadata.ProductName = $winVer.ProductName }
                        if ($winVer.CurrentBuild) { $metadata.BuildNumber = $winVer.CurrentBuild }
                        if ($winVer.EditionID) { $metadata.Edition = $winVer.EditionID }
                        if ($winVer.RegisteredOwner) { $metadata.RegisteredOwner = $winVer.RegisteredOwner }
                        if ($winVer.InstallationType) { $metadata.InstallationType = $winVer.InstallationType }
                        if ($winVer.DisplayVersion) { $metadata.DisplayVersion = $winVer.DisplayVersion }
                        
                        if ($winVer.InstallDate) {
                            try {
                                $epoch = Get-Date "1970-01-01 00:00:00"
                                $installDateTime = $epoch.AddSeconds($winVer.InstallDate)
                                $metadata.InstallDate = $installDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                            } catch {
                                Write-LogMessage "Failed to parse InstallDate" "WARNING"
                            }
                        }
                    }
                }
                
                # Unload the registry hive
                $null = reg unload "HKLM\$tempKeyName" 2>&1
                Start-Sleep -Seconds 1  # Give it time to unload
            } catch {
                Write-LogMessage "Failed to read from SOFTWARE registry hive: $_" "WARNING"
                try {
                    $null = reg unload "HKLM\$tempKeyName" 2>&1
                } catch { }
            }
        }
        
        Write-LogMessage "Collected OS Info: $($metadata.ProductName) Build $($metadata.BuildNumber) ($($metadata.Architecture))" "INFO"
        return $metadata
    } catch {
        Write-LogMessage "Error getting offline Windows info: $_" "ERROR"
        return $metadata
    }
}

function Get-CustomerList {
    [CmdletBinding()]
    param()
    
    try {
        $customerConfigBase = "Y:\DeploymentModules\Config\CustomerConfig"
        $customers = @()
        
        if (Test-Path $customerConfigBase) {
            $customerDirs = Get-ChildItem -Path $customerConfigBase -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $customerDirs) {
                $customers += $dir.Name
            }
        }
        
        return $customers | Sort-Object
    } catch {
        Write-LogMessage "Failed to get customer list: $_" "ERROR"
        return @()
    }
}

function Update-CustomerImageConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        Write-LogMessage "Updating customer image configuration for $CustomerName..." "INFO"
        
        # Ensure customer config directory exists
        $configDir = "Y:\DeploymentModules\Config\CustomerConfig\$CustomerName"
        if (-not (Test-Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created customer config directory: $configDir" "INFO"
        }
        
        $configPath = Join-Path $configDir "Config.json"
        
        # Load existing config or create new one
        $config = @{
            CustomerName = $CustomerName
            LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Images = @{}
            BaseImages = @{}
            CustomerImages = @{
            }
        }
        
        if (Test-Path $configPath) {
            try {
                $configContent = Get-Content $configPath -Raw
                $configObject = $configContent | ConvertFrom-Json
                
                # Convert to hashtable for compatibility
                $existingConfig = Convert-PSObjectToHashtable -InputObject $configObject
                if ($existingConfig) {
                    $config = $existingConfig
                }
                Write-LogMessage "Loaded existing customer configuration" "INFO"
            } catch {
                Write-LogMessage "Failed to load existing config, creating new one: $_" "WARNING"
            }
        }
        
        # Create the image entry with comprehensive capture information
        $imageEntry = @{
            ImageID = $ImageInfo.ImageID
            ImageName = $ImageInfo.ImageName
            Description = $ImageInfo.Description
            Path = $ImageInfo.RelativePath
            FullPath = $ImageInfo.FullPath
            Type = $ImageInfo.Type
            CaptureMethod = $ImageInfo.CaptureMethod -or $ImageInfo.Type
            OSInfo = @{
                Version = $ImageInfo.OSVersion
                Build = $ImageInfo.OSBuild
                Edition = $ImageInfo.OSEdition
            }
            FileSize = $ImageInfo.FileSize
            CaptureDate = $ImageInfo.CaptureDate
            active = $true                # Use lowercase 'active' to match config standard
            ReadyForDeployment = $true
            RequiredUpdates = $false      # Default to false for captured images
            ApplyUnattend = $true         # Default to true for captured images
            DriverInject = $true          # Default to true for captured images
            SysprepGeneralized = $ImageInfo.SysprepGeneralized -or $false
            RequiresDrivers = $ImageInfo.RequiresDrivers -or $false
        }
        
        # Add compression info for WIM images
        if ($ImageInfo.Type -eq 'WIM' -and $ImageInfo.Compression) {
            $imageEntry['Compression'] = $ImageInfo.Compression
        }
        
        # Add the image to the config
        if (-not $config.CustomerImages) {
            $config.CustomerImages = @{
            }
        }
        $config.CustomerImages[$ImageInfo.ImageID] = $imageEntry
        
        # Ensure DeploymentSettings section exists with RequiredUpdates default
        if (-not $config.DeploymentSettings) {
            $config.DeploymentSettings = @{
                DefaultDriverInject = $true
                DefaultApplyUnattend = $true
                DefaultRequiredUpdates = $false
            }
        }
        
        # Ensure CustomerInfo section exists
        if (-not $config.CustomerInfo) {
            $config.CustomerInfo = @{
                Name = $CustomerName
                DeploymentNotes = "Standard deployment configuration"
            }
        }
        
        $config.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Save updated configuration
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force
        Write-LogMessage "Saved updated customer configuration to: $configPath" "SUCCESS"
        
        return @{
            Success = $true
            ConfigPath = $configPath
            ImageID = $ImageInfo.ImageID
        }
    }
    catch {
        Write-LogMessage "Failed to update customer image configuration: $_" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
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
            $hashtable = @{
            
            }
            
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

Export-ModuleMember -Function Invoke-ImageCapture, Update-CustomerConfig, Get-OfflineWindowsInfo, Get-CustomerList, Set-CaptureProgressCallback, Update-CustomerImageConfig
