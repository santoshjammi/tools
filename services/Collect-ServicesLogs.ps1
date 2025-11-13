[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [int]$HoursBack = 24,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",

    [Parameter(Mandatory=$false)]
    [switch]$IncludeSystemLogs,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Error", "Warning", "Information", "All")]
    [string]$LogLevel = "All",

    [Parameter(Mandatory=$false)]
    [switch]$CompressOutput
)

$ErrorActionPreference = "Stop"

function Get-ServiceEventLogs {
    param(
        [string[]]$ServiceNames,
        [int]$HoursBack,
        [string]$LogLevel
    )

    $startTime = (Get-Date).AddHours(-$HoursBack)
    $logs = @()

    Write-Host "Collecting event logs from $HoursBack hours ago..." -ForegroundColor Cyan

    foreach ($serviceName in $ServiceNames) {
        Write-Host "Processing logs for service: $serviceName" -ForegroundColor Yellow

        try {
            # Get logs from System event log where source matches service name
            $systemLogs = Get-EventLog -LogName System -After $startTime -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -like "*$serviceName*" }

            # Get logs from Application event log
            $appLogs = Get-EventLog -LogName Application -After $startTime -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -like "*$serviceName*" }

            # Get logs from service-specific event logs if they exist
            $serviceLogs = @()
            try {
                $serviceLogs = Get-EventLog -LogName $serviceName -After $startTime -ErrorAction SilentlyContinue
            } catch {
                # Service-specific log doesn't exist, skip
            }

            # Combine all logs
            $allServiceLogs = $systemLogs + $appLogs + $serviceLogs

            # Filter by log level
            if ($LogLevel -ne "All") {
                $levelMap = @{
                    "Error" = "Error"
                    "Warning" = "Warning"
                    "Information" = "Information"
                }
                $allServiceLogs = $allServiceLogs | Where-Object { $_.EntryType -eq $levelMap[$LogLevel] }
            }

            # Format logs
            foreach ($log in $allServiceLogs) {
                $logEntry = @{
                    ServiceName = $serviceName
                    TimeGenerated = $log.TimeGenerated
                    EntryType = $log.EntryType
                    Source = $log.Source
                    EventID = $log.EventID
                    Message = $log.Message
                    LogName = $log.LogName
                }
                $logs += $logEntry
            }

            Write-Host "Found $($allServiceLogs.Count) log entries for $serviceName" -ForegroundColor Green

        } catch {
            Write-Warning "Failed to collect logs for service $serviceName`: $($_.Exception.Message)"
        }
    }

    # Include system-wide service events if requested
    if ($IncludeSystemLogs) {
        Write-Host "Including system-wide service events..." -ForegroundColor Yellow

        $systemServiceLogs = Get-EventLog -LogName System -After $startTime -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -like "*Service*" -or $_.Source -like "*SCM*" }

        foreach ($log in $systemServiceLogs) {
            $logEntry = @{
                ServiceName = "SYSTEM"
                TimeGenerated = $log.TimeGenerated
                EntryType = $log.EntryType
                Source = $log.Source
                EventID = $log.EventID
                Message = $log.Message
                LogName = $log.LogName
            }
            $logs += $logEntry
        }
    }

    return $logs
}

function Export-LogsToFile {
    param(
        [array]$Logs,
        [string]$OutputFile,
        [switch]$CompressOutput
    )

    if (-not $OutputFile) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $OutputFile = "ServiceLogs_$timestamp.csv"
    }

    Write-Host "Exporting $($Logs.Count) log entries to: $OutputFile" -ForegroundColor Cyan

    # Export to CSV
    $Logs | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

    Write-Host "Logs exported successfully" -ForegroundColor Green

    # Compress if requested
    if ($CompressOutput) {
        $zipFile = $OutputFile -replace '\.csv$', '.zip'
        Compress-Archive -Path $OutputFile -DestinationPath $zipFile -Force
        Remove-Item $OutputFile
        Write-Host "Logs compressed to: $zipFile" -ForegroundColor Green
    }
}

# Main execution
$logs = Get-ServiceEventLogs -ServiceNames $ServiceNames -HoursBack $HoursBack -LogLevel $LogLevel

Write-Host ""
Write-Host "Log Collection Summary:" -ForegroundColor Cyan
Write-Host "Total log entries collected: $($logs.Count)" -ForegroundColor White
Write-Host "Services processed: $($ServiceNames.Count)" -ForegroundColor White
Write-Host "Time range: $HoursBack hours back from $(Get-Date)" -ForegroundColor White

if ($logs.Count -gt 0) {
    # Group by service and entry type for summary
    $summary = $logs | Group-Object ServiceName, EntryType | Select-Object Count, Name

    Write-Host ""
    Write-Host "Breakdown by service and severity:" -ForegroundColor Yellow
    $summary | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) entries" -ForegroundColor White
    }

    Export-LogsToFile -Logs $logs -OutputFile $OutputFile -CompressOutput:$CompressOutput
} else {
    Write-Host "No log entries found for the specified criteria" -ForegroundColor Yellow
}