#!/bin/bash

echo "================================================"
echo "Verification)"
echo "================================================"

number_of_node=$1
start_node=$2
end_node=$3
partition=$4
clients_string=$5
servers_string=$6
username=$7

if [ -z "$number_of_node" ] || [ -z "$start_node" ] || [ -z "$end_node" ] || [ -z "$partition" ] || [ -z "$clients_string" ] || [ -z "$servers_string" ] || [ -z "$username" ]; then
    echo "Error: Missing arguments"
    echo "Usage: $0 <number_of_node> <start_node> <end_node> <partition> <clients_string> <servers_string> <username>"
    exit 1
fi

IFS=',' read -r -a clients <<< "$clients_string"
IFS=',' read -r -a servers <<< "$servers_string"

declare -A machine_client_map
declare -A machine_server_map
declare -A partitions
declare -A server_client_map

#generate maps
generate_map(){
    for server in "${servers[@]}"; do
        machine_server_map["$server"]="${username}@$server.uwyo.edu"
    done
    for client in "${clients[@]}"; do
        machine_client_map["$client"]="${username}@$client.uwyo.edu"
    done
}

assign_clients_to_servers(){
    local server_index=0
    local num_servers=${#servers[@]}

    for client in "${clients[@]}"; do
        local assigned_server="${servers[$server_index]}"
        server_client_map["$client"]="$assigned_server"
        server_index=$(( (server_index + 1) % num_servers ))
    done

    echo "Server Client Mapping:"
    for client in "${clients[@]}"; do
        echo "Client $client -> Server ${server_client_map[$client]}"
    done
    echo ""
}

#node partition
get_partition(){
    local range=$((end_node - start_node + 1))
    local partition_size=$((range / partition))
    local remaining=$((range % partition))
    local current_start=$start_node
    for ((i = 1; i <= partition; i++)); do
        local current_end=$((current_start + partition_size - 1))
        if ((remaining > 0)); then
            current_end=$((current_end + 1))
            remaining=$((remaining - 1))
        fi

        partitions["Partition_$i"]="$current_start,$current_end"
        current_start=$((current_end + 1))
    done

    echo "Partitions:"
    for key in "${!partitions[@]}"; do
        echo "$key: ${partitions[$key]}"
    done
    echo ""
}

#verify the results 
run_verification(){
    echo "================================================"
    echo "Running Verification)"
    echo "================================================"

    generate_map
    assign_clients_to_servers
    get_partition

    local first_server="${servers[0]}"
    local server_ssh="${machine_server_map[$first_server]}"
    
    echo "Fetching all graph data from server $first_server..."
    
    # Test connection
    if ! ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost PING" > /dev/null 2>&1; then
        echo "ERROR: Cannot connect to KeyDB on server $first_server"
        exit 1
    fi
    
    echo "Connection verified. Fetching data (this may take 10-30 seconds)..."
    local start_time=$(date +%s)
    
    # Fetch all data in one SSH call using seq for loop
    local all_data=$(ssh -n "$server_ssh" \
        "cd ~/fall_2025; \
        for node_id in \$(seq $start_node $end_node); do \
            color=\$(./KeyDB/src/keydb-cli -h localhost GET node_\${node_id}_color 2>/dev/null | tr -d '\"'); \
            [ -z \"\$color\" ] || [ \"\$color\" = \"(nil)\" ] || [ \"\$color\" = \"(empty)\" ] && continue; \
            neighbors=\$(./KeyDB/src/keydb-cli -h localhost SMEMBERS node_\${node_id}_neighbours 2>/dev/null | grep -v '^(\$' | grep -v '^empty' | tr '\n' ',' | sed 's/,$//'); \
            [ -z \"\$neighbors\" ] && continue; \
            echo \"\${node_id}|\${color}|\${neighbors}\"; \
        done" 2>&1)
    
    local fetch_time=$(($(date +%s) - start_time))
    
    # Check for errors in output
    if echo "$all_data" | grep -qi "error\|failed\|connection\|refused"; then
        echo "ERROR: Failed to fetch data from server"
        echo "Error details:"
        echo "$all_data" | grep -i "error\|failed\|connection" | head -3
        exit 1
    fi
    
    if [ -z "$all_data" ]; then
        echo "ERROR: No data fetched. Is the graph colored?"
        echo "Testing single node fetch..."
        local test_data=$(ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost GET 'node_0_color'" 2>/dev/null)
        if [ -z "$test_data" ]; then
            echo "ERROR: Cannot fetch data. Is KeyDB running? Are nodes colored?"
        else
            echo "Debug: Single fetch works. No nodes in range $start_node-$end_node have colors."
        fi
        exit 1
    fi
    
    local line_count=$(echo "$all_data" | grep -c "^[0-9]*|[0-9]*|" || echo "0")
    echo "Data fetched in ${fetch_time} seconds. Got $line_count nodes."
    echo "Verifying..."
    
    # Store data in associative arrays for fast lookup
    declare -A node_colors
    declare -A node_neighbors
    
    # Parse all data into arrays
    while IFS='|' read -r node_id color neighbors; do
        [ -z "$node_id" ] && continue
        # Remove quotes from color if present
        color=$(echo "$color" | tr -d '"')
        node_colors["$node_id"]="$color"
        node_neighbors["$node_id"]="$neighbors"
    done <<< "$all_data"
    
    local total_nodes=${#node_colors[@]}
    
    if [ $total_nodes -eq 0 ]; then
        echo "ERROR: No valid nodes found in data"
        exit 1
    fi
    
    echo "Verifying $total_nodes nodes..."
    
    # Verify each node
    local conflict_found=false
    local verified_count=0
    local conflict_count=0
    declare -A seen_conflicts  # Track conflicts to avoid double counting
    
    for node_id in "${!node_colors[@]}"; do
        local node_color="${node_colors[$node_id]}"
        local neighbors="${node_neighbors[$node_id]}"
        
        # Check each neighbor
        IFS=',' read -r -a neighbor_array <<< "$neighbors"
        for neighbor_id in "${neighbor_array[@]}"; do
            [ -z "$neighbor_id" ] && continue
            
            # Get neighbor color from our array
            local neighbor_color="${node_colors[$neighbor_id]}"
            
            # Skip if neighbor not in our data (outside range or no color)
            [ -z "$neighbor_color" ] && continue
            
            # Check for conflict
            if [ "$node_color" = "$neighbor_color" ]; then
                conflict_found=true
                
                # Create a unique key for this conflict pair (smaller_id:larger_id)
                local smaller_id=$node_id
                local larger_id=$neighbor_id
                if [ "$node_id" -gt "$neighbor_id" ]; then
                    smaller_id=$neighbor_id
                    larger_id=$node_id
                fi
                local conflict_key="${smaller_id}:${larger_id}"
                
                # Only count and report if we haven't seen this conflict before
                if [ -z "${seen_conflicts[$conflict_key]}" ]; then
                    seen_conflicts["$conflict_key"]=1
                    ((conflict_count++))
                    echo "CONFLICT: Node $node_id (color=$node_color) conflicts with neighbor $neighbor_id (color=$neighbor_color)"
                fi
            fi
        done
        
        ((verified_count++))
        # if [ $total_nodes -gt 0 ] && [ $((verified_count % 25)) -eq 0 ]; then
        #     local percent=$((verified_count * 100 / total_nodes))
        #     echo -n "  Progress: $verified_count/$total_nodes nodes ($percent%)...\r"
        # fi
    done
    
    echo ""  # New line after progress
    
    if [ "$conflict_found" = false ]; then
        echo ""
        echo "================================================"
        echo "VERIFICATION SUCCESSFUL"
        echo "================================================"
        echo "All nodes verified: $start_node to $end_node"
        echo "Total nodes checked: $verified_count"
        echo "Fetch time: ${fetch_time}s"
        echo "Incorrectly colored nodes: 0"
        echo "================================================"
    else
        echo ""
        echo "================================================"
        echo "VERIFICATION FAILED"
        echo "================================================"
        echo "Total nodes checked: $verified_count"
        echo "Incorrectly colored nodes: $conflict_count"
        echo "Server: $first_server"
        echo "Fetch time: ${fetch_time}s"
        echo "================================================"
        exit 1
    fi
}

run_verification