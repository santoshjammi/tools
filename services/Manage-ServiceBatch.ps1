[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GroupName,

    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "service-groups.json",

    [Parameter(Mandatory=$false)]
    [ValidateSet("start", "stop", "restart", "status", "enable", "disable")]
    [string]$Operation,

    [Parameter(Mandatory=$false)]
    [switch]$ListGroups,

    [Parameter(Mandatory=$false)]
    [switch]$CreateGroup,

    [Parameter(Mandatory=$false)]
    [string[]]$Services,

    [Parameter(Mandatory=$false)]
    [string]$Description,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Get-ServiceGroups {
    param([string]$ConfigFile)

    if (Test-Path $ConfigFile) {
        try {
            $groups = Get-Content $ConfigFile | ConvertFrom-Json
            return $groups
        } catch {
            Write-Warning "Failed to load config file: $($_.Exception.Message)"
            return @{}
        }
    } else {
        Write-Warning "Config file not found: $ConfigFile"
        return @{}
    }
}

function Save-ServiceGroups {
    param([string]$ConfigFile, [object]$Groups)

    try {
        $Groups | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding UTF8
        Write-Host "Service groups saved to: $ConfigFile" -ForegroundColor Green
    } catch {
        Write-Error "Failed to save config file: $($_.Exception.Message)"
    }
}

function New-ServiceGroup {
    param([string]$Name, [string[]]$Services, [string]$Description)

    $group = @{
        Name = $Name
        Description = $Description
        Services = $Services
        Created = Get-Date
        Modified = Get-Date
    }

    return $group
}

function Invoke-ServiceBatchOperation {
    param(
        [object]$Group,
        [string]$Operation,
        [int]$TimeoutSeconds,
        [switch]$Force
    )

    Write-Host "Executing '$Operation' on service group: $($Group.Name)" -ForegroundColor Cyan
    if ($Group.Description) {
        Write-Host "Description: $($Group.Description)" -ForegroundColor Gray
    }
    Write-Host "Services: $($Group.Services -join ', ')" -ForegroundColor White
    Write-Host ""

    $successCount = 0
    $failureCount = 0

    foreach ($serviceName in $Group.Services) {
        Write-Host "Processing service: $serviceName" -ForegroundColor Yellow

        try {
            switch ($Operation) {
                "start" {
                    if ((Get-Service $serviceName).Status -ne 'Running' -or $Force) {
                        Start-Service $serviceName
                        Write-Host "  ✓ Started successfully" -ForegroundColor Green
                        $successCount++
                    } else {
                        Write-Host "  - Already running" -ForegroundColor Gray
                        $successCount++
                    }
                }
                "stop" {
                    if ((Get-Service $serviceName).Status -eq 'Running' -or $Force) {
                        Stop-Service $serviceName
                        Write-Host "  ✓ Stopped successfully" -ForegroundColor Green
                        $successCount++
                    } else {
                        Write-Host "  - Already stopped" -ForegroundColor Gray
                        $successCount++
                    }
                }
                "restart" {
                    Restart-Service $serviceName
                    Write-Host "  ✓ Restarted successfully" -ForegroundColor Green
                    $successCount++
                }
                "status" {
                    $status = (Get-Service $serviceName).Status
                    $statusColor = switch ($status) {
                        'Running' { 'Green' }
                        'Stopped' { 'Red' }
                        default { 'Yellow' }
                    }
                    Write-Host "  Status: $status" -ForegroundColor $statusColor
                    $successCount++
                }
                "enable" {
                    $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                    $result = $wmiService.ChangeStartMode('Automatic')
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "  ✓ Enabled successfully" -ForegroundColor Green
                        $successCount++
                    } else {
                        throw "Failed to enable service (code: $($result.ReturnValue))"
                    }
                }
                "disable" {
                    $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                    $result = $wmiService.ChangeStartMode('Disabled')
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "  ✓ Disabled successfully" -ForegroundColor Green
                        $successCount++
                    } else {
                        throw "Failed to disable service (code: $($result.ReturnValue))"
                    }
                }
            }

        } catch {
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            $failureCount++
        }

        Write-Host ""
    }

    # Summary
    Write-Host "=== OPERATION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Group: $($Group.Name)" -ForegroundColor White
    Write-Host "Operation: $Operation" -ForegroundColor White
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failureCount" -ForegroundColor Red
    Write-Host "Total: $($Group.Services.Count)" -ForegroundColor White

    return @{
        SuccessCount = $successCount
        FailureCount = $failureCount
        TotalCount = $Group.Services.Count
    }
}

# Main execution
if ($ListGroups) {
    Write-Host "Available Service Groups:" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan

    $groups = Get-ServiceGroups -ConfigFile $ConfigFile

    if ($groups.PSObject.Properties.Count -eq 0) {
        Write-Host "No service groups found in: $ConfigFile" -ForegroundColor Yellow
        Write-Host "Use -CreateGroup to create your first group." -ForegroundColor Gray
    } else {
        foreach ($groupName in $groups.PSObject.Properties.Name) {
            $group = $groups.$groupName
            Write-Host "$groupName" -ForegroundColor White -NoNewline
            Write-Host " ($($group.Services.Count) services)" -ForegroundColor Gray
            if ($group.Description) {
                Write-Host "  $($group.Description)" -ForegroundColor Gray
            }
        }
    }
    exit 0
}

if ($CreateGroup) {
    if (-not $GroupName -or -not $Services) {
        Write-Error "GroupName and Services parameters are required when using -CreateGroup"
        exit 1
    }

    $groups = Get-ServiceGroups -ConfigFile $ConfigFile

    if ($groups.PSObject.Properties.Name -contains $GroupName) {
        if (-not $Force) {
            Write-Error "Group '$GroupName' already exists. Use -Force to overwrite."
            exit 1
        }
    }

    $newGroup = New-ServiceGroup -Name $GroupName -Services $Services -Description $Description
    $groups.$GroupName = $newGroup

    Save-ServiceGroups -ConfigFile $ConfigFile -Groups $groups
    Write-Host "Service group '$GroupName' created successfully." -ForegroundColor Green
    exit 0
}

if ($Operation -and $GroupName) {
    $groups = Get-ServiceGroups -ConfigFile $ConfigFile

    if (-not $groups.PSObject.Properties.Name -contains $GroupName) {
        Write-Error "Service group '$GroupName' not found. Use -ListGroups to see available groups."
        exit 1
    }

    $group = $groups.$GroupName
    $result = Invoke-ServiceBatchOperation -Group $group -Operation $Operation -TimeoutSeconds $TimeoutSeconds -Force:$Force

    if ($result.FailureCount -gt 0) {
        Write-Warning "Some operations failed. Check the output above for details."
        exit 1
    } else {
        Write-Host "All operations completed successfully." -ForegroundColor Green
        exit 0
    }
}

# If no specific action was requested, show usage
Write-Host "Service Batch Operations Tool" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Available operations:" -ForegroundColor White
Write-Host "  -ListGroups           : List all service groups"
Write-Host "  -CreateGroup          : Create a new service group"
Write-Host "  -Operation <op>       : Execute operation on a group"
Write-Host ""
Write-Host "Operations: start, stop, restart, status, enable, disable" -ForegroundColor Gray
Write-Host ""
Write-Host "Examples:" -ForegroundColor Yellow
Write-Host "  .\Manage-ServiceBatch.ps1 -ListGroups"
Write-Host "  .\Manage-ServiceBatch.ps1 -CreateGroup -GroupName 'WebServices' -Services 'IISADMIN','W3SVC' -Description 'Web server services'"
Write-Host "  .\Manage-ServiceBatch.ps1 -GroupName 'WebServices' -Operation start"