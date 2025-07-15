# Script to update all customer configuration files to new image structure
# Moves CustomerImages -> WIMImages and Images -> FFUImages
# Run this once to migrate all existing customer configurations

param(
    [switch]$WhatIf
)

# Import required modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$modulesPath = Join-Path (Split-Path -Parent $scriptDir) "Modules"

Import-Module "$modulesPath\Core\CustomerConfigManager.psm1" -Force

try {
    Write-Host "Starting customer configuration migration process..." -ForegroundColor Cyan
    Write-Host "Customer Configuration Migration Script" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    
    if ($WhatIf) {
        Write-Host "Running in WhatIf mode - no changes will be made" -ForegroundColor Yellow
    }
    
    $customerConfigPath = "Y:\DeploymentModules\Config\CustomerConfig"
    if (-not (Test-Path $customerConfigPath)) {
        Write-Host "Customer config directory not found: $customerConfigPath" -ForegroundColor Red
        exit 1
    }
    
    $customerDirs = Get-ChildItem -Path $customerConfigPath -Directory | Where-Object { 
        $_.Name -ne "DEFAULTIMAGECONFIG" -and $_.Name -notlike ".*" 
    }
    
    Write-Host "`nFound $($customerDirs.Count) customer configuration(s):" -ForegroundColor Green
    
    foreach ($customerDir in $customerDirs) {
        $configFile = Join-Path $customerDir.FullName "Config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile -Raw | ConvertFrom-Json
                $changed = $false

                # Helper: get default flag value from DeploymentSettings or fallback
                function Get-DefaultFlag {
                    param($config, $flag, $fallback)
                    if ($config.PSObject.Properties.Name -contains 'DeploymentSettings') {
                        $ds = $config.DeploymentSettings
                        $key = "Default$flag"
                        if ($ds.PSObject.Properties.Name -contains $key) {
                            return [bool]$ds.$key
                        }
                    }
                    return $fallback
                }

                $requiredFlags = @(
                    @{ Name = 'DriverInject'; Fallback = $true },
                    @{ Name = 'ApplyUnattend'; Fallback = $true },
                    @{ Name = 'RequiredUpdates'; Fallback = $true }
                )

                # Migrate CustomerImages -> WIMImages
                if ($config.PSObject.Properties.Name -contains "CustomerImages") {
                    foreach ($key in $config.CustomerImages.PSObject.Properties.Name) {
                        $img = $config.CustomerImages.$key
                        if (-not ($img.PSObject.Properties.Name -contains 'Active') -and -not ($img.PSObject.Properties.Name -contains 'active')) {
                            $img | Add-Member -MemberType NoteProperty -Name 'Active' -Value $true -Force
                        }
                        foreach ($flag in $requiredFlags) {
                            if (-not ($img.PSObject.Properties.Name -contains $flag.Name)) {
                                $img | Add-Member -MemberType NoteProperty -Name $flag.Name -Value (Get-DefaultFlag $config $flag.Name $flag.Fallback) -Force
                            }
                        }
                        $config.CustomerImages.$key = $img
                    }
                    $config | Add-Member -MemberType NoteProperty -Name "WIMImages" -Value $config.CustomerImages -Force
                    $config.PSObject.Properties.Remove("CustomerImages")
                    $changed = $true
                    Write-Host "  - $($customerDir.Name): Migrated CustomerImages -> WIMImages (Active/flags ensured)" -ForegroundColor Yellow
                }
                # Migrate Images -> FFUImages
                if ($config.PSObject.Properties.Name -contains "Images") {
                    foreach ($key in $config.Images.PSObject.Properties.Name) {
                        $img = $config.Images.$key
                        if (-not ($img.PSObject.Properties.Name -contains 'Active') -and -not ($img.PSObject.Properties.Name -contains 'active')) {
                            $img | Add-Member -MemberType NoteProperty -Name 'Active' -Value $true -Force
                        }
                        foreach ($flag in $requiredFlags) {
                            if (-not ($img.PSObject.Properties.Name -contains $flag.Name)) {
                                $img | Add-Member -MemberType NoteProperty -Name $flag.Name -Value (Get-DefaultFlag $config $flag.Name $flag.Fallback) -Force
                            }
                        }
                        $config.Images.$key = $img
                    }
                    $config | Add-Member -MemberType NoteProperty -Name "FFUImages" -Value $config.Images -Force
                    $config.PSObject.Properties.Remove("Images")
                    $changed = $true
                    Write-Host "  - $($customerDir.Name): Migrated Images -> FFUImages (Active/flags ensured)" -ForegroundColor Yellow
                }
                # Ensure all images in WIMImages, FFUImages, and customImages have required flags
                foreach ($section in @('WIMImages','FFUImages')) {
                    if ($config.PSObject.Properties.Name -contains $section) {
                        foreach ($key in $config.$section.PSObject.Properties.Name) {
                            $img = $config.$section.$key
                            if ($null -eq $img) { continue }
                            foreach ($flag in $requiredFlags) {
                                if ($null -eq $img) { break }
                                if (-not ($img.PSObject.Properties.Name -contains $flag.Name)) {
                                    $img | Add-Member -MemberType NoteProperty -Name $flag.Name -Value (Get-DefaultFlag $config $flag.Name $flag.Fallback) -Force
                                }
                            }
                            $config.$section.$key = $img
                        }
                    }
                }
                if ($config.PSObject.Properties.Name -contains 'customImages') {
                    for ($idx = 0; $idx -lt $config.customImages.Count; $idx++) {
                        $img = $config.customImages[$idx]
                        if ($null -eq $img) { continue }
                        foreach ($flag in $requiredFlags) {
                            if ($null -eq $img) { break }
                            if (-not ($img.PSObject.Properties.Name -contains $flag.Name)) {
                                $img | Add-Member -MemberType NoteProperty -Name $flag.Name -Value (Get-DefaultFlag $config $flag.Name $flag.Fallback) -Force
                            }
                        }
                        $config.customImages[$idx] = $img
                    }
                }
                if ($changed -and -not $WhatIf) {
                    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFile -Force
                    Write-Host "    Saved migrated config for $($customerDir.Name)" -ForegroundColor Green
                } elseif ($changed) {
                    Write-Host "    Would save migrated config for $($customerDir.Name) (WhatIf mode)" -ForegroundColor Gray
                } else {
                    Write-Host "  - $($customerDir.Name): Already migrated or no changes needed" -ForegroundColor Green
                }
            } catch {
                Write-Host "  - $($customerDir.Name): ERROR during migration: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  - $($customerDir.Name): NO CONFIG FILE" -ForegroundColor Red
        }
    }
    Write-Host "`nMigration complete!" -ForegroundColor Green
} catch {
    Write-Host "Error in customer configuration migration script: $_" -ForegroundColor Red
    exit 1
}
