# Customer Configuration Manager Module
# Handles updating and managing customer configuration files with dynamic ISO discovery

Import-Module "$PSScriptRoot\Logging.psm1" -Force

function Refresh-CustomerISOs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName
    )
    
    try {
        Write-LogMessage "Refreshing ISO list for customer: $CustomerName" "INFO"
        
        $customerConfigPath = "Y:\DeploymentModules\Config\CustomerConfig"
        $configFile = Join-Path $customerConfigPath "$CustomerName\Config.json"
        
        if (-not (Test-Path $configFile)) {
            throw "Customer configuration file not found: $configFile"
        }
        
        # Customer's ISO directory
        $customerISOPath = "Z:\CustomerImages\$CustomerName\ISO"
        
        if (-not (Test-Path $customerISOPath)) {
            Write-LogMessage "Customer ISO directory not found: $customerISOPath" "WARNING"
            # Create the directory structure
            try {
                New-Item -Path $customerISOPath -ItemType Directory -Force | Out-Null
                Write-LogMessage "Created customer ISO directory: $customerISOPath" "INFO"
            } catch {
                Write-LogMessage "Failed to create customer ISO directory: $_" "ERROR"
                throw $_
            }
        }
        
        # Discover all subfolder categories and ISOs
        $discoveredISOs = @()
        $discoveredCategories = @{
            General = @{
                DisplayName = "General"
                ISOs = @()
            }
        }
        
        try {
            # First, scan the root ISO directory for any direct ISO files
            $rootISOFiles = Get-ChildItem -Path $customerISOPath -Filter "*.iso" -File -ErrorAction SilentlyContinue
            foreach ($isoFile in $rootISOFiles) {
                $categoryName = "General"  # Default category for root ISOs
                $discoveredISO = New-ISOObject -ISOFile $isoFile -CustomerName $CustomerName -CategoryName $categoryName -CustomerISOPath $customerISOPath
                $discoveredISOs += $discoveredISO
                
                if (-not $discoveredCategories.ContainsKey($categoryName)) {
                    $discoveredCategories[$categoryName] = @{
                        DisplayName = $categoryName
                        ISOs = @()
                    }
                }
            }
            
            # Then scan all subfolders for ISOs and use subfolder name as category
            $subfolders = Get-ChildItem -Path $customerISOPath -Directory -ErrorAction SilentlyContinue
            foreach ($subfolder in $subfolders) {
                $categoryName = $subfolder.Name
                Write-LogMessage "Scanning subfolder category: $categoryName" "VERBOSE"
                
                # Get all ISO files in this subfolder (recursively)
                $isoFiles = Get-ChildItem -Path $subfolder.FullName -Recurse -Filter "*.iso" -File -ErrorAction SilentlyContinue
                
                foreach ($isoFile in $isoFiles) {
                    $discoveredISO = New-ISOObject -ISOFile $isoFile -CustomerName $CustomerName -CategoryName $categoryName -CustomerISOPath $customerISOPath
                    $discoveredISOs += $discoveredISO
                }
                
                # Create category structure if ISOs were found
                if ($isoFiles.Count -gt 0) {
                    $discoveredCategories[$categoryName] = @{
                        DisplayName = $categoryName
                        ISOs = @()
                    }
                    Write-LogMessage "Found $($isoFiles.Count) ISO(s) in category: $categoryName" "INFO"
                }
            }
            
        } catch {
            Write-LogMessage "Error scanning for ISO files: $_" "ERROR"
        }
        
        # Read existing configuration
        $configContent = Get-Content $configFile -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        # Remove BaseImages if it exists (no longer used)
        if ($config.PSObject.Properties.Name -contains "BaseImages") {
            $config.PSObject.Properties.Remove("BaseImages")
            Write-LogMessage "Removed BaseImages from customer config (now using DEFAULTIMAGECONFIG)" "INFO"
        }
        
        # Create new ISO structure completely
        $newISOStructure = [PSCustomObject]@{
            DefaultISO = ""
            Categories = [PSCustomObject]@{}
            AllISOs = @()
            LastRefresh = ""
        }
        
        # Add discovered categories to the structure
        foreach ($categoryName in $discoveredCategories.Keys) {
            $newISOStructure.Categories | Add-Member -NotePropertyName $categoryName -NotePropertyValue $discoveredCategories[$categoryName] -Force
        }
        
        # Distribute ISOs to their respective categories
        foreach ($iso in $discoveredISOs) {
            $categoryName = $iso.Category
            # Ensure the category exists in the structure
            if (-not $newISOStructure.Categories.PSObject.Properties.Name -contains $categoryName) {
                $newISOStructure.Categories | Add-Member -NotePropertyName $categoryName -NotePropertyValue @{
                    DisplayName = $categoryName
                    ISOs = @()
                } -Force
            }
            $newISOStructure.Categories.$categoryName.ISOs += $iso
            $newISOStructure.AllISOs += $iso
        }
        
        # Set default ISO if ISOs exist
        if ($newISOStructure.AllISOs.Count -gt 0) {
            $newISOStructure.DefaultISO = $newISOStructure.AllISOs[0].ID
            Write-LogMessage "Set default ISO to: $($newISOStructure.AllISOs[0].Name)" "INFO"
        }
        
        # Update refresh timestamp
        $newISOStructure.LastRefresh = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        
        # Add or replace the ISO property completely
        if ($config.PSObject.Properties.Name -contains "ISO") {
            $config.PSObject.Properties.Remove("ISO")
        }
        $config | Add-Member -NotePropertyName "ISO" -NotePropertyValue $newISOStructure -Force
        
        # Update last modified timestamp
        if ($config.PSObject.Properties.Name -contains "CustomerInfo") {
            if ($config.CustomerInfo.PSObject.Properties.Name -contains "LastModified") {
                $config.CustomerInfo.LastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            } else {
                $config.CustomerInfo | Add-Member -NotePropertyName "LastModified" -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
            }
        } else {
            # Create CustomerInfo if it doesn't exist
            $config | Add-Member -NotePropertyName "CustomerInfo" -NotePropertyValue ([PSCustomObject]@{
                LastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }) -Force
        }
        
        # Save updated configuration
        $updatedJson = $config | ConvertTo-Json -Depth 10 -Compress:$false
        $updatedJson | Out-File -FilePath $configFile -Encoding UTF8 -Force
        
        Write-LogMessage "Refreshed ISO list for customer $CustomerName`: found $($discoveredISOs.Count) ISOs in $($discoveredCategories.Count) categories" "SUCCESS"
        return $discoveredISOs.Count
        
    } catch {
        Write-LogMessage "Error refreshing customer ISOs: $_" "ERROR"
        throw $_
    }
}

function New-ISOObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$ISOFile,
        
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [Parameter(Mandatory)]
        [string]$CategoryName,
        
        [Parameter(Mandatory)]
        [string]$CustomerISOPath
    )
    
    # Get file size
    $sizeMB = [Math]::Round($ISOFile.Length / 1MB, 2)
    $fileSize = "$sizeMB MB"
    
    # Extract version info from filename if possible
    $versionInfo = Get-ISOVersionInfo -FileName $ISOFile.Name
    
    # Generate unique ID based on file path and modified date
    $relativePath = $ISOFile.FullName -replace [regex]::Escape($customerISOPath), ""
    $cleanPath = $relativePath.TrimStart('\').Replace('\', '_').Replace(' ', '_').Replace('-', '_')
    $isoID = "iso_" + $CustomerName.ToLower() + "_" + $cleanPath.ToLower() + "_" + $ISOFile.LastWriteTime.ToString("yyyyMMddHHmmss")
    
    return @{
        ID = $isoID
        Name = [System.IO.Path]::GetFileNameWithoutExtension($ISOFile.Name)
        Path = $ISOFile.FullName
        Category = $CategoryName
        Description = "Auto-discovered from $($ISOFile.DirectoryName)"
        DateAdded = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        DateModified = $ISOFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        Size = $fileSize
        Version = $versionInfo.Version
        Architecture = $versionInfo.Architecture
        Edition = $versionInfo.Edition
        RelativePath = $relativePath
        SubfolderCategory = $CategoryName
    }
}

function Get-ISOVersionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    $fileName = $FileName.ToLower()
    $versionInfo = @{
        Version = ""
        Architecture = ""
        Edition = ""
    }
    
    # Extract version information
    if ($fileName -match "22h2") {
        $versionInfo.Version = "22H2"
    } elseif ($fileName -match "21h2") {
        $versionInfo.Version = "21H2"
    } elseif ($fileName -match "20h2") {
        $versionInfo.Version = "20H2"
    } elseif ($fileName -match "2019") {
        $versionInfo.Version = "2019"
    } elseif ($fileName -match "2022") {
        $versionInfo.Version = "2022"
    } elseif ($fileName -match "2016") {
        $versionInfo.Version = "2016"
    }
    
    # Extract architecture
    if ($fileName -match "x64|64.?bit") {
        $versionInfo.Architecture = "x64"
    } elseif ($fileName -match "x86|32.?bit") {
        $versionInfo.Architecture = "x86"
    } elseif ($fileName -match "arm64") {
        $versionInfo.Architecture = "ARM64"
    }
    
    # Extract edition
    if ($fileName -match "pro") {
        $versionInfo.Edition = "Professional"
    } elseif ($fileName -match "enterprise") {
        $versionInfo.Edition = "Enterprise"
    } elseif ($fileName -match "home") {
        $versionInfo.Edition = "Home"
    } elseif ($fileName -match "education") {
        $versionInfo.Edition = "Education"
    } elseif ($fileName -match "standard") {
        $versionInfo.Edition = "Standard"
    } elseif ($fileName -match "datacenter") {
        $versionInfo.Edition = "Datacenter"
    }
    
    return $versionInfo
}

function Get-CustomerISOs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [string]$Category = "",
        
        [switch]$RefreshFirst
    )
    
    try {
        # Refresh ISO list if requested
        if ($RefreshFirst) {
            Refresh-CustomerISOs -CustomerName $CustomerName | Out-Null
        }
        
        $customerConfigPath = "Y:\DeploymentModules\Config\CustomerConfig"
        $configFile = Join-Path $customerConfigPath "$CustomerName\Config.json"
        
        if (-not (Test-Path $configFile)) {
            Write-LogMessage "Customer configuration file not found: $configFile" "WARNING"
            return @()
        }
        
        $configContent = Get-Content $configFile -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        if (-not $config.PSObject.Properties.Name -contains "ISO") {
            Write-LogMessage "ISO configuration not found for customer: $CustomerName" "WARNING"
            return @()
        }
        
        if ([string]::IsNullOrEmpty($Category)) {
            # Return all ISOs
            return $config.ISO.AllISOs
        } else {
            # Return ISOs from specific category
            if ($config.ISO.Categories.PSObject.Properties.Name -contains $Category) {
                return $config.ISO.Categories.$Category.ISOs
            } else {
                Write-LogMessage "Category '$Category' not found for customer: $CustomerName" "WARNING"
                return @()
            }
        }
        
    } catch {
        Write-LogMessage "Error getting customer ISOs: $_" "ERROR"
        return @()
    }
}

function Get-CustomerDefaultISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CustomerName,
        
        [switch]$RefreshFirst
    )
    
    try {
        # Refresh ISO list if requested
        if ($RefreshFirst) {
            Refresh-CustomerISOs -CustomerName $CustomerName | Out-Null
        }
        
        $customerConfigPath = "Y:\DeploymentModules\Config\CustomerConfig"
        $configFile = Join-Path $customerConfigPath "$CustomerName\Config.json"
        
        if (-not (Test-Path $configFile)) {
            Write-LogMessage "Customer configuration file not found: $configFile" "WARNING"
            return $null
        }
        
        $configContent = Get-Content $configFile -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        if (-not $config.PSObject.Properties.Name -contains "ISO") {
            Write-LogMessage "ISO configuration not found for customer: $CustomerName" "WARNING"
            return $null
        }
        
        if ([string]::IsNullOrEmpty($config.ISO.DefaultISO)) {
            Write-LogMessage "No default ISO set for customer: $CustomerName" "WARNING"
            return $null
        }
        
        # Find the default ISO
        $defaultISO = $config.ISO.AllISOs | Where-Object { $_.ID -eq $config.ISO.DefaultISO }
        if ($defaultISO) {
            Write-LogMessage "Found default ISO: $($defaultISO.Name)" "SUCCESS"
            return $defaultISO
        } else {
            Write-LogMessage "Default ISO ID not found in AllISOs list" "WARNING"
            return $null
        }
        
    } catch {
        Write-LogMessage "Error getting customer default ISO: $_" "ERROR"
        return $null
    }
}

function Get-DefaultBaseImages {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage "Getting base images from DEFAULTIMAGECONFIG" "INFO"
        
        $defaultConfigPath = "Y:\DeploymentModules\Config\CustomerConfig\DEFAULTIMAGECONFIG\Config.json"
        
        if (-not (Test-Path $defaultConfigPath)) {
            Write-LogMessage "Default image config not found: $defaultConfigPath" "WARNING"
            return @()
        }
        
        $configContent = Get-Content $defaultConfigPath -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        if ($config.PSObject.Properties.Name -contains "BaseImages") {
            Write-LogMessage "Found $($config.BaseImages.Count) base images in DEFAULTIMAGECONFIG" "SUCCESS"
            return $config.BaseImages
        } else {
            Write-LogMessage "No BaseImages section found in DEFAULTIMAGECONFIG" "WARNING"
            return @()
        }
        
    } catch {
        Write-LogMessage "Error getting default base images: $_" "ERROR"
        return @()
    }
}

Export-ModuleMember -Function Refresh-CustomerISOs, Get-CustomerISOs, Get-CustomerDefaultISO, Get-DefaultBaseImages
