# ISO Manager Module
# Handles mounting ISO files and extracting Windows image information
# Uses DISM for reliable mounting in WinPE

Import-Module "$PSScriptRoot\Logging.psm1" -Force

function Get-ISOImageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath,
        
        [Parameter()]
        [switch]$KeepMounted
    )
    
    try {
        Write-LogMessage "Getting image information from ISO: $ISOPath" "INFO"
        
        if (-not (Test-Path $ISOPath)) {
            throw "ISO file not found: $ISOPath"
        }
        
        # Check if ISO is already mounted
        $existingMount = Find-MountedISO -ISOPath $ISOPath
        if ($existingMount) {
            Write-LogMessage "ISO already mounted at: $($existingMount.DriveLetter)" "INFO"
            $actualMountLetter = $existingMount.DriveLetter
            $shouldDismount = -not $KeepMounted
        } else {
            # Find available drive letter for mounting
            $mountLetter = Get-AvailableDriveLetter
            if (-not $mountLetter) {
                throw "No available drive letters for ISO mounting"
            }
            
            Write-LogMessage "Using drive letter $mountLetter for ISO mounting" "VERBOSE"
            
            # Mount the ISO
            Write-LogMessage "Mounting ISO using diskpart: $ISOPath" "VERBOSE"
            $mountResult = Mount-ISOWithDiskpart -ISOPath $ISOPath -MountLetter $mountLetter
            
            if (-not $mountResult.Success) {
                throw "Failed to mount ISO: $($mountResult.Message)"
            }
            
            # Use the actual mounted drive letter from the mount result
            $actualMountLetter = $mountResult.ActualDrive
            Write-LogMessage "ISO mounted successfully to: $actualMountLetter" "SUCCESS"
            $shouldDismount = -not $KeepMounted
        }
        
        try {
            # Look for install.wim or install.esd using the actual mount letter
            $installWimPath = Join-Path $actualMountLetter "sources\install.wim"
            $installEsdPath = Join-Path $actualMountLetter "sources\install.esd"
            
            $imagePath = $null
            if (Test-Path $installWimPath) {
                $imagePath = $installWimPath
                Write-LogMessage "Found install.wim at: $imagePath" "VERBOSE"
            } elseif (Test-Path $installEsdPath) {
                $imagePath = $installEsdPath
                Write-LogMessage "Found install.esd at: $imagePath" "VERBOSE"
            } else {
                throw "No install.wim or install.esd found in mounted ISO"
            }
            
            # Get image information using DISM
            Write-LogMessage "Getting image information using DISM from: $imagePath" "VERBOSE"
            $dismInfoOutput = & dism.exe /Get-WimInfo /WimFile:"$imagePath" 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "DISM failed to get image info: $($dismInfoOutput -join ' ')"
            }
            
            # Parse DISM output to extract image information
            $images = @()
            $currentImage = $null
            
            foreach ($line in $dismInfoOutput) {
                if ($line -match "Index\s*:\s*(\d+)") {
                    if ($currentImage) {
                        $images += $currentImage
                    }
                    $currentImage = @{
                        ImageIndex = [int]$matches[1]
                        ImageName = ""
                        ImageDescription = ""
                        ImageVersion = ""
                        Architecture = ""
                        InstallWimPath = $imagePath
                    }
                } elseif ($line -match "Name\s*:\s*(.+)") {
                    if ($currentImage) {
                        $currentImage.ImageName = $matches[1].Trim()
                    }
                } elseif ($line -match "Description\s*:\s*(.+)") {
                    if ($currentImage) {
                        $currentImage.ImageDescription = $matches[1].Trim()
                    }
                } elseif ($line -match "Version\s*:\s*(.+)") {
                    if ($currentImage) {
                        $currentImage.ImageVersion = $matches[1].Trim()
                    }
                } elseif ($line -match "Architecture\s*:\s*(.+)") {
                    if ($currentImage) {
                        $currentImage.Architecture = $matches[1].Trim()
                    }
                }
            }
            
            # Add the last image if it exists
            if ($currentImage) {
                $images += $currentImage
            }
            
            # Add mount information to each image
            foreach ($image in $images) {
                $image.MountedDrive = $actualMountLetter
                $image.ISOPath = $ISOPath
                $image.IsMounted = $true
            }
            
            Write-LogMessage "Found $($images.Count) Windows images in ISO" "INFO"
            foreach ($image in $images) {
                Write-LogMessage "  Index $($image.ImageIndex): $($image.ImageName) - $($image.ImageDescription)" "VERBOSE"
            }
            
            if ($KeepMounted) {
                Write-LogMessage "Keeping ISO mounted at: $actualMountLetter" "INFO"
            }
            
            return $images
            
        } finally {
            # Only dismount if we're not keeping it mounted and we mounted it ourselves
            if ($shouldDismount -and -not $existingMount) {
                try {
                    Write-LogMessage "Dismounting ISO from: $actualMountLetter" "VERBOSE"
                    $dismountResult = Dismount-ISOWithDiskpart -MountLetter $actualMountLetter
                    if (-not $dismountResult.Success) {
                        Write-LogMessage "Diskpart dismount warning: $($dismountResult.Message)" "WARNING"
                    }
                } catch {
                    Write-LogMessage "Warning: Failed to dismount ISO: $_" "WARNING"
                }
            }
        }
        
    } catch {
        Write-LogMessage "Error getting ISO image info: $_" "ERROR"
        throw $_
    }
}

function Find-MountedISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath
    )
    
    try {
        # Check CD drives with 0 bytes free for the sources folder
        $cdDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
            $_.DriveType -eq 5 -and $_.FreeSpace -eq 0 
        }
        
        foreach ($cdDrive in $cdDrives) {
            $driveLetter = $cdDrive.DeviceID.Replace(':', '')
            $drivePath = "${driveLetter}:"
            
            # Check if this drive has the sources folder
            $sourcesPath = Join-Path $drivePath "sources"
            if (Test-Path $sourcesPath) {
                Write-LogMessage "Found mounted ISO at: $drivePath" "VERBOSE"
                return @{
                    DriveLetter = $drivePath
                    ISOPath = $ISOPath
                }
            }
        }
        
        # Check subst mappings
        $availableLetters = 'I','J','K','L','M','N','O','P','Q','R','S','T','U'
        foreach ($letter in $availableLetters) {
            $drivePath = "${letter}:"
            if (Test-Path $drivePath) {
                $sourcesPath = Join-Path $drivePath "sources"
                if (Test-Path $sourcesPath) {
                    Write-LogMessage "Found mounted ISO at: $drivePath (subst mapping)" "VERBOSE"
                    return @{
                        DriveLetter = $drivePath
                        ISOPath = $ISOPath
                    }
                }
            }
        }
        
        return $null
        
    } catch {
        Write-LogMessage "Error finding mounted ISO: $_" "WARNING"
        return $null
    }
}

function Mount-ISOForDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath
    )
    
    try {
        Write-LogMessage "Mounting ISO for deployment: $ISOPath" "INFO"
        
        if (-not (Test-Path $ISOPath)) {
            throw "ISO file not found: $ISOPath"
        }
        
        # Find available drive letter for mounting
        $mountLetter = Get-AvailableDriveLetter
        if (-not $mountLetter) {
            throw "No available drive letters for ISO mounting"
        }
        
        Write-LogMessage "Using drive letter $mountLetter for ISO deployment mounting" "VERBOSE"
        
        # Mount the ISO using diskpart
        $mountResult = Mount-ISOWithDiskpart -ISOPath $ISOPath -MountLetter $mountLetter
        
        if (-not $mountResult.Success) {
            throw "Failed to mount ISO: $($mountResult.Message)"
        }
        
        # Use the actual mounted drive letter from the mount result
        $actualMountLetter = $mountResult.ActualDrive
        Write-LogMessage "ISO mounted successfully to: $actualMountLetter" "SUCCESS"
        
        # Look for install.wim or install.esd using the actual mount letter
        $installWimPath = Join-Path $actualMountLetter "sources\install.wim"
        $installEsdPath = Join-Path $actualMountLetter "sources\install.esd"
        
        if (Test-Path $installWimPath) {
            $imagePath = $installWimPath
            Write-LogMessage "Found install.wim at: $imagePath" "VERBOSE"
        } elseif (Test-Path $installEsdPath) {
            $imagePath = $installEsdPath
            Write-LogMessage "Found install.esd at: $imagePath" "VERBOSE"
        } else {
            # Clean up mount and throw error using the actual mount letter
            try {
                Dismount-ISOWithDiskpart -MountLetter $actualMountLetter | Out-Null
            } catch {
                Write-LogMessage "Failed to dismount ISO after error: $_" "WARNING"
            }
            throw "No install.wim or install.esd found in mounted ISO"
        }
        
        return @{
            DriveLetter = $actualMountLetter
            InstallWimPath = $imagePath
            ISOPath = $ISOPath
            MountDir = $actualMountLetter
        }
        
    } catch {
        Write-LogMessage "Error mounting ISO for deployment: $_" "ERROR"
        throw $_
    }
}

function Mount-ISOWithDiskpart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath,
        
        [Parameter(Mandatory)]
        [string]$MountLetter
    )
    
    try {
        Write-LogMessage "Attempting to mount ISO using PowerShell: $ISOPath" "VERBOSE"
        
        # Get list of existing CD drives before mounting
        $existingCDDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
            $_.DriveType -eq 5 -and $_.FreeSpace -eq 0 
        } | ForEach-Object { $_.DeviceID.Replace(':', '') }
        
        Write-LogMessage "Existing CD drives before mount: $($existingCDDrives -join ', ')" "VERBOSE"
        
        # Try PowerShell Mount-DiskImage (works in many WinPE environments)
        try {
            $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
            
            if ($mountResult) {
                Write-LogMessage "PowerShell mount command succeeded" "VERBOSE"
                
                # Wait for file system to settle
                Start-Sleep -Seconds 3
                
                # Find the new CD drive with 0 bytes free (characteristic of mounted ISOs)
                $newCDDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
                    $_.DriveType -eq 5 -and $_.FreeSpace -eq 0 
                } | ForEach-Object { $_.DeviceID.Replace(':', '') }
                
                Write-LogMessage "CD drives after mount: $($newCDDrives -join ', ')" "VERBOSE"
                
                # Find the newly mounted drive
                $mountedDrive = $null
                foreach ($drive in $newCDDrives) {
                    if ($drive -notin $existingCDDrives) {
                        $mountedDrive = $drive
                        break
                    }
                }
                
                if (-not $mountedDrive) {
                    # Fallback: try to get drive letter from PowerShell volume
                    try {
                        $volume = Get-Volume -DiskImage $mountResult -ErrorAction Stop
                        if ($volume.DriveLetter) {
                            $mountedDrive = $volume.DriveLetter
                            Write-LogMessage "Got drive letter from PowerShell volume: $mountedDrive" "VERBOSE"
                        }
                    } catch {
                        Write-LogMessage "Failed to get volume from PowerShell: $_" "VERBOSE"
                    }
                }
                
                if ($mountedDrive) {
                    $actualDriveLetter = "${mountedDrive}:"
                    Write-LogMessage "ISO mounted successfully to actual drive: $actualDriveLetter" "SUCCESS"
                    
                    # Verify the mount worked by checking for sources folder
                    $sourcesPath = Join-Path $actualDriveLetter "sources"
                    if (Test-Path $sourcesPath) {
                        Write-LogMessage "Verified ISO mount at $actualDriveLetter (found sources folder)" "SUCCESS"
                        return @{ 
                            Success = $true
                            Message = "ISO mounted successfully using PowerShell"
                            ActualDrive = $actualDriveLetter
                            MountMethod = "PowerShell"
                        }
                    } else {
                        Write-LogMessage "Drive $actualDriveLetter exists but no sources folder found" "WARNING"
                    }
                } else {
                    Write-LogMessage "Could not determine mounted drive letter" "WARNING"
                }
                
                # If we get here, something went wrong - dismount
                Write-LogMessage "PowerShell mount failed verification, dismounting..." "WARNING"
                try {
                    Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
                } catch {
                    # Ignore dismount errors
                }
            }
        } catch {
            Write-LogMessage "PowerShell Mount-DiskImage failed: $_" "VERBOSE"
        }
        
        Write-LogMessage "Falling back to extraction method..." "VERBOSE"
        
        # Fallback: Extract ISO contents and use subst
        $driveLetter = $MountLetter.TrimEnd('\').TrimEnd(':')
        
        try {
            # Create extraction directory
            $extractDir = "C:\TEMP_ISO_EXTRACT_$(Get-Random)"
            New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
            Write-LogMessage "Created extraction directory: $extractDir" "VERBOSE"
            
            # Copy ISO to temp location if path is too long
            $tempISOPath = $ISOPath
            if ($ISOPath.Length -gt 200) {
                $tempDir = "C:\TEMP_ISO"
                if (-not (Test-Path $tempDir)) {
                    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                }
                $tempISOPath = Join-Path $tempDir "temp.iso"
                Write-LogMessage "Copying ISO to temporary location due to long path..." "VERBOSE"
                Copy-Item -Path $ISOPath -Destination $tempISOPath -Force
                Write-LogMessage "Copied ISO to: $tempISOPath" "VERBOSE"
            }
            
            # Try to extract ISO using expand command
            Write-LogMessage "Extracting ISO contents using expand command..." "VERBOSE"
            $expandOutput = & expand.exe "$tempISOPath" -F:* "$extractDir\" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                # Check if sources folder exists in extracted content
                $sourcesPath = Join-Path $extractDir "sources"
                if (Test-Path $sourcesPath) {
                    Write-LogMessage "Successfully extracted ISO, found sources folder" "SUCCESS"
                    
                    # Use subst to map the extracted directory to drive letter
                    Write-LogMessage "Mapping extracted directory to drive $driveLetter using subst..." "VERBOSE"
                    $substOutput = & subst.exe "${driveLetter}:" "$extractDir" 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "Successfully mapped extracted ISO to drive ${driveLetter}: using subst" "SUCCESS"
                        
                        # Verify mapping worked
                        $verifyPath = "${driveLetter}:\sources"
                        if (Test-Path $verifyPath) {
                            return @{ 
                                Success = $true
                                Message = "ISO extracted and mapped successfully"
                                ActualDrive = "${driveLetter}:"
                                MountMethod = "Extract+Subst"
                                ExtractDir = $extractDir
                            }
                        } else {
                            Write-LogMessage "Subst mapping failed verification" "ERROR"
                        }
                    } else {
                        Write-LogMessage "Subst command failed: $($substOutput -join ' ')" "ERROR"
                    }
                } else {
                    Write-LogMessage "Extracted ISO but no sources folder found" "ERROR"
                }
            } else {
                Write-LogMessage "Expand command failed: $($expandOutput -join ' ')" "ERROR"
            }
            
            # Clean up temporary files if extraction failed
            if (Test-Path $extractDir) {
                Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($tempISOPath -ne $ISOPath -and (Test-Path $tempISOPath)) {
                Remove-Item -Path $tempISOPath -Force -ErrorAction SilentlyContinue
            }
            
        } catch {
            Write-LogMessage "Extract/subst approach failed: $_" "ERROR"
        }
        
        # Final attempt: Look for any newly appeared CD drives with sources folder
        Write-LogMessage "Final attempt: Scanning for any mounted CD drives..." "VERBOSE"
        
        $allCDDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
            $_.DriveType -eq 5 
        } | ForEach-Object { $_.DeviceID.Replace(':', '') }
        
        foreach ($drive in $allCDDrives) {
            $drivePath = "${drive}:"
            $sourcesPath = Join-Path $drivePath "sources"
            if (Test-Path $sourcesPath) {
                Write-LogMessage "Found CD drive with sources folder: $drivePath" "SUCCESS"
                return @{ 
                    Success = $true
                    Message = "Found existing mounted ISO"
                    ActualDrive = $drivePath
                    MountMethod = "Detected"
                }
            }
        }
        
        # Return failure if all methods failed
        Write-LogMessage "All ISO mounting methods failed in this WinPE environment" "ERROR"
        return @{ Success = $false; Message = "All ISO mounting methods failed in this WinPE environment" }
        
    } catch {
        Write-LogMessage "Exception in Mount-ISOWithDiskpart: $_" "ERROR"
        return @{ Success = $false; Message = "Exception: $($_.Exception.Message)" }
    }
}

function Dismount-ISOWithDiskpart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MountLetter
    )
    
    try {
        $driveLetter = $MountLetter.TrimEnd('\').TrimEnd(':')
        
        Write-LogMessage "Attempting to dismount drive: $driveLetter" "VERBOSE"
        
        # First try to remove subst mapping
        try {
            $substOutput = & subst.exe "${driveLetter}:" /D 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully removed subst mapping for $driveLetter" "SUCCESS"
                
                # Clean up extraction directory if it exists
                $tempDirs = Get-ChildItem -Path "C:\" -Directory -Name "TEMP_ISO_EXTRACT_*" -ErrorAction SilentlyContinue
                foreach ($tempDir in $tempDirs) {
                    try {
                        $fullPath = "C:\$tempDir"
                        Remove-Item -Path $fullPath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogMessage "Cleaned up extraction directory: $fullPath" "VERBOSE"
                    } catch {
                        # Ignore cleanup errors
                    }
                }
                
                return @{ Success = $true; Message = "Subst mapping removed successfully" }
            }
        } catch {
            Write-LogMessage "Subst removal failed (may not be subst mounted): $_" "VERBOSE"
        }
        
        # Try PowerShell dismount for any mounted disk images
        try {
            $mountedImages = Get-DiskImage | Where-Object { $_.Attached -eq $true }
            foreach ($image in $mountedImages) {
                try {
                    # Check if this is our ISO by looking for a CD drive with 0 free space
                    $cdDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
                        $_.DriveType -eq 5 -and $_.FreeSpace -eq 0 
                    }
                    
                    foreach ($cdDrive in $cdDrives) {
                        $cdDriveLetter = $cdDrive.DeviceID.Replace(':', '')
                        if ($cdDriveLetter -eq $driveLetter) {
                            # Found our mounted ISO
                            Dismount-DiskImage -ImagePath $image.ImagePath -ErrorAction Stop
                            Write-LogMessage "Successfully dismounted PowerShell disk image for drive $driveLetter" "SUCCESS"
                            return @{ Success = $true; Message = "ISO dismounted successfully" }
                        }
                    }
                } catch {
                    # Continue to next image
                    continue
                }
            }
            
            # If no specific match found, try dismounting any attached ISO
            foreach ($image in $mountedImages) {
                try {
                    if ($image.ImagePath -like "*.iso") {
                        Dismount-DiskImage -ImagePath $image.ImagePath -ErrorAction Stop
                        Write-LogMessage "Dismounted ISO image: $($image.ImagePath)" "SUCCESS"
                        return @{ Success = $true; Message = "ISO dismounted successfully" }
                    }
                } catch {
                    continue
                }
            }
            
        } catch {
            Write-LogMessage "PowerShell dismount attempt failed: $_" "VERBOSE"
        }
        
        Write-LogMessage "Dismount completed (drive may have been already unmounted)" "INFO"
        return @{ Success = $true; Message = "Dismount completed" }
        
    } catch {
        Write-LogMessage "Exception in Dismount-ISOWithDiskpart: $_" "ERROR"
        return @{ Success = $false; Message = "Exception: $($_.Exception.Message)" }
    }
}

function Dismount-ISOAfterDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath
    )
    
    try {
        Write-LogMessage "Dismounting ISO after deployment: $ISOPath" "INFO"
        
        # First check if the ISO file path makes sense
        if ([string]::IsNullOrWhiteSpace($ISOPath) -or $ISOPath -like "*install.wim*" -or $ISOPath -like "*install.esd*") {
            Write-LogMessage "Invalid ISO path provided for dismount (looks like install.wim path): $ISOPath" "WARNING"
            Write-LogMessage "Skipping dismount - path appears to be install.wim rather than original ISO" "INFO"
            return
        }
        
        # Find mounted ISO by looking for CD drives with 0 bytes free and sources folder
        $cdDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { 
            $_.DriveType -eq 5 -and $_.FreeSpace -eq 0 
        }
        
        $foundMountedISO = $false
        
        foreach ($cdDrive in $cdDrives) {
            $driveLetter = $cdDrive.DeviceID.Replace(':', '')
            $drivePath = "${driveLetter}:"
            
            # Check if this drive has the sources folder (indicating it's our mounted ISO)
            $sourcesPath = Join-Path $drivePath "sources"
            if (Test-Path $sourcesPath) {
                Write-LogMessage "Found mounted ISO at: $drivePath (CD drive with 0 free space)" "VERBOSE"
                $dismountResult = Dismount-ISOWithDiskpart -MountLetter $drivePath
                if ($dismountResult.Success) {
                    Write-LogMessage "Successfully dismounted ISO from: $drivePath" "SUCCESS"
                } else {
                    Write-LogMessage "Dismount failed: $($dismountResult.Message)" "WARNING"
                }
                $foundMountedISO = $true
                return
            }
        }
        
        # Fallback: Check available letters that might have subst mappings
        $availableLetters = 'I','J','K','L','M','N','O','P','Q','R','S','T','U'
        foreach ($letter in $availableLetters) {
            $drivePath = "${letter}:"
            if (Test-Path $drivePath) {
                # Check if this drive has the sources folder
                $sourcesPath = Join-Path $drivePath "sources"
                if (Test-Path $sourcesPath) {
                    Write-LogMessage "Found mounted ISO at: $drivePath (subst mapping)" "VERBOSE"
                    $dismountResult = Dismount-ISOWithDiskpart -MountLetter $drivePath
                    if ($dismountResult.Success) {
                        Write-LogMessage "Successfully dismounted ISO from: $drivePath" "SUCCESS"
                    } else {
                        Write-LogMessage "Dismount failed: $($dismountResult.Message)" "WARNING"
                    }
                    $foundMountedISO = $true
                    return
                }
            }
        }
        
        if (-not $foundMountedISO) {
            Write-LogMessage "No mounted ISO found to dismount - may already be dismounted or deployment was successful" "INFO"
        }
        
    } catch {
        Write-LogMessage "Warning: Failed to dismount ISO: $_" "WARNING"
    }
}

function Get-AvailableDriveLetter {
    [CmdletBinding()]
    param()
    
    try {
        # Get all used drive letters
        $usedLetters = @()
        $usedLetters += (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name })
        $usedLetters += (Get-WmiObject -Class Win32_LogicalDisk | ForEach-Object { $_.DeviceID.Replace(':', '') })
        
        # Remove duplicates and convert to uppercase
        $usedLetters = $usedLetters | Sort-Object -Unique | ForEach-Object { $_.ToUpper() }
        
        Write-LogMessage "Currently used drive letters: $($usedLetters -join ', ')" "VERBOSE"
        
        # Find first available letter (avoiding system letters and network drives)
        $availableLetters = 'I','J','K','L','M','N','O','P','Q','R','S','T','U'
        foreach ($letter in $availableLetters) {
            if ($letter -notin $usedLetters) {
                $drivePath = "${letter}:\\"
                Write-LogMessage "Found available drive letter: $letter" "VERBOSE"
                return $drivePath
            }
        }
        
        throw "No available drive letters found"
        
    } catch {
        Write-LogMessage "Error finding available drive letter: $_" "ERROR"
        throw $_
    }
}

function Get-DismMountedImages {
    [CmdletBinding()]
    param()
    
    try {
        $mountedImages = @()
        $dismOutput = & dism.exe /Get-MountedImageInfo 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "DISM Get-MountedImageInfo failed: $($dismOutput -join ' ')" "WARNING"
            return @()
        }
        
        $currentMount = $null
        foreach ($line in $dismOutput) {
            if ($line -match "Mount Dir\s*:\s*(.+)") {
                if ($currentMount) {
                    $mountedImages += $currentMount
                }
                $currentMount = @{
                    MountDir = $matches[1].Trim()
                    ImagePath = ""
                    ImageIndex = ""
                    Status = ""
                }
            } elseif ($line -match "Image File\s*:\s*(.+)") {
                if ($currentMount) {
                    $currentMount.ImagePath = $matches[1].Trim()
                }
            } elseif ($line -match "Image Index\s*:\s*(.+)") {
                if ($currentMount) {
                    $currentMount.ImageIndex = $matches[1].Trim()
                }
            } elseif ($line -match "Status\s*:\s*(.+)") {
                if ($currentMount) {
                    $currentMount.Status = $matches[1].Trim()
                }
            }
        }
        
        # Add the last mount if it exists
        if ($currentMount) {
            $mountedImages += $currentMount
        }
        
        return $mountedImages
        
    } catch {
        Write-LogMessage "Error getting mounted images info: $_" "WARNING"
        return @()
    }
}

Export-ModuleMember -Function Get-ISOImageInfo, Mount-ISOForDeployment, Dismount-ISOAfterDeployment
