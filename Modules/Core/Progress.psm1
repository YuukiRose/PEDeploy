# Progress module for deployment operations

# Import logging if available
try {
    Import-Module "$PSScriptRoot\Logging.psm1" -Force -ErrorAction SilentlyContinue
} catch {
    # Define basic logging if not available
    if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
        function Write-LogMessage {
            param([string]$Message, [string]$Level = "INFO")
            Write-Host "[$Level] $Message"
        }
    }
}

function Update-DeploymentProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory)]
        [string]$Status
    )
    
    try {
        # Clamp percentage to valid range
        $PercentComplete = [Math]::Max(0, [Math]::Min(100, $PercentComplete))
        
        # Display progress with plain text indicators
        $indicator = if ($PercentComplete -eq 100) { "COMPLETE" } elseif ($PercentComplete -gt 0) { "PROGRESS" } else { "START" }
        
        Write-Host "[$indicator $PercentComplete%] $Status" -ForegroundColor Cyan
        
        # Log progress if logging is available
        if (Get-Command Write-LogMessage -ErrorAction SilentlyContinue) {
            Write-LogMessage "Progress: [$PercentComplete%] $Status" "INFO"
        }
        
        # Call any registered callback
        if ($Script:ProgressCallback) {
            try {
                & $Script:ProgressCallback $PercentComplete $Status
            } catch {
                Write-Warning "Progress callback error: $_"
            }
        }
    }
    catch {
        Write-Warning "Error updating deployment progress: $_"
    }
}

# Script-level variable for callback
$Script:ProgressCallback = $null

function Set-DeploymentProgressCallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Callback
    )
    
    $Script:ProgressCallback = $Callback
    Write-LogMessage "Progress callback registered" "INFO"
}

function Get-DeploymentProgressStatus {
    return @{
        CallbackRegistered = ($null -ne $Script:ProgressCallback)
        FunctionAvailable = (Get-Command Update-DeploymentProgress -ErrorAction SilentlyContinue) -ne $null
    }
}

Export-ModuleMember -Function Update-DeploymentProgress, Set-DeploymentProgressCallback, Get-DeploymentProgressStatus
