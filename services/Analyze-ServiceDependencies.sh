#!/bin/bash

# Bash script for analyzing service dependencies on Linux systems
# Limited functionality compared to Windows version due to systemd/init.d constraints

set -e  # Exit on any error

# Default values
OUTPUT_FILE=""
SHOW_GRAPH=false
MAX_DEPTH=3

# Function to display usage
usage() {
    echo "Usage: $0 [-s service_names] [options]"
    echo "  -s service_names    : Comma-separated list of service names (required)"
    echo "  -o output_file      : Output file for detailed report"
    echo "  -g                  : Show graphical dependency tree"
    echo "  -d max_depth        : Maximum dependency depth to analyze (default: $MAX_DEPTH)"
    echo "  -a                  : Analyze all services (systemd only)"
    exit 1
}

# Parse command line options
while getopts "s:o:gd:ah" opt; do
    case $opt in
        s) SERVICE_NAMES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        g) SHOW_GRAPH=true ;;
        d) MAX_DEPTH="$OPTARG" ;;
        a) ANALYZE_ALL=true ;;
        *) usage ;;
    esac
done

# Check if service names are provided or analyze all
if [ -z "$SERVICE_NAMES" ] && [ "$ANALYZE_ALL" != true ]; then
    usage
fi

# Convert comma-separated to array
if [ -n "$SERVICE_NAMES" ]; then
    IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICE_NAMES"
else
    # Get all services (systemd only)
    if command -v systemctl >/dev/null 2>&1; then
        mapfile -t SERVICE_ARRAY < <(systemctl list-units --type=service --all --no-pager --no-legend | awk '{print $1}' | sed 's/\.service$//')
    else
        echo "ERROR: -a option requires systemd"
        exit 1
    fi
fi

# Function to get systemd service dependencies
get_systemd_dependencies() {
    local service_name="$1"
    local depth="${2:-0}"

    # Prevent infinite recursion
    if [ "$depth" -ge "$MAX_DEPTH" ]; then
        return
    fi

    echo "Analyzing: $service_name (depth: $depth)"

    if ! systemctl show "$service_name" >/dev/null 2>&1; then
        echo "  ERROR: Service '$service_name' not found"
        return
    fi

    # Get service status
    local status
    status=$(systemctl is-active "$service_name" 2>/dev/null || echo "unknown")
    local enabled
    enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "unknown")

    echo "  Status: $status"
    echo "  Enabled: $enabled"

    # Get dependencies (services this service requires)
    local requires
    requires=$(systemctl show "$service_name" -p Requires --value 2>/dev/null | tr ' ' '\n' | grep '\.service$' | sed 's/\.service$//' || true)

    local wants
    wants=$(systemctl show "$service_name" -p Wants --value 2>/dev/null | tr ' ' '\n' | grep '\.service$' | sed 's/\.service$//' || true)

    if [ -n "$requires" ]; then
        echo "  Requires: $requires"
        # Recursively analyze required services
        for req in $requires; do
            echo "  └─ Required: $req"
            get_systemd_dependencies "$req" $((depth + 1))
        done
    fi

    if [ -n "$wants" ]; then
        echo "  Wants: $wants"
    fi

    # Get services that require this service (reverse dependencies)
    local required_by
    required_by=$(systemctl show "$service_name" -p RequiredBy --value 2>/dev/null | tr ' ' '\n' | grep '\.service$' | sed 's/\.service$//' || true)

    if [ -n "$required_by" ]; then
        echo "  Required by: $required_by"
    fi

    echo ""
}

# Function to analyze init.d service (limited info)
get_initd_dependencies() {
    local service_name="$1"

    echo "Analyzing init.d service: $service_name"

    # Check if service exists
    if [ ! -x "/etc/init.d/$service_name" ]; then
        echo "  ERROR: Service script not found in /etc/init.d/"
        return
    fi

    # Try to get LSB headers for dependencies
    if [ -f "/etc/init.d/$service_name" ]; then
        local provides
        provides=$(grep -i "^# Provides:" "/etc/init.d/$service_name" | cut -d: -f2- | xargs 2>/dev/null || echo "unknown")
        local required_start
        required_start=$(grep -i "^# Required-Start:" "/etc/init.d/$service_name" | cut -d: -f2- | xargs 2>/dev/null || echo "unknown")
        local required_stop
        required_stop=$(grep -i "^# Required-Stop:" "/etc/init.d/$service_name" | cut -d: -f2- | xargs 2>/dev/null || echo "unknown")

        echo "  Provides: $provides"
        echo "  Required-Start: $required_start"
        echo "  Required-Stop: $required_stop"
    fi

    echo ""
}

# Function to show graphical tree (simple text-based)
show_dependency_tree() {
    local service_name="$1"
    local prefix="${2:-}"

    echo "${prefix}┌─ $service_name"

    if command -v systemctl >/dev/null 2>&1; then
        local requires
        requires=$(systemctl show "$service_name" -p Requires --value 2>/dev/null | tr ' ' '\n' | grep '\.service$' | sed 's/\.service$//' | head -5 || true)

        local i=0
        for req in $requires; do
            if [ $i -eq 0 ]; then
                show_dependency_tree "$req" "${prefix}├─ "
            else
                show_dependency_tree "$req" "${prefix}│  "
            fi
            ((i++))
        done
    fi
}

# Main execution
echo "Service Dependency Analyzer"
echo "=========================="
echo "Analyzing ${#SERVICE_ARRAY[@]} services..."
echo ""

# Create output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    exec > >(tee "$OUTPUT_FILE") 2>&1
fi

# Analyze each service
for service in "${SERVICE_ARRAY[@]}"; do
    service=$(echo "$service" | xargs)  # Trim whitespace

    if [ "$SHOW_GRAPH" = true ]; then
        echo "=== DEPENDENCY TREE ==="
        show_dependency_tree "$service"
        echo ""
    fi

    echo "=== DETAILED ANALYSIS ==="
    if command -v systemctl >/dev/null 2>&1; then
        get_systemd_dependencies "$service"
    else
        get_initd_dependencies "$service"
    fi
done

echo "Dependency analysis completed."

if [ -n "$OUTPUT_FILE" ]; then
    echo "Results saved to: $OUTPUT_FILE"
fi