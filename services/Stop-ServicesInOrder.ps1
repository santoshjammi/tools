[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [int]$CheckIntervalSeconds = 10,

    [Parameter(Mandatory=$false)]
    [int]$TotalTimeoutMinutes = 5
)

$ErrorActionPreference = "Stop" # Ensure any major errors halt execution

$TotalTimeoutSeconds = $TotalTimeoutMinutes * 60

function Stop-ServiceWithTimeout {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    Write-Host "--- Checking service: **$ServiceName** ---" -ForegroundColor Cyan

    # 1. Check initial status
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Error "Service '$ServiceName' not found. Exiting."
        exit 1
    }

    if ($service.Status -eq 'Stopped') {
        Write-Host "SUCCESS: Service '$ServiceName' is already **Stopped**." -ForegroundColor Green
        return $true
    }

    # 2. Attempt to stop
    if ($service.Status -ne 'StopPending') {
        Write-Host "Status is '$($service.Status)'. Attempting to stop service..."
        Stop-Service -InputObject $service
        # Give a small initial grace period after the stop command
        Start-Sleep -Seconds 2
    }

    # 3. Polling loop with timeout
    $startTime = Get-Date

    while ((Get-Date) -lt $startTime.AddSeconds($TotalTimeoutSeconds)) {

        $currentStatus = (Get-Service -Name $ServiceName).Status
        $elapsedTime = (Get-Date) - $startTime

        Write-Host "Service status: **$currentStatus** (Elapsed: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s)" -ForegroundColor Yellow

        if ($currentStatus -eq 'Stopped') {
            Write-Host "SUCCESS: Service '$ServiceName' stopped and is **Stopped**." -ForegroundColor Green
            return $true
        }

        # If it's still 'StopPending' or 'Running', wait T seconds and recheck
        Start-Sleep -Seconds $CheckIntervalSeconds
    }

    # 4. Timeout failure
    Write-Error "FAILURE: Service '$ServiceName' failed to stop after $TotalTimeoutMinutes minutes."
    return $false
}

## 🚀 Main Execution Block
# Process services in the provided order
foreach ($serviceName in $ServiceNames) {
    if (-not (Stop-ServiceWithTimeout -ServiceName $serviceName)) {
        Write-Error "Script halting due to failure of service '$serviceName'."
        exit 1
    }
}

Write-Host "`nAll specified services stopped successfully." -ForegroundColor Green
exit 0