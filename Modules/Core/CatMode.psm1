# Cat Mode Module - Threaded Version with Individual Script Blocks per GIF
# Runs each GIF in its own script block for proper termination

# Module variables
$script:CatJob = $null
$script:CatEnabled = $false
$script:CurrentStage = "PREPARING"

# Fallback logging function if Write-LogMessage is not available
if (-not (Get-Command -Name Write-LogMessage -ErrorAction SilentlyContinue)) {
    function Write-LogMessage {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "INFO" { "White" }
            "VERBOSE" { "Gray" }
            default { "Gray" }
        }
        Write-Host "[$timestamp] [$Level] [CatMode] $Message" -ForegroundColor $color
    }
}

function Start-CatMode {
    Write-Host "CAT: Starting Cat Mode (Individual Script Blocks)..." -ForegroundColor Cyan
    
    try {
        # Stop any existing cat mode job
        if ($script:CatJob) {
            Stop-CatMode
        }
        
        # Load required assemblies FIRST
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            Write-Host "CAT: Assemblies loaded successfully" -ForegroundColor Green
        } catch {
            Write-Host "CAT: Failed to load required assemblies: $_" -ForegroundColor Red
            return
        }
        
        # Get screen resolution for the job
        try {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen
            $screenWidth = $screen.Bounds.Width
            $screenHeight = $screen.Bounds.Height
            Write-Host "CAT: Screen resolution: ${screenWidth}x${screenHeight}" -ForegroundColor Green
        } catch {
            Write-Host "CAT: Failed to get screen resolution, using defaults: $_" -ForegroundColor Yellow
            $screenWidth = 1920
            $screenHeight = 1080
        }
        
        # Calculate standardized window size based on screen resolution
        $baseWindowSize = 256
        $scaleFactor = [Math]::Min($screenWidth / 1920, $screenHeight / 1080)
        $scaleFactor = [Math]::Max($scaleFactor, 0.4)
        $scaleFactor = [Math]::Min($scaleFactor, 2.0)
        $standardWindowSize = [int]($baseWindowSize * $scaleFactor)
        
        Write-Host "CAT: Scale factor: $scaleFactor, Window size: ${standardWindowSize}x${standardWindowSize}" -ForegroundColor Green
        
        # Pre-load and cache GIF data to eliminate file access delays
        $assetsPath = "Y:\DeploymentModules\Assets\CatMode"
        $gifFiles = @{
            "PREPARING" = @("preparing.gif", "cat.gif", "deployment.gif", "animated.gif")
            "FORMATTING" = @("formatting.gif", "preparing.gif", "cat.gif", "deployment.gif")
            "INSTALLING" = @("installing.gif", "deployment.gif", "cat.gif", "animated.gif")
            "CONFIGURING" = @("configuring.gif", "installing.gif", "deployment.gif", "cat.gif")
            "COMPLETED" = @("completed.gif", "installing.gif", "deployment.gif", "cat.gif")
        }
        
        # Pre-cache GIF data as base64 for faster loading
        $cachedGifData = @{
        }
        foreach ($stage in $gifFiles.Keys) {
            foreach ($gifName in $gifFiles[$stage]) {
                $testPath = Join-Path $assetsPath $gifName
                if (Test-Path $testPath) {
                    try {
                        $gifBytes = [System.IO.File]::ReadAllBytes($testPath)
                        $cachedGifData[$stage] = @{
                            Path = $testPath
                            Data = $gifBytes
                            Name = $gifName
                        }
                        Write-Host "CAT: Cached GIF data for $stage`: $gifName ($($gifBytes.Length) bytes)" -ForegroundColor Green
                        break
                    } catch {
                        Write-Host "CAT: Failed to cache GIF for $stage`: $gifName - $_" -ForegroundColor Yellow
                    }
                }
            }
            
            if (-not $cachedGifData[$stage]) {
                $cachedGifData[$stage] = "TEXTFALLBACK"
                Write-Host "CAT: No GIF found for $stage, will use text fallback" -ForegroundColor Yellow
            }
        }
        
        # Initialize with PREPARING stage
        $script:CurrentStage = "PREPARING"
        $script:CatEnabled = $true
        $global:catModeEnabled = $true
        
        # Create main coordinator job with cached data
        $script:CatJob = Start-Job -ScriptBlock {
            param($CachedGifData, $ScreenWidth, $ScreenHeight, $InitialStage, $WindowSize)
            
            # Load assemblies in the coordinator job
            try {
                [void][reflection.assembly]::LoadWithPartialName("System.Windows.Forms")
                Add-Type -AssemblyName System.Drawing
                Write-Output "CAT: Coordinator job assemblies loaded"
            } catch {
                Write-Output "CAT: Failed to load assemblies in coordinator job: $_"
                return
            }
            
            # Shared variables
            $currentStage = $InitialStage
            $currentDisplayForm = $null
            $stageFile = "$env:TEMP\catmode_stage.txt"
            
            # Function to create display form directly (no job overhead)
            function Show-StageDisplay {
                param($Stage)
                
                Write-Output "CAT: Creating direct display for stage: $Stage"
                
                # Calculate position (top-right corner)
                $margin = [Math]::Max(10, [int](20 * ($WindowSize / 256)))
                $posX = $ScreenWidth - $WindowSize - $margin
                $posY = $margin
                
                $gifData = $CachedGifData[$Stage]
                
                try {
                    [System.Windows.Forms.Application]::EnableVisualStyles()
                    
                    # Create form directly
                    $catWindow = New-Object Windows.Forms.Form
                    $catWindow.Width = $WindowSize
                    $catWindow.Height = $WindowSize
                    $catWindow.TopMost = $true
                    $catWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
                    $catWindow.StartPosition = "Manual"
                    $catWindow.Location = New-Object System.Drawing.Point($posX, $posY)
                    $catWindow.BackColor = [System.Drawing.Color]::Black
                    $catWindow.ShowInTaskbar = $false
                    
                    if ($gifData -eq "TEXTFALLBACK") {
                        # Create text display
                        $stageText = switch ($Stage) {
                            "PREPARING" { "CAT`nGETTING`nREADY" }
                            "FORMATTING" { "CAT`nFORMAT`nTING" }
                            "INSTALLING" { "CAT`nINSTALL`nING" }
                            "CONFIGURING" { "CAT`nCONFIG`nURING" }
                            "COMPLETED" { "CAT`nDONE!" }
                            default { "CAT`nMODE" }
                        }
                        
                        $textLabel = New-Object System.Windows.Forms.Label
                        $textLabel.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(12, [int](16 * ($WindowSize / 256))), [System.Drawing.FontStyle]::Bold)
                        $textLabel.ForeColor = [System.Drawing.Color]::White
                        $textLabel.BackColor = [System.Drawing.Color]::Black
                        $textLabel.Width = $WindowSize
                        $textLabel.Height = $WindowSize
                        $textLabel.TextAlign = "MiddleCenter"
                        $textLabel.Location = New-Object System.Drawing.Point(0, 0)
                        $textLabel.Text = $stageText
                        $catWindow.Controls.Add($textLabel)
                        
                        Write-Output "CAT: Text display created for $Stage"
                        
                    } else {
                        # Create GIF display from cached data (no file I/O)
                        $pictureBox = New-Object Windows.Forms.PictureBox
                        $pictureBox.Width = $WindowSize
                        $pictureBox.Height = $WindowSize
                        $pictureBox.Location = New-Object System.Drawing.Point(0, 0)
                        $pictureBox.SizeMode = "Zoom"
                        $pictureBox.BackColor = [System.Drawing.Color]::Black
                        
                        # Load image directly from cached byte array (much faster)
                        $memoryStream = New-Object System.IO.MemoryStream(,$gifData.Data)
                        $image = [System.Drawing.Image]::FromStream($memoryStream)
                        $pictureBox.Image = $image
                        $catWindow.Controls.Add($pictureBox)
                        
                        # Store references for cleanup
                        $catWindow.Tag = @{
                            MemoryStream = $memoryStream
                            PictureBox = $pictureBox
                        }
                        
                        Write-Output "CAT: GIF display created for $Stage from cached data ($($gifData.Data.Length) bytes)"
                    }
                    
                    # Show the form immediately and keep it running indefinitely
                    $catWindow.Show()
                    [System.Windows.Forms.Application]::DoEvents()
                    
                    return $catWindow
                    
                } catch {
                    Write-Output "CAT: Error creating display for $Stage`: $_"
                    return $null
                }
            }
            
            # Function to hide current display
            function Hide-CurrentDisplay {
                if ($currentDisplayForm -and -not $currentDisplayForm.IsDisposed) {
                    try {
                        # Cleanup resources
                        if ($currentDisplayForm.Tag) {
                            $tag = $currentDisplayForm.Tag
                            if ($tag.PictureBox -and $tag.PictureBox.Image) {
                                $tag.PictureBox.Image.Dispose()
                            }
                            if ($tag.MemoryStream) {
                                $tag.MemoryStream.Dispose()
                            }
                        }
                        
                        $currentDisplayForm.Hide()
                        $currentDisplayForm.Dispose()
                        Write-Output "CAT: Previous display hidden and disposed"
                    } catch {
                        Write-Output "CAT: Error hiding previous display: $_"
                    }
                }
                $currentDisplayForm = $null
            }
            
            try {
                # Start initial stage display
                $currentDisplayForm = Show-StageDisplay -Stage $currentStage
                $currentStage | Out-File -FilePath $stageFile -Encoding UTF8 -Force
                
                Write-Output "CAT: Started initial stage display: $currentStage"
                
                # Main coordinator loop - simplified for live deployment
                $loopCount = 0
                while ($true) {
                    $loopCount++
                    Start-Sleep -Milliseconds 150
                    
                    # Process Windows messages to keep display responsive
                    if ($currentDisplayForm -and -not $currentDisplayForm.IsDisposed) {
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    
                    # Debug every 40 loops (6 seconds) - reduced frequency for live use
                    if ($loopCount % 40 -eq 0) {
                        $formStatus = if ($currentDisplayForm -and -not $currentDisplayForm.IsDisposed) { 'active' } else { 'disposed' }
                        Write-Output "CAT: Coordinator active - Current stage: $currentStage, Form: $formStatus"
                    }
                    
                    # Check for stage changes ONLY
                    if (Test-Path $stageFile) {
                        try {
                            $fileContent = Get-Content $stageFile -Encoding UTF8 -ErrorAction SilentlyContinue
                            $newStage = $fileContent | Select-Object -First 1
                            
                            # Only change display when stage actually changes
                            if ($newStage -and $newStage.Trim() -ne $currentStage) {
                                $newStage = $newStage.Trim()
                                Write-Output "CAT: Stage change detected: '$currentStage' -> '$newStage'"
                                
                                # Hide current display immediately
                                Hide-CurrentDisplay
                                
                                # Show new stage display immediately
                                $currentStage = $newStage
                                $currentDisplayForm = Show-StageDisplay -Stage $currentStage
                                Write-Output "CAT: Successfully switched to new stage display: $currentStage"
                            }
                        } catch {
                            Write-Output "CAT: Error checking stage file: $_"
                        }
                    }
                    
                    # Check if current form is still valid and recreate if needed
                    if ($currentDisplayForm -and $currentDisplayForm.IsDisposed) {
                        Write-Output "CAT: Current display was disposed unexpectedly, recreating for stage: $currentStage"
                        $currentDisplayForm = Show-StageDisplay -Stage $currentStage
                    }
                }
                
            } catch {
                Write-Output "CAT COORDINATOR ERROR: $_"
            } finally {
                Write-Output "CAT: Coordinator cleanup starting"
                Hide-CurrentDisplay
                
                if (Test-Path $stageFile) {
                    Remove-Item $stageFile -Force -ErrorAction SilentlyContinue
                }
                
                Write-Output "CAT: Coordinator cleanup completed"
            }
            
        } -ArgumentList $cachedGifData, $screenWidth, $screenHeight, $script:CurrentStage, $standardWindowSize
        
        # Minimal startup delay
        Start-Sleep -Milliseconds 200
        
        Write-Host "CAT: Optimized coordinator job started successfully!" -ForegroundColor Green
        
    } catch {
        Write-Host "CAT: Failed to start coordinator job: $_" -ForegroundColor Red
        $script:CatJob = $null
        $script:CatEnabled = $false
        $global:catModeEnabled = $false
    }
}

function Update-CatModeProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory)]
        [string]$Status
    )
    
    if (-not $script:CatEnabled -or -not $script:CatJob) {
        return
    }
    
    try {
        # Determine stage from status with improved keyword matching
        $stage = "PREPARING"
        
        # More comprehensive keyword matching
        if ($Status -match "format|partition|disk|diskpart|clean|create partition|active|assign") {
            $stage = "FORMATTING"
        }
        elseif ($Status -match "install|apply|image|copying|dism|expand|wim|esd") {
            $stage = "INSTALLING"
        }
        elseif ($Status -match "config|driver|boot|update|setup|inject|bcd|bootmgr") {
            $stage = "CONFIGURING"
        }
        elseif ($Status -match "complete|success|finished|done" -or $PercentComplete -eq 100) {
            $stage = "COMPLETED"
        }
        
        # Override based on percentage ranges as backup
        if ($PercentComplete -ge 0 -and $PercentComplete -lt 15) {
            if ($stage -eq "PREPARING") { $stage = "PREPARING" }
        }
        elseif ($PercentComplete -ge 15 -and $PercentComplete -lt 40) {
            if ($stage -eq "PREPARING") { $stage = "FORMATTING" }
        }
        elseif ($PercentComplete -ge 40 -and $PercentComplete -lt 85) {
            if ($stage -in @("PREPARING", "FORMATTING")) { $stage = "INSTALLING" }
        }
        elseif ($PercentComplete -ge 85 -and $PercentComplete -lt 100) {
            if ($stage -in @("PREPARING", "FORMATTING", "INSTALLING")) { $stage = "CONFIGURING" }
        }
        elseif ($PercentComplete -eq 100) {
            $stage = "COMPLETED"
        }
        
        Write-Host "CAT: Status '$Status' -> Stage '$stage' (Current: $script:CurrentStage, Progress: $PercentComplete%)" -ForegroundColor Yellow
        
        # Update stage if it changed
        if ($stage -ne $script:CurrentStage) {
            $script:CurrentStage = $stage
            
            # Communicate stage change to background job via temp file
            try {
                $stageFile = "$env:TEMP\catmode_stage.txt"
                
                # Force write with UTF8 encoding to ensure proper reading
                $stage | Out-File -FilePath $stageFile -Encoding UTF8 -Force
                
                Write-Host "CAT: Stage changed to $stage (written to file)" -ForegroundColor Magenta
                
                # Give the background job time to process the change
                Start-Sleep -Milliseconds 500
                
                # Verify the file was written correctly
                $verifyStage = Get-Content $stageFile -ErrorAction SilentlyContinue
                if ($verifyStage -ne $stage) {
                    Write-Host "CAT: WARNING - Stage file verification failed. Expected: $stage, Got: $verifyStage" -ForegroundColor Red
                }
                
            } catch {
                Write-Host "CAT: Error updating stage file: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "CAT: Stage unchanged ($stage)" -ForegroundColor DarkGray
        }
        
        # Verify the job is still running
        if ($script:CatJob.State -ne "Running") {
            Write-Host "CAT: Background job stopped unexpectedly (State: $($script:CatJob.State))" -ForegroundColor Yellow
            $script:CatEnabled = $false
        }
        
    } catch {
        Write-Host "CAT: Error in Update-CatModeProgress: $_" -ForegroundColor Yellow
    }
}

function Stop-CatMode {
    Write-Host "CAT: Stopping Cat Mode..." -ForegroundColor Cyan
    
    try {
        # Clean up stage communication file
        try {
            $stageFile = "$env:TEMP\catmode_stage.txt"
            if (Test-Path $stageFile) {
                Remove-Item $stageFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore cleanup errors
        }
        
        if ($script:CatJob) {
            try {
                # Stop the background job
                Stop-Job -Job $script:CatJob -Force
                Remove-Job -Job $script:CatJob -Force
                Write-Host "CAT: Background job stopped successfully" -ForegroundColor Green
            } catch {
                Write-Host "CAT: Error stopping background job: $_" -ForegroundColor Yellow
                try {
                    # Force cleanup if normal stop fails
                    Remove-Job -Job $script:CatJob -Force
                } catch {
                    # Ignore final cleanup errors
                }
            }
        }
        
        # Clear references
        $script:CatJob = $null
        $script:CatEnabled = $false
        $script:CurrentStage = "PREPARING"
        $global:catModeEnabled = $false
        
        Write-Host "CAT: Deployment complete! *purrs*" -ForegroundColor Magenta
        
    } catch {
        Write-Host "CAT: Error during cleanup: $_" -ForegroundColor Red
        
        # Force cleanup
        $script:CatJob = $null
        $script:CatEnabled = $false
        $script:CurrentStage = "PREPARING"
        $global:catModeEnabled = $false
    }
}

# Simple test function
function Test-CatMode {
    Start-CatMode
    
    Write-Host "CAT: Testing animated display for 15 seconds..." -ForegroundColor Yellow
    
    # Simulate deployment progress updates
    for ($i = 0; $i -le 100; $i += 10) {
        Update-CatModeProgress -PercentComplete $i -Status "Testing progress $i%..."
        Start-Sleep -Seconds 1
    }
    
    Write-Host "CAT: Test complete, stopping cat mode..." -ForegroundColor Yellow
    Stop-CatMode
}

# Test function that can be run manually to verify Cat Mode works
function Test-CatModeManual {
    Write-Host "CAT: Testing Cat Mode manually with proper stage switching..." -ForegroundColor Yellow
    
    try {
        # Test all stages with appropriate progress percentages and longer delays
        $stages = @(
            @{ Stage = "PREPARING"; Status = "Preparing deployment..."; Progress = 5 }
            @{ Stage = "FORMATTING"; Status = "Running diskpart to format drive..."; Progress = 20 }
            @{ Stage = "INSTALLING"; Status = "Applying Windows image with dism..."; Progress = 60 }
            @{ Stage = "CONFIGURING"; Status = "Installing device drivers..."; Progress = 85 }
            @{ Stage = "COMPLETED"; Status = "Deployment completed successfully!"; Progress = 100 }
        )
        
        Start-CatMode
        Write-Host "CAT: Started, testing stages with enhanced debugging..." -ForegroundColor Green
        Start-Sleep -Seconds 3  # Let cat mode fully initialize
        
        foreach ($test in $stages) {
            Write-Host "=" * 60 -ForegroundColor White
            Write-Host "CAT: Testing stage: $($test.Stage) with status: $($test.Status)" -ForegroundColor Cyan
            Write-Host "CAT: Expected progress: $($test.Progress)%" -ForegroundColor Cyan
            
            # Update progress and force stage change
            Update-CatModeProgress -PercentComplete $test.Progress -Status $test.Status
            
            # Give extra time for background job to process
            Start-Sleep -Seconds 3
            
            # Check background job output for debugging
            if ($script:CatJob) {
                $jobOutput = Receive-Job -Job $script:CatJob -Keep
                if ($jobOutput) {
                    Write-Host "CAT JOB OUTPUT:" -ForegroundColor Gray
                    $jobOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                }
                
                # Check job state
                Write-Host "CAT: Job state: $($script:CatJob.State)" -ForegroundColor Yellow
                if ($script:CatJob.State -ne "Running") {
                    Write-Host "CAT: WARNING - Job is not running!" -ForegroundColor Red
                    break
                }
            }
            
            Write-Host "CAT: Waiting 5 seconds to observe stage: $($test.Stage)" -ForegroundColor Magenta
            Start-Sleep -Seconds 5
        }
        
        Write-Host "=" * 60 -ForegroundColor White
        Write-Host "CAT: Test complete, stopping..." -ForegroundColor Yellow
        
        # Get final job output before stopping
        if ($script:CatJob) {
            $finalOutput = Receive-Job -Job $script:CatJob
            if ($finalOutput) {
                Write-Host "CAT FINAL JOB OUTPUT:" -ForegroundColor Gray
                $finalOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            }
        }
        
        Start-Sleep -Seconds 2
        Stop-CatMode
        
        Write-Host "CAT: Manual test completed successfully!" -ForegroundColor Green
        
    } catch {
        Write-Host "CAT: Test failed: $_" -ForegroundColor Red
        try { Stop-CatMode } catch {}
    }
}

# Enhanced test that shows stage detection logic with better debugging
function Test-CatModeStages {
    Write-Host "CAT: Testing Cat Mode stage detection with detailed output..." -ForegroundColor Yellow
    
    try {
        Start-CatMode
        Start-Sleep -Seconds 3
        
        # Test specific keywords that trigger each stage
        $testCases = @(
            @{ Status = "Gathering system information..."; ExpectedStage = "PREPARING" }
            @{ Status = "Running diskpart to format drive..."; ExpectedStage = "FORMATTING" }
            @{ Status = "Partitioning disk 0..."; ExpectedStage = "FORMATTING" }
            @{ Status = "Applying Windows image with dism..."; ExpectedStage = "INSTALLING" }
            @{ Status = "Copying system files..."; ExpectedStage = "INSTALLING" }
            @{ Status = "Installing device drivers..."; ExpectedStage = "CONFIGURING" }
            @{ Status = "Configuring boot loader..."; ExpectedStage = "CONFIGURING" }
            @{ Status = "Running Windows setup..."; ExpectedStage = "CONFIGURING" }
            @{ Status = "Deployment completed successfully!"; ExpectedStage = "COMPLETED" }
        )
        
        foreach ($test in $testCases) {
            Write-Host "=" * 50 -ForegroundColor White
            Write-Host "CAT: Testing: '$($test.Status)'" -ForegroundColor Cyan
            Write-Host "CAT: Expected stage: $($test.ExpectedStage)" -ForegroundColor Cyan
            
            Update-CatModeProgress -PercentComplete 50 -Status $test.Status
            
            # Check what stage was actually detected
            Start-Sleep -Seconds 1
            Write-Host "CAT: Current stage after update: $script:CurrentStage" -ForegroundColor Yellow
            
            # Get job output
            if ($script:CatJob) {
                $jobOutput = Receive-Job -Job $script:CatJob -Keep
                if ($jobOutput) {
                    $latestOutput = $jobOutput | Select-Object -Last 3
                    Write-Host "CAT: Recent job output:" -ForegroundColor Gray
                    $latestOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                }
            }
            
            Start-Sleep -Seconds 2
        }
        
        Write-Host "=" * 50 -ForegroundColor White
        Write-Host "CAT: Stage detection test complete" -ForegroundColor Yellow
        Stop-CatMode
        
    } catch {
        Write-Host "CAT: Stage test failed: $_" -ForegroundColor Red
        try { Stop-CatMode } catch {}
    }
}

# Test function to display all GIFs simultaneously for visual verification
function Test-CatModeAllGifs {
    Write-Host "CAT: Testing all GIFs simultaneously..." -ForegroundColor Yellow
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        
        # Get screen resolution
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        
        # Calculate window size (smaller for multiple windows)
        $windowSize = 200
        $margin = 20
        
        # Find available GIF files
        $assetsPath = "Y:\DeploymentModules\Assets\CatMode"
        $gifFiles = @{
            "PREPARING" = @("preparing.gif", "cat.gif", "deployment.gif", "animated.gif")
            "FORMATTING" = @("formatting.gif", "preparing.gif", "cat.gif", "deployment.gif")
            "INSTALLING" = @("installing.gif", "deployment.gif", "cat.gif", "animated.gif")
            "CONFIGURING" = @("configuring.gif", "installing.gif", "deployment.gif", "cat.gif")
            "COMPLETED" = @("completed.gif", "installing.gif", "deployment.gif", "cat.gif")
        }
        
        # Build available GIF paths
        $availableGifs = @{}
        foreach ($stage in $gifFiles.Keys) {
            foreach ($gifName in $gifFiles[$stage]) {
                $testPath = Join-Path $assetsPath $gifName
                if (Test-Path $testPath) {
                    $availableGifs[$stage] = $testPath
                    Write-Host "CAT: Found GIF for $stage`: $gifName" -ForegroundColor Green
                    break
                }
            }
            
            if (-not $availableGifs[$stage]) {
                $availableGifs[$stage] = "TEXTFALLBACK"
                Write-Host "CAT: No GIF found for $stage, using text fallback" -ForegroundColor Yellow
            }
        }
        
        # Create jobs for all stages simultaneously
        $allJobs = @()
        $stages = @("PREPARING", "FORMATTING", "INSTALLING", "CONFIGURING", "COMPLETED")
        
        for ($i = 0; $i -lt $stages.Count; $i++) {
            $stage = $stages[$i]
            $gifPath = $availableGifs[$stage]
            
            # Calculate position (arrange in a grid)
            $col = $i % 3  # 3 columns
            $row = [Math]::Floor($i / 3)  # Multiple rows if needed
            
            $posX = $margin + ($col * ($windowSize + $margin))
            $posY = $margin + ($row * ($windowSize + $margin + 50))  # Extra space for title
            
            Write-Host "CAT: Starting $stage at position ($posX, $posY)" -ForegroundColor Cyan
            
            if ($gifPath -eq "TEXTFALLBACK") {
                # Create text display job
                $stageText = switch ($stage) {
                    "PREPARING" { "CAT`nGETTING`nREADY" }
                    "FORMATTING" { "CAT`nFORMAT`nTING" }
                    "INSTALLING" { "CAT`nINSTALL`nING" }
                    "CONFIGURING" { "CAT`nCONFIG`nURING" }
                    "COMPLETED" { "CAT`nDONE!" }
                    default { "CAT`nMODE" }
                }
                
                $job = Start-Job -ScriptBlock {
                    param($WindowSize, $PosX, $PosY, $Stage, $StageText)
                    
                    [void][reflection.assembly]::LoadWithPartialName("System.Windows.Forms")
                    Add-Type -AssemblyName System.Drawing
                    
                    try {
                        [System.Windows.Forms.Application]::EnableVisualStyles()
                        
                        # Create form
                        $catWindow = New-Object Windows.Forms.Form
                        $catWindow.Width = $WindowSize
                        $catWindow.Height = $WindowSize + 30  # Extra space for title
                        $catWindow.TopMost = $true
                        $catWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
                        $catWindow.StartPosition = "Manual"
                        $catWindow.Location = New-Object System.Drawing.Point($PosX, $PosY)
                        $catWindow.BackColor = [System.Drawing.Color]::Black
                        $catWindow.Text = $Stage
                        
                        # Create text label
                        $textLabel = New-Object System.Windows.Forms.Label
                        $textLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
                        $textLabel.ForeColor = [System.Drawing.Color]::White
                        $textLabel.BackColor = [System.Drawing.Color]::Black
                        $textLabel.Width = $WindowSize
                        $textLabel.Height = $WindowSize
                        $textLabel.TextAlign = "MiddleCenter"
                        $textLabel.Location = New-Object System.Drawing.Point(0, 0)
                        $textLabel.Text = $StageText
                        $catWindow.Controls.Add($textLabel)
                        
                        # Show and run
                        $catWindow.Show()
                        
                        # Keep alive for 30 seconds
                        $startTime = Get-Date
                        while (((Get-Date) - $startTime).TotalSeconds -lt 30 -and -not $catWindow.IsDisposed) {
                            [System.Windows.Forms.Application]::DoEvents()
                            Start-Sleep -Milliseconds 100
                        }
                        
                    } catch {
                        Write-Output "CAT TEXT ERROR ($Stage): $_"
                    } finally {
                        if ($catWindow -and -not $catWindow.IsDisposed) {
                            $catWindow.Close()
                            $catWindow.Dispose()
                        }
                    }
                    
                } -ArgumentList $windowSize, $posX, $posY, $stage, $stageText
                
            } else {
                # Create GIF display job
                $job = Start-Job -ScriptBlock {
                    param($WindowSize, $PosX, $PosY, $Stage, $GifPath)
                    
                    [void][reflection.assembly]::LoadWithPartialName("System.Windows.Forms")
                    Add-Type -AssemblyName System.Drawing
                    
                    try {
                        [System.Windows.Forms.Application]::EnableVisualStyles()
                        
                        # Create form
                        $catWindow = New-Object Windows.Forms.Form
                        $catWindow.Width = $WindowSize
                        $catWindow.Height = $WindowSize + 30  # Extra space for title
                        $catWindow.TopMost = $true
                        $catWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
                        $catWindow.StartPosition = "Manual"
                        $catWindow.Location = New-Object System.Drawing.Point($PosX, $PosY)
                        $catWindow.BackColor = [System.Drawing.Color]::Black
                        $catWindow.Text = "$Stage - $(Split-Path $GifPath -Leaf)"
                        
                        # Create temporary copy of GIF
                        $tempGifPath = [System.IO.Path]::GetTempFileName()
                        $tempGifPath = [System.IO.Path]::ChangeExtension($tempGifPath, ".gif")
                        Copy-Item -Path $GifPath -Destination $tempGifPath -Force
                        
                        # Create picture box
                        $pictureBox = New-Object Windows.Forms.PictureBox
                        $pictureBox.Width = $WindowSize
                        $pictureBox.Height = $WindowSize
                        $pictureBox.Location = New-Object System.Drawing.Point(0, 0)
                        $pictureBox.SizeMode = "Zoom"
                        $pictureBox.BackColor = [System.Drawing.Color]::Black
                        
                        # Load GIF
                        $image = [System.Drawing.Image]::FromFile($tempGifPath)
                        $pictureBox.Image = $image
                        $catWindow.Controls.Add($pictureBox)
                        
                        # Show and run
                        $catWindow.Show()
                        
                        Write-Output "CAT: Displaying $Stage GIF: $GifPath (Original: $($image.Width)x$($image.Height), Display: ${WindowSize}x${WindowSize})"
                        
                        # Keep alive for 30 seconds
                        $startTime = Get-Date
                        while (((Get-Date) - $startTime).TotalSeconds -lt 30 -and -not $catWindow.IsDisposed) {
                            [System.Windows.Forms.Application]::DoEvents()
                            Start-Sleep -Milliseconds 100
                        }
                        
                    } catch {
                        Write-Output "CAT GIF ERROR ($Stage): $_"
                    } finally {
                        # Cleanup
                        if ($pictureBox -and $pictureBox.Image) {
                            $pictureBox.Image.Dispose()
                        }
                        if ($catWindow -and -not $catWindow.IsDisposed) {
                            $catWindow.Close()
                            $catWindow.Dispose()
                        }
                        if ($tempGifPath -and (Test-Path $tempGifPath)) {
                            Remove-Item $tempGifPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                    
                } -ArgumentList $windowSize, $posX, $posY, $stage, $gifPath
            }
            
            $allJobs += $job
        }
        
        Write-Host "CAT: All $($allJobs.Count) GIF windows started! Displaying for 30 seconds..." -ForegroundColor Green
        Write-Host "CAT: Windows are arranged in a grid pattern starting from top-left" -ForegroundColor Green
        Write-Host "CAT: Each window shows the stage name and GIF filename in the title bar" -ForegroundColor Green
        
        # Wait for all jobs to complete (30 seconds each)
        Write-Host "CAT: Waiting for display to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 32
        
        # Get output from all jobs
        foreach ($job in $allJobs) {
            try {
                $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
                if ($output) {
                    Write-Host "JOB OUTPUT:" -ForegroundColor Gray
                    $output | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                }
            } catch {}
        }
        
        # Clean up jobs
        foreach ($job in $allJobs) {
            try {
                Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            } catch {}
        }
        
        Write-Host "CAT: All GIFs test completed!" -ForegroundColor Green
        
    } catch {
        Write-Host "CAT: All GIFs test failed: $_" -ForegroundColor Red
    }
}

# Individual GIF test functions - each displays like the AllGifs test
function Test-CatModePreparing {
    Write-Host "CAT: Testing PREPARING stage GIF..." -ForegroundColor Yellow
    Show-SingleStageGif -Stage "PREPARING" -Duration 15
}

function Test-CatModeFormatting {
    Write-Host "CAT: Testing FORMATTING stage GIF..." -ForegroundColor Yellow
    Show-SingleStageGif -Stage "FORMATTING" -Duration 15
}

function Test-CatModeInstalling {
    Write-Host "CAT: Testing INSTALLING stage GIF..." -ForegroundColor Yellow
    Show-SingleStageGif -Stage "INSTALLING" -Duration 15
}

function Test-CatModeConfiguring {
    Write-Host "CAT: Testing CONFIGURING stage GIF..." -ForegroundColor Yellow
    Show-SingleStageGif -Stage "CONFIGURING" -Duration 15
}

function Test-CatModeCompleted {
    Write-Host "CAT: Testing COMPLETED stage GIF..." -ForegroundColor Yellow
    Show-SingleStageGif -Stage "COMPLETED" -Duration 15
}

# Core function to display a single stage GIF using optimized method - live deployment version
function Show-SingleStageGif {
    param(
        [Parameter(Mandatory)]
        [string]$Stage,
        
        [int]$Duration = 0,  # 0 = run indefinitely
        
        [int]$WindowSize = 256,
        
        [bool]$TopRight = $true
    )
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        
        # Get screen resolution
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $screenWidth = $screen.Bounds.Width
        $screenHeight = $screen.Bounds.Height
        
        # Calculate standardized window size based on screen resolution
        $scaleFactor = [Math]::Min($screenWidth / 1920, $screenHeight / 1080)
        $scaleFactor = [Math]::Max($scaleFactor, 0.4)
        $scaleFactor = [Math]::Min($scaleFactor, 2.0)
        $actualWindowSize = [int]($WindowSize * $scaleFactor)
        
        # Find and cache the GIF for this stage
        $assetsPath = "Y:\DeploymentModules\Assets\CatMode"
        $gifFiles = @{
            "PREPARING" = @("preparing.gif", "cat.gif", "deployment.gif", "animated.gif")
            "FORMATTING" = @("formatting.gif", "preparing.gif", "cat.gif", "deployment.gif")
            "INSTALLING" = @("installing.gif", "deployment.gif", "cat.gif", "animated.gif")
            "CONFIGURING" = @("configuring.gif", "installing.gif", "deployment.gif", "cat.gif")
            "COMPLETED" = @("completed.gif", "installing.gif", "deployment.gif", "cat.gif")
        }
        
        $gifPath = $null
        $gifData = $null
        foreach ($gifName in $gifFiles[$Stage]) {
            $testPath = Join-Path $assetsPath $gifName
            if (Test-Path $testPath) {
                $gifPath = $testPath
                $gifData = [System.IO.File]::ReadAllBytes($testPath)
                Write-Host "CAT: Cached GIF data for $Stage`: $gifName ($($gifData.Length) bytes)" -ForegroundColor Green
                break
            }
        }
        
        if (-not $gifData) {
            Write-Host "CAT: No GIF found for $Stage, using text fallback" -ForegroundColor Yellow
        }
        
        # Calculate position
        $margin = [Math]::Max(10, [int](20 * $scaleFactor))
        if ($TopRight) {
            $posX = $screenWidth - $actualWindowSize - $margin
            $posY = $margin
        } else {
            $posX = $margin
            $posY = $margin
        }
        
        Write-Host "CAT: Starting $Stage at position ($posX, $posY) with size ${actualWindowSize}x${actualWindowSize}" -ForegroundColor Cyan
        
        # Create display directly (no job overhead)
        $memoryStream = $null
        try {
            [System.Windows.Forms.Application]::EnableVisualStyles()
            
            $catWindow = New-Object Windows.Forms.Form
            $catWindow.Width = $actualWindowSize
            $catWindow.Height = $actualWindowSize
            $catWindow.TopMost = $true
            $catWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
            $catWindow.StartPosition = "Manual"
            $catWindow.Location = New-Object System.Drawing.Point($posX, $posY)
            $catWindow.BackColor = [System.Drawing.Color]::Black
            $catWindow.ShowInTaskbar = $false
            
            if (-not $gifData) {
                # Create text display
                $stageText = switch ($Stage) {
                    "PREPARING" { "CAT`nGETTING`nREADY" }
                    "FORMATTING" { "CAT`nFORMAT`nTING" }
                    "INSTALLING" { "CAT`nINSTALL`nING" }
                    "CONFIGURING" { "CAT`nCONFIG`nURING" }
                    "COMPLETED" { "CAT`nDONE!" }
                    default { "CAT`nMODE" }
                }
                
                $textLabel = New-Object System.Windows.Forms.Label
                $textLabel.Font = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(12, [int](16 * ($actualWindowSize / 256))), [System.Drawing.FontStyle]::Bold)
                $textLabel.ForeColor = [System.Drawing.Color]::White
                $textLabel.BackColor = [System.Drawing.Color]::Black
                $textLabel.Width = $actualWindowSize
                $textLabel.Height = $actualWindowSize
                $textLabel.TextAlign = "MiddleCenter"
                $textLabel.Location = New-Object System.Drawing.Point(0, 0)
                $textLabel.Text = $stageText
                $catWindow.Controls.Add($textLabel)
                
                Write-Host "CAT: Displaying $Stage text fallback" -ForegroundColor Green
                
            } else {
                # Create GIF display from cached data
                $pictureBox = New-Object Windows.Forms.PictureBox
                $pictureBox.Width = $actualWindowSize
                $pictureBox.Height = $actualWindowSize
                $pictureBox.Location = New-Object System.Drawing.Point(0, 0)
                $pictureBox.SizeMode = "Zoom"
                $pictureBox.BackColor = [System.Drawing.Color]::Black
                
                # Load image directly from byte array (with proper comma operator for array)
                $memoryStream = New-Object System.IO.MemoryStream(,$gifData)
                $image = [System.Drawing.Image]::FromStream($memoryStream)
                $pictureBox.Image = $image
                $catWindow.Controls.Add($pictureBox)
                
                Write-Host "CAT: Displaying $Stage GIF from cached data (Original: $($image.Width)x$($image.Height), Display: ${actualWindowSize}x${actualWindowSize})" -ForegroundColor Green
            }
            
            # Show immediately
            $catWindow.Show()
            [System.Windows.Forms.Application]::DoEvents()
            
            if ($Duration -gt 0) {
                Write-Host "CAT: $Stage display shown! Running for $Duration seconds..." -ForegroundColor Green
                
                # Keep alive for specified duration (for test functions only)
                $startTime = Get-Date
                while (((Get-Date) - $startTime).TotalSeconds -lt $Duration -and -not $catWindow.IsDisposed) {
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 50
                }
            } else {
                Write-Host "CAT: $Stage display shown and will run indefinitely until manually stopped" -ForegroundColor Green
                
                # For live deployment - keep the form alive but don't block
                # The coordinator job will handle the lifecycle
                return $catWindow
            }
            
        } catch {
            Write-Host "CAT: Error displaying $Stage`: $_" -ForegroundColor Red
        } finally {
            # Only cleanup if this was a timed display (test function)
            if ($Duration -gt 0) {
                if ($catWindow -and -not $catWindow.IsDisposed) {
                    $catWindow.Close()
                    $catWindow.Dispose()
                }
                if ($memoryStream) {
                    $memoryStream.Dispose()
                }
                Write-Host "CAT: $Stage display completed!" -ForegroundColor Green
            }
        }
        
    } catch {
        Write-Host "CAT: $Stage display failed: $_" -ForegroundColor Red
    }
}

Export-ModuleMember -Function Start-CatMode, Update-CatModeProgress, Stop-CatMode, Test-CatMode, Test-CatModeManual, Test-CatModeStages, Test-CatModeAllGifs, Test-CatModePreparing, Test-CatModeFormatting, Test-CatModeInstalling, Test-CatModeConfiguring, Test-CatModeCompleted, Show-SingleStageGif
