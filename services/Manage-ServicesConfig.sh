#!/bin/bash

# Bash script for managing service configurations
# Note: Limited functionality compared to Windows version due to systemd/service limitations

set -e  # Exit on any error

# Function to display usage
usage() {
    echo "Usage: $0 -s service_name [options]"
    echo "Options:"
    echo "  -s service_name    : Service name (required)"
    echo "  -t startup_type    : Set startup type (enabled/disabled) - systemd only"
    echo "  -b [backup_file]   : Backup service configuration"
    echo "  -r backup_file     : Restore service configuration"
    echo "  -w                 : Show current configuration"
    echo "  -m                 : Show service unit file (systemd only)"
    exit 1
}

# Default values
SERVICE_NAME=""
STARTUP_TYPE=""
BACKUP_FILE=""
RESTORE_FILE=""
SHOW_CONFIG=false
SHOW_UNIT=false

# Parse command line options
while getopts "s:t:b:r:wmh" opt; do
    case $opt in
        s) SERVICE_NAME="$OPTARG" ;;
        t) STARTUP_TYPE="$OPTARG" ;;
        b) BACKUP_FILE="$OPTARG" ;;
        r) RESTORE_FILE="$OPTARG" ;;
        w) SHOW_CONFIG=true ;;
        m) SHOW_UNIT=true ;;
        *) usage ;;
    esac
done

# Check if service name is provided
if [ -z "$SERVICE_NAME" ]; then
    usage
fi

# Function to show service configuration
show_service_config() {
    local service_name="$1"

    echo "Current configuration for service: $service_name"
    echo "----------------------------------------"

    if command -v systemctl >/dev/null 2>&1; then
        echo "System: systemd"

        # Get various systemctl properties
        properties=("Description" "LoadState" "ActiveState" "SubState" "UnitFileState" "Type" "Restart")
        for prop in "${properties[@]}"; do
            value=$(systemctl show "$service_name" -p "$prop" --value 2>/dev/null || echo "N/A")
            echo "$prop: $value"
        done
    else
        echo "System: init.d/service"
        echo "Note: Limited configuration info available"

        # Try to get basic info
        if command -v service >/dev/null 2>&1; then
            echo "Service command available: Yes"
        else
            echo "Service command available: No"
        fi
    fi
}

# Function to set startup type (systemd only)
set_startup_type() {
    local service_name="$1"
    local startup_type="$2"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: Startup type management requires systemd"
        return 1
    fi

    case $startup_type in
        enabled|enable)
            echo "Enabling service: $service_name"
            systemctl enable "$service_name"
            ;;
        disabled|disable)
            echo "Disabling service: $service_name"
            systemctl disable "$service_name"
            ;;
        *)
            echo "ERROR: Invalid startup type. Use 'enabled' or 'disabled'"
            return 1
            ;;
    esac
}

# Function to backup service configuration
backup_service_config() {
    local service_name="$1"
    local backup_file="$2"

    if [ -z "$backup_file" ]; then
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="${service_name}_config_${timestamp}.txt"
    fi

    echo "Backing up configuration for service: $service_name"

    {
        echo "# Service Configuration Backup"
        echo "# Service: $service_name"
        echo "# Date: $(date)"
        echo "# System: $(uname -a)"
        echo ""

        if command -v systemctl >/dev/null 2>&1; then
            echo "### systemctl show output ###"
            systemctl show "$service_name" 2>/dev/null || echo "Failed to get systemctl info"
            echo ""

            echo "### systemctl status output ###"
            systemctl status "$service_name" 2>/dev/null || echo "Failed to get status"
            echo ""

            echo "### Unit file location ###"
            unit_file=$(systemctl show "$service_name" -p FragmentPath --value 2>/dev/null)
            if [ -n "$unit_file" ] && [ -f "$unit_file" ]; then
                echo "Unit file: $unit_file"
                echo ""
                echo "### Unit file contents ###"
                cat "$unit_file" 2>/dev/null || echo "Failed to read unit file"
            fi
        else
            echo "Non-systemd system - limited backup capability"
            echo "Service exists: $(service "$service_name" status >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
        fi
    } > "$backup_file"

    echo "Configuration backed up to: $backup_file"
}

# Function to show unit file (systemd only)
show_unit_file() {
    local service_name="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: Unit file viewing requires systemd"
        return 1
    fi

    unit_file=$(systemctl show "$service_name" -p FragmentPath --value 2>/dev/null)
    if [ -n "$unit_file" ] && [ -f "$unit_file" ]; then
        echo "Unit file: $unit_file"
        echo "----------------------------------------"
        cat "$unit_file"
    else
        echo "Unit file not found for service: $service_name"
    fi
}

# Main execution
if [ "$SHOW_CONFIG" = true ]; then
    show_service_config "$SERVICE_NAME"
elif [ "$SHOW_UNIT" = true ]; then
    show_unit_file "$SERVICE_NAME"
elif [ -n "$BACKUP_FILE" ] || [ "$#" -eq 2 ] && [ "$1" = "-b" ]; then
    # Handle backup (with or without filename)
    backup_service_config "$SERVICE_NAME" "$BACKUP_FILE"
elif [ -n "$RESTORE_FILE" ]; then
    echo "Restore functionality not implemented yet"
    echo "Manual restoration required from backup file: $RESTORE_FILE"
elif [ -n "$STARTUP_TYPE" ]; then
    set_startup_type "$SERVICE_NAME" "$STARTUP_TYPE"
else
    echo "No action specified. Use -w to show config, -b to backup, -t to set startup type, etc."
    usage
fi