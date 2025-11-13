#!/bin/bash

# Bash script for collecting service logs from Linux systems
# Supports systemd journald and traditional syslog

set -e  # Exit on any error

# Default values
HOURS_BACK=24
OUTPUT_FILE=""
INCLUDE_SYSTEM_LOGS=false
LOG_LEVEL="all"
COMPRESS_OUTPUT=false

# Function to display usage
usage() {
    echo "Usage: $0 [-s service_names] [options]"
    echo "  -s service_names    : Comma-separated list of service names (required)"
    echo "  -t hours            : Hours back to collect logs (default: $HOURS_BACK)"
    echo "  -o output_file      : Output file path (default: auto-generated)"
    echo "  -l log_level        : Log level filter (emerg,alert,crit,err,warn,notice,info,debug,all) (default: $LOG_LEVEL)"
    echo "  -y                  : Include system-wide service logs"
    echo "  -z                  : Compress output file"
    exit 1
}

# Parse command line options
while getopts "s:t:o:l:yzh" opt; do
    case $opt in
        s) SERVICE_NAMES="$OPTARG" ;;
        t) HOURS_BACK="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        l) LOG_LEVEL="$OPTARG" ;;
        y) INCLUDE_SYSTEM_LOGS=true ;;
        z) COMPRESS_OUTPUT=true ;;
        *) usage ;;
    esac
done

# Check if service names are provided
if [ -z "$SERVICE_NAMES" ]; then
    usage
fi

# Convert comma-separated to array
IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICE_NAMES"

# Generate output filename if not provided
if [ -z "$OUTPUT_FILE" ]; then
    timestamp=$(date +%Y%m%d_%H%M%S)
    OUTPUT_FILE="service_logs_${timestamp}.log"
fi

# Function to collect systemd journal logs
collect_systemd_logs() {
    local service_name="$1"
    local hours_back="$2"
    local log_level="$3"

    echo "Collecting systemd journal logs for: $service_name"

    # Build journalctl command
    local cmd="journalctl -u \"$service_name\" --since \"${hours_back} hours ago\""

    # Add log level filter if specified
    case $log_level in
        emerg) cmd="$cmd -p 0" ;;
        alert) cmd="$cmd -p 1" ;;
        crit) cmd="$cmd -p 2" ;;
        err) cmd="$cmd -p 3" ;;
        warn) cmd="$cmd -p 4" ;;
        notice) cmd="$cmd -p 5" ;;
        info) cmd="$cmd -p 6" ;;
        debug) cmd="$cmd -p 7" ;;
        all) ;; # No filter
        *) echo "Warning: Unknown log level '$log_level', using 'all'" ;;
    esac

    cmd="$cmd --no-pager"

    echo "Executing: $cmd"

    # Execute and capture output
    if eval "$cmd" 2>/dev/null; then
        return 0
    else
        echo "Failed to collect systemd logs for $service_name"
        return 1
    fi
}

# Function to collect syslog logs (fallback for non-systemd)
collect_syslog_logs() {
    local service_name="$1"
    local hours_back="$2"

    echo "Collecting syslog logs for: $service_name"

    # Calculate timestamp for filtering
    local since_time=$(date -d "${hours_back} hours ago" +%Y%m%d%H%M%S 2>/dev/null || date -v-${hours_back}H +%Y%m%d%H%M%S 2>/dev/null)

    # Common log files to check
    local log_files=("/var/log/syslog" "/var/log/messages" "/var/log/daemon.log")

    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ] && [ -r "$log_file" ]; then
            echo "Checking $log_file for $service_name entries..."

            # Use grep to find relevant entries (basic filtering)
            grep -i "$service_name" "$log_file" 2>/dev/null || true
        fi
    done
}

# Function to collect system-wide service logs
collect_system_service_logs() {
    local hours_back="$2"

    echo "Collecting system-wide service logs..."

    if command -v journalctl >/dev/null 2>&1; then
        journalctl --since "${hours_back} hours ago" -u "*.service" --no-pager 2>/dev/null || true
    else
        # Fallback to syslog for system service events
        echo "Systemd not available, checking syslog for service events..."
        collect_syslog_logs "service\|systemd" "$hours_back"
    fi
}

# Main execution
echo "Starting log collection..."
echo "Services: ${SERVICE_NAMES}"
echo "Hours back: $HOURS_BACK"
echo "Log level: $LOG_LEVEL"
echo "Include system logs: $INCLUDE_SYSTEM_LOGS"
echo "Output file: $OUTPUT_FILE"
echo ""

# Create output file with header
{
    echo "# Service Log Collection Report"
    echo "# Generated: $(date)"
    echo "# System: $(uname -a)"
    echo "# Services: $SERVICE_NAMES"
    echo "# Hours back: $HOURS_BACK"
    echo "# Log level: $LOG_LEVEL"
    echo "# Include system logs: $INCLUDE_SYSTEM_LOGS"
    echo ""
} > "$OUTPUT_FILE"

total_entries=0

# Collect logs for each service
for service in "${SERVICE_ARRAY[@]}"; do
    service=$(echo "$service" | xargs)  # Trim whitespace

    {
        echo ""
        echo "=== Logs for service: $service ==="
        echo "Timestamp: $(date)"
        echo ""

        entries_before=$(wc -l < "$OUTPUT_FILE")

        if command -v journalctl >/dev/null 2>&1; then
            collect_systemd_logs "$service" "$HOURS_BACK" "$LOG_LEVEL" >> "$OUTPUT_FILE" 2>&1 || true
        else
            collect_syslog_logs "$service" "$HOURS_BACK" >> "$OUTPUT_FILE" 2>&1 || true
        fi

        entries_after=$(wc -l < "$OUTPUT_FILE")
        service_entries=$((entries_after - entries_before))
        total_entries=$((total_entries + service_entries))

        echo ""
        echo "Entries collected for $service: $service_entries"
    } >> "$OUTPUT_FILE"
done

# Collect system-wide logs if requested
if [ "$INCLUDE_SYSTEM_LOGS" = true ]; then
    {
        echo ""
        echo "=== System-wide service logs ==="
        echo "Timestamp: $(date)"
        echo ""

        entries_before=$(wc -l < "$OUTPUT_FILE")
        collect_system_service_logs "$HOURS_BACK" >> "$OUTPUT_FILE" 2>&1 || true
        entries_after=$(wc -l < "$OUTPUT_FILE")
        system_entries=$((entries_after - entries_before))
        total_entries=$((total_entries + system_entries))

        echo ""
        echo "System-wide entries collected: $system_entries"
    } >> "$OUTPUT_FILE"
fi

# Compress output if requested
if [ "$COMPRESS_OUTPUT" = true ]; then
    if command -v gzip >/dev/null 2>&1; then
        gzip "$OUTPUT_FILE"
        OUTPUT_FILE="${OUTPUT_FILE}.gz"
        echo "Output compressed with gzip"
    elif command -v xz >/dev/null 2>&1; then
        xz "$OUTPUT_FILE"
        OUTPUT_FILE="${OUTPUT_FILE}.xz"
        echo "Output compressed with xz"
    else
        echo "Warning: Compression requested but gzip/xz not available"
    fi
fi

echo ""
echo "Log collection completed!"
echo "Total entries collected: $total_entries"
echo "Output saved to: $OUTPUT_FILE"