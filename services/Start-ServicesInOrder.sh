#!/bin/bash

# Bash alternative to Start-ServicesInOrder.ps1
# Starts services in order with timeout and polling

set -e  # Exit on any error

# Default values
CHECK_INTERVAL_SECONDS=10
TOTAL_TIMEOUT_MINUTES=5

# Function to display usage
usage() {
    echo "Usage: $0 [-i check_interval_seconds] [-t total_timeout_minutes] service_name [service_name ...]"
    echo "  -i: Check interval in seconds (default: $CHECK_INTERVAL_SECONDS)"
    echo "  -t: Total timeout in minutes (default: $TOTAL_TIMEOUT_MINUTES)"
    exit 1
}

# Parse command line options
while getopts "i:t:" opt; do
    case $opt in
        i) CHECK_INTERVAL_SECONDS="$OPTARG" ;;
        t) TOTAL_TIMEOUT_MINUTES="$OPTARG" ;;
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

# Function to start service with timeout
start_service_with_timeout() {
    local service_name="$1"
    
    echo "--- Checking service: $service_name ---"
    
    # Check if systemctl is available, otherwise use service command
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_CMD="systemctl"
        STATUS_CMD="systemctl is-active"
        START_CMD="systemctl start"
    else
        SERVICE_CMD="service"
        STATUS_CMD="service status"
        START_CMD="service start"
    fi
    
    # 1. Check initial status
    if ! $STATUS_CMD "$service_name" >/dev/null 2>&1; then
        echo "ERROR: Service '$service_name' not found or not manageable. Exiting."
        return 1
    fi
    
    if $STATUS_CMD "$service_name" | grep -q "active\|running"; then
        echo "SUCCESS: Service '$service_name' is already running."
        return 0
    fi
    
    # 2. Attempt to start
    echo "Status is not running. Attempting to start service..."
    if ! $START_CMD "$service_name"; then
        echo "ERROR: Failed to start service '$service_name'."
        return 1
    fi
    
    # Give a small initial grace period after the start command
    sleep 2
    
    # 3. Polling loop with timeout
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $TOTAL_TIMEOUT_SECONDS ]; do
        local current_status
        if ! current_status=$($STATUS_CMD "$service_name" 2>/dev/null); then
            current_status="unknown"
        fi
        
        local elapsed_seconds=$(($(date +%s) - start_time))
        local elapsed_minutes=$((elapsed_seconds / 60))
        local elapsed_secs_remainder=$((elapsed_seconds % 60))
        
        echo "Service status: $current_status (Elapsed: ${elapsed_minutes}m ${elapsed_secs_remainder}s)"
        
        if echo "$current_status" | grep -q "active\|running"; then
            echo "SUCCESS: Service '$service_name' started and is running."
            return 0
        fi
        
        # Wait and recheck
        sleep $CHECK_INTERVAL_SECONDS
    done
    
    # 4. Timeout failure
    echo "FAILURE: Service '$service_name' failed to start after $TOTAL_TIMEOUT_MINUTES minutes."
    return 1
}

# Main execution block
# Process services in the provided order
for service_name in "${SERVICE_NAMES[@]}"; do
    if ! start_service_with_timeout "$service_name"; then
        echo "Script halting due to failure of service '$service_name'."
        exit 1
    fi
done

echo ""
echo "All specified services started successfully."
exit 0
