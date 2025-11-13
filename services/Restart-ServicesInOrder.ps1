[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [int]$CheckIntervalSeconds = 10,

    [Parameter(Mandatory=$false)]
    [int]$TotalTimeoutMinutes = 5,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop" # Ensure any major errors halt execution

$TotalTimeoutSeconds = $TotalTimeoutMinutes * 60

function Restart-ServiceWithTimeout {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    Write-Host "--- Restarting service: $ServiceName ---" -ForegroundColor Cyan

    # 1. Check if service exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Error "Service '$ServiceName' not found. Exiting."
        exit 1
    }

    $initialStatus = $service.Status
    Write-Host "Initial status: $initialStatus" -ForegroundColor Yellow

    # 2. Stop the service if it's running
    if ($initialStatus -eq 'Running' -or $Force) {
        Write-Host "Stopping service..." -ForegroundColor Yellow

        if ($service.Status -ne 'StopPending') {
            Stop-Service -InputObject $service
            Start-Sleep -Seconds 2
        }

        # Wait for service to stop
        $stopStartTime = Get-Date
        while ((Get-Date) -lt $stopStartTime.AddSeconds($TotalTimeoutSeconds)) {
            $currentStatus = (Get-Service -Name $ServiceName).Status
            $elapsedTime = (Get-Date) - $stopStartTime

            if ($currentStatus -eq 'Stopped') {
                Write-Host "Service stopped successfully." -ForegroundColor Green
                break
            }

            Write-Host "Waiting for stop... Status: $currentStatus (Elapsed: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s)" -ForegroundColor Yellow
            Start-Sleep -Seconds $CheckIntervalSeconds
        }

        if ((Get-Service -Name $ServiceName).Status -ne 'Stopped') {
            Write-Error "FAILURE: Service '$ServiceName' failed to stop within timeout."
            return $false
        }
    } else {
        Write-Host "Service was not running, skipping stop phase." -ForegroundColor Yellow
    }

    # 3. Start the service
    Write-Host "Starting service..." -ForegroundColor Yellow

    if ((Get-Service -Name $ServiceName).Status -ne 'StartPending') {
        Start-Service -InputObject (Get-Service -Name $ServiceName)
        Start-Sleep -Seconds 2
    }

    # 4. Wait for service to start
    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($TotalTimeoutSeconds)) {
        $currentStatus = (Get-Service -Name $ServiceName).Status
        $elapsedTime = (Get-Date) - $startTime

        Write-Host "Waiting for start... Status: $currentStatus (Elapsed: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s)" -ForegroundColor Yellow

        if ($currentStatus -eq 'Running') {
            Write-Host "SUCCESS: Service '$ServiceName' restarted successfully." -ForegroundColor Green
            return $true
        }

        Start-Sleep -Seconds $CheckIntervalSeconds
    }

    # 5. Timeout failure
    Write-Error "FAILURE: Service '$ServiceName' failed to start after restart within $TotalTimeoutMinutes minutes."
    return $false
}

## Main Execution Block
# Process services in the provided order
foreach ($serviceName in $ServiceNames) {
    if (-not (Restart-ServiceWithTimeout -ServiceName $serviceName)) {
        Write-Error "Script halting due to failure to restart service '$serviceName'."
        exit 1
    }
    Write-Host ""
}

Write-Host "All specified services restarted successfully." -ForegroundColor Green
exit 0