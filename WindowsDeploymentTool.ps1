# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires administrator privileges. Restarting as administrator..."
    Start-Process PowerShell -ArgumentList "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Set execution policy for current session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Change to script directory
Set-Location $PSScriptRoot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Import core modules with error handling for WinPE
try {
    $moduleErrors = @()
    
    # Prioritize working modules - Load Progress before WindowsInstaller
    $modulesToImport = @(
        "$PSScriptRoot\Modules\Core\Logging.psm1"
        "$PSScriptRoot\Modules\Core\Progress.psm1"  # Load Progress before WindowsInstaller
        "$PSScriptRoot\Modules\Core\DeviceInfo.psm1" 
        "$PSScriptRoot\Modules\Core\ISOManager.psm1"  # Add ISOManager module
        "$PSScriptRoot\Modules\Deployment\WindowsInstaller.psm1"
        "$PSScriptRoot\Modules\Imaging\ImageCapture.psm1"
        "$PSScriptRoot\Modules\Drivers\DriverHarvesting.psm1"
        "$PSScriptRoot\Modules\GUI\DeploymentMenu.psm1"
        "$PSScriptRoot\Modules\GUI\ImageMenu.psm1"
        "$PSScriptRoot\Modules\GUI\ImageCaptureMenu.psm1" # Load ImageCaptureMenu module
    )
    
    foreach ($module in $modulesToImport) {
        try {
            if (Test-Path $module) {
                Import-Module $module -Force -ErrorAction Stop
                Write-Host "Loaded: $(Split-Path $module -Leaf)" -ForegroundColor Green
                
                # Verify key functions are available after loading critical modules
                if ($module -like "*Progress.psm1") {
                    if (Get-Command Update-DeploymentProgress -ErrorAction SilentlyContinue) {
                        Write-Host "Update-DeploymentProgress function available" -ForegroundColor Green
                    } else {
                        Write-Warning "Update-DeploymentProgress function NOT available"
                    }
                }

                if ($progressModulePath -like "*WindowsInstaller.psm1") {
                    if (Get-Command Start-WindowsDeployment -ErrorAction SilentlyContinue) {
                        Write-Host "Start-WindowsDeployment function available" -ForegroundColor Green
                    } else {
                        Write-Warning "  ✗ Start-WindowsDeployment function NOT available"
                    }
                }
            } else {
                $moduleErrors += "Module not found: $module"
                Write-Warning "Module not found: $module"
            }
        }
        catch {
            $moduleErrors += "Failed to load $module : $($_.Exception.Message)"
            Write-Warning "Failed to load $module : $($_.Exception.Message)"
        }
    }
    
    if ($moduleErrors.Count -gt 0) {
        Write-Warning "Some modules failed to load. Functionality may be limited."
        foreach ($error in $moduleErrors) {
            Write-Warning $error
        }
    }

    # Import all required modules
    try {
        Import-Module "$PSScriptRoot\Modules\Core\Logging.psm1" -Force -ErrorAction Stop
        Import-Module "$PSScriptRoot\Modules\GUI\DeploymentMenu.psm1" -Force -ErrorAction Stop
        Import-Module "$PSScriptRoot\Modules\GUI\ImageCaptureMenu.psm1" -Force -ErrorAction Stop
    } catch {
        Write-Host "Failed to import required modules: $_" -ForegroundColor Red
        exit 1
    }

    # Initialize the deployment system
    Write-Host "Windows Deployment Tool v2.0" -ForegroundColor Green
    Write-Host "Initializing deployment environment..." -ForegroundColor Yellow
    
    # Check if Show-DeploymentMenu is available
    if (Get-Command Show-DeploymentMenu -ErrorAction SilentlyContinue) {
        
        # Set up progress callback for GUI integration
        if (Get-Command Set-DeploymentProgressCallback -ErrorAction SilentlyContinue) {
            Write-Host "Setting up progress callback for GUI integration..." -ForegroundColor Green
        }
        
        # Show the advanced deployment menu
        Write-Host "Launching deployment menu with REAL functionality..." -ForegroundColor Green
        $deploymentResult = Show-DeploymentMenu
        
        if ($deploymentResult) {
            Write-Host "Deployment configuration completed:" -ForegroundColor Green
            Write-Host "Customer: $($deploymentResult.CustomerName)" -ForegroundColor White
            Write-Host "Order: $($deploymentResult.OrderNumber)" -ForegroundColor White
            if ($deploymentResult.ImageInfo -and $deploymentResult.ImageInfo.ImageID) {
                Write-Host "Image: $($deploymentResult.ImageInfo.ImageID)" -ForegroundColor White
            }
            
            # Verify the deployment actually happened
            Write-Host "Checking deployment results..." -ForegroundColor Yellow
            if ($deploymentResult.Success) {
                Write-Host "REAL DEPLOYMENT WAS SUCCESSFUL!" -ForegroundColor Green
            } else {
                Write-Host "Deployment configuration only - no actual deployment performed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Deployment cancelled by user" -ForegroundColor Yellow
        }
    } else {
        Write-Error "Show-DeploymentMenu function not available. GUI module failed to load."
        Write-Host "Available functions:" -ForegroundColor Yellow
        Get-Command -Module "*Deploy*" -ErrorAction SilentlyContinue | Select-Object Name, ModuleName | Format-Table -AutoSize
        
        # Fallback to direct deployment testing
        Write-Host "Testing direct deployment functionality..." -ForegroundColor Yellow
        try {
            if (Get-Command Start-WindowsDeployment -ErrorAction SilentlyContinue) {
                Write-Host "Start-WindowsDeployment function is available for testing" -ForegroundColor Green
                Write-Host "Note: This would require a valid image file and will FORMAT DISK 0!" -ForegroundColor Red
                
                # Don't actually run it without user confirmation
                $confirmation = Read-Host "Type 'YES' to proceed with actual deployment test (WARNING: WILL FORMAT DISK 0)"
                if ($confirmation -eq "YES") {
                    # Simple file selection dialog
                    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
                    $openFileDialog.Filter = "Windows Image Files (*.wim;*.esd)|*.wim;*.esd|All Files (*.*)|*.*"
                    $openFileDialog.Title = "Select Windows Image File"
                    
                    if ($openFileDialog.ShowDialog() -eq "OK") {
                        $imageParams = @{
                            ImagePath = $openFileDialog.FileName
                            CustomerName = "TestDeploy"
                            OrderNumber = "TEST-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                            DeviceInfo = @{
                                Manufacturer = "Test"
                                Model = "Test"
                                SerialNumber = "TEST001"
                            }
                        }
                        
                        Write-Host "Starting REAL deployment test with image: $($openFileDialog.FileName)" -ForegroundColor Green
                        $result = Start-WindowsDeployment @imageParams
                        
                        if ($result.Success) {
                            Write-Host "REAL deployment test completed successfully!" -ForegroundColor Green
                        } else {
                            Write-Host "REAL deployment test failed: $($result.Message)" -ForegroundColor Red
                        }
                    }
                } else {
                    Write-Host "Deployment test cancelled by user" -ForegroundColor Yellow
                }
            } else {
                Write-Error "No deployment functions available. Please check module files."
            }
        }
        catch {
            Write-Error "Direct deployment test failed: $_"
        }
    }
}
catch {
    Write-Error "Failed to start Windows Deployment Tool: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Write-Host "Module errors: $($moduleErrors -join '; ')" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}

function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "         Windows Deployment Tool" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Select an option:" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] Deploy Windows Image" -ForegroundColor Green
        Write-Host "  [2] Capture Windows Image" -ForegroundColor Blue
        Write-Host "  [3] System Information" -ForegroundColor Cyan
        Write-Host "  [Q] Quit" -ForegroundColor Red
        Write-Host ""
        
        $choice = Read-Host "Enter your choice"
        
        switch ($choice.ToUpper()) {
            "1" {
                Show-DeploymentMenu
            }
            "2" {
                Show-ImageCaptureMenu
            }
            "3" {
                Show-SystemInfo
            }
            "Q" {
                Write-Host "Goodbye!" -ForegroundColor Yellow
                return
            }
            default {
                Write-Host "Invalid choice. Please try again." -ForegroundColor Red
                Start-Sleep 2
            }
        }
    } while ($true)
}
