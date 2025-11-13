[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$ServiceNames,

    [Parameter(Mandatory=$false)]
    [switch]$AllServices,

    [Parameter(Mandatory=$false)]
    [switch]$ShowGraph,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [int]$MaxDepth = 5
)

$ErrorActionPreference = "Stop"

function Get-ServiceDependencies {
    param([string]$ServiceName, [int]$Depth = 0, [System.Collections.Hashtable]$Visited = @{})

    if ($Depth -ge $MaxDepth -or $Visited.ContainsKey($ServiceName)) {
        return @{
            Name = $ServiceName
            Dependencies = @()
            Dependents = @()
            Depth = $Depth
            Cycle = $Visited.ContainsKey($ServiceName)
        }
    }

    $Visited[$ServiceName] = $true

    try {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
        if (-not $service) {
            return @{
                Name = $ServiceName
                Dependencies = @()
                Dependents = @()
                Depth = $Depth
                Error = "Service not found"
            }
        }

        # Get dependencies (services this service depends on)
        $dependencies = @()
        if ($service.DependentServices) {
            foreach ($dep in $service.DependentServices) {
                $dependencies += $dep.Name
            }
        }

        # Get dependents (services that depend on this service)
        $dependents = @()
        if ($service.DependentServices) {
            # This is actually the reverse - services that depend on this one
            $dependentServices = Get-WmiObject -Class Win32_Service -Filter "Name!='$ServiceName'"
            foreach ($svc in $dependentServices) {
                if ($svc.DependentServices -and ($svc.DependentServices | Where-Object { $_.Name -eq $ServiceName })) {
                    $dependents += $svc.Name
                }
            }
        }

        # Recursively get dependency details
        $dependencyDetails = @()
        foreach ($dep in $dependencies) {
            $dependencyDetails += Get-ServiceDependencies -ServiceName $dep -Depth ($Depth + 1) -Visited $Visited.Clone()
        }

        return @{
            Name = $ServiceName
            DisplayName = $service.DisplayName
            Status = $service.State
            StartMode = $service.StartMode
            Dependencies = $dependencies
            Dependents = $dependents
            DependencyDetails = $dependencyDetails
            Depth = $Depth
        }

    } catch {
        return @{
            Name = $ServiceName
            Dependencies = @()
            Dependents = @()
            Depth = $Depth
            Error = $_.Exception.Message
        }
    }
}

function Show-DependencyGraph {
    param([array]$ServiceData, [int]$Indent = 0)

    foreach ($service in $ServiceData) {
        $prefix = "  " * $Indent
        $status = switch ($service.Status) {
            "Running" { "🟢" }
            "Stopped" { "🔴" }
            default { "🟡" }
        }

        Write-Host "$prefix$status $($service.Name) ($($service.DisplayName))" -ForegroundColor $(if ($service.Status -eq "Running") { "Green" } else { "Red" })

        if ($service.Error) {
            Write-Host "$prefix  ❌ Error: $($service.Error)" -ForegroundColor Red
        }

        if ($service.Dependents.Count -gt 0) {
            Write-Host "$prefix  📈 Dependents: $($service.Dependents -join ', ')" -ForegroundColor Yellow
        }

        if ($service.Dependencies.Count -gt 0) {
            Write-Host "$prefix  📉 Dependencies:" -ForegroundColor Cyan
            foreach ($dep in $service.Dependencies) {
                Write-Host "$prefix    └─ $dep" -ForegroundColor Gray
            }
        }

        # Recursively show dependency details
        if ($service.DependencyDetails -and $service.DependencyDetails.Count -gt 0) {
            Show-DependencyGraph -ServiceData $service.DependencyDetails -Indent ($Indent + 2)
        }
    }
}

function Export-DependencyReport {
    param([array]$ServiceData, [string]$OutputFile)

    $report = @()
    $report += "Service Dependency Analysis Report"
    $report += "Generated: $(Get-Date)"
    $report += "=================================="
    $report += ""

    function Add-ServiceToReport {
        param([object]$Service, [int]$Indent = 0)

        $prefix = "  " * $Indent
        $report += "$prefix$($Service.Name) - $($Service.DisplayName)"
        $report += "$prefix  Status: $($Service.Status)"
        $report += "$prefix  Start Mode: $($Service.StartMode)"

        if ($Service.Dependents.Count -gt 0) {
            $report += "$prefix  Dependents: $($Service.Dependents -join ', ')"
        }

        if ($Service.Dependencies.Count -gt 0) {
            $report += "$prefix  Dependencies: $($Service.Dependencies -join ', ')"
        }

        if ($Service.Error) {
            $report += "$prefix  Error: $($Service.Error)"
        }

        $report += ""

        foreach ($dep in $Service.DependencyDetails) {
            Add-ServiceToReport -Service $dep -Indent ($Indent + 1)
        }
    }

    foreach ($service in $ServiceData) {
        Add-ServiceToReport -Service $service
    }

    if ($OutputFile) {
        $report | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "Dependency report exported to: $OutputFile" -ForegroundColor Green
    } else {
        $report | Write-Output
    }
}

# Main execution
$servicesToAnalyze = @()

if ($AllServices) {
    Write-Host "Analyzing all services..." -ForegroundColor Cyan
    $allServices = Get-WmiObject -Class Win32_Service | Select-Object -ExpandProperty Name
    $servicesToAnalyze = $allServices
} elseif ($ServiceNames) {
    $servicesToAnalyze = $ServiceNames
} else {
    Write-Error "Please specify -ServiceNames or use -AllServices"
    exit 1
}

Write-Host "Analyzing dependencies for $($servicesToAnalyze.Count) services..." -ForegroundColor Cyan

$analysisResults = @()
foreach ($serviceName in $servicesToAnalyze) {
    $result = Get-ServiceDependencies -ServiceName $serviceName
    $analysisResults += $result
}

if ($ShowGraph) {
    Write-Host ""
    Write-Host "=== DEPENDENCY GRAPH ===" -ForegroundColor Cyan
    Show-DependencyGraph -ServiceData $analysisResults
}

if ($OutputFile -or -not $ShowGraph) {
    Write-Host ""
    Write-Host "=== DEPENDENCY REPORT ===" -ForegroundColor Cyan
    Export-DependencyReport -ServiceData $analysisResults -OutputFile $OutputFile
}

Write-Host ""
Write-Host "Dependency analysis completed." -ForegroundColor Green