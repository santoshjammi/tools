#!/bin/bash

# Bash script for monitoring service health with optional auto-restart

set -e  # Exit on any error

# Default values
CHECK_INTERVAL_SECONDS=60
MAX_RETRIES=3
AUTO_RESTART=false
LOG_FILE=""
QUIET=false

# Function to display usage
usage() {
    echo "Usage: $0 [-i check_interval] [-r max_retries] [-a] [-l log_file] [-q] service_name [service_name ...]"
    echo "  -i: Check interval in seconds (default: $CHECK_INTERVAL_SECONDS)"
    echo "  -r: Maximum retries before auto-restart (default: $MAX_RETRIES)"
    echo "  -a: Enable auto-restart on failures"
    echo "  -l: Log file path (default: stdout only)"
    echo "  -q: Quiet mode (no console output)"
    exit 1
}

# Parse command line options
while getopts "i:r:al:qh" opt; do
    case $opt in
        i) CHECK_INTERVAL_SECONDS="$OPTARG" ;;
        r) MAX_RETRIES="$OPTARG" ;;
        a) AUTO_RESTART=true ;;
        l) LOG_FILE="$OPTARG" ;;
        q) QUIET=true ;;
        *) usage ;;
    esac
done

shift $((OPTIND-1))

# Check if at least one service name is provided
if [ $# -eq 0 ]; then
    usage
fi

SERVICE_NAMES=("$@")

# Function to write log messages
write_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_message="[$timestamp] [$level] $message"

    # Console output unless quiet
    if [ "$QUIET" = false ]; then
        case $level in
            ERROR) echo -e "\033[31m$log_message\033[0m" ;;  # Red
            WARN) echo -e "\033[33m$log_message\033[0m" ;;   # Yellow
            SUCCESS) echo -e "\033[32m$log_message\033[0m" ;; # Green
            *) echo "$log_message" ;;
        esac
    fi

    # File output if log file specified
    if [ -n "$LOG_FILE" ]; then
        echo "$log_message" >> "$LOG_FILE"
    fi
}

# Function to test service health
test_service_health() {
    local service_name="$1"

    # Check if systemctl is available, otherwise use service command
    if command -v systemctl >/dev/null 2>&1; then
        STATUS_CMD="systemctl is-active"
    else
        STATUS_CMD="service status"
    fi

    if $STATUS_CMD "$service_name" >/dev/null 2>&1; then
        local status
        status=$($STATUS_CMD "$service_name" 2>/dev/null)
        if echo "$status" | grep -q "active\|running"; then
            return 0  # Healthy
        fi
    fi

    return 1  # Unhealthy
}

# Function to restart service
restart_service() {
    local service_name="$1"

    write_log "Attempting to restart service: $service_name" "WARN"

    # Check if systemctl is available, otherwise use service command
    if command -v systemctl >/dev/null 2>&1; then
        RESTART_CMD="systemctl restart"
        STATUS_CMD="systemctl is-active"
    else
        RESTART_CMD="service restart"
        STATUS_CMD="service status"
    fi

    if $RESTART_CMD "$service_name"; then
        sleep 5

        # Verify restart
        if $STATUS_CMD "$service_name" >/dev/null 2>&1; then
            local status
            status=$($STATUS_CMD "$service_name" 2>/dev/null)
            if echo "$status" | grep -q "active\|running"; then
                write_log "Service $service_name restarted successfully" "SUCCESS"
                return 0
            fi
        fi
    fi

    write_log "Service $service_name failed to restart properly" "ERROR"
    return 1
}

# Initialize service states
declare -A service_states
for service in "${SERVICE_NAMES[@]}"; do
    service_states["$service,last_status"]="unknown"
    service_states["$service,failure_count"]=0
    service_states["$service,last_check"]="never"
done

# Main monitoring loop
write_log "Starting service health monitoring for: ${SERVICE_NAMES[*]}"
write_log "Check interval: $CHECK_INTERVAL_SECONDS seconds"
write_log "Auto-restart: $AUTO_RESTART"
write_log "Max retries: $MAX_RETRIES"
if [ -n "$LOG_FILE" ]; then
    write_log "Logging to: $LOG_FILE"
fi

while true; do
    current_time=$(date)

    for service in "${SERVICE_NAMES[@]}"; do
        if test_service_health "$service"; then
            # Service is healthy
            if [ "${service_states["$service,last_status"]}" = "false" ]; then
                write_log "Service $service is now healthy" "SUCCESS"
            fi
            service_states["$service,failure_count"]=0
            service_states["$service,last_status"]="true"
        else
            # Service is unhealthy
            failure_count=$((service_states["$service,failure_count"] + 1))
            service_states["$service,failure_count"]=$failure_count
            write_log "Service $service is unhealthy (failure count: $failure_count)" "WARN"

            if [ "$AUTO_RESTART" = true ] && [ $failure_count -ge $MAX_RETRIES ]; then
                if restart_service "$service"; then
                    service_states["$service,failure_count"]=0
                fi
            fi

            service_states["$service,last_status"]="false"
        fi

        service_states["$service,last_check"]="$current_time"
    done

    sleep $CHECK_INTERVAL_SECONDS
done