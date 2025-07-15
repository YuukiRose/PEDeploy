# Boot Configuration Manager Module
# Handles both UEFI and BIOS/Legacy boot configurations based on image compatibility

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

# Windows Version Database - Comprehensive compatibility matrix
$script:WindowsVersionDatabase = @{
    # Windows 11 (all UEFI compatible, BIOS support varies)
    "11.0.22000" = @{ Name = "Windows 11 21H2"; UEFISupported = $true; BIOSSupported = $false; Recommended = "UEFI" }
    "11.0.22621" = @{ Name = "Windows 11 22H2"; UEFISupported = $true; BIOSSupported = $false; Recommended = "UEFI" }
    "11.0.22631" = @{ Name = "Windows 11 23H2"; UEFISupported = $true; BIOSSupported = $false; Recommended = "UEFI" }
    "11.0.26100" = @{ Name = "Windows 11 24H2"; UEFISupported = $true; BIOSSupported = $false; Recommended = "UEFI" }
    
    # Windows 10 (all support both UEFI and BIOS)
    "10.0.19041" = @{ Name = "Windows 10 2004"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.19042" = @{ Name = "Windows 10 20H2"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.19043" = @{ Name = "Windows 10 21H1"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.19044" = @{ Name = "Windows 10 21H2"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.19045" = @{ Name = "Windows 10 22H2"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.18363" = @{ Name = "Windows 10 1909"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.18362" = @{ Name = "Windows 10 1903"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.17763" = @{ Name = "Windows 10 1809"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.17134" = @{ Name = "Windows 10 1803"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.16299" = @{ Name = "Windows 10 1709"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.15063" = @{ Name = "Windows 10 1703"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.14393" = @{ Name = "Windows 10 1607"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.10586" = @{ Name = "Windows 10 1511"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "10.0.10240" = @{ Name = "Windows 10 1507"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    
    # Windows 8.1 (UEFI and BIOS support)
    "6.3.9600"  = @{ Name = "Windows 8.1"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "6.3.9200"  = @{ Name = "Windows 8.1 RTM"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    
    # Windows 8 (UEFI and BIOS support)
    "6.2.9200"  = @{ Name = "Windows 8"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    
    # Windows 7 (BIOS only, no UEFI support)
    "6.1.7601"  = @{ Name = "Windows 7 SP1"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    "6.1.7600"  = @{ Name = "Windows 7 RTM"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    
    # Windows Vista (BIOS only)
    "6.0.6003"  = @{ Name = "Windows Vista SP2"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    "6.0.6002"  = @{ Name = "Windows Vista SP1"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    "6.0.6000"  = @{ Name = "Windows Vista RTM"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    
    # Windows XP (BIOS only)
    "5.1.2600"  = @{ Name = "Windows XP SP3"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    "5.1.2400"  = @{ Name = "Windows XP RTM"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
    
    # Server versions (use unique keys to avoid duplicates)
    "SRV.10.0.20348" = @{ Name = "Windows Server 2022"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "SRV.10.0.17763" = @{ Name = "Windows Server 2019"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "SRV.10.0.14393" = @{ Name = "Windows Server 2016"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "SRV.6.3.9600"  = @{ Name = "Windows Server 2012 R2"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "SRV.6.2.9200"  = @{ Name = "Windows Server 2012"; UEFISupported = $true; BIOSSupported = $true; Recommended = "UEFI" }
    "SRV.6.1.7601"  = @{ Name = "Windows Server 2008 R2"; UEFISupported = $false; BIOSSupported = $true; Recommended = "BIOS" }
}

function Get-WindowsVersionFromImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        Write-LogMessage "Analyzing Windows version from image information" "VERBOSE"
        
        # Method 1: Direct version string parsing
        $detectedVersion = $null
        
        # Check for explicit version information
        if ($ImageInfo.ImageVersion) {
            $detectedVersion = $ImageInfo.ImageVersion
            Write-LogMessage "Found explicit ImageVersion: $detectedVersion" "VERBOSE"
        }
        
        # Method 2: Parse from OSInfo
        if (-not $detectedVersion -and $ImageInfo.OSInfo) {
            $osInfo = $ImageInfo.OSInfo
            if ($osInfo -match "Version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
                $detectedVersion = $matches[1]
                Write-LogMessage "Extracted version from OSInfo: $detectedVersion" "VERBOSE"
            }
        }
        
        # Method 3: Use DISM to get image information
        if (-not $detectedVersion -and $ImageInfo.FullPath -and (Test-Path $ImageInfo.FullPath)) {
            try {
                $imageIndex = if ($ImageInfo.ImageIndex) { $ImageInfo.ImageIndex } else { 1 }
                Write-LogMessage "Querying image with DISM: $($ImageInfo.FullPath), Index: $imageIndex" "VERBOSE"
                
                $dismOutput = & dism.exe /Get-WimInfo /WimFile:"$($ImageInfo.FullPath)" /Index:$imageIndex 2>&1
                
                if ($dismOutput -match "Version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
                    $detectedVersion = $matches[1]
                    Write-LogMessage "DISM detected version: $detectedVersion" "VERBOSE"
                    
                    # Check if this is a server version by looking for server indicators
                    $isServer = $false
                    if ($dismOutput -match "Server|server" -or 
                        $ImageInfo.ImageName -match "Server|server" -or 
                        $ImageInfo.Description -match "Server|server") {
                        $isServer = $true
                        Write-LogMessage "Detected server version based on DISM output or image name" "VERBOSE"
                    }
                    
                    # If it's a server version, prefix with SRV. to use server database entries
                    if ($isServer) {
                        $detectedVersion = "SRV.$detectedVersion"
                        Write-LogMessage "Using server version key: $detectedVersion" "VERBOSE"
                    }
                }
                
                # Also look for build numbers in DISM output
                if ($dismOutput -match "Build\s*:\s*([0-9]+)") {
                    $buildNumber = $matches[1]
                    Write-LogMessage "DISM detected build: $buildNumber" "VERBOSE"
                    
                    # Map common build numbers to versions
                    $detectedVersion = Get-VersionFromBuildNumber -BuildNumber $buildNumber
                }
            } catch {
                Write-LogMessage "Could not query image with DISM: $_" "WARNING"
            }
        }
        
        # Method 4: Parse from image name/description
        if (-not $detectedVersion) {
            $detectedVersion = Get-VersionFromImageName -ImageInfo $ImageInfo
        }
        
        # Method 5: Look for install.wim in mounted ISO
        if (-not $detectedVersion -and $ImageInfo.IsISO) {
            $detectedVersion = Get-VersionFromMountedISO -ImageInfo $ImageInfo
        }
        
        if ($detectedVersion) {
            Write-LogMessage "Final detected Windows version: $detectedVersion" "INFO"
            return $detectedVersion
        } else {
            Write-LogMessage "Could not determine Windows version from image" "WARNING"
            return $null
        }
        
    } catch {
        Write-LogMessage "Error detecting Windows version: $_" "ERROR"
        return $null
    }
}

function Get-VersionFromBuildNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildNumber
    )
    
    # Map common build numbers to version strings
    $buildMap = @{
        "26100" = "11.0.26100"  # Windows 11 24H2
        "22631" = "11.0.22631"  # Windows 11 23H2
        "22621" = "11.0.22621"  # Windows 11 22H2
        "22000" = "11.0.22000"  # Windows 11 21H2
        "19045" = "10.0.19045"  # Windows 10 22H2
        "19044" = "10.0.19044"  # Windows 10 21H2
        "19043" = "10.0.19043"  # Windows 10 21H1
        "19042" = "10.0.19042"  # Windows 10 20H2
        "19041" = "10.0.19041"  # Windows 10 2004
        "18363" = "10.0.18363"  # Windows 10 1909
        "18362" = "10.0.18362"  # Windows 10 1903
        "17763" = "10.0.17763"  # Windows 10 1809
        "17134" = "10.0.17134"  # Windows 10 1803
        "16299" = "10.0.16299"  # Windows 10 1709
        "15063" = "10.0.15063"  # Windows 10 1703
        "14393" = "10.0.14393"  # Windows 10 1607
        "10586" = "10.0.10586"  # Windows 10 1511
        "10240" = "10.0.10240"  # Windows 10 1507
        "9600"  = "6.3.9600"    # Windows 8.1
        "9200"  = "6.2.9200"    # Windows 8
        "7601"  = "6.1.7601"    # Windows 7 SP1
        "7600"  = "6.1.7600"    # Windows 7 RTM
        "6003"  = "6.0.6003"    # Vista SP2
        "6002"  = "6.0.6002"    # Vista SP1
        "6000"  = "6.0.6000"    # Vista RTM
        "2600"  = "5.1.2600"    # Windows XP SP3
        "2400"  = "5.1.2400"    # Windows XP RTM
    }
    
    if ($buildMap.ContainsKey($BuildNumber)) {
        $version = $buildMap[$BuildNumber]
        Write-LogMessage "Mapped build $BuildNumber to version $version" "VERBOSE"
        return $version
    }
    
    # For unknown builds, try to infer based on ranges
    $buildInt = [int]$BuildNumber
    
    if ($buildInt -ge 22000) {
        Write-LogMessage "Build $BuildNumber appears to be Windows 11 (>=22000)" "VERBOSE"
        return "11.0.$BuildNumber"
    } elseif ($buildInt -ge 10240) {
        Write-LogMessage "Build $BuildNumber appears to be Windows 10 (>=10240)" "VERBOSE"
        return "10.0.$BuildNumber"
    } elseif ($buildInt -ge 9200) {
        Write-LogMessage "Build $BuildNumber appears to be Windows 8/8.1 (>=9200)" "VERBOSE"
        return "6.3.$BuildNumber"
    } elseif ($buildInt -ge 7600) {
        Write-LogMessage "Build $BuildNumber appears to be Windows 7 (>=7600)" "VERBOSE"
        return "6.1.$BuildNumber"
    } elseif ($buildInt -ge 6000) {
        Write-LogMessage "Build $BuildNumber appears to be Windows Vista (>=6000)" "VERBOSE"
        return "6.0.$BuildNumber"
    } else {
        Write-LogMessage "Unknown build number: $BuildNumber" "WARNING"
        return $null
    }
}

function Get-VersionFromImageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    $searchStrings = @($ImageInfo.Name, $ImageInfo.ImageName, $ImageInfo.Description, $ImageInfo.Edition)
    
    # Check if this is a server version
    $isServer = $false
    foreach ($searchString in $searchStrings) {
        if ([string]::IsNullOrEmpty($searchString)) { continue }
        if ($searchString -match "Server|server") {
            $isServer = $true
            break
        }
    }
    
    foreach ($searchString in $searchStrings) {
        if ([string]::IsNullOrEmpty($searchString)) { continue }
        
        $detectedVersion = $null
        
        # Windows 11 detection
        if ($searchString -match "Windows\s*11|Win11|W11") {
            if ($searchString -match "24H2|2024") { $detectedVersion = "11.0.26100" }
            elseif ($searchString -match "23H2|2023") { $detectedVersion = "11.0.22631" }
            elseif ($searchString -match "22H2|2022") { $detectedVersion = "11.0.22621" }
            elseif ($searchString -match "21H2|2021") { $detectedVersion = "11.0.22000" }
            else { $detectedVersion = "11.0.22000" }  # Default Windows 11
        }
        # Windows 10 detection
        elseif ($searchString -match "Windows\s*10|Win10|W10") {
            if ($searchString -match "22H2|2022") { $detectedVersion = "10.0.19045" }
            elseif ($searchString -match "21H2") { $detectedVersion = "10.0.19044" }
            elseif ($searchString -match "21H1") { $detectedVersion = "10.0.19043" }
            elseif ($searchString -match "20H2") { $detectedVersion = "10.0.19042" }
            elseif ($searchString -match "2004") { $detectedVersion = "10.0.19041" }
            elseif ($searchString -match "1909") { $detectedVersion = "10.0.18363" }
            elseif ($searchString -match "1903") { $detectedVersion = "10.0.18362" }
            elseif ($searchString -match "1809") { $detectedVersion = "10.0.17763" }
            else { $detectedVersion = "10.0.19045" }  # Default to latest Windows 10
        }
        # Windows 8.1 detection
        elseif ($searchString -match "Windows\s*8\.1|Win8\.1|W8\.1") {
            $detectedVersion = "6.3.9600"
        }
        # Windows 8 detection
        elseif ($searchString -match "Windows\s*8|Win8|W8") {
            $detectedVersion = "6.2.9200"
        }
        # Windows 7 detection
        elseif ($searchString -match "Windows\s*7|Win7|W7") {
            if ($searchString -match "SP1") { $detectedVersion = "6.1.7601" }
            else { $detectedVersion = "6.1.7600" }
        }
        # Windows Vista detection
        elseif ($searchString -match "Windows\s*Vista|Vista") {
            if ($searchString -match "SP2") { $detectedVersion = "6.0.6003" }
            elseif ($searchString -match "SP1") { $detectedVersion = "6.0.6002" }
            else { $detectedVersion = "6.0.6000" }
        }
        # Windows XP detection
        elseif ($searchString -match "Windows\s*XP|XP") {
            $detectedVersion = "5.1.2600"
        }
        # Server 2022 detection
        elseif ($searchString -match "Server\s*2022|2022\s*Server") {
            $detectedVersion = "10.0.20348"
        }
        # Server 2019 detection
        elseif ($searchString -match "Server\s*2019|2019\s*Server") {
            $detectedVersion = "10.0.17763"
        }
        # Server 2016 detection
        elseif ($searchString -match "Server\s*2016|2016\s*Server") {
            $detectedVersion = "10.0.14393"
        }
        # Server 2012 R2 detection
        elseif ($searchString -match "Server\s*2012\s*R2|2012\s*R2\s*Server") {
            $detectedVersion = "6.3.9600"
        }
        # Server 2012 detection
        elseif ($searchString -match "Server\s*2012|2012\s*Server") {
            $detectedVersion = "6.2.9200"
        }
        # Server 2008 R2 detection
        elseif ($searchString -match "Server\s*2008\s*R2|2008\s*R2\s*Server") {
            $detectedVersion = "6.1.7601"
        }
        
        if ($detectedVersion) {
            # If this is a server version, prefix with SRV. to use server database entries
            if ($isServer -and -not $detectedVersion.StartsWith("SRV.")) {
                $detectedVersion = "SRV.$detectedVersion"
                Write-LogMessage "Using server version key: $detectedVersion" "VERBOSE"
            }
            return $detectedVersion
        }
    }
    
    return $null
}

function Get-VersionFromMountedISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        # Check if we have install.wim path from mounted ISO
        if ($ImageInfo.InstallWimPath -and (Test-Path $ImageInfo.InstallWimPath)) {
            Write-LogMessage "Checking install.wim from mounted ISO: $($ImageInfo.InstallWimPath)" "VERBOSE"
            
            $dismOutput = & dism.exe /Get-WimInfo /WimFile:"$($ImageInfo.InstallWimPath)" /Index:1 2>&1
            
            if ($dismOutput -match "Version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
                $version = $matches[1]
                Write-LogMessage "Found version in ISO install.wim: $version" "VERBOSE"
                return $version
            }
            
            if ($dismOutput -match "Build\s*:\s*([0-9]+)") {
                $buildNumber = $matches[1]
                $version = Get-VersionFromBuildNumber -BuildNumber $buildNumber
                Write-LogMessage "Found build in ISO install.wim: $buildNumber -> $version" "VERBOSE"
                return $version
            }
        }
        
        return $null
    } catch {
        Write-LogMessage "Error checking mounted ISO: $_" "WARNING"
        return $null
    }
}

function New-UEFIBootConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo,
        
        [Parameter(Mandatory)]
        [string]$TargetDisk
    )
    
    try {
        Write-LogMessage "Creating UEFI boot configuration for: $($ImageInfo.Name)" "INFO"
        
        # Create EFI system partition with improved error handling
        Write-LogMessage "Creating EFI system partition..." "INFO"
        $efiScript = "$env:TEMP\diskpart_efi_$(Get-Random).txt"
        
        try {
            $efiCommands = @(
                "select disk $TargetDisk",
                "create partition efi size=100",
                "format quick fs=fat32 label=`"System`"",
                "assign letter=S",
                "active",
                "exit"
            )
            
            $efiCommands | Out-File -FilePath $efiScript -Encoding ASCII -Force
            
            Write-LogMessage "Creating EFI partition with commands: $($efiCommands -join '; ')" "VERBOSE"
            
            $efiOutput = & diskpart.exe /s $efiScript 2>&1
            $efiExitCode = $LASTEXITCODE
            
            if ($efiOutput) {
                foreach ($line in $efiOutput) {
                    Write-LogMessage "[DISKPART-EFI] $line" "VERBOSE"
                }
            }
            
            if ($efiExitCode -ne 0) {
                throw "Failed to create EFI system partition. Exit code: $efiExitCode"
            }
            
        } finally {
            if (Test-Path $efiScript) {
                Remove-Item $efiScript -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-LogMessage "Created EFI system partition (100MB)" "SUCCESS"
        
        # Wait for the system to recognize the new partition
        Start-Sleep -Seconds 3
        
        # Verify S: drive exists
        if (-not (Test-Path "S:\")) {
            Write-LogMessage "Warning: S: drive not immediately available, waiting..." "WARNING"
            Start-Sleep -Seconds 5
            if (-not (Test-Path "S:\")) {
                throw "EFI system partition S: is not accessible after creation"
            }
        }
        
        # Create main Windows partition with improved error handling
        Write-LogMessage "Creating main Windows partition..." "INFO"
        $mainScript = "$env:TEMP\diskpart_main_uefi_$(Get-Random).txt"
        
        try {
            $mainCommands = @(
                "select disk $TargetDisk",
                "create partition primary",
                "format quick fs=ntfs label=`"Windows`"",
                "assign letter=W",
                "exit"
            )
            
            $mainCommands | Out-File -FilePath $mainScript -Encoding ASCII -Force
            
            Write-LogMessage "Creating Windows partition with commands: $($mainCommands -join '; ')" "VERBOSE"
            
            $mainOutput = & diskpart.exe /s $mainScript 2>&1
            $mainExitCode = $LASTEXITCODE
            
            if ($mainOutput) {
                foreach ($line in $mainOutput) {
                    Write-LogMessage "[DISKPART-WIN] $line" "VERBOSE"
                }
            }
            
            if ($mainExitCode -ne 0) {
                throw "Failed to create main Windows partition. Exit code: $mainExitCode"
            }
            
        } finally {
            if (Test-Path $mainScript) {
                Remove-Item $mainScript -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-LogMessage "Created main Windows partition" "SUCCESS"
        
        # Copy boot files to EFI partition
        $bootFilesResult = & bcdboot.exe W:\Windows /s S: /f UEFI
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create UEFI boot files"
        }
        
        Write-LogMessage "Successfully created UEFI boot configuration" "SUCCESS"
        
        return @{
            Success = $true
            BootType = "UEFI"
            SystemPartition = "S:"
            WindowsPartition = "W:"
            Message = "UEFI boot configuration created successfully"
        }
        
    } catch {
        Write-LogMessage "Error creating UEFI boot configuration: $_" "ERROR"
        return @{
            Success = $false
            BootType = "UEFI"
            Message = "Failed to create UEFI boot configuration: $_"
        }
    }
}

function New-BIOSBootConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo,
        
        [Parameter(Mandatory)]
        [string]$TargetDisk
    )
    
    try {
        Write-LogMessage "Creating BIOS/Legacy boot configuration for: $($ImageInfo.Name)" "INFO"
        
        # Create system reserved partition for BIOS boot with improved error handling
        Write-LogMessage "Creating system reserved partition..." "INFO"
        $systemScript = "$env:TEMP\diskpart_system_$(Get-Random).txt"
        
        try {
            $systemCommands = @(
                "select disk $TargetDisk",
                "create partition primary size=100",
                "format quick fs=ntfs label=`"System Reserved`"",
                "assign letter=S",
                "active",
                "exit"
            )
            
            $systemCommands | Out-File -FilePath $systemScript -Encoding ASCII -Force
            
            Write-LogMessage "Creating system partition with commands: $($systemCommands -join '; ')" "VERBOSE"
            
            $systemOutput = & diskpart.exe /s $systemScript 2>&1
            $systemExitCode = $LASTEXITCODE
            
            if ($systemOutput) {
                foreach ($line in $systemOutput) {
                    Write-LogMessage "[DISKPART-SYS] $line" "VERBOSE"
                }
            }
            
            if ($systemExitCode -ne 0) {
                throw "Failed to create system reserved partition. Exit code: $systemExitCode"
            }
            
        } finally {
            if (Test-Path $systemScript) {
                Remove-Item $systemScript -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-LogMessage "Created System Reserved partition (100MB)" "SUCCESS"
        
        # Wait for the system to recognize the new partition
        Start-Sleep -Seconds 3
        
        # Verify S: drive exists
        if (-not (Test-Path "S:\")) {
            Write-LogMessage "Warning: S: drive not immediately available, waiting..." "WARNING"
            Start-Sleep -Seconds 5
            if (-not (Test-Path "S:\")) {
                throw "System partition S: is not accessible after creation"
            }
        }
        
        # Create main Windows partition with improved error handling
        Write-LogMessage "Creating main Windows partition..." "INFO"
        $mainScript = "$env:TEMP\diskpart_main_$(Get-Random).txt"
        
        try {
            $mainCommands = @(
                "select disk $TargetDisk",
                "create partition primary",
                "format quick fs=ntfs label=`"Windows`"",
                "assign letter=W",
                "exit"
            )
            
            $mainCommands | Out-File -FilePath $mainScript -Encoding ASCII -Force
            
            Write-LogMessage "Creating Windows partition with commands: $($mainCommands -join '; ')" "VERBOSE"
            
            $mainOutput = & diskpart.exe /s $mainScript 2>&1
            $mainExitCode = $LASTEXITCODE
            
            if ($mainOutput) {
                foreach ($line in $mainOutput) {
                    Write-LogMessage "[DISKPART-WIN] $line" "VERBOSE"
                }
            }
            
            if ($mainExitCode -ne 0) {
                throw "Failed to create main Windows partition. Exit code: $mainExitCode"
            }
            
        } finally {
            if (Test-Path $mainScript) {
                Remove-Item $mainScript -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-LogMessage "Created main Windows partition" "SUCCESS"
        
        # Wait for the system to recognize the new partition
        Start-Sleep -Seconds 3
        
        # Verify W: drive exists
        if (-not (Test-Path "W:\")) {
            Write-LogMessage "Warning: W: drive not immediately available, waiting..." "WARNING"
            Start-Sleep -Seconds 5
            if (-not (Test-Path "W:\")) {
                throw "Windows partition W: is not accessible after creation"
            }
        }
        
        Write-LogMessage "Both partitions created and accessible" "SUCCESS"
        
        # Determine Windows version for boot configuration
        $isWindows7 = ($ImageInfo.Name -match "Windows 7|Win7|W7" -or 
                      $ImageInfo.Edition -match "Windows 7|Win7|W7" -or
                      $ImageInfo.WindowsVersion -eq "7" -or
                      $ImageInfo.ImageVersion -match "6\.1\.")
        
        if ($isWindows7) {
            Write-LogMessage "Configuring Windows 7 BIOS boot files" "INFO"
            
            # For Windows 7, don't use /f parameter which may not be supported
            $bootFilesResult = & bcdboot.exe W:\Windows /s S:
            
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Standard bcdboot failed for Windows 7, trying alternative method" "WARNING"
                
                # Alternative method for Windows 7
                try {
                    # Ensure boot directory exists
                    $bootDir = "S:\Boot"
                    if (-not (Test-Path $bootDir)) {
                        New-Item -Path $bootDir -ItemType Directory -Force | Out-Null
                        Write-LogMessage "Created Boot directory on system partition" "INFO"
                    }
                    
                    # Copy bootmgr manually
                    if (Test-Path "W:\bootmgr") {
                        Copy-Item "W:\bootmgr" "S:\" -Force
                        Write-LogMessage "Copied bootmgr to system partition" "INFO"
                    } else {
                        Write-LogMessage "Warning: bootmgr not found in W:\bootmgr" "WARNING"
                    }
                    
                    # Copy Boot directory contents if they exist
                    if (Test-Path "W:\Boot") {
                        Copy-Item "W:\Boot\*" $bootDir -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogMessage "Copied Boot folder contents" "INFO"
                    }
                    
                    # Use bootrec to rebuild boot configuration
                    Write-LogMessage "Running bootrec to rebuild boot configuration" "INFO"
                    
                    # Fix boot sector
                    $fixbootResult = & bootrec.exe /fixboot
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "bootrec /fixboot completed successfully" "INFO"
                    } else {
                        Write-LogMessage "bootrec /fixboot returned exit code: $LASTEXITCODE" "WARNING"
                    }
                    
                    # Fix MBR
                    $fixmbrResult = & bootrec.exe /fixmbr
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "bootrec /fixmbr completed successfully" "INFO"
                    } else {
                        Write-LogMessage "bootrec /fixmbr returned exit code: $LASTEXITCODE" "WARNING"
                    }
                    
                    # Rebuild BCD
                    $rebuildbcdResult = & bootrec.exe /rebuildbcd
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "bootrec /rebuildbcd completed successfully" "INFO"
                    } else {
                        Write-LogMessage "bootrec /rebuildbcd returned exit code: $LASTEXITCODE (this may be normal)" "INFO"
                    }
                    
                    Write-LogMessage "Windows 7 boot configuration completed using alternative method" "SUCCESS"
                    
                } catch {
                    Write-LogMessage "Alternative Windows 7 boot setup failed: $_" "ERROR"
                    throw "Failed to configure Windows 7 boot files using alternative method: $_"
                }
            } else {
                Write-LogMessage "Standard bcdboot completed successfully for Windows 7" "SUCCESS"
            }
        } else {
            # For newer Windows versions that support BIOS mode, use /f BIOS parameter
            Write-LogMessage "Configuring modern Windows BIOS boot files" "INFO"
            $bootFilesResult = & bcdboot.exe W:\Windows /s S: /f BIOS
            
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "BIOS bcdboot failed, trying without /f parameter" "WARNING"
                # Fallback: try without /f parameter
                $bootFilesResult = & bcdboot.exe W:\Windows /s S:
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to create BIOS boot files even without /f parameter"
                } else {
                    Write-LogMessage "bcdboot succeeded without /f parameter" "SUCCESS"
                }
            } else {
                Write-LogMessage "BIOS bcdboot completed successfully" "SUCCESS"
            }
        }
        
        # Set up MBR boot sector using bootsect if available
        try {
            Write-LogMessage "Setting up MBR boot sector" "INFO"
            $bootsectResult = & bootsect.exe /nt60 SYS /mbr /force
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "bootsect completed successfully" "SUCCESS"
            } else {
                Write-LogMessage "bootsect returned exit code: $LASTEXITCODE, but continuing" "WARNING"
            }
        } catch {
            Write-LogMessage "bootsect not available or failed: $_" "WARNING"
        }
        
        Write-LogMessage "Successfully created BIOS/Legacy boot configuration" "SUCCESS"
        
        return @{
            Success = $true
            BootType = "BIOS"
            SystemPartition = "S:"
            WindowsPartition = "W:"
            Message = "BIOS/Legacy boot configuration created successfully"
        }
        
    } catch {
        Write-LogMessage "Error creating BIOS boot configuration: $_" "ERROR"
        return @{
            Success = $false
            BootType = "BIOS"
            Message = "Failed to create BIOS boot configuration: $_"
        }
    }
}

function New-BootConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo,
        
        [Parameter(Mandatory)]
        [string]$TargetDisk,
        
        [Parameter()]
        [string]$ForceBootType  # "UEFI", "BIOS", or $null for auto-detect
    )
    
    try {
        Write-LogMessage "=== Boot Configuration Setup ===" "INFO"
        Write-LogMessage "Image: $($ImageInfo.Name)" "INFO"
        Write-LogMessage "Target Disk: $TargetDisk" "INFO"
        
        # Determine boot type
        $useUEFI = $true
        
        if ($ForceBootType) {
            $useUEFI = ($ForceBootType -eq "UEFI")
            Write-LogMessage "Boot type forced to: $ForceBootType" "INFO"
        } else {
            # Auto-detect based on image compatibility
            $useUEFI = Test-ImageUEFICompatibility -ImageInfo $ImageInfo
            Write-LogMessage "Auto-detected boot type: $(if ($useUEFI) { 'UEFI' } else { 'BIOS/Legacy' })" "INFO"
        }
        
        # Clean the target disk first with improved error handling
        Write-LogMessage "Cleaning target disk..." "INFO"
        
        # Create diskpart script file for better control and debugging
        $diskpartScript = "$env:TEMP\diskpart_clean_$(Get-Random).txt"
        
        try {
            # Create the diskpart script with proper commands
            $diskpartCommands = @(
                "select disk $TargetDisk",
                "clean",
                "convert $(if ($useUEFI) { 'gpt' } else { 'mbr' })",
                "exit"
            )
            
            $diskpartCommands | Out-File -FilePath $diskpartScript -Encoding ASCII -Force
            
            Write-LogMessage "Diskpart script created: $diskpartScript" "VERBOSE"
            Write-LogMessage "Diskpart commands: $($diskpartCommands -join '; ')" "VERBOSE"
            
            # Execute diskpart with the script
            $diskpartOutput = & diskpart.exe /s $diskpartScript 2>&1
            $diskpartExitCode = $LASTEXITCODE
            
            # Log diskpart output for debugging
            Write-LogMessage "Diskpart exit code: $diskpartExitCode" "VERBOSE"
            if ($diskpartOutput) {
                foreach ($line in $diskpartOutput) {
                    Write-LogMessage "[DISKPART] $line" "VERBOSE"
                }
            }
            
            # Check for success
            if ($diskpartExitCode -ne 0) {
                throw "Diskpart failed with exit code $diskpartExitCode. Output: $($diskpartOutput -join '; ')"
            }
            
            # Verify the conversion worked by checking if we can list the disk
            Start-Sleep -Seconds 2  # Give the system time to recognize changes
            
            $verifyScript = "$env:TEMP\diskpart_verify_$(Get-Random).txt"
            "select disk $TargetDisk`r`ndetail disk`r`nexit" | Out-File -FilePath $verifyScript -Encoding ASCII -Force
            
            $verifyOutput = & diskpart.exe /s $verifyScript 2>&1
            $verifyExitCode = $LASTEXITCODE
            
            if ($verifyExitCode -ne 0) {
                Write-LogMessage "Warning: Could not verify disk conversion, but continuing..." "WARNING"
            } else {
                # Check if the disk shows the correct partition style
                $partitionStyle = if ($useUEFI) { "GPT" } else { "MBR" }
                if ($verifyOutput -match $partitionStyle) {
                    Write-LogMessage "Verified disk is converted to $partitionStyle" "SUCCESS"
                } else {
                    Write-LogMessage "Warning: Disk conversion to $partitionStyle could not be verified" "WARNING"
                }
            }
            
            # Clean up temporary files
            Remove-Item $verifyScript -Force -ErrorAction SilentlyContinue
            
        } catch {
            throw "Failed to clean and convert disk: $_"
        } finally {
            # Clean up diskpart script
            if (Test-Path $diskpartScript) {
                Remove-Item $diskpartScript -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-LogMessage "Disk cleaned and converted to $(if ($useUEFI) { 'GPT' } else { 'MBR' })" "SUCCESS"
        
        # Create appropriate boot configuration
        if ($useUEFI) {
            $result = New-UEFIBootConfiguration -ImageInfo $ImageInfo -TargetDisk $TargetDisk
        } else {
            $result = New-BIOSBootConfiguration -ImageInfo $ImageInfo -TargetDisk $TargetDisk
        }
        
        if ($result.Success) {
            Write-LogMessage "Boot configuration completed successfully" "SUCCESS"
            Write-LogMessage "Boot Type: $($result.BootType)" "INFO"
            Write-LogMessage "System Partition: $($result.SystemPartition)" "INFO"
            Write-LogMessage "Windows Partition: $($result.WindowsPartition)" "INFO"
        } else {
            Write-LogMessage "Boot configuration failed: $($result.Message)" "ERROR"
        }
        
        return $result
        
    } catch {
        Write-LogMessage "Critical error in boot configuration: $_" "ERROR"
        return @{
            Success = $false
            BootType = "Unknown"
            Message = "Critical error in boot configuration: $_"
        }
    }
}

function Get-WindowsVersionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        $windowsVersion = Get-WindowsVersionFromImage -ImageInfo $ImageInfo
        
        if ($windowsVersion -and $script:WindowsVersionDatabase.ContainsKey($windowsVersion)) {
            $versionInfo = $script:WindowsVersionDatabase[$windowsVersion]
            
            return @{
                Version = $windowsVersion
                Name = $versionInfo.Name
                UEFISupported = $versionInfo.UEFISupported
                BIOSSupported = $versionInfo.BIOSSupported
                Recommended = $versionInfo.Recommended
                DatabaseMatch = $true
            }
        } else {
            return @{
                Version = $windowsVersion
                Name = "Unknown Windows Version"
                UEFISupported = $false
                BIOSSupported = $true
                Recommended = "BIOS"
                DatabaseMatch = $false
            }
        }
    } catch {
        Write-LogMessage "Error getting Windows version info: $_" "ERROR"
        return @{
            Version = "Unknown"
            Name = "Unknown Windows Version"
            UEFISupported = $false
            BIOSSupported = $true
            Recommended = "BIOS"
            DatabaseMatch = $false
        }
    }
}

function Get-RecommendedBootType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    $versionInfo = Get-WindowsVersionInfo -ImageInfo $ImageInfo
    
    return @{
        RecommendedType = $versionInfo.Recommended
        UEFICompatible = $versionInfo.UEFISupported
        BIOSCompatible = $versionInfo.BIOSSupported
        WindowsVersion = $versionInfo.Version
        WindowsName = $versionInfo.Name
        DatabaseMatch = $versionInfo.DatabaseMatch
        Reason = if ($versionInfo.DatabaseMatch) {
            "Database match: $($versionInfo.Name) - Recommended: $($versionInfo.Recommended)"
        } else {
            "Unknown version, defaulting to BIOS for compatibility"
        }
    }
}

function Test-ImageUEFICompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        Write-LogMessage "Testing UEFI compatibility using Windows version database" "INFO"
        
        # Get the Windows version from the image
        $windowsVersion = Get-WindowsVersionFromImage -ImageInfo $ImageInfo
        
        if ($windowsVersion) {
            # Look up in our database
            if ($script:WindowsVersionDatabase.ContainsKey($windowsVersion)) {
                $versionInfo = $script:WindowsVersionDatabase[$windowsVersion]
                $isUEFICompatible = $versionInfo.UEFISupported
                $recommendedType = $versionInfo.Recommended
                
                Write-LogMessage "Database lookup: $($versionInfo.Name) - UEFI: $isUEFICompatible, Recommended: $recommendedType" "INFO"
                
                return $isUEFICompatible
            } else {
                Write-LogMessage "Version $windowsVersion not found in database, using heuristics" "WARNING"
                
                # Fallback heuristics based on version numbers
                $cleanVersion = $windowsVersion -replace "^SRV\.", ""  # Remove SRV prefix for heuristics
                
                if ($cleanVersion -match "^11\.") {
                    Write-LogMessage "Windows 11 detected by version number - UEFI compatible" "INFO"
                    return $true
                } elseif ($cleanVersion -match "^10\.") {
                    Write-LogMessage "Windows 10/Server detected by version number - UEFI compatible" "INFO"
                    return $true
                } elseif ($cleanVersion -match "^6\.[2-3]\.") {
                    Write-LogMessage "Windows 8/8.1/Server 2012 detected by version number - UEFI compatible" "INFO"
                    return $true
                } elseif ($cleanVersion -match "^6\.[0-1]\.") {
                    Write-LogMessage "Windows 7/Vista/Server 2008 detected by version number - BIOS only" "INFO"
                    return $false
                } elseif ($cleanVersion -match "^5\.") {
                    Write-LogMessage "Windows XP detected by version number - BIOS only" "INFO"
                    return $false
                } else {
                    Write-LogMessage "Unknown version pattern: $windowsVersion - defaulting to BIOS for safety" "WARNING"
                    return $false
                }
            }
        } else {
            Write-LogMessage "Could not determine Windows version, falling back to legacy detection" "WARNING"
            
            # Fallback to original detection logic
            return Test-ImageUEFICompatibilityLegacy -ImageInfo $ImageInfo
        }
        
    } catch {
        Write-LogMessage "Error in database-based UEFI compatibility test: $_" "ERROR"
        # Fallback to legacy method
        return Test-ImageUEFICompatibilityLegacy -ImageInfo $ImageInfo
    }
}

function Test-ImageUEFICompatibilityLegacy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ImageInfo
    )
    
    try {
        Write-LogMessage "Using legacy UEFI compatibility detection" "WARNING"
        
        # Check if it's a Windows 7 image (not UEFI compatible) - more comprehensive checks
        if ($ImageInfo.Name -match "Windows 7|Win7|W7" -or 
            $ImageInfo.Edition -match "Windows 7|Win7|W7" -or
            $ImageInfo.ImageName -match "Windows 7|Win7|W7" -or
            $ImageInfo.Description -match "Windows 7|Win7|W7") {
            Write-LogMessage "Detected Windows 7 image - not UEFI compatible" "INFO"
            return $false
        }
        
        # Check image version information
        if ($ImageInfo.ImageVersion -and $ImageInfo.ImageVersion -match "6\.1\.") {
            Write-LogMessage "Detected Windows version 6.1 (Windows 7) - not UEFI compatible" "INFO"
            return $false
        }
        
        # Check if image has UEFI support based on version info
        if ($ImageInfo.WindowsVersion) {
            # Windows 10 and 11 are UEFI compatible
            if ($ImageInfo.WindowsVersion -eq "10" -or $ImageInfo.WindowsVersion -eq "11") {
                Write-LogMessage "Detected Windows $($ImageInfo.WindowsVersion) - UEFI compatible" "INFO"
                return $true
            }
            
            # Windows 8/8.1 are UEFI compatible
            if ($ImageInfo.WindowsVersion -eq "8" -or $ImageInfo.WindowsVersion -eq "8.1") {
                Write-LogMessage "Detected Windows $($ImageInfo.WindowsVersion) - UEFI compatible" "INFO"
                return $true
            }
            
            # Windows 7 and earlier are not UEFI compatible
            if ($ImageInfo.WindowsVersion -eq "7" -or $ImageInfo.WindowsVersion -eq "Vista" -or $ImageInfo.WindowsVersion -eq "XP") {
                Write-LogMessage "Detected Windows $($ImageInfo.WindowsVersion) - not UEFI compatible" "INFO"
                return $false
            }
        }
        
        # Check OSInfo for version details
        if ($ImageInfo.OSInfo) {
            $osInfo = $ImageInfo.OSInfo
            if ($osInfo -match "Windows 7|6\.1\." -or $osInfo -match "Vista|6\.0\." -or $osInfo -match "XP|5\.1\.") {
                Write-LogMessage "OSInfo indicates legacy Windows version - not UEFI compatible" "INFO"
                return $false
            }
            
            if ($osInfo -match "Windows 10|10\.0\." -or $osInfo -match "Windows 11|11\.0\." -or $osInfo -match "Windows 8|6\.2\.|6\.3\.") {
                Write-LogMessage "OSInfo indicates modern Windows version - UEFI compatible" "INFO"
                return $true
            }
        }
        
        # Check image file itself if path is available
        if ($ImageInfo.FullPath -and (Test-Path $ImageInfo.FullPath)) {
            try {
                # Use DISM to get detailed image information
                $dismOutput = & dism.exe /Get-WimInfo /WimFile:"$($ImageInfo.FullPath)" /Index:$($ImageInfo.ImageIndex) 2>&1
                
                if ($dismOutput -match "Version\s*:\s*6\.1\." -or $dismOutput -match "Windows 7") {
                    Write-LogMessage "DISM output indicates Windows 7 - not UEFI compatible" "INFO"
                    return $false
                }
                
                if ($dismOutput -match "Version\s*:\s*(10\.0\.|11\.0\.|6\.2\.|6\.3\.)" -or $dismOutput -match "Windows (10|11|8)") {
                    Write-LogMessage "DISM output indicates modern Windows - UEFI compatible" "INFO"
                    return $true
                }
            } catch {
                Write-LogMessage "Could not analyze image with DISM: $_" "WARNING"
            }
        }
        
        # For ISOs, be more conservative - if we can't determine, assume BIOS for legacy compatibility
        if ($ImageInfo.IsISO -or $ImageInfo.Type -eq "ISO") {
            Write-LogMessage "ISO detected - defaulting to BIOS for maximum compatibility" "WARNING"
            return $false
        }
        
        # Default assumption for unknown images - prefer BIOS for better compatibility
        Write-LogMessage "Could not determine UEFI compatibility - defaulting to BIOS for safety" "WARNING"
        return $false
        
    } catch {
        Write-LogMessage "Error testing UEFI compatibility: $_" "ERROR"
        # Default to BIOS for safety with unknown images
        return $false
    }
}

Export-ModuleMember -Function New-BootConfiguration, Test-ImageUEFICompatibility, Get-RecommendedBootType, New-UEFIBootConfiguration, New-BIOSBootConfiguration, Get-WindowsVersionInfo, Get-WindowsVersionFromImage
