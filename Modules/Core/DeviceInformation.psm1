# Device Information Module
# Provides comprehensive hardware information gathering for deployment tracking

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

function Get-DeviceInformation {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Gathering comprehensive device information..." "INFO"
        $startTime = Get-Date
        
        # Initialize device info hashtable
        $deviceInfo = @{
            GatheredAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            BasicInfo = @{}
            SystemSpecs = @{}
            Storage = @{}
            Network = @{}
            Memory = @{}
            Processor = @{}
            Graphics = @{}
            Audio = @{}
            USB = @{}
            BIOS = @{}
            Motherboard = @{}
            PowerSupply = @{}
            Errors = @()
        }
        
        # Get basic system information (WMI)
        Write-LogMessage "Collecting basic system information..." "INFO"
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
            $biosInfo = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
            $baseBoard = Get-WmiObject -Class Win32_BaseBoard -ErrorAction SilentlyContinue
            $systemEnclosure = Get-WmiObject -Class Win32_SystemEnclosure -ErrorAction SilentlyContinue
            
            if ($computerSystem) {
                $deviceInfo.BasicInfo.Manufacturer = if ($computerSystem.Manufacturer) { $computerSystem.Manufacturer.Trim() } else { "Unknown" }
                $deviceInfo.BasicInfo.Model = if ($computerSystem.Model) { $computerSystem.Model.Trim() } else { "Unknown" }
                $deviceInfo.BasicInfo.TotalPhysicalMemoryGB = [Math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
                $deviceInfo.BasicInfo.Domain = $computerSystem.Domain
                $deviceInfo.BasicInfo.Workgroup = $computerSystem.Workgroup
                $deviceInfo.BasicInfo.UserName = $computerSystem.UserName
                $deviceInfo.BasicInfo.SystemType = $computerSystem.SystemType
                $deviceInfo.BasicInfo.PCSystemType = $computerSystem.PCSystemType
                
                Write-LogMessage "Found system: $($deviceInfo.BasicInfo.Manufacturer) $($deviceInfo.BasicInfo.Model)" "INFO"
            }
            
            if ($biosInfo) {
                $deviceInfo.BasicInfo.SerialNumber = if ($biosInfo.SerialNumber) { $biosInfo.SerialNumber.Trim() } else { "Unknown" }
                $deviceInfo.BIOS.Version = $biosInfo.SMBIOSBIOSVersion
                $deviceInfo.BIOS.ReleaseDate = $biosInfo.ReleaseDate
                $deviceInfo.BIOS.Manufacturer = $biosInfo.Manufacturer
                
                Write-LogMessage "Found serial number: $($deviceInfo.BasicInfo.SerialNumber)" "INFO"
            }
            
            if ($systemEnclosure) {
                $deviceInfo.BasicInfo.AssetTag = if ($systemEnclosure.SMBIOSAssetTag) { $systemEnclosure.SMBIOSAssetTag.Trim() } else { $null }
                $deviceInfo.BasicInfo.ChassisTypes = $systemEnclosure.ChassisTypes
                
                if ($deviceInfo.BasicInfo.AssetTag -and $deviceInfo.BasicInfo.AssetTag -ne "No Asset Tag" -and $deviceInfo.BasicInfo.AssetTag -ne "None") {
                    Write-LogMessage "Found asset tag: $($deviceInfo.BasicInfo.AssetTag)" "INFO"
                } else {
                    $deviceInfo.BasicInfo.AssetTag = $null
                    Write-LogMessage "No asset tag found or tag is generic" "INFO"
                }
            }
            
            if ($baseBoard) {
                $deviceInfo.Motherboard.Manufacturer = $baseBoard.Manufacturer
                $deviceInfo.Motherboard.Product = $baseBoard.Product
                $deviceInfo.Motherboard.Version = $baseBoard.Version
                $deviceInfo.Motherboard.SerialNumber = $baseBoard.SerialNumber
            }
            
        } catch {
            $deviceInfo.Errors += "Failed to get basic system info: $_"
            Write-LogMessage "Error getting basic system info: $_" "ERROR"
        }
        
        # Get processor information
        Write-LogMessage "Collecting processor information..." "INFO"
        try {
            $processors = Get-WmiObject -Class Win32_Processor -ErrorAction SilentlyContinue
            $deviceInfo.Processor.Count = $processors.Count
            $deviceInfo.Processor.Details = @()
            
            foreach ($proc in $processors) {
                $procInfo = @{
                    Name = $proc.Name
                    Manufacturer = $proc.Manufacturer
                    MaxClockSpeed = $proc.MaxClockSpeed
                    NumberOfCores = $proc.NumberOfCores
                    NumberOfLogicalProcessors = $proc.NumberOfLogicalProcessors
                    Architecture = $proc.Architecture
                    Family = $proc.Family
                    Level = $proc.Level
                    Revision = $proc.Revision
                    ProcessorId = $proc.ProcessorId
                    SocketDesignation = $proc.SocketDesignation
                }
                $deviceInfo.Processor.Details += $procInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Processor.Count) processor(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get processor info: $_"
            Write-LogMessage "Error getting processor info: $_" "ERROR"
        }
        
        # Get memory information
        Write-LogMessage "Collecting memory information..." "INFO"
        try {
            $memoryModules = Get-WmiObject -Class Win32_PhysicalMemory -ErrorAction SilentlyContinue
            $deviceInfo.Memory.TotalModules = $memoryModules.Count
            $deviceInfo.Memory.TotalCapacityGB = [Math]::Round(($memoryModules | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
            $deviceInfo.Memory.Details = @()
            
            foreach ($mem in $memoryModules) {
                $memInfo = @{
                    BankLabel = $mem.BankLabel
                    DeviceLocator = $mem.DeviceLocator
                    CapacityGB = [Math]::Round($mem.Capacity / 1GB, 2)
                    Speed = $mem.Speed
                    Manufacturer = $mem.Manufacturer
                    PartNumber = if ($mem.PartNumber) { $mem.PartNumber.Trim() } else { "" }
                    SerialNumber = if ($mem.SerialNumber) { $mem.SerialNumber.Trim() } else { "" }
                    TypeDetail = $mem.TypeDetail
                    FormFactor = $mem.FormFactor
                }
                $deviceInfo.Memory.Details += $memInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Memory.TotalModules) memory module(s), total: $($deviceInfo.Memory.TotalCapacityGB) GB" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get memory info: $_"
            Write-LogMessage "Error getting memory info: $_" "ERROR"
        }
        
        # Get storage information
        Write-LogMessage "Collecting storage information..." "INFO"
        try {
            $diskDrives = Get-WmiObject -Class Win32_DiskDrive -ErrorAction SilentlyContinue
            $logicalDisks = Get-WmiObject -Class Win32_LogicalDisk -ErrorAction SilentlyContinue
            
            $deviceInfo.Storage.PhysicalDrives = @()
            $deviceInfo.Storage.LogicalDrives = @()
            
            foreach ($disk in $diskDrives) {
                $diskInfo = @{
                    Model = $disk.Model
                    Manufacturer = $disk.Manufacturer
                    SerialNumber = if ($disk.SerialNumber) { $disk.SerialNumber.Trim() } else { "" }
                    SizeGB = [Math]::Round($disk.Size / 1GB, 2)
                    InterfaceType = $disk.InterfaceType
                    MediaType = $disk.MediaType
                    Partitions = $disk.Partitions
                    Index = $disk.Index
                    DeviceID = $disk.DeviceID
                }
                $deviceInfo.Storage.PhysicalDrives += $diskInfo
            }
            
            foreach ($logical in $logicalDisks) {
                $logicalInfo = @{
                    DeviceID = $logical.DeviceID
                    VolumeName = $logical.VolumeName
                    FileSystem = $logical.FileSystem
                    SizeGB = [Math]::Round($logical.Size / 1GB, 2)
                    FreeSpaceGB = [Math]::Round($logical.FreeSpace / 1GB, 2)
                    DriveType = $logical.DriveType
                }
                $deviceInfo.Storage.LogicalDrives += $logicalInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Storage.PhysicalDrives.Count) physical drive(s) and $($deviceInfo.Storage.LogicalDrives.Count) logical drive(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get storage info: $_"
            Write-LogMessage "Error getting storage info: $_" "ERROR"
        }
        
        # Get network adapter information
        Write-LogMessage "Collecting network adapter information..." "INFO"
        try {
            $networkAdapters = Get-WmiObject -Class Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalAdapter -eq $true }
            $deviceInfo.Network.Adapters = @()
            
            foreach ($adapter in $networkAdapters) {
                $adapterInfo = @{
                    Name = $adapter.Name
                    Manufacturer = $adapter.Manufacturer
                    MACAddress = $adapter.MACAddress
                    AdapterType = $adapter.AdapterType
                    Speed = $adapter.Speed
                    DeviceID = $adapter.DeviceID
                    NetEnabled = $adapter.NetEnabled
                    PhysicalAdapter = $adapter.PhysicalAdapter
                }
                $deviceInfo.Network.Adapters += $adapterInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Network.Adapters.Count) network adapter(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get network info: $_"
            Write-LogMessage "Error getting network info: $_" "ERROR"
        }
        
        # Get graphics information
        Write-LogMessage "Collecting graphics information..." "INFO"
        try {
            $videoControllers = Get-WmiObject -Class Win32_VideoController -ErrorAction SilentlyContinue
            $deviceInfo.Graphics.Controllers = @()
            
            foreach ($video in $videoControllers) {
                $videoInfo = @{
                    Name = $video.Name
                    AdapterRAM = if ($video.AdapterRAM) { [Math]::Round($video.AdapterRAM / 1MB, 2) } else { 0 }
                    DriverVersion = $video.DriverVersion
                    DriverDate = $video.DriverDate
                    VideoProcessor = $video.VideoProcessor
                    VideoArchitecture = $video.VideoArchitecture
                    VideoMemoryType = $video.VideoMemoryType
                    CurrentHorizontalResolution = $video.CurrentHorizontalResolution
                    CurrentVerticalResolution = $video.CurrentVerticalResolution
                    CurrentBitsPerPixel = $video.CurrentBitsPerPixel
                    CurrentRefreshRate = $video.CurrentRefreshRate
                }
                $deviceInfo.Graphics.Controllers += $videoInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Graphics.Controllers.Count) graphics controller(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get graphics info: $_"
            Write-LogMessage "Error getting graphics info: $_" "ERROR"
        }
        
        # Get audio information
        Write-LogMessage "Collecting audio information..." "INFO"
        try {
            $soundDevices = Get-WmiObject -Class Win32_SoundDevice -ErrorAction SilentlyContinue
            $deviceInfo.Audio.Devices = @()
            
            foreach ($sound in $soundDevices) {
                $soundInfo = @{
                    Name = $sound.Name
                    Manufacturer = $sound.Manufacturer
                    DeviceID = $sound.DeviceID
                    Status = $sound.Status
                }
                $deviceInfo.Audio.Devices += $soundInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.Audio.Devices.Count) audio device(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get audio info: $_"
            Write-LogMessage "Error getting audio info: $_" "ERROR"
        }
        
        # Get USB controller information
        Write-LogMessage "Collecting USB controller information..." "INFO"
        try {
            $usbControllers = Get-WmiObject -Class Win32_USBController -ErrorAction SilentlyContinue
            $deviceInfo.USB.Controllers = @()
            
            foreach ($usb in $usbControllers) {
                $usbInfo = @{
                    Name = $usb.Name
                    Manufacturer = $usb.Manufacturer
                    DeviceID = $usb.DeviceID
                    Status = $usb.Status
                }
                $deviceInfo.USB.Controllers += $usbInfo
            }
            
            Write-LogMessage "Found $($deviceInfo.USB.Controllers.Count) USB controller(s)" "INFO"
        } catch {
            $deviceInfo.Errors += "Failed to get USB info: $_"
            Write-LogMessage "Error getting USB info: $_" "ERROR"
        }
        
        # Get additional system specs using CIM (if available)
        Write-LogMessage "Collecting additional system specifications..." "INFO"
        try {
            # Try to get additional info using Get-ComputerInfo if available
            if (Get-Command Get-ComputerInfo -ErrorAction SilentlyContinue) {
                $computerInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
                if ($computerInfo) {
                    $deviceInfo.SystemSpecs.WindowsVersion = $computerInfo.WindowsVersion
                    $deviceInfo.SystemSpecs.WindowsBuildLabEx = $computerInfo.WindowsBuildLabEx
                    $deviceInfo.SystemSpecs.WindowsInstallationType = $computerInfo.WindowsInstallationType
                    $deviceInfo.SystemSpecs.TotalPhysicalMemoryGB = [Math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
                    $deviceInfo.SystemSpecs.CsProcessors = $computerInfo.CsProcessors.Count
                    $deviceInfo.SystemSpecs.TimeZone = $computerInfo.TimeZone
                    $deviceInfo.SystemSpecs.PowerPlatformRole = $computerInfo.PowerPlatformRole
                    $deviceInfo.SystemSpecs.HyperVisorPresent = $computerInfo.HyperVisorPresent
                    $deviceInfo.SystemSpecs.DeviceGuardSmartStatus = $computerInfo.DeviceGuardSmartStatus
                }
            }
        } catch {
            Write-LogMessage "Could not get additional system specs: $_" "WARNING"
        }
        
        # Create summary for quick reference
        $deviceInfo.Summary = @{
            Manufacturer = $deviceInfo.BasicInfo.Manufacturer
            Model = $deviceInfo.BasicInfo.Model  
            SerialNumber = $deviceInfo.BasicInfo.SerialNumber
            AssetTag = $deviceInfo.BasicInfo.AssetTag
            ProcessorCount = $deviceInfo.Processor.Count
            TotalMemoryGB = $deviceInfo.Memory.TotalCapacityGB
            StorageDevices = $deviceInfo.Storage.PhysicalDrives.Count
            NetworkAdapters = $deviceInfo.Network.Adapters.Count
            HasErrors = $deviceInfo.Errors.Count -gt 0
            ErrorCount = $deviceInfo.Errors.Count
        }
        
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        Write-LogMessage "Device information gathering completed in $duration seconds" "INFO"
        
        if ($deviceInfo.Errors.Count -gt 0) {
            Write-LogMessage "Gathering completed with $($deviceInfo.Errors.Count) error(s)" "WARNING"
            foreach ($error in $deviceInfo.Errors) {
                Write-LogMessage "Error: $error" "WARNING"
            }
        }
        
        return $deviceInfo
        
    } catch {
        Write-LogMessage "Critical error in device information gathering: $_" "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
            BasicInfo = @{
                Manufacturer = "Unknown"
                Model = "Unknown" 
                SerialNumber = "Unknown"
                AssetTag = $null
            }
        }
    }
}

function Format-DeviceInformationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DeviceInfo,
        
        [Parameter()]
        [string]$OutputPath = $null
    )
    
    try {
        Write-LogMessage "Formatting device information report..." "INFO"
        
        $report = @"
================================
DEVICE INFORMATION REPORT
================================
Generated: $($DeviceInfo.GatheredAt)

BASIC INFORMATION
-----------------
Manufacturer: $($DeviceInfo.BasicInfo.Manufacturer)
Model: $($DeviceInfo.BasicInfo.Model)
Serial Number: $($DeviceInfo.BasicInfo.SerialNumber)
Asset Tag: $(if ($DeviceInfo.BasicInfo.AssetTag) { $DeviceInfo.BasicInfo.AssetTag } else { 'Not Available' })
System Type: $($DeviceInfo.BasicInfo.SystemType)
PC System Type: $($DeviceInfo.BasicInfo.PCSystemType)

PROCESSOR INFORMATION
--------------------
Processor Count: $($DeviceInfo.Processor.Count)
"@

        foreach ($proc in $DeviceInfo.Processor.Details) {
            $report += @"

Processor: $($proc.Name)
  Manufacturer: $($proc.Manufacturer)
  Cores: $($proc.NumberOfCores)
  Logical Processors: $($proc.NumberOfLogicalProcessors)
  Max Clock Speed: $($proc.MaxClockSpeed) MHz
  Socket: $($proc.SocketDesignation)
"@
        }

        $report += @"

MEMORY INFORMATION
------------------
Total Memory: $($DeviceInfo.Memory.TotalCapacityGB) GB
Memory Modules: $($DeviceInfo.Memory.TotalModules)
"@

        foreach ($mem in $DeviceInfo.Memory.Details) {
            $report += @"

Module: $($mem.DeviceLocator) ($($mem.BankLabel))
  Capacity: $($mem.CapacityGB) GB
  Speed: $($mem.Speed) MHz
  Manufacturer: $($mem.Manufacturer)
  Part Number: $($mem.PartNumber)
"@
        }

        $report += @"

STORAGE INFORMATION
-------------------
Physical Drives: $($DeviceInfo.Storage.PhysicalDrives.Count)
"@

        foreach ($drive in $DeviceInfo.Storage.PhysicalDrives) {
            $report += @"

Drive: $($drive.Model)
  Manufacturer: $($drive.Manufacturer)
  Serial: $($drive.SerialNumber)
  Size: $($drive.SizeGB) GB
  Interface: $($drive.InterfaceType)
  Media Type: $($drive.MediaType)
"@
        }

        $report += @"

NETWORK ADAPTERS
----------------
"@

        foreach ($adapter in $DeviceInfo.Network.Adapters) {
            $report += @"

Adapter: $($adapter.Name)
  Manufacturer: $($adapter.Manufacturer)
  MAC Address: $($adapter.MACAddress)
  Type: $($adapter.AdapterType)
  Enabled: $($adapter.NetEnabled)
"@
        }

        $report += @"

GRAPHICS CONTROLLERS
--------------------
"@

        foreach ($gpu in $DeviceInfo.Graphics.Controllers) {
            $report += @"

Controller: $($gpu.Name)
  Video RAM: $($gpu.AdapterRAM) MB
  Current Resolution: $($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)
  Bits Per Pixel: $($gpu.CurrentBitsPerPixel)
  Refresh Rate: $($gpu.CurrentRefreshRate) Hz
"@
        }

        $report += @"

MOTHERBOARD INFORMATION
-----------------------
Manufacturer: $($DeviceInfo.Motherboard.Manufacturer)
Product: $($DeviceInfo.Motherboard.Product)
Version: $($DeviceInfo.Motherboard.Version)
Serial Number: $($DeviceInfo.Motherboard.SerialNumber)

BIOS INFORMATION
----------------
Manufacturer: $($DeviceInfo.BIOS.Manufacturer)
Version: $($DeviceInfo.BIOS.Version)
Release Date: $($DeviceInfo.BIOS.ReleaseDate)

"@

        if ($DeviceInfo.Errors.Count -gt 0) {
            $report += @"

ERRORS ENCOUNTERED
------------------
$($DeviceInfo.Errors.Count) error(s) occurred during information gathering:
"@
            foreach ($error in $DeviceInfo.Errors) {
                $report += "`n- $error"
            }
        }

        $report += @"

================================
END OF REPORT
================================
"@

        if ($OutputPath) {
            try {
                $report | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
                Write-LogMessage "Device information report saved to: $OutputPath" "SUCCESS"
            } catch {
                Write-LogMessage "Failed to save report to file: $_" "ERROR"
            }
        }
        
        return $report
        
    } catch {
        Write-LogMessage "Error formatting device information report: $_" "ERROR"
        return "Error generating report: $($_.Exception.Message)"
    }
}

function Get-DeviceBasicInfo {
    [CmdletBinding()]
    param()
    
    # Quick function to get just the essential info for deployment
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        $biosInfo = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
        $systemEnclosure = Get-WmiObject -Class Win32_SystemEnclosure -ErrorAction SilentlyContinue
        
        $basicInfo = @{
            Manufacturer = if ($computerSystem -and $computerSystem.Manufacturer) { $computerSystem.Manufacturer.Trim() } else { "Unknown" }
            Model = if ($computerSystem -and $computerSystem.Model) { $computerSystem.Model.Trim() } else { "Unknown" }
            SerialNumber = if ($biosInfo -and $biosInfo.SerialNumber) { $biosInfo.SerialNumber.Trim() } else { "Unknown" }
            AssetTag = $null
        }
        
        if ($systemEnclosure -and $systemEnclosure.SMBIOSAssetTag) {
            $assetTag = $systemEnclosure.SMBIOSAssetTag.Trim()
            if ($assetTag -and $assetTag -ne "No Asset Tag" -and $assetTag -ne "None" -and $assetTag -ne "Default string") {
                $basicInfo.AssetTag = $assetTag
            }
        }
        
        Write-LogMessage "Basic device info: $($basicInfo.Manufacturer) $($basicInfo.Model) (S/N: $($basicInfo.SerialNumber))" "INFO"
        
        return $basicInfo
        
    } catch {
        Write-LogMessage "Error getting basic device info: $_" "ERROR"
        return @{
            Manufacturer = "Unknown"
            Model = "Unknown"
            SerialNumber = "Unknown"
            AssetTag = $null
        }
    }
}

Export-ModuleMember -Function Get-DeviceInformation, Format-DeviceInformationReport, Get-DeviceBasicInfo
