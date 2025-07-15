function Get-DeviceInformation {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Gathering device information..." "INFO"
        
        # Get computer system info
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction Stop
        $processor = Get-WmiObject -Class Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $memory = Get-WmiObject -Class Win32_PhysicalMemory -ErrorAction Stop
        
        # Calculate total memory
        $totalMemoryGB = [Math]::Round(($memory | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
        
        # Clean strings
        $manufacturer = $computerSystem.Manufacturer.Trim() -replace '[^\w\-\.]', '_'
        $model = $computerSystem.Model.Trim() -replace '[^\w\-\.]', '_'
        $serialNumber = $bios.SerialNumber.Trim()
        
        $deviceInfo = @{
            Manufacturer = $manufacturer
            Model = $model
            SerialNumber = $serialNumber
            AssetTag = if ($bios.AssetTag -and $bios.AssetTag -ne "0") { $bios.AssetTag } else { "Not Set" }
            MemoryTotal = "$totalMemoryGB GB"
            Processor = $processor.Name.Trim()
            BIOSVersion = $bios.SMBIOSBIOSVersion
            SystemType = $computerSystem.PCSystemType
            TotalPhysicalMemory = $computerSystem.TotalPhysicalMemory
            Domain = $computerSystem.Domain
            Workgroup = $computerSystem.Workgroup
        }
        
        Write-LogMessage "Device detected: $manufacturer $model (S/N: $serialNumber)" "SUCCESS"
        return $deviceInfo
    }
    catch {
        Write-LogMessage "Failed to get device information: $_" "ERROR"
        
        # Return minimal info
        return @{
            Manufacturer = "Unknown"
            Model = "Unknown"
            SerialNumber = "Unknown"
            AssetTag = "Unknown"
            MemoryTotal = "Unknown"
            Processor = "Unknown"
            BIOSVersion = "Unknown"
            SystemType = 0
            TotalPhysicalMemory = 0
            Domain = "Unknown"
            Workgroup = "Unknown"
        }
    }
}

function Get-DiskInformation {
    [CmdletBinding()]
    param()
    
    try {
        $disks = Get-WmiObject -Class Win32_DiskDrive
        $diskInfo = @()
        
        foreach ($disk in $disks) {
            $diskInfo += @{
                Index = $disk.Index
                Model = $disk.Model
                Size = [Math]::Round($disk.Size / 1GB, 2)
                Interface = $disk.InterfaceType
                SerialNumber = $disk.SerialNumber
                MediaType = $disk.MediaType
            }
        }
        
        return $diskInfo
    }
    catch {
        Write-LogMessage "Failed to get disk information: $_" "WARNING"
        return @()
    }
}

function Get-SystemDeviceInfo {
    [CmdletBinding()]
    param()
    
    try {
        $deviceInfo = @{
            Manufacturer = "Unknown"
            Model = "Unknown"
            SerialNumber = "Unknown"
            AssetTag = "Unknown"
            SKU = "Unknown"
            UUID = "Unknown"
        }
        
        # Get computer system information
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem) {
                $deviceInfo.Manufacturer = if ($computerSystem.Manufacturer) { $computerSystem.Manufacturer.Trim() } else { "Unknown" }
                $deviceInfo.Model = if ($computerSystem.Model) { $computerSystem.Model.Trim() } else { "Unknown" }
                
                # Clean up common manufacturer variations
                if ($deviceInfo.Manufacturer -eq "System manufacturer") { $deviceInfo.Manufacturer = "Unknown" }
                if ($deviceInfo.Model -eq "System Product Name") { $deviceInfo.Model = "Unknown" }
            }
        } catch {
            Write-Warning "Failed to get computer system info: $_"
        }
        
        # Get BIOS information
        try {
            $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction Stop
            if ($bios) {
                $deviceInfo.SerialNumber = if ($bios.SerialNumber) { $bios.SerialNumber.Trim() } else { "Unknown" }
                
                # Clean up common serial number variations
                if ($deviceInfo.SerialNumber -eq "To Be Filled By O.E.M.") { $deviceInfo.SerialNumber = "Unknown" }
                if ($deviceInfo.SerialNumber -eq "System Serial Number") { $deviceInfo.SerialNumber = "Unknown" }
            }
        } catch {
            Write-Warning "Failed to get BIOS info: $_"
        }
        
        # Get system enclosure for asset tag
        try {
            $enclosure = Get-WmiObject -Class Win32_SystemEnclosure -ErrorAction Stop
            if ($enclosure) {
                $deviceInfo.AssetTag = if ($enclosure.SMBIOSAssetTag) { $enclosure.SMBIOSAssetTag.Trim() } else { "Unknown" }
                $deviceInfo.SKU = if ($enclosure.SKU) { $enclosure.SKU.Trim() } else { "Unknown" }
            }
        } catch {
            Write-Warning "Failed to get system enclosure info: $_"
        }
        
        # Get UUID from computer system product
        try {
            $product = Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction Stop
            if ($product) {
                $deviceInfo.UUID = if ($product.UUID) { $product.UUID.Trim() } else { "Unknown" }
            }
        } catch {
            Write-Warning "Failed to get computer system product info: $_"
        }
        
        return $deviceInfo
        
    } catch {
        Write-Error "Failed to collect device information: $_"
        return @{
            Manufacturer = "Unknown"
            Model = "Unknown"
            SerialNumber = "Unknown"
            AssetTag = "Unknown"
            SKU = "Unknown"
            UUID = "Unknown"
        }
    }
}

Export-ModuleMember -Function Get-DeviceInformation, Get-DiskInformation, Get-SystemDeviceInfo
