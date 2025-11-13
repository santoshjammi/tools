#!/bin/bash

# Service Batch Operations Script for Linux
# Allows defining service groups and performing batch operations

set -e  # Exit on any error

# Default values
CONFIG_FILE="service-groups.json"
TIMEOUT_SECONDS=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
usage() {
    print_color $CYAN "Service Batch Operations Tool"
    print_color $CYAN "============================"
    echo ""
    print_color $WHITE "Usage: $0 [OPTIONS]"
    echo ""
    print_color $WHITE "Options:"
    echo "  -g, --group NAME       Service group name"
    echo "  -o, --operation OP     Operation to perform (start|stop|restart|status|enable|disable)"
    echo "  -c, --config FILE      Config file (default: service-groups.json)"
    echo "  -l, --list             List all service groups"
    echo "  --create-group         Create a new service group"
    echo "  -s, --services LIST    Comma-separated list of services for new group"
    echo "  -d, --description DESC Description for new group"
    echo "  -f, --force            Force operation (overwrite existing group)"
    echo "  -t, --timeout SEC      Timeout in seconds (default: 300)"
    echo "  -h, --help             Show this help"
    echo ""
    print_color $GRAY "Operations:"
    echo "  start   - Start all services in group"
    echo "  stop    - Stop all services in group"
    echo "  restart - Restart all services in group"
    echo "  status  - Show status of all services in group"
    echo "  enable  - Enable all services in group"
    echo "  disable - Disable all services in group"
    echo ""
    print_color $YELLOW "Examples:"
    echo "  $0 --list"
    echo "  $0 --create-group -g WebServices -s 'apache2,mysql' -d 'Web server services'"
    echo "  $0 -g WebServices -o start"
}

# Function to load service groups from JSON
load_service_groups() {
    local config_file=$1

    if [[ ! -f "$config_file" ]]; then
        print_color $YELLOW "Config file not found: $config_file"
        echo "{}"
        return 1
    fi

    # Use python or jq if available, otherwise basic parsing
    if command -v python3 &> /dev/null; then
        python3 -c "
import json
import sys
try:
    with open('$config_file', 'r') as f:
        data = json.load(f)
    print(json.dumps(data))
except Exception as e:
    print('{}', file=sys.stderr)
    sys.exit(1)
"
    elif command -v jq &> /dev/null; then
        jq '.' "$config_file" 2>/dev/null || echo "{}"
    else
        print_color $YELLOW "Warning: Neither python3 nor jq found. Using basic parsing."
        cat "$config_file"
    fi
}

# Function to save service groups to JSON
save_service_groups() {
    local config_file=$1
    local groups_data=$2

    if command -v python3 &> /dev/null; then
        python3 -c "
import json
import sys
try:
    data = json.loads('''$groups_data''')
    with open('$config_file', 'w') as f:
        json.dump(data, f, indent=2)
    print('Service groups saved to: $config_file')
except Exception as e:
    print(f'Error saving config: {e}', file=sys.stderr)
    sys.exit(1)
"
    elif command -v jq &> /dev/null; then
        echo "$groups_data" | jq '.' > "$config_file"
        print_color $GREEN "Service groups saved to: $config_file"
    else
        echo "$groups_data" > "$config_file"
        print_color $GREEN "Service groups saved to: $config_file"
    fi
}

# Function to create a new service group
create_service_group() {
    local name=$1
    local services=$2
    local description=$3
    local config_file=$4

    # Load existing groups
    local groups=$(load_service_groups "$config_file")

    # Check if group already exists
    if [[ "$force" != "true" ]] && echo "$groups" | grep -q "\"$name\":"; then
        print_color $RED "Error: Group '$name' already exists. Use --force to overwrite."
        exit 1
    fi

    # Create new group data
    local timestamp=$(date -Iseconds)
    local group_data="{\"Name\":\"$name\",\"Description\":\"$description\",\"Services\":[${services}],\"Created\":\"$timestamp\",\"Modified\":\"$timestamp\"}"

    # Add to groups (basic JSON manipulation)
    if [[ "$groups" == "{}" ]]; then
        groups="{$name: $group_data}"
    else
        # Remove trailing }
        groups=${groups%?}
        groups="$groups,\"$name\":$group_data}"
    fi

    save_service_groups "$config_file" "$groups"
    print_color $GREEN "Service group '$name' created successfully."
}

# Function to list service groups
list_service_groups() {
    local config_file=$1

    print_color $CYAN "Available Service Groups:"
    print_color $CYAN "========================"

    local groups=$(load_service_groups "$config_file")

    if [[ "$groups" == "{}" ]]; then
        print_color $YELLOW "No service groups found in: $config_file"
        print_color $GRAY "Use --create-group to create your first group."
        return
    fi

    # Parse groups using basic string manipulation
    echo "$groups" | sed 's/[{}"]//g' | while IFS=: read -r group_name group_data; do
        if [[ -n "$group_name" && "$group_name" != "{"* ]]; then
            # Extract service count and description
            local service_count=$(echo "$group_data" | grep -o '"Services":\[[^]]*\]' | grep -o ',' | wc -l)
            ((service_count++))  # Add 1 since wc -l counts commas
            local description=$(echo "$group_data" | grep -o '"Description":"[^"]*"' | cut -d'"' -f4)

            print_color $WHITE "$group_name"
            echo "  ($service_count services)"
            if [[ -n "$description" ]]; then
                print_color $GRAY "  $description"
            fi
            echo ""
        fi
    done
}

# Function to execute batch operation
execute_batch_operation() {
    local group_name=$1
    local operation=$2
    local config_file=$3
    local timeout=$4

    local groups=$(load_service_groups "$config_file")

    # Extract group data (basic parsing)
    local group_data=$(echo "$groups" | sed 's/[{}"]//g' | grep "^$group_name:" | cut -d: -f2-)

    if [[ -z "$group_data" ]]; then
        print_color $RED "Error: Service group '$group_name' not found."
        print_color $GRAY "Use --list to see available groups."
        exit 1
    fi

    # Extract services array
    local services_str=$(echo "$group_data" | grep -o '"Services":\[[^]]*\]' | cut -d'[' -f2 | cut -d']' -f1)
    local description=$(echo "$group_data" | grep -o '"Description":"[^"]*"' | cut -d'"' -f4)

    # Convert comma-separated services to array
    IFS=',' read -ra services <<< "$services_str"

    print_color $CYAN "Executing '$operation' on service group: $group_name"
    if [[ -n "$description" ]]; then
        print_color $GRAY "Description: $description"
    fi
    print_color $WHITE "Services: ${services[*]}"
    echo ""

    local success_count=0
    local failure_count=0

    for service in "${services[@]}"; do
        # Remove quotes and whitespace
        service=$(echo "$service" | sed 's/[" ]//g')

        print_color $YELLOW "Processing service: $service"

        if ! execute_service_operation "$service" "$operation"; then
            ((failure_count++))
        else
            ((success_count++))
        fi
        echo ""
    done

    # Summary
    print_color $CYAN "=== OPERATION SUMMARY ==="
    print_color $WHITE "Group: $group_name"
    print_color $WHITE "Operation: $operation"
    print_color $GREEN "Successful: $success_count"
    print_color $RED "Failed: $failure_count"
    print_color $WHITE "Total: ${#services[@]}"

    if [[ $failure_count -gt 0 ]]; then
        print_color $YELLOW "Warning: Some operations failed. Check the output above for details."
        return 1
    else
        print_color $GREEN "All operations completed successfully."
        return 0
    fi
}

# Function to execute operation on a single service
execute_service_operation() {
    local service=$1
    local operation=$2

    case $operation in
        start)
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                print_color $GRAY "  - Already running"
                return 0
            else
                if sudo systemctl start "$service"; then
                    print_color $GREEN "  ✓ Started successfully"
                    return 0
                else
                    print_color $RED "  ✗ Failed to start"
                    return 1
                fi
            fi
            ;;
        stop)
            if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                print_color $GRAY "  - Already stopped"
                return 0
            else
                if sudo systemctl stop "$service"; then
                    print_color $GREEN "  ✓ Stopped successfully"
                    return 0
                else
                    print_color $RED "  ✗ Failed to stop"
                    return 1
                fi
            fi
            ;;
        restart)
            if sudo systemctl restart "$service"; then
                print_color $GREEN "  ✓ Restarted successfully"
                return 0
            else
                print_color $RED "  ✗ Failed to restart"
                return 1
            fi
            ;;
        status)
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                print_color $GREEN "  Status: Running"
            elif systemctl is-failed --quiet "$service" 2>/dev/null; then
                print_color $RED "  Status: Failed"
            else
                print_color $YELLOW "  Status: Stopped"
            fi
            return 0
            ;;
        enable)
            if sudo systemctl enable "$service"; then
                print_color $GREEN "  ✓ Enabled successfully"
                return 0
            else
                print_color $RED "  ✗ Failed to enable"
                return 1
            fi
            ;;
        disable)
            if sudo systemctl disable "$service"; then
                print_color $GREEN "  ✓ Disabled successfully"
                return 0
            else
                print_color $RED "  ✗ Failed to disable"
                return 1
            fi
            ;;
        *)
            print_color $RED "  ✗ Unknown operation: $operation"
            return 1
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--group)
            group_name="$2"
            shift 2
            ;;
        -o|--operation)
            operation="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -l|--list)
            list_groups=true
            shift
            ;;
        --create-group)
            create_group=true
            shift
            ;;
        -s|--services)
            services="$2"
            shift 2
            ;;
        -d|--description)
            description="$2"
            shift 2
            ;;
        -f|--force)
            force=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_color $RED "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main logic
if [[ "$list_groups" == "true" ]]; then
    list_service_groups "$CONFIG_FILE"
    exit 0
fi

if [[ "$create_group" == "true" ]]; then
    if [[ -z "$group_name" || -z "$services" ]]; then
        print_color $RED "Error: Group name and services are required when creating a group."
        usage
        exit 1
    fi

    # Convert comma-separated services to JSON array format
    services_json=$(echo "$services" | sed 's/,/","/g; s/^/"/; s/$/"/')

    create_service_group "$group_name" "$services_json" "$description" "$CONFIG_FILE"
    exit 0
fi

if [[ -n "$operation" && -n "$group_name" ]]; then
    if ! execute_batch_operation "$group_name" "$operation" "$CONFIG_FILE" "$TIMEOUT_SECONDS"; then
        exit 1
    fi
    exit 0
fi

# If no specific action was requested, show usage
usage