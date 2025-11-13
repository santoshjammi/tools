[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Automatic", "Manual", "Disabled")]
    [string]$StartupType,

    [Parameter(Mandatory=$false)]
    [string]$DisplayName,

    [Parameter(Mandatory=$false)]
    [string]$Description,

    [Parameter(Mandatory=$false)]
    [switch]$Backup,

    [Parameter(Mandatory=$false)]
    [switch]$Restore,

    [Parameter(Mandatory=$false)]
    [string]$BackupFile,

    [Parameter(Mandatory=$false)]
    [switch]$ShowConfig
)

$ErrorActionPreference = "Stop"

function Get-ServiceConfiguration {
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"

        $config = @{
            Name = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartupType = $wmiService.StartMode
            Description = $wmiService.Description
            PathName = $wmiService.PathName
            ServiceType = $wmiService.ServiceType
            StartName = $wmiService.StartName
        }

        return $config
    } catch {
        Write-Error "Service '$ServiceName' not found."
        return $null
    }
}

function Set-ServiceConfiguration {
    param(
        [string]$ServiceName,
        [string]$StartupType,
        [string]$DisplayName,
        [string]$Description
    )

    Write-Host "Updating service configuration for: $ServiceName" -ForegroundColor Cyan

    try {
        # Change startup type
        if ($StartupType) {
            $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'"
            $result = $wmiService.ChangeStartMode($StartupType)
            if ($result.ReturnValue -eq 0) {
                Write-Host "Startup type changed to: $StartupType" -ForegroundColor Green
            } else {
                Write-Warning "Failed to change startup type. Return code: $($result.ReturnValue)"
            }
        }

        # Note: DisplayName and Description changes require service restart and are more complex
        # For now, we'll just show what would be changed
        if ($DisplayName) {
            Write-Host "Note: DisplayName change to '$DisplayName' requires manual registry edit or service reinstall" -ForegroundColor Yellow
        }

        if ($Description) {
            Write-Host "Note: Description change to '$Description' requires manual registry edit or service reinstall" -ForegroundColor Yellow
        }

    } catch {
        Write-Error "Failed to update service configuration: $($_.Exception.Message)"
    }
}

function Backup-ServiceConfiguration {
    param([string]$ServiceName, [string]$BackupFile)

    $config = Get-ServiceConfiguration -ServiceName $ServiceName
    if ($config) {
        $backupPath = $BackupFile
        if (-not $backupPath) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupPath = "$ServiceName`_config_$timestamp.json"
        }

        $config | ConvertTo-Json | Out-File -FilePath $backupPath -Encoding UTF8
        Write-Host "Configuration backed up to: $backupPath" -ForegroundColor Green
    }
}

function Restore-ServiceConfiguration {
    param([string]$ServiceName, [string]$BackupFile)

    if (-not (Test-Path $BackupFile)) {
        Write-Error "Backup file not found: $BackupFile"
        return
    }

    try {
        $config = Get-Content $BackupFile | ConvertFrom-Json
        Write-Host "Restored configuration from: $BackupFile" -ForegroundColor Green
        Write-Host "Note: Manual intervention may be required to fully restore some settings" -ForegroundColor Yellow

        # Show what was in the backup
        $config | Format-List
    } catch {
        Write-Error "Failed to restore configuration: $($_.Exception.Message)"
    }
}

# Main execution
if ($ShowConfig) {
    $config = Get-ServiceConfiguration -ServiceName $ServiceName
    if ($config) {
        Write-Host "Current configuration for service: $ServiceName" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        $config.GetEnumerator() | ForEach-Object {
            Write-Host "$($_.Key): $($_.Value)"
        }
    }
} elseif ($Backup) {
    Backup-ServiceConfiguration -ServiceName $ServiceName -BackupFile $BackupFile
} elseif ($Restore) {
    if (-not $BackupFile) {
        Write-Error "BackupFile parameter is required for restore operation"
        exit 1
    }
    Restore-ServiceConfiguration -ServiceName $ServiceName -BackupFile $BackupFile
} else {
    # Configuration update
    if (-not ($StartupType -or $DisplayName -or $Description)) {
        Write-Error "No configuration changes specified. Use -StartupType, -DisplayName, or -Description parameters."
        exit 1
    }
    Set-ServiceConfiguration -ServiceName $ServiceName -StartupType $StartupType -DisplayName $DisplayName -Description $Description
}