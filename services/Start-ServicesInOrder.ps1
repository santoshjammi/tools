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

function Start-ServiceWithTimeout {
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

    if ($service.Status -eq 'Running') {
        Write-Host "SUCCESS: Service '$ServiceName' is already **Running**." -ForegroundColor Green
        return $true
    }

    # 2. Attempt to start
    if ($service.Status -ne 'StartPending') {
        Write-Host "Status is '$($service.Status)'. Attempting to start service..."
        Start-Service -InputObject $service
        # Give a small initial grace period after the start command
        Start-Sleep -Seconds 2
    }

    # 3. Polling loop with timeout
    $startTime = Get-Date
    
    while ((Get-Date) -lt $startTime.AddSeconds($TotalTimeoutSeconds)) {
        
        $currentStatus = (Get-Service -Name $ServiceName).Status
        $elapsedTime = (Get-Date) - $startTime
        
        Write-Host "Service status: **$currentStatus** (Elapsed: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s)" -ForegroundColor Yellow

        if ($currentStatus -eq 'Running') {
            Write-Host "SUCCESS: Service '$ServiceName' started and is **Running**." -ForegroundColor Green
            return $true
        }

        # If it's still 'StartPending' or 'Stopped', wait T seconds and recheck
        Start-Sleep -Seconds $CheckIntervalSeconds
    }

    # 4. Timeout failure
    Write-Error "FAILURE: Service '$ServiceName' failed to start after $TotalTimeoutMinutes minutes."
    return $false
}

## 🚀 Main Execution Block
# Process services in the provided order
foreach ($serviceName in $ServiceNames) {
    if (-not (Start-ServiceWithTimeout -ServiceName $serviceName)) {
        Write-Error "Script halting due to failure of service '$serviceName'."
        exit 1
    }
}

Write-Host "`nAll specified services started successfully." -ForegroundColor Green
exit 0
