# AdditionalTasks.ps1
# This script runs in Audit Mode during Windows deployment.
# Place your custom tasks below. This script will self-delete after execution.

$logFile = "$env:SystemDrive\Scripts\AdditionalTasks.log"

function Write-TaskLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-TaskLog "=== Starting AdditionalTasks.ps1 ==="

try {
    # --- Close Sysprep window if open ---
    try {
        $sysprepProc = Get-Process -Name sysprep -ErrorAction SilentlyContinue
        if ($sysprepProc) {
            Write-TaskLog "Sysprep process found. Closing Sysprep window..."
            $sysprepProc | Stop-Process -Force
            Write-TaskLog "Sysprep process closed."
        } else {
            Write-TaskLog "No Sysprep process found to close."
        }
    } catch {
        Write-TaskLog "Error closing Sysprep: $($_.Exception.Message)" "ERROR"
    }

    # --- BEGIN CUSTOM TASKS ---
    # Example: Install a package, copy files, set registry keys, etc.
    # Write-TaskLog "Performing custom task..."
    
    # --- EXAMPLES FOR COMMON TASKS ---
    # 1. Run another PowerShell script with ExecutionPolicy Bypass:
    # Write-TaskLog "Running MyScript.ps1 with ExecutionPolicy Bypass..."
    # Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -File C:\Scripts\MyScript.ps1' -Wait
    
    # 2. Run a batch file:
    # Write-TaskLog "Running mybatch.bat..."
    # Start-Process cmd.exe -ArgumentList '/c C:\Scripts\mybatch.bat' -Wait
    
    # 3. Open an application (e.g., Notepad):
    # Write-TaskLog "Opening Notepad..."
    # Start-Process notepad.exe
    
    # 4. Open a custom application (by full path):
    # Write-TaskLog "Opening custom app..."
    # Start-Process "C:\Path\To\YourApp.exe"
    
    # 5. Install an EXE installer (with silent options):
    # Write-TaskLog "Installing MyInstaller.exe silently..."
    # Start-Process "C:\Scripts\MyInstaller.exe" -ArgumentList '/silent' -Wait
    
    # 6. Install an MSI file (with msiexec and silent options):
    # Write-TaskLog "Installing MyInstaller.msi silently..."
    # Start-Process msiexec.exe -ArgumentList '/i "C:\Scripts\MyInstaller.msi" /qn /norestart' -Wait
    
    # Add your custom PowerShell code here
    # --- END CUSTOM TASKS ---
    Write-TaskLog "All additional tasks completed successfully." "SUCCESS"
} catch {
    Write-TaskLog "ERROR: $($_.Exception.Message)" "ERROR"
}

# --- Windows Forms confirmation before self-delete ---
Add-Type -AssemblyName System.Windows.Forms
$confirmation = [System.Windows.Forms.MessageBox]::Show(
    "All additional tasks have been run.`n`nDo you want to continue and finalize the deployment?`n(This will delete this script and reopen Sysprep)",
    "Confirm Completion",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)
if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
    Write-TaskLog "User cancelled finalization. Script will not self-delete or reopen Sysprep." "WARNING"
    exit 0
}

# --- Reopen Sysprep ---
try {
    $sysprepPath = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
    if (Test-Path $sysprepPath) {
        Start-Process -FilePath $sysprepPath
        Write-TaskLog "Sysprep relaunched after confirmation." "SUCCESS"
    } else {
        Write-TaskLog "Sysprep.exe not found at $sysprepPath. Cannot relaunch." "ERROR"
    }
} catch {
    Write-TaskLog "Error relaunching Sysprep: $($_.Exception.Message)" "ERROR"
}

Write-TaskLog "Self-deleting C:\Scripts folder..."

# Self-delete the entire Scripts folder
$scriptsFolder = "$env:SystemDrive\Scripts"
Remove-Item -Path $scriptsFolder -Recurse -Force
