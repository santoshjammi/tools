#!/bin/bash

# Bash script to restart services in order with timeout and polling

set -e  # Exit on any error

# Default values
CHECK_INTERVAL_SECONDS=10
TOTAL_TIMEOUT_MINUTES=5
FORCE=false

# Function to display usage
usage() {
    echo "Usage: $0 [-i check_interval_seconds] [-t total_timeout_minutes] [-f] service_name [service_name ...]"
    echo "  -i: Check interval in seconds (default: $CHECK_INTERVAL_SECONDS)"
    echo "  -t: Total timeout in minutes (default: $TOTAL_TIMEOUT_MINUTES)"
    echo "  -f: Force restart even if service is not running"
    exit 1
}

# Parse command line options
while getopts "i:t:f" opt; do
    case $opt in
        i) CHECK_INTERVAL_SECONDS="$OPTARG" ;;
        t) TOTAL_TIMEOUT_MINUTES="$OPTARG" ;;
        f) FORCE=true ;;
        *) usage ;;
    esac
done

shift $((OPTIND-1))

# Check if at least one service name is provided
if [ $# -eq 0 ]; then
    usage
fi

SERVICE_NAMES=("$@")
TOTAL_TIMEOUT_SECONDS=$((TOTAL_TIMEOUT_MINUTES * 60))

# Function to restart service with timeout
restart_service_with_timeout() {
    local service_name="$1"

    echo "--- Restarting service: $service_name ---"

    # Check if systemctl is available, otherwise use service command
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_CMD="systemctl"
        STATUS_CMD="systemctl is-active"
        STOP_CMD="systemctl stop"
        START_CMD="systemctl start"
        RESTART_CMD="systemctl restart"
    else
        SERVICE_CMD="service"
        STATUS_CMD="service status"
        STOP_CMD="service stop"
        START_CMD="service start"
        RESTART_CMD="service restart"
    fi

    # 1. Check initial status
    if ! $STATUS_CMD "$service_name" >/dev/null 2>&1; then
        echo "ERROR: Service '$service_name' not found or not manageable. Exiting."
        return 1
    fi

    local initial_status
    if ! initial_status=$($STATUS_CMD "$service_name" 2>/dev/null); then
        initial_status="unknown"
    fi

    echo "Initial status: $initial_status"

    # 2. Stop the service if it's running or force is specified
    if echo "$initial_status" | grep -q "active\|running" || [ "$FORCE" = true ]; then
        echo "Stopping service..."

        if ! $STOP_CMD "$service_name"; then
            echo "ERROR: Failed to stop service '$service_name'."
            return 1
        fi

        # Give a small initial grace period after the stop command
        sleep 2

        # Wait for service to stop
        local stop_start_time=$(date +%s)
        while [ $(($(date +%s) - stop_start_time)) -lt $TOTAL_TIMEOUT_SECONDS ]; do
            local current_status
            if ! current_status=$($STATUS_CMD "$service_name" 2>/dev/null); then
                current_status="unknown"
            fi

            local elapsed_seconds=$(($(date +%s) - stop_start_time))
            local elapsed_minutes=$((elapsed_seconds / 60))
            local elapsed_secs_remainder=$((elapsed_seconds % 60))

            if echo "$current_status" | grep -q "inactive\|dead\|stopped"; then
                echo "Service stopped successfully."
                break
            fi

            echo "Waiting for stop... Status: $current_status (Elapsed: ${elapsed_minutes}m ${elapsed_secs_remainder}s)"
            sleep $CHECK_INTERVAL_SECONDS
        done

        if ! echo "$($STATUS_CMD "$service_name" 2>/dev/null)" | grep -q "inactive\|dead\|stopped"; then
            echo "FAILURE: Service '$service_name' failed to stop within timeout."
            return 1
        fi
    else
        echo "Service was not running, skipping stop phase."
    fi

    # 3. Start the service
    echo "Starting service..."

    if ! $START_CMD "$service_name"; then
        echo "ERROR: Failed to start service '$service_name'."
        return 1
    fi

    # Give a small initial grace period after the start command
    sleep 2

    # 4. Wait for service to start
    local start_time=$(date +%s)
    while [ $(($(date +%s) - start_time)) -lt $TOTAL_TIMEOUT_SECONDS ]; do
        local current_status
        if ! current_status=$($STATUS_CMD "$service_name" 2>/dev/null); then
            current_status="unknown"
        fi

        local elapsed_seconds=$(($(date +%s) - start_time))
        local elapsed_minutes=$((elapsed_seconds / 60))
        local elapsed_secs_remainder=$((elapsed_seconds % 60))

        echo "Waiting for start... Status: $current_status (Elapsed: ${elapsed_minutes}m ${elapsed_secs_remainder}s)"

        if echo "$current_status" | grep -q "active\|running"; then
            echo "SUCCESS: Service '$service_name' restarted successfully."
            return 0
        fi

        sleep $CHECK_INTERVAL_SECONDS
    done

    # 5. Timeout failure
    echo "FAILURE: Service '$service_name' failed to start after restart within $TOTAL_TIMEOUT_MINUTES minutes."
    return 1
}

# Main execution block
# Process services in the provided order
for service_name in "${SERVICE_NAMES[@]}"; do
    if ! restart_service_with_timeout "$service_name"; then
        echo "Script halting due to failure to restart service '$service_name'."
        exit 1
    fi
    echo ""
done

echo "All specified services restarted successfully."
exit 0