#!/bin/bash


username=$1
servers_string=$2

IFS=',' read -r -a servers <<< "$servers_string"
EXPECTED_SERVERS=${#servers[@]}

declare -A server_status

check_server_health() {
    local server=$1
    if ssh -n -o ConnectTimeout=2 "$username@${server}.uwyo.edu" \
        "./fall_2025/KeyDB/src/keydb-cli -h localhost PING" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

get_client_stats() {
    local server=$1
    ssh -n -o ConnectTimeout=2 "$username@${server}.uwyo.edu" \
        "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO commandstats 2>/dev/null | \
         grep -E 'cmdstat_get:|cmdstat_set:|cmdstat_sadd:|cmdstat_smembers:'" 2>/dev/null
}

parse_command_calls() {
    local stats_output=$1
    local command_name=$2  # e.g., "get", "set", "sadd", "smembers"
    
    # Use [0-9]\+ (one or more) instead of [0-9]* (zero or more) to ensure we match digits
    echo "$stats_output" | grep "cmdstat_${command_name}:" | \
        sed 's/.*calls=\([0-9]\+\).*/\1/' | head -1
}

# 
# SNIPPET: Calculate total client operations
# 
calculate_client_ops() {
    local server=$1
    local stats=$(get_client_stats "$server")
    
    if [ -z "$stats" ]; then
        echo "0|0|0"  # reads|writes|total
        return
    fi
    
    # Read commands: GET, SMEMBERS
    local get_calls=$(parse_command_calls "$stats" "get")
    local smembers_calls=$(parse_command_calls "$stats" "smembers")
    local total_reads=$((get_calls + smembers_calls))
    
    # Write commands: SET, SADD
    local set_calls=$(parse_command_calls "$stats" "set")
    local sadd_calls=$(parse_command_calls "$stats" "sadd")
    local total_writes=$((set_calls + sadd_calls))
    
    # Total operations
    local total_ops=$((total_reads + total_writes))
    
    echo "${total_reads}|${total_writes}|${total_ops}"
}

monitor_servers() {
    echo "=========================================="
    echo "Server Monitor Started"
    echo "Monitoring $EXPECTED_SERVERS servers"
    echo "Showing only client operations (GET, SET, SMEMBERS)"
    echo "=========================================="
    echo ""
    
    # Initialize all as "ok"
    for server in "${servers[@]}"; do
        server_status["$server"]="ok"
    done
    
    local iteration=0
    
    while true; do
        local all_ok=true
        
        # Check server health
        for server in "${servers[@]}"; do
            if check_server_health "$server"; then
                if [ "${server_status[$server]}" = "error" ]; then
                    echo "[OK] $server: KeyDB recovered"
                    server_status["$server"]="ok"
                fi
            else
                if [ "${server_status[$server]}" = "ok" ]; then
                    echo "[ERROR] $server: KeyDB not responding"
                    server_status["$server"]="error"
                fi
                all_ok=false
            fi
        done
        
        # Show stats every minute (every 6th iteration)
        if [ $((iteration % 6)) -eq 0 ] && [ "$iteration" -gt 0 ]; then
            echo ""
            echo "=== Client Operations on Servers ($(date +%H:%M:%S)) ==="
            
            for server in "${servers[@]}"; do
                if [ "${server_status[$server]}" = "ok" ]; then
                    local ops=$(calculate_client_ops "$server")
                    local reads=$(echo "$ops" | cut -d'|' -f1)
                    local writes=$(echo "$ops" | cut -d'|' -f2)
                    local total=$(echo "$ops" | cut -d'|' -f3)
                    
                    # Initialize to 0 if empty
                    [ -z "$reads" ] && reads=0
                    [ -z "$writes" ] && writes=0
                    [ -z "$total" ] && total=0
                    
                    echo "$server:"
                    echo "  Total Operations: $total"
                    echo "  Reads (GET+SMEMBERS): $reads"
                    echo "  Writes (SET+SADD): $writes"
                else
                    echo "$server: Server down (no stats)"
                fi
            done
            echo ""
        fi
        
        ((iteration++))
        sleep 10  # Check every 10 seconds
    done
}

if [ -z "$username" ] || [ -z "$servers_string" ]; then
    echo "Usage: $0 <username> <servers_string>"
    echo "Example: $0 mmanjee 'lhotse4,lhotse3,nuptse4,manaslu11,manaslu12'"
    exit 1
fi

monitor_servers