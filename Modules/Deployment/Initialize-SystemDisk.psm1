#
# Module: Initialize-SystemDisk.psm1
# Description: Functions for disk partitioning and setup for Windows deployment

# Import local logging module
try {
    Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -Global -ErrorAction SilentlyContinue
} catch {
    # Define basic function if module not available
    if (-not (Get-Command -Name Write-LogMessage -ErrorAction SilentlyContinue)) {
        function Write-LogMessage {
            param(
                [string]$Message,
                [string]$Level = "INFO"
            )
            Write-Host "[$Level] $Message" -ForegroundColor $(
                switch ($Level) {
                    "ERROR" { "Red" }
                    "WARNING" { "Yellow" }
                    "SUCCESS" { "Green" }
                    "INFO" { "White" }
                    default { "Gray" }
                }
            )
        }
    }
}

# Define Write-Log function for compatibility
if (-not (Get-Command -Name Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        Write-LogMessage -Message $Message -Level $Level
    }
}

function Get-UnusedDriveLetter {
    param(
        [string[]]$PreferredLetters = @(),
        [string[]]$ExcludeLetters = @()
    )
    
    # Get all currently used drive letters
    $usedLetters = @()
    $usedLetters += (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name })
    $usedLetters += (Get-WmiObject -Class Win32_LogicalDisk | ForEach-Object { $_.DeviceID.Replace(':', '') })
    
    # Add excluded letters (already assigned in this operation)
    $usedLetters += $ExcludeLetters
    
    # Remove duplicates and convert to uppercase
    $usedLetters = $usedLetters | Sort-Object -Unique | ForEach-Object { $_.ToUpper() }
    
    Write-LogMessage "Currently used drive letters: $($usedLetters -join ', ')" "VERBOSE"
    
    # Try preferred letters first
    foreach ($letter in $PreferredLetters) {
        $upperLetter = $letter.ToUpper()
        if ($upperLetter -notin $usedLetters -and $upperLetter -notin @('A', 'B', 'V','W','X', 'Y', 'Z')) {
            Write-LogMessage "Found unused preferred drive letter: $upperLetter" "INFO"
            return $upperLetter
        }
    }
    
    # If no preferred letters available, find any unused letter
    $allLetters = 'C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U'
    foreach ($letter in $allLetters) {
        if ($letter -notin $usedLetters) {
            Write-LogMessage "Found unused drive letter: $letter" "INFO"
            return $letter
        }
    }
    
    throw "No unused drive letters available"
}

function Initialize-SystemDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DiskConfig
    )
    
    try {
        $startTime = Get-Date
        Write-LogMessage "Starting system disk initialization at $startTime" "INFO"
        
        $diskNumber = if ($DiskConfig.ContainsKey('DiskNumber')) { $DiskConfig.DiskNumber } else { 0 }
        $windowsLabel = if ($DiskConfig.ContainsKey('WindowsPartitionLabel')) { $DiskConfig.WindowsPartitionLabel } else { "Windows" }
        $systemLabel = if ($DiskConfig.ContainsKey('SystemPartitionLabel')) { $DiskConfig.SystemPartitionLabel } else { "System" }
        $recoveryLabel = if ($DiskConfig.ContainsKey('RecoveryPartitionLabel')) { $DiskConfig.RecoveryPartitionLabel } else { "Recovery" }

        # Use fixed drive letters to avoid conflicts - avoid X, Y, Z used by WinPE
        $systemDriveLetter = "S"
        $windowsDriveLetter = "C"
        $recoveryDriveLetter = "R"
        
        $systemDrive = "${systemDriveLetter}:\"
        $windowsDrive = "${windowsDriveLetter}:\"
        $recoveryDrive = "${recoveryDriveLetter}:\"
        
        Write-LogMessage "Using fixed drive letters: System=$systemDrive, Windows=$windowsDrive, Recovery=$recoveryDrive" "INFO"

        # Quick disk validation
        Write-LogMessage "Validating disk $diskNumber exists..." "INFO"
        $listDiskScriptPath = "$env:TEMP\list_disks_$(Get-Random).txt"
        "list disk`r`nexit" | Out-File -FilePath $listDiskScriptPath -Encoding ASCII -Force
        
        try {
            $diskListOutput = & diskpart.exe /s $listDiskScriptPath 2>&1
            Remove-Item $listDiskScriptPath -Force -ErrorAction SilentlyContinue
            
            $diskLines = $diskListOutput | Where-Object { $_ -match "Disk\s+\d+" }
            if ($diskLines.Count -eq 0) {
                throw "No disks found in system"
            }
            
            $targetDiskFound = $diskLines | Where-Object { $_ -match "Disk\s+$diskNumber\s+" }
            if (-not $targetDiskFound) {
                throw "Disk $diskNumber not found. Available disks: $($diskLines -join '; ')"
            }
            
            Write-LogMessage "Disk $diskNumber validated successfully" "INFO"
        } catch {
            throw "Failed to validate disk: $_"
        }

        # Create simplified diskpart script with timeout protection
        Write-LogMessage "Creating diskpart script for Disk $diskNumber..." "INFO"
        $diskpartScriptPath = "$env:TEMP\diskpart_script_$(Get-Random).txt"
        
        # Simplified script without complex retry logic
        $diskpartScript = @"
select disk $diskNumber
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label="$systemLabel"
assign letter=$systemDriveLetter
create partition msr size=128
create partition primary
format quick fs=ntfs label="$windowsLabel"
assign letter=$windowsDriveLetter
create partition primary size=1024
format quick fs=ntfs label="$recoveryLabel"
assign letter=$recoveryDriveLetter
set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
gpt attributes=0x8000000000000001
list volume
exit
"@

        $diskpartScript | Out-File -FilePath $diskpartScriptPath -Encoding ASCII -Force
        Write-LogMessage "Diskpart script created successfully" "INFO"

        # Execute diskpart with timeout protection
        $diskpartStartTime = Get-Date
        Write-LogMessage "Executing diskpart script..." "INFO"
        
        try {
            # Add timeout mechanism for diskpart execution
            $diskpartJob = Start-Job -ScriptBlock {
                param($scriptPath)
                & diskpart.exe /s $scriptPath 2>&1
            } -ArgumentList $diskpartScriptPath
            
            # Wait for completion with timeout (max 5 minutes for disk operations)
            $timeoutMinutes = 5
            $completed = Wait-Job $diskpartJob -Timeout ($timeoutMinutes * 60)
            
            if ($completed) {
                $diskpartOutput = Receive-Job $diskpartJob
                $diskpartExitCode = if ($diskpartJob.State -eq "Completed") { 0 } else { 1 }
                Remove-Job $diskpartJob -Force
            } else {
                Write-LogMessage "Diskpart operation timed out after $timeoutMinutes minutes" "ERROR"
                Stop-Job $diskpartJob -ErrorAction SilentlyContinue
                Remove-Job $diskpartJob -Force -ErrorAction SilentlyContinue
                throw "Diskpart operation timed out after $timeoutMinutes minutes"
            }
            
            $diskpartEndTime = Get-Date
            $diskpartDuration = ($diskpartEndTime - $diskpartStartTime).TotalSeconds
            Write-LogMessage "Diskpart execution completed in $diskpartDuration seconds" "INFO"
            
            # Clean up script file
            Remove-Item $diskpartScriptPath -Force -ErrorAction SilentlyContinue
            
        } catch {
            Remove-Item $diskpartScriptPath -Force -ErrorAction SilentlyContinue
            throw "Failed to execute diskpart: $_"
        }

        # Log diskpart output
        if ($diskpartOutput) {
            Write-LogMessage "Diskpart output ($($diskpartOutput.Count) lines):" "VERBOSE"
            foreach ($line in $diskpartOutput) {
                Write-LogMessage "[Diskpart] $line" "VERBOSE"
            }
        }

        # Check for critical errors in output
        $criticalErrors = $diskpartOutput | Where-Object { 
            $_ -match "failed|error|cannot|denied|invalid" -and 
            $_ -notmatch "Virtual Disk Service" -and
            $_ -notmatch "noerr"
        }
        
        if ($criticalErrors.Count -gt 0) {
            Write-LogMessage "Critical errors found in diskpart output:" "ERROR"
            foreach ($error in $criticalErrors) {
                Write-LogMessage "ERROR: $error" "ERROR"
            }
            throw "Diskpart failed with critical errors"
        }

        # Wait for file system to settle
        Write-LogMessage "Waiting for file system to settle..." "INFO"
        Start-Sleep -Seconds 10

        # Verify drives exist with retry logic (but limited retries)
        Write-LogMessage "Verifying drive creation..." "INFO"
        $maxRetries = 3
        $retryCount = 0
        $allDrivesReady = $false
        
        while ($retryCount -lt $maxRetries -and -not $allDrivesReady) {
            $retryCount++
            Write-LogMessage "Drive verification attempt $retryCount of $maxRetries" "INFO"
            
            $sExists = Test-Path "$systemDrive\" -ErrorAction SilentlyContinue
            $cExists = Test-Path "$windowsDrive\" -ErrorAction SilentlyContinue
            $rExists = Test-Path "$recoveryDrive\" -ErrorAction SilentlyContinue
            
            Write-LogMessage "Drive status: $systemDrive=$sExists, $windowsDrive=$cExists, $recoveryDrive=$rExists" "INFO"
            
            if ($sExists -and $cExists) {
                $allDrivesReady = $true
                Write-LogMessage "Required drives are available" "SUCCESS"
                break
            }
            
            if ($retryCount -lt $maxRetries) {
                Write-LogMessage "Drives not ready, waiting 5 seconds before retry..." "WARNING"
                Start-Sleep -Seconds 5
            }
        }

        # Final drive validation
        if (-not (Test-Path "$systemDrive\")) {
            throw "System partition $systemDrive not accessible after disk formatting"
        }
        
        if (-not (Test-Path "$windowsDrive\")) {
            throw "Windows partition $windowsDrive not accessible after disk formatting"
        }

        # Test write access
        Write-LogMessage "Testing write access to drives..." "INFO"
        try {
            $testFileS = "$systemDrive\test_$(Get-Random).tmp"
            "test" | Out-File -FilePath $testFileS -ErrorAction Stop
            Remove-Item $testFileS -Force -ErrorAction Stop
            Write-LogMessage "System drive $systemDrive write access verified" "SUCCESS"
        } catch {
            throw "System drive $systemDrive is not writable: $_"
        }
        
        try {
            $testFileC = "$windowsDrive\test_$(Get-Random).tmp"
            "test" | Out-File -FilePath $testFileC -ErrorAction Stop
            Remove-Item $testFileC -Force -ErrorAction Stop
            Write-LogMessage "Windows drive $windowsDrive write access verified" "SUCCESS"
        } catch {
            throw "Windows drive $windowsDrive is not writable: $_"
        }

        # Check recovery drive (non-critical)
        $recoveryAvailable = $false
        if (Test-Path "$recoveryDrive\") {
            try {
                $testFileR = "$recoveryDrive\test_$(Get-Random).tmp"
                "test" | Out-File -FilePath $testFileR -ErrorAction Stop
                Remove-Item $testFileR -Force -ErrorAction Stop
                Write-LogMessage "Recovery drive $recoveryDrive verified" "SUCCESS"
                $recoveryAvailable = $true
            } catch {
                Write-LogMessage "Recovery drive $recoveryDrive is not fully accessible: $_" "WARNING"
            }
        }

        $endTime = Get-Date
        $totalDuration = ($endTime - $startTime).TotalSeconds
        Write-LogMessage "Disk initialization completed in $totalDuration seconds" "SUCCESS"

        return @{
            Success = $true
            SystemDrive = $systemDrive
            WindowsDrive = $windowsDrive
            RecoveryDrive = if ($recoveryAvailable) { $recoveryDrive } else { $null }
            DiskNumber = $diskNumber
            Message = "Disk initialization completed successfully"
            Duration = $totalDuration
        }
    }
    catch {
        Write-LogMessage "Error initializing system disk: $_" "ERROR"
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return @{
            Success = $false
            Error = "Failed to initialize system disk: $($_.Exception.Message)"
            Message = $_.Exception.Message
            Exception = $_
        }
    }
}

Export-ModuleMember -Function Initialize-SystemDisk, Get-UnusedDriveLetter