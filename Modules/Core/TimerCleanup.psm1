# Timer Cleanup Module - Prevents JIT debugging errors from orphaned timers

function Stop-AllTimers {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Cleaning up all timers..." -ForegroundColor Yellow
        
        # Stop all Windows Forms timers
        [System.Windows.Forms.Application]::DoEvents()
        
        # Find and stop all timer variables in all scopes
        @('Global', 'Script', 'Local') | ForEach-Object {
            $scope = $_
            try {
                Get-Variable -Name "*timer*" -Scope $scope -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        if ($_.Value -and ($_.Value.GetType().Name -like "*Timer*")) {
                            Write-Host "Stopping timer: $($_.Name) in scope: $scope" -ForegroundColor Gray
                            if ($_.Value | Get-Member -Name "Stop" -ErrorAction SilentlyContinue) {
                                $_.Value.Stop()
                            }
                            if ($_.Value | Get-Member -Name "Dispose" -ErrorAction SilentlyContinue) {
                                $_.Value.Dispose()
                            }
                            Remove-Variable -Name $_.Name -Scope $scope -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        # Silently handle individual timer cleanup errors
                    }
                }
            } catch {
                # Silently handle scope access errors
            }
        }
        
        # Clean up any disposed labels that timers might reference
        @('Global', 'Script') | ForEach-Object {
            $scope = $_
            try {
                Get-Variable -Name "*label*" -Scope $scope -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        if ($_.Value -and $_.Value.GetType().Name -like "*Label*" -and ($_.Value | Get-Member -Name "IsDisposed" -ErrorAction SilentlyContinue)) {
                            if ($_.Value.IsDisposed) {
                                Remove-Variable -Name $_.Name -Scope $scope -Force -ErrorAction SilentlyContinue
                            }
                        }
                    } catch {
                        # Silently handle cleanup errors
                    }
                }
            } catch {
                # Silently handle scope access errors
            }
        }
        
        Write-Host "Timer cleanup completed" -ForegroundColor Green
        
    } catch {
        Write-Host "Error during timer cleanup: $_" -ForegroundColor Red
    }
}

function Initialize-SafeFormHandlers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.Form]$Form
    )
    
    # Add comprehensive form closing handler
    $Form.Add_FormClosing({
        try {
            Stop-AllTimers
        } catch {
            # Silently handle cleanup errors
        }
    })
    
    # Add form disposed handler
    $Form.Add_Disposed({
        try {
            Stop-AllTimers
        } catch {
            # Silently handle cleanup errors
        }
    })
}

Export-ModuleMember -Function Stop-AllTimers, Initialize-SafeFormHandlers
