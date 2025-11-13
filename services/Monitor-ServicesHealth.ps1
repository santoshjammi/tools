[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [int]$CheckIntervalSeconds = 60,

    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory=$false)]
    [switch]$AutoRestart,

    [Parameter(Mandatory=$false)]
    [string]$LogFile = "",

    [Parameter(Mandatory=$false)]
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    if (-not $Quiet) {
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }

    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage
    }
}

function Test-ServiceHealth {
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq 'Running') {
            # Additional health checks could be added here
            # For example: check if the service is responding to requests
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

function Restart-ServiceIfNeeded {
    param([string]$ServiceName)

    Write-Log "Attempting to restart service: $ServiceName" "WARN"

    try {
        Restart-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 5

        # Verify restart was successful
        $service = Get-Service -Name $ServiceName
        if ($service.Status -eq 'Running') {
            Write-Log "Service $ServiceName restarted successfully" "SUCCESS"
            return $true
        } else {
            Write-Log "Service $ServiceName failed to restart properly" "ERROR"
            return $false
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "Failed to restart service $ServiceName`: $errorMsg" "ERROR"
        return $false
    }
}

# Main monitoring loop
Write-Log "Starting service health monitoring for: $($ServiceNames -join ', ')"
Write-Log "Check interval: $CheckIntervalSeconds seconds"
Write-Log "Auto-restart: $AutoRestart"
if ($LogFile) { Write-Log "Logging to: $LogFile" }

$serviceStates = @{}
foreach ($service in $ServiceNames) {
    $serviceStates[$service] = @{
        LastStatus = $null
        FailureCount = 0
        LastCheck = $null
    }
}

try {
    while ($true) {
        $currentTime = Get-Date

        foreach ($service in $ServiceNames) {
            $isHealthy = Test-ServiceHealth -ServiceName $service
            $state = $serviceStates[$service]

            if ($isHealthy) {
                if ($state.LastStatus -eq $false) {
                    Write-Log "Service $service is now healthy" "SUCCESS"
                }
                $state.FailureCount = 0
            } else {
                $state.FailureCount++
                Write-Log "Service $service is unhealthy (failure count: $($state.FailureCount))" "WARN"

                if ($AutoRestart -and $state.FailureCount -ge $MaxRetries) {
                    if (Restart-ServiceIfNeeded -ServiceName $service) {
                        $state.FailureCount = 0
                    }
                }
            }

            $state.LastStatus = $isHealthy
            $state.LastCheck = $currentTime
        }

        Start-Sleep -Seconds $CheckIntervalSeconds
    }
} catch {
    Write-Log "Monitoring stopped due to error: $($_.Exception.Message)" "ERROR"
    exit 1
}