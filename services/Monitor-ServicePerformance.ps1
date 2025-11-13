[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 10,

    [Parameter(Mandatory=$false)]
    [int]$DurationMinutes = 5,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [switch]$Continuous,

    [Parameter(Mandatory=$false)]
    [hashtable]$Thresholds = @{
        CPUPercent = 80
        MemoryMB = 500
        ThreadCount = 100
    }
)

$ErrorActionPreference = "Stop"

function Get-ServicePerformanceMetrics {
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        $servicePid = (Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'").ProcessId

        if ($servicePid -and $servicePid -gt 0) {
            $process = Get-Process -Id $servicePid -ErrorAction SilentlyContinue

            if ($process) {
                $cpuPercent = $process.CPU
                $memoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
                $threadCount = $process.Threads.Count
                $handleCount = $process.HandleCount
                $startTime = $process.StartTime

                # Calculate uptime
                $uptime = $null
                if ($startTime) {
                    $uptime = (Get-Date) - $startTime
                }

                return @{
                    ServiceName = $ServiceName
                    Status = $service.Status
                    ProcessId = $servicePid
                    CPUPercent = $cpuPercent
                    MemoryMB = $memoryMB
                    ThreadCount = $threadCount
                    HandleCount = $handleCount
                    StartTime = $startTime
                    Uptime = $uptime
                    Timestamp = Get-Date
                    Error = $null
                }
            }
        }

        # Service exists but no process (stopped or system service)
        return @{
            ServiceName = $ServiceName
            Status = $service.Status
            ProcessId = $null
            CPUPercent = 0
            MemoryMB = 0
            ThreadCount = 0
            HandleCount = 0
            StartTime = $null
            Uptime = $null
            Timestamp = Get-Date
            Error = "No associated process"
        }

    } catch {
        return @{
            ServiceName = $ServiceName
            Status = "Unknown"
            ProcessId = $null
            CPUPercent = 0
            MemoryMB = 0
            ThreadCount = 0
            HandleCount = 0
            StartTime = $null
            Uptime = $null
            Timestamp = Get-Date
            Error = $_.Exception.Message
        }
    }
}

function Format-PerformanceData {
    param([array]$PerformanceData)

    $output = @()

    foreach ($data in $PerformanceData) {
        $uptimeStr = if ($data.Uptime) {
            "$($data.Uptime.Days)d $($data.Uptime.Hours)h $($data.Uptime.Minutes)m"
        } else { "N/A" }

        $cpuAlert = if ($data.CPUPercent -gt $Thresholds.CPUPercent) { " ⚠️ HIGH CPU" } else { "" }
        $memAlert = if ($data.MemoryMB -gt $Thresholds.MemoryMB) { " ⚠️ HIGH MEM" } else { "" }
        $threadAlert = if ($data.ThreadCount -gt $Thresholds.ThreadCount) { " ⚠️ HIGH THREADS" } else { "" }

        $output += [PSCustomObject]@{
            Service = $data.ServiceName
            Status = $data.Status
            PID = $data.ProcessId
            CPU = "$($data.CPUPercent)%$cpuAlert"
            Memory = "$($data.MemoryMB) MB$memAlert"
            Threads = "$($data.ThreadCount)$threadAlert"
            Handles = $data.HandleCount
            Uptime = $uptimeStr
            Timestamp = $data.Timestamp
        }
    }

    return $output
}

function Show-PerformanceSummary {
    param([array]$PerformanceHistory)

    Write-Host ""
    Write-Host "=== PERFORMANCE SUMMARY ===" -ForegroundColor Cyan

    $latestData = $PerformanceHistory | Group-Object ServiceName | ForEach-Object {
        $_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1
    }

    foreach ($data in $latestData) {
        $statusColor = switch ($data.Status) {
            "Running" { "Green" }
            "Stopped" { "Red" }
            default { "Yellow" }
        }

        Write-Host "$($data.ServiceName):" -ForegroundColor White -NoNewline
        Write-Host " $($data.Status)" -ForegroundColor $statusColor -NoNewline

        if ($data.Error) {
            Write-Host " (Error: $($data.Error))" -ForegroundColor Red
        } elseif ($data.ProcessId) {
            Write-Host " (PID: $($data.ProcessId), CPU: $($data.CPUPercent)%, Mem: $($data.MemoryMB) MB)" -ForegroundColor Gray
        } else {
            Write-Host " (No process)" -ForegroundColor Gray
        }
    }

    # Show alerts
    $alerts = $latestData | Where-Object {
        $_.CPUPercent -gt $Thresholds.CPUPercent -or
        $_.MemoryMB -gt $Thresholds.MemoryMB -or
        $_.ThreadCount -gt $Thresholds.ThreadCount
    }

    if ($alerts.Count -gt 0) {
        Write-Host ""
        Write-Host "⚠️  PERFORMANCE ALERTS:" -ForegroundColor Red
        foreach ($alert in $alerts) {
            $alertReasons = @()
            if ($alert.CPUPercent -gt $Thresholds.CPUPercent) { $alertReasons += "High CPU ($($alert.CPUPercent)%)" }
            if ($alert.MemoryMB -gt $Thresholds.MemoryMB) { $alertReasons += "High Memory ($($alert.MemoryMB) MB)" }
            if ($alert.ThreadCount -gt $Thresholds.ThreadCount) { $alertReasons += "High Thread Count ($($alert.ThreadCount))" }

            Write-Host "  $($alert.ServiceName): $($alertReasons -join ', ')" -ForegroundColor Yellow
        }
    }
}

# Main monitoring loop
Write-Host "Starting service performance monitoring..." -ForegroundColor Cyan
Write-Host "Services: $($ServiceNames -join ', ')" -ForegroundColor White
Write-Host "Interval: $IntervalSeconds seconds" -ForegroundColor White
Write-Host "Duration: $(if ($Continuous) { 'Continuous' } else { "$DurationMinutes minutes" })" -ForegroundColor White
Write-Host "Thresholds: CPU > $($Thresholds.CPUPercent)%, Memory > $($Thresholds.MemoryMB) MB, Threads > $($Thresholds.ThreadCount)" -ForegroundColor White
Write-Host ""

$performanceHistory = @()
$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)

try {
    $iteration = 0
    while ($Continuous -or (Get-Date) -lt $endTime) {
        $iteration++
        $currentTime = Get-Date

        Write-Host "[$currentTime] Monitoring iteration $iteration..." -ForegroundColor Gray

        $currentMetrics = @()
        foreach ($service in $ServiceNames) {
            $metrics = Get-ServicePerformanceMetrics -ServiceName $service
            $currentMetrics += $metrics
            $performanceHistory += $metrics
        }

        Show-PerformanceSummary -PerformanceHistory $currentMetrics

        if (-not $Continuous) {
            $remainingTime = $endTime - (Get-Date)
            if ($remainingTime.TotalSeconds -gt 0) {
                Write-Host "Next check in $IntervalSeconds seconds... (Remaining: $($remainingTime.Minutes)m $($remainingTime.Seconds)s)" -ForegroundColor Gray
            }
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Export results if requested
    if ($OutputFile) {
        Write-Host ""
        Write-Host "Exporting performance data to: $OutputFile" -ForegroundColor Cyan

        $formattedData = Format-PerformanceData -PerformanceData $performanceHistory
        $formattedData | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

        Write-Host "Performance monitoring data exported successfully." -ForegroundColor Green
    }

} catch {
    Write-Error "Performance monitoring stopped due to error: $($_.Exception.Message)"
} finally {
    Write-Host ""
    Write-Host "Performance monitoring completed." -ForegroundColor Green
}