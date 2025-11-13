# Service Management Scripts

This repository contains PowerShell and Bash scripts for starting and stopping Windows/Linux services in a specified order with timeout and polling functionality.

## Scripts Overview

### PowerShell Scripts (Windows)

- `Start-ServicesInOrder.ps1` - Starts services sequentially
- `Stop-ServicesInOrder.ps1` - Stops services sequentially

### Bash Scripts (Linux/Unix)

- `Start-ServicesInOrder.sh` - Starts services sequentially
- `Stop-ServicesInOrder.sh` - Stops services sequentially

## Features

- **Sequential Processing**: Services are processed in the order provided
- **Timeout Handling**: Configurable timeout with polling
- **Error Handling**: Script halts on any service failure
- **Status Monitoring**: Real-time status updates during operation
- **Cross-Platform**: Separate implementations for Windows (PowerShell) and Linux (Bash)

## Prerequisites

### PowerShell Scripts

- Windows operating system
- PowerShell 5.1 or later
- Administrative privileges (for service management)
- Services must exist on the system

### Bash Scripts

- Linux/Unix operating system
- `systemctl` (preferred) or `service` command available
- Appropriate permissions to manage services
- Services must be configured in systemd or init.d

## Usage

### PowerShell Scripts Usage

#### Starting Services

```powershell
# Basic usage
.\Start-ServicesInOrder.ps1 -ServiceNames "Service1", "Service2", "Service3"

# With custom timeout and check interval
.\Start-ServicesInOrder.ps1 -ServiceNames "Service1", "Service2" -CheckIntervalSeconds 5 -TotalTimeoutMinutes 10
```

#### Stopping Services

```powershell
# Basic usage
.\Stop-ServicesInOrder.ps1 -ServiceNames "Service1", "Service2", "Service3"

# With custom timeout and check interval
.\Stop-ServicesInOrder.ps1 -ServiceNames "Service1", "Service2" -CheckIntervalSeconds 5 -TotalTimeoutMinutes 10
```

### Bash Scripts Usage

#### Bash: Starting Services

```bash
# Basic usage
./Start-ServicesInOrder.sh service1 service2 service3

# With custom timeout and check interval
./Start-ServicesInOrder.sh -t 10 -i 5 service1 service2 service3
```

#### Stopping Services

```bash
# Basic usage
./Stop-ServicesInOrder.sh service1 service2 service3

# With custom timeout and check interval
./Stop-ServicesInOrder.sh -t 10 -i 5 service1 service2 service3
```

## Parameters

### PowerShell Parameters

- `ServiceNames` (mandatory): Array of service names to process
- `CheckIntervalSeconds` (optional): Polling interval in seconds (default: 10)
- `TotalTimeoutMinutes` (optional): Maximum wait time in minutes (default: 5)

### Bash Parameters

- `service_name` (positional, mandatory): One or more service names
- `-i check_interval_seconds`: Polling interval in seconds (default: 10)
- `-t total_timeout_minutes`: Maximum wait time in minutes (default: 5)

## Examples

### Example 1: Start Database and Web Services

```powershell
# PowerShell
.\Start-ServicesInOrder.ps1 -ServiceNames "MSSQLSERVER", "IISADMIN", "W3SVC"
```

```bash
# Bash
./Start-ServicesInOrder.sh mysql httpd nginx
```

### Example 2: Stop Services with Custom Timeout

```powershell
# PowerShell
.\Stop-ServicesInOrder.ps1 -ServiceNames "W3SVC", "IISADMIN", "MSSQLSERVER" -TotalTimeoutMinutes 15 -CheckIntervalSeconds 5
```

```bash
# Bash
./Stop-ServicesInOrder.sh -t 15 -i 5 nginx httpd mysql
```

## Behavior

### Starting Services

1. Checks if service exists
2. If already running, reports success
3. If not running, attempts to start the service
4. Polls service status until running or timeout
5. Reports success or failure with elapsed time

### Stopping Services

1. Checks if service exists
2. If already stopped, reports success
3. If running, attempts to stop the service
4. Polls service status until stopped or timeout
5. Reports success or failure with elapsed time

### Error Handling

- Script exits with code 1 if any service fails to start/stop within timeout
- Continues processing remaining services only if current service succeeds
- Provides detailed error messages for troubleshooting

## Notes

### PowerShell vs Bash Differences

- **Service Commands**: PowerShell uses `Get-Service`, `Start-Service`, `Stop-Service`; Bash uses `systemctl` or `service`
- **Status Values**: PowerShell checks 'Running'/'Stopped'; Bash checks 'active'/'inactive' patterns
- **Parameter Style**: PowerShell uses named parameters; Bash uses positional args with flags
- **Execution**: PowerShell scripts need execution policy consideration; Bash scripts need execute permissions

### Service Dependencies

- Scripts process services in the order provided
- Consider service dependencies when ordering (e.g., start dependencies first, stop dependents first)
- No automatic dependency resolution - order must be managed manually

### Timeout Considerations

- Default 5-minute timeout may need adjustment for slow-starting services
- Check interval of 10 seconds balances responsiveness with system load
- Adjust based on your system's performance and service startup times

### Permissions

- Windows: Run as Administrator or with service control permissions
- Linux: Run with sudo or appropriate service management permissions
- Ensure the executing user has rights to query and control the specified services

## Troubleshooting

### Common Issues

1. **Service not found**: Verify service name spelling and existence
2. **Permission denied**: Run with elevated privileges
3. **Timeout exceeded**: Increase timeout or check service health
4. **Service fails to start/stop**: Check service dependencies and system logs

### Logging

- Scripts provide real-time console output
- Check system event logs (Windows Event Viewer/Linux journalctl) for additional service errors
- Use script output for debugging timeout or status issues

## Contributing

When modifying these scripts:

- Maintain consistent parameter naming and behavior
- Update both PowerShell and Bash versions for feature parity
- Test on target platforms before committing
- Update this README for any new features or parameters
