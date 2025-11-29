#!/bin/bash

# Comprehensive monitoring script for clients and servers

clients=("lhotse101" "lhotse102" "nuptse1" "nuptse2" "nuptse3" "manaslu1" "manaslu2" "manaslu3" "manaslu4" "manaslu5" "manaslu6" "manaslu7" "manaslu8" "manaslu9" "manaslu10")
servers=("lhotse4" "lhotse3" "nuptse4" "manaslu11" "manaslu12")
username="mmanjee"
monitor_server="yangra101"

show_client_status() {
    echo "================================================"
    echo "CLIENT STATUS"
    echo "================================================"
    
    # Completion status
    COMPLETED=$($HOME/final/KeyDB/src/keydb-cli -h "$monitor_server" KEYS "*_status" 2>/dev/null | wc -l)
    echo "Completed: $COMPLETED / ${#clients[@]}"
    
    if [ "$COMPLETED" -gt 0 ]; then
        echo "Completed clients:"
        $HOME/final/KeyDB/src/keydb-cli -h "$monitor_server" KEYS "*_status" 2>/dev/null | sed 's/_status$//' | head -10
    fi
    echo ""
    
    # Process status
    echo "Process Status:"
    completed_list=$($HOME/final/KeyDB/src/keydb-cli -h "$monitor_server" KEYS "*_status" 2>/dev/null | sed 's/_status$//' || echo "")
    
    for client in "${clients[@]}"; do
        is_completed=false
        if echo "$completed_list" | grep -q "^${client}$"; then
            is_completed=true
        fi
        
        if ssh -n -o ConnectTimeout=2 "${username}@${client}.uwyo.edu" "pgrep -f 'color.sh' > /dev/null 2>&1" 2>/dev/null; then
            if [ "$is_completed" = true ]; then
                echo "  ⚠ $client: RUNNING (completed)"
            else
                echo "  ✓ $client: RUNNING"
            fi
        else
            if [ "$is_completed" = true ]; then
                echo "  ✓ $client: COMPLETED"
            else
                echo "  ✗ $client: NOT RUNNING"
            fi
        fi
    done
    echo ""
}

show_client_logs() {
    local client=$1
    local lines=${2:-10}
    
    echo "=== Recent logs from $client (last $lines lines) ==="
    ssh -n -o ConnectTimeout=2 "${username}@${client}.uwyo.edu" \
        "cd ~/fall_2025/color/sync 2>/dev/null && \
         (ls -t color_*.log 2>/dev/null | head -1 | xargs tail -n $lines 2>/dev/null || \
          echo 'No log files found')" 2>/dev/null || echo "Could not fetch logs"
    echo ""
}

show_client_details() {
    local client=$1
    
    echo "=== Client Details: $client ==="
    
    # Process info
    echo "Process Info:"
    ssh -n -o ConnectTimeout=2 "${username}@${client}.uwyo.edu" \
        "ps aux | grep '[c]olor.sh' | head -1" 2>/dev/null || echo "  No process found"
    echo ""
    
    # Log files
    echo "Log Files:"
    ssh -n -o ConnectTimeout=2 "${username}@${client}.uwyo.edu" \
        "cd ~/fall_2025/color/sync 2>/dev/null && ls -lh color_*.log 2>/dev/null | tail -3 || echo 'No log files'" 2>/dev/null
    echo ""
    
    # Recent log output
    show_client_logs "$client" 5
}

show_server_status() {
    echo "================================================"
    echo "SERVER STATUS"
    echo "================================================"
    
    for server in "${servers[@]}"; do
        echo "=== $server ==="
        
        # Health check
        if ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost PING" >/dev/null 2>&1; then
            echo "  Status: ✓ ONLINE"
        else
            echo "  Status: ✗ OFFLINE"
            echo ""
            continue
        fi
        
        # Key count
        key_count=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost DBSIZE 2>/dev/null | grep -o '[0-9]*'" 2>/dev/null)
        echo "  Keys: $key_count"
        
        # Operations stats
        stats=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO commandstats 2>/dev/null | \
             grep -E 'cmdstat_get:|cmdstat_set:|cmdstat_sadd:|cmdstat_smembers:'" 2>/dev/null)
        
        if [ -n "$stats" ]; then
            get_calls=$(echo "$stats" | grep "cmdstat_get:" | sed 's/.*calls=\([0-9]*\).*/\1/' | head -1)
            set_calls=$(echo "$stats" | grep "cmdstat_set:" | sed 's/.*calls=\([0-9]*\).*/\1/' | head -1)
            smembers_calls=$(echo "$stats" | grep "cmdstat_smembers:" | sed 's/.*calls=\([0-9]*\).*/\1/' | head -1)
            sadd_calls=$(echo "$stats" | grep "cmdstat_sadd:" | sed 's/.*calls=\([0-9]*\).*/\1/' | head -1)
            
            [ -z "$get_calls" ] && get_calls=0
            [ -z "$set_calls" ] && set_calls=0
            [ -z "$smembers_calls" ] && smembers_calls=0
            [ -z "$sadd_calls" ] && sadd_calls=0
            
            reads=$((get_calls + smembers_calls))
            writes=$((set_calls + sadd_calls))
            total=$((reads + writes))
            
            echo "  Operations:"
            echo "    Total: $total"
            echo "    Reads (GET+SMEMBERS): $reads"
            echo "    Writes (SET+SADD): $writes"
        fi
        
        # Connected clients
        connected_clients=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO clients 2>/dev/null | \
             grep 'connected_clients:' | grep -o '[0-9]*'" 2>/dev/null)
        echo "  Connected Clients: $connected_clients"
        
        # Memory usage
        used_memory=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO memory 2>/dev/null | \
             grep 'used_memory_human:' | cut -d: -f2 | tr -d '\r'" 2>/dev/null)
        echo "  Memory Used: $used_memory"
        
        echo ""
    done
}

show_server_realtime() {
    local server=$1
    
    echo "=== Real-time Server Activity: $server ==="
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    while true; do
        clear
        echo "=== $server - $(date +%H:%M:%S) ==="
        
        # Operations per second
        ops_per_sec=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO stats 2>/dev/null | \
             grep 'instantaneous_ops_per_sec:' | grep -o '[0-9]*'" 2>/dev/null)
        echo "Ops/sec: $ops_per_sec"
        
        # Connected clients
        connected=$(ssh -n -o ConnectTimeout=2 "${username}@${server}.uwyo.edu" \
            "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO clients 2>/dev/null | \
             grep 'connected_clients:' | grep -o '[0-9]*'" 2>/dev/null)
        echo "Connected Clients: $connected"
        
        # Recent commands (if MONITOR is enabled)
        echo ""
        echo "Recent activity (last 5 seconds)..."
        
        sleep 5
    done
}

# Main menu
case "${1:-summary}" in
    "summary"|"")
        show_client_status
        show_server_status
        ;;
    "clients")
        show_client_status
        ;;
    "servers")
        show_server_status
        ;;
    "client-logs")
        if [ -z "$2" ]; then
            echo "Usage: $0 client-logs <client_name> [lines]"
            echo "Example: $0 client-logs lhotse101 20"
            exit 1
        fi
        show_client_logs "$2" "${3:-10}"
        ;;
    "client-details")
        if [ -z "$2" ]; then
            echo "Usage: $0 client-details <client_name>"
            echo "Example: $0 client-details lhotse101"
            exit 1
        fi
        show_client_details "$2"
        ;;
    "server-realtime")
        if [ -z "$2" ]; then
            echo "Usage: $0 server-realtime <server_name>"
            echo "Example: $0 server-realtime lhotse4"
            exit 1
        fi
        show_server_realtime "$2"
        ;;
    "all-clients")
        for client in "${clients[@]}"; do
            show_client_details "$client"
        done
        ;;
    *)
        echo "Usage: $0 [command] [args]"
        echo ""
        echo "Commands:"
        echo "  summary              - Show client and server summary (default)"
        echo "  clients              - Show client status only"
        echo "  servers              - Show server status only"
        echo "  client-logs <name>   - Show recent logs from a client"
        echo "  client-details <name> - Show detailed info for a client"
        echo "  all-clients          - Show details for all clients"
        echo "  server-realtime <name> - Real-time monitoring of a server"
        echo ""
        echo "Examples:"
        echo "  $0                                    # Summary"
        echo "  $0 client-logs lhotse101 20          # Last 20 lines from lhotse101"
        echo "  $0 client-details lhotse101         # Detailed info for lhotse101"
        echo "  $0 server-realtime lhotse4          # Real-time monitoring"
        exit 1
        ;;
esac

