$Script:LogFilePath = $null
$Script:LogInitialized = $false

function Initialize-DeploymentLogging {
    [CmdletBinding()]
    param(
        [string]$CustomerName,
        [string]$OrderNumber,
        [string]$SerialNumber
    )
    
    try {
        $Script:CustomerName = $CustomerName
        $Script:OrderNumber = $OrderNumber
        $Script:SerialNumber = $SerialNumber

        # Check W:\Logs with more robust path validation
        $logsRoot = "W:\Logs"
        $useWDrive = $false
        
        try {
            if (Test-Path "W:\") {
                if (-not (Test-Path $logsRoot)) {
                    New-Item -Path $logsRoot -ItemType Directory -Force | Out-Null
                }
                $useWDrive = $true
                Write-Host "Using W:\Logs for logging." -ForegroundColor Green
            }
        } catch {
            Write-Host "Cannot access W:\ drive: $_" -ForegroundColor Yellow
        }
        
        if (-not $useWDrive) {
            $logsRoot = Join-Path $env:TEMP "Logs"
            if (-not (Test-Path $logsRoot)) {
                New-Item -Path $logsRoot -ItemType Directory -Force | Out-Null
            }
            Write-Host "WARNING: W:\Logs not available, using $logsRoot for logging." -ForegroundColor Yellow
        }

        # Create customer folder if not exists
        $customerDir = Join-Path $logsRoot $CustomerName
        if (-not (Test-Path $customerDir)) {
            New-Item -Path $customerDir -ItemType Directory -Force | Out-Null
        }

        # Create order number folder if not exists
        $logDir = Join-Path $customerDir $OrderNumber
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        # Sanitize SerialNumber for filename
        $safeSerial = $SerialNumber -replace '[\\/:*?"<>|]', '_'
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logFileName = "${safeSerial}-${timestamp}.log"
        $Script:LogFilePath = Join-Path $logDir $logFileName
        $Script:LogInitialized = $true

        try {
            # Touch the log file to ensure it can be created
            "" | Out-File -FilePath $Script:LogFilePath -Encoding UTF8 -Force
        } catch {
            Write-Host "ERROR: Failed to create log file at $Script:LogFilePath : $_" -ForegroundColor Red
            $Script:LogFilePath = $null
            throw "Failed to create log file at $logDir"
        }

        Write-LogMessage "=== Deployment Session Started ===" "INFO"
        Write-LogMessage "Customer: $CustomerName" "INFO"
        Write-LogMessage "Order: $OrderNumber" "INFO"
        Write-LogMessage "Serial: $SerialNumber" "INFO"
        Write-LogMessage "Session ID: $timestamp" "INFO"
        Write-LogMessage "Log File: $Script:LogFilePath" "INFO"
        
        return $true
    }
    catch {
        Write-Host "Failed to initialize logging: $_" -ForegroundColor Red
        return $false
    }
}

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "VERBOSE")]
        [string]$Level = "INFO"
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Console output with colors
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "INFO" { "White" }
            "VERBOSE" { "Gray" }
            default { "White" }
        }
        
        Write-Host $logEntry -ForegroundColor $color
        
        # File output if initialized
        if ($Script:LogInitialized -and $Script:LogFilePath) {
            try {
                # Use UTF8 encoding without BOM to avoid character issues
                Add-Content -Path $Script:LogFilePath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
            } catch {
                # Silently continue if file logging fails
            }
        }
    }
    catch {
        Write-Host "Logging error: $_" -ForegroundColor Red
    }
}

function Get-LogFilePath {
    return $Script:LogFilePath
}

Export-ModuleMember -Function Initialize-DeploymentLogging, Write-LogMessage, Get-LogFilePath
