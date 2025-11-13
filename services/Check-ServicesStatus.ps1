[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [switch]$Detailed,

    [Parameter(Mandatory=$false)]
    [switch]$AlertOnly
)

$ErrorActionPreference = "Stop" # Ensure any major errors halt execution

function Get-ServiceStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    Write-Host "--- Service: $ServiceName ---" -ForegroundColor Cyan

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        $status = $service.Status
        $startType = (Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'").StartMode

        if ($Detailed) {
            $displayName = $service.DisplayName
            $description = (Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'").Description

            Write-Host "Display Name: $displayName" -ForegroundColor White
            Write-Host "Description: $description" -ForegroundColor White
            Write-Host "Status: $status" -ForegroundColor $(if ($status -eq 'Running') { 'Green' } else { 'Red' })
            Write-Host "Start Type: $startType" -ForegroundColor Yellow
        } else {
            $statusColor = switch ($status) {
                'Running' { 'Green' }
                'Stopped' { 'Red' }
                'StartPending' { 'Yellow' }
                'StopPending' { 'Yellow' }
                default { 'Gray' }
            }
            Write-Host "Status: $status" -ForegroundColor $statusColor
        }

        return @{
            Name = $ServiceName
            Status = $status
            StartType = $startType
            Exists = $true
        }

    } catch {
        Write-Host "ERROR: Service '$ServiceName' not found or inaccessible." -ForegroundColor Red
        return @{
            Name = $ServiceName
            Status = 'NotFound'
            StartType = 'Unknown'
            Exists = $false
        }
    }
}

## Main Execution Block
$results = @()
$runningCount = 0
$stoppedCount = 0
$notFoundCount = 0

Write-Host "Checking status of $($ServiceNames.Count) services..." -ForegroundColor Cyan
Write-Host ""

foreach ($serviceName in $ServiceNames) {
    $result = Get-ServiceStatus -ServiceName $serviceName
    $results += $result

    switch ($result.Status) {
        'Running' { $runningCount++ }
        'Stopped' { $stoppedCount++ }
        'NotFound' { $notFoundCount++ }
        default { $stoppedCount++ } # Other states count as not running
    }

    Write-Host ""
}

# Summary
Write-Host "=== STATUS SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Services: $($ServiceNames.Count)" -ForegroundColor White
Write-Host "Running: $runningCount" -ForegroundColor Green
Write-Host "Stopped/Not Running: $stoppedCount" -ForegroundColor Red
Write-Host "Not Found: $notFoundCount" -ForegroundColor Yellow

if ($AlertOnly) {
    $issues = $results | Where-Object { $_.Status -ne 'Running' -or -not $_.Exists }
    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-Host "=== ALERTS ===" -ForegroundColor Red
        foreach ($issue in $issues) {
            if (-not $issue.Exists) {
                Write-Host "Service '$($issue.Name)' not found!" -ForegroundColor Red
            } elseif ($issue.Status -ne 'Running') {
                Write-Host "Service '$($issue.Name)' is $($issue.Status)!" -ForegroundColor Yellow
            }
        }
        exit 1
    }
}

Write-Host ""
Write-Host "Status check completed." -ForegroundColor Green
exit 0