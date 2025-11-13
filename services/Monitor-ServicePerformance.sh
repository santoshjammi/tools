#!/bin/bash

# Bash script for monitoring service performance metrics on Linux systems

set -e  # Exit on any error

# Default values
INTERVAL_SECONDS=10
DURATION_MINUTES=5
OUTPUT_FILE=""
CONTINUOUS=false
CPU_THRESHOLD=80
MEMORY_THRESHOLD=500  # MB
THREAD_THRESHOLD=100

# Function to display usage
usage() {
    echo "Usage: $0 -s service_names [options]"
    echo "  -s service_names    : Comma-separated list of service names (required)"
    echo "  -i interval         : Monitoring interval in seconds (default: $INTERVAL_SECONDS)"
    echo "  -d duration         : Duration in minutes (default: $DURATION_MINUTES)"
    echo "  -o output_file      : CSV output file for results"
    echo "  -c                  : Continuous monitoring (ignore duration)"
    echo "  -t cpu_thresh       : CPU usage threshold percentage (default: $CPU_THRESHOLD)"
    echo "  -m mem_thresh       : Memory usage threshold MB (default: $MEMORY_THRESHOLD)"
    echo "  -r thread_thresh    : Thread count threshold (default: $THREAD_THRESHOLD)"
    exit 1
}

# Parse command line options
while getopts "s:i:d:o:ct:m:r:h" opt; do
    case $opt in
        s) SERVICE_NAMES="$OPTARG" ;;
        i) INTERVAL_SECONDS="$OPTARG" ;;
        d) DURATION_MINUTES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        c) CONTINUOUS=true ;;
        t) CPU_THRESHOLD="$OPTARG" ;;
        m) MEMORY_THRESHOLD="$OPTARG" ;;
        r) THREAD_THRESHOLD="$OPTARG" ;;
        *) usage ;;
    esac
done

# Check if service names are provided
if [ -z "$SERVICE_NAMES" ]; then
    usage
fi

# Convert comma-separated to array
IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICE_NAMES"

# Function to get service process information
get_service_process_info() {
    local service_name="$1"

    # Get service status
    local status="unknown"
    if command -v systemctl >/dev/null 2>&1; then
        status=$(systemctl is-active "$service_name" 2>/dev/null || echo "unknown")
    fi

    # Find process ID(s) for the service
    local pids=""
    if command -v systemctl >/dev/null 2>&1; then
        # For systemd services, get main PID
        local main_pid
        main_pid=$(systemctl show "$service_name" -p MainPID --value 2>/dev/null || echo "")
        if [ -n "$main_pid" ] && [ "$main_pid" != "0" ]; then
            pids="$main_pid"
        fi
    fi

    # If no PID from systemd, try to find by process name
    if [ -z "$pids" ]; then
        pids=$(pgrep -f "$service_name" 2>/dev/null || echo "")
    fi

    echo "$status|$pids"
}

# Function to get process performance metrics
get_process_metrics() {
    local pid="$1"

    if [ -z "$pid" ] || [ "$pid" = "0" ] || [ ! -d "/proc/$pid" ]; then
        echo "0|0|0|0|N/A"
        return
    fi

    # CPU usage (simplified - percentage since last check)
    local cpu_usage=0
    if command -v ps >/dev/null 2>&1; then
        cpu_usage=$(ps -p "$pid" -o pcpu= 2>/dev/null | xargs 2>/dev/null || echo "0")
    fi

    # Memory usage in MB
    local mem_kb=0
    if [ -f "/proc/$pid/status" ]; then
        mem_kb=$(grep -E "^VmRSS:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
    fi
    local mem_mb=$((mem_kb / 1024))

    # Thread count
    local thread_count=0
    if [ -d "/proc/$pid/task" ]; then
        thread_count=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
    fi

    # Handle count (file descriptors)
    local handle_count=0
    if [ -d "/proc/$pid/fd" ]; then
        handle_count=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
    fi

    # Start time
    local start_time="unknown"
    if [ -f "/proc/$pid/stat" ]; then
        local start_ticks
        start_ticks=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo "0")
        if [ "$start_ticks" != "0" ]; then
            local hertz
            hertz=$(getconf CLK_TCK 2>/dev/null || echo "100")
            local uptime_seconds
            uptime_seconds=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d'.' -f1 || echo "0")
            local proc_seconds=$((uptime_seconds - start_ticks / hertz))
            start_time="$proc_seconds seconds ago"
        fi
    fi

    echo "$cpu_usage|$mem_mb|$thread_count|$handle_count|$start_time"
}

# Function to display current metrics
show_current_metrics() {
    local timestamp="$1"

    echo ""
    echo "=== PERFORMANCE METRICS [$timestamp] ==="

    for service in "${SERVICE_ARRAY[@]}"; do
        service=$(echo "$service" | xargs)

        # Get service and process info
        local service_info
        service_info=$(get_service_process_info "$service")
        IFS='|' read -r status pids <<< "$service_info"

        # Status color
        case $status in
            active|running)
                echo -e "\033[32m$service: RUNNING\033[0m"
                ;;
            inactive|stopped|dead)
                echo -e "\033[31m$service: STOPPED\033[0m"
                continue
                ;;
            *)
                echo -e "\033[33m$service: $status\033[0m"
                ;;
        esac

        # Process metrics
        local total_cpu=0
        local total_mem=0
        local max_threads=0
        local total_handles=0
        local process_count=0

        IFS=' ' read -ra pid_array <<< "$pids"
        for pid in "${pid_array[@]}"; do
            if [ -n "$pid" ] && [ "$pid" != "0" ]; then
                local metrics
                metrics=$(get_process_metrics "$pid")
                IFS='|' read -r cpu mem threads handles start_time <<< "$metrics"

                total_cpu=$(echo "$total_cpu + $cpu" | bc 2>/dev/null || echo "$total_cpu")
                total_mem=$((total_mem + mem))
                [ "$threads" -gt "$max_threads" ] && max_threads="$threads"
                total_handles=$((total_handles + handles))
                process_count=$((process_count + 1))

                if [ "$process_count" -eq 1 ]; then
                    echo "  PID: $pid, CPU: ${cpu}%, Memory: ${mem} MB, Threads: $threads, Handles: $handles"
                fi
            fi
        done

        if [ "$process_count" -gt 1 ]; then
            echo "  Total Processes: $process_count, Combined CPU: ${total_cpu}%, Total Memory: ${total_mem} MB"
        fi

        # Check thresholds and show alerts
        local alerts=""
        if (( $(echo "$total_cpu > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
            alerts="${alerts}HIGH CPU "
        fi
        if [ "$total_mem" -gt "$MEMORY_THRESHOLD" ]; then
            alerts="${alerts}HIGH MEM "
        fi
        if [ "$max_threads" -gt "$THREAD_THRESHOLD" ]; then
            alerts="${alerts}HIGH THREADS "
        fi

        if [ -n "$alerts" ]; then
            echo -e "  \033[31m⚠️  ALERTS: $alerts\033[0m"
        fi
    done
}

# Function to log metrics to CSV
log_metrics_to_csv() {
    local timestamp="$1"
    local output_file="$2"

    # Write header if file doesn't exist
    if [ ! -f "$output_file" ]; then
        echo "Timestamp,Service,Status,CPU_Percent,Memory_MB,Threads,Handles,Alerts" > "$output_file"
    fi

    for service in "${SERVICE_ARRAY[@]}"; do
        service=$(echo "$service" | xargs)

        local service_info
        service_info=$(get_service_process_info "$service")
        IFS='|' read -r status pids <<< "$service_info"

        local total_cpu=0
        local total_mem=0
        local max_threads=0
        local total_handles=0

        IFS=' ' read -ra pid_array <<< "$pids"
        for pid in "${pid_array[@]}"; do
            if [ -n "$pid" ] && [ "$pid" != "0" ]; then
                local metrics
                metrics=$(get_process_metrics "$pid")
                IFS='|' read -r cpu mem threads handles start_time <<< "$metrics"

                total_cpu=$(echo "$total_cpu + $cpu" | bc 2>/dev/null || echo "$total_cpu")
                total_mem=$((total_mem + mem))
                [ "$threads" -gt "$max_threads" ] && max_threads="$threads"
                total_handles=$((total_handles + handles))
            fi
        done

        # Determine alerts
        local alerts=""
        if (( $(echo "$total_cpu > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
            alerts="${alerts}HIGH_CPU,"
        fi
        if [ "$total_mem" -gt "$MEMORY_THRESHOLD" ]; then
            alerts="${alerts}HIGH_MEM,"
        fi
        if [ "$max_threads" -gt "$THREAD_THRESHOLD" ]; then
            alerts="${alerts}HIGH_THREADS,"
        fi
        alerts=$(echo "$alerts" | sed 's/,$//')

        echo "$timestamp,$service,$status,$total_cpu,$total_mem,$max_threads,$total_handles,$alerts" >> "$output_file"
    done
}

# Main monitoring loop
echo "Service Performance Monitor"
echo "=========================="
echo "Services: ${SERVICE_NAMES}"
echo "Interval: $INTERVAL_SECONDS seconds"
echo "Duration: $(if [ "$CONTINUOUS" = true ]; then echo "Continuous"; else echo "$DURATION_MINUTES minutes"; fi)"
echo "Thresholds: CPU > ${CPU_THRESHOLD}%, Memory > ${MEMORY_THRESHOLD} MB, Threads > ${THREAD_THRESHOLD}"
if [ -n "$OUTPUT_FILE" ]; then
    echo "Output file: $OUTPUT_FILE"
fi
echo ""

start_time=$(date +%s)
end_time=$((start_time + DURATION_MINUTES * 60))
iteration=0

while [ "$CONTINUOUS" = true ] || [ $(date +%s) -lt $end_time ]; do
    iteration=$((iteration + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    show_current_metrics "$timestamp"

    if [ -n "$OUTPUT_FILE" ]; then
        log_metrics_to_csv "$timestamp" "$OUTPUT_FILE"
    fi

    if [ "$CONTINUOUS" = false ]; then
        remaining=$((end_time - $(date +%s)))
        if [ $remaining -gt 0 ]; then
            echo "Next check in $INTERVAL_SECONDS seconds... (Remaining: $((remaining / 60))m $((remaining % 60))s)"
        fi
    fi

    sleep $INTERVAL_SECONDS
done

echo ""
echo "Performance monitoring completed."

if [ -n "$OUTPUT_FILE" ]; then
    echo "Results saved to: $OUTPUT_FILE"
fi