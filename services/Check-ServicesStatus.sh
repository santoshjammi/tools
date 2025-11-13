#!/bin/bash

# Bash script to check status of multiple services
# Provides summary and optional detailed information

set -e  # Exit on any error

# Default values
DETAILED=false
ALERT_ONLY=false

# Function to display usage
usage() {
    echo "Usage: $0 [-d] [-a] service_name [service_name ...]"
    echo "  -d: Show detailed information (display name, description, etc.)"
    echo "  -a: Alert only mode - exit with error if any service is not running"
    exit 1
}

# Parse command line options
while getopts "da" opt; do
    case $opt in
        d) DETAILED=true ;;
        a) ALERT_ONLY=true ;;
        *) usage ;;
    esac
done

shift $((OPTIND-1))

# Check if at least one service name is provided
if [ $# -eq 0 ]; then
    usage
fi

SERVICE_NAMES=("$@")

# Function to get service status
get_service_status() {
    local service_name="$1"

    echo "--- Service: $service_name ---"

    # Check if systemctl is available, otherwise use service command
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_CMD="systemctl"
        STATUS_CMD="systemctl show"
        IS_ACTIVE_CMD="systemctl is-active"
    else
        SERVICE_CMD="service"
        STATUS_CMD="service status"
        IS_ACTIVE_CMD="service status"
    fi

    # Get basic status
    if $IS_ACTIVE_CMD "$service_name" >/dev/null 2>&1; then
        status="active"
    else
        status="inactive"
    fi

    if [ "$DETAILED" = true ]; then
        # Try to get more details
        if command -v systemctl >/dev/null 2>&1; then
            # Get detailed info from systemctl
            unit_file=$(systemctl show "$service_name" -p UnitFileState --value 2>/dev/null || echo "unknown")
            description=$(systemctl show "$service_name" -p Description --value 2>/dev/null || echo "No description")
            load_state=$(systemctl show "$service_name" -p LoadState --value 2>/dev/null || echo "unknown")

            echo "Description: $description"
            echo "Load State: $load_state"
            echo "Unit File State: $unit_file"
        else
            # For older systems, just show basic status
            echo "Status: $status"
        fi
    fi

    # Color coding for status
    case $status in
        active|running)
            echo -e "\033[32mStatus: $status\033[0m"  # Green
            ;;
        inactive|stopped|dead)
            echo -e "\033[31mStatus: $status\033[0m"  # Red
            ;;
        *)
            echo -e "\033[33mStatus: $status\033[0m"  # Yellow
            ;;
    esac

    # Return status for summary
    echo "$status"
}

# Main execution
echo "Checking status of $# services..."
echo ""

results=()
running_count=0
stopped_count=0
unknown_count=0

for service_name in "${SERVICE_NAMES[@]}"; do
    status=$(get_service_status "$service_name")
    results+=("$service_name:$status")

    case $status in
        active|running)
            ((running_count++))
            ;;
        inactive|stopped|dead)
            ((stopped_count++))
            ;;
        *)
            ((unknown_count++))
            ;;
    esac

    echo ""
done

# Summary
echo "=== STATUS SUMMARY ==="
echo "Total Services: $#"
echo -e "\033[32mRunning/Active: $running_count\033[0m"
echo -e "\033[31mStopped/Inactive: $stopped_count\033[0m"
echo -e "\033[33mUnknown: $unknown_count\033[0m"

# Alert only mode
if [ "$ALERT_ONLY" = true ]; then
    issues_found=false

    for result in "${results[@]}"; do
        IFS=':' read -r name status <<< "$result"
        case $status in
            inactive|stopped|dead|unknown)
                if [ "$issues_found" = false ]; then
                    echo ""
                    echo "=== ALERTS ==="
                    issues_found=true
                fi
                echo -e "\033[31mService '$name' is $status!\033[0m"
                ;;
        esac
    done

    if [ "$issues_found" = true ]; then
        exit 1
    fi
fi

echo ""
echo "Status check completed."
exit 0