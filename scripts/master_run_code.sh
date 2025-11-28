#!/bin/bash

# Assign the first four arguments to variables
username=$1            # Username (single string)
dataset=$2             # Dataset name
servers_string=$3      # Servers array (comma-separated string)
clients_string=$4      # Clients array (comma-separated string)

# Remaining arguments are the partitions
shift 4                # Remove the first four arguments
partitions=("$@")      # Store all remaining arguments as an array

# Parse the clients and servers into arrays
IFS=',' read -r -a clients <<< "$clients_string"
IFS=',' read -r -a servers <<< "$servers_string"

# Initialize associative arrays
declare -A machine_server_map
declare -A machine_client_map

# Function to display the maps
display_map(){
    for key in "${!machine_server_map[@]}"; do
        echo " server $key : ${machine_server_map[$key]}"
    done

    for key in "${!machine_client_map[@]}"; do
        echo " client $key : ${machine_client_map[$key]}"
    done
}

# Function to generate the server and client maps
generate_map(){
    for server in "${servers[@]}"; do
        machine_server_map["$server"]="${username}@$server.uwyo.edu"
    done

    for client in "${clients[@]}"; do
        machine_client_map["$client"]="${username}@$client.uwyo.edu"
    done
    display_map
}





echo "Partitions:"
for partition in "${partitions[@]}"; do
    echo "${partition/,/ }"
done



pair_clients_to_servers() {
    generate_map
    declare -A server_client_map
    local server_index=0
    local num_servers=${#servers[@]}
    
    for client in "${clients[@]}"; do
        local assigned_server="${servers[$server_index]}"
        server_client_map["$assigned_server"]+="$client "

        # Move to the next server in a round-robin fashion
        server_index=$(( (server_index + 1) % num_servers ))
    done

    # Display the mapping
    for server in "${servers[@]}"; do
        echo "Server $server (${machine_server_map[$server]}) is assigned clients: ${server_client_map[$server]}"
    done
}



# run_code_1_1(){
#     # Implement your logic here
# echo "---------------------------------------------------------------------------------------------------"
# echo "                  Executing Code in Clients                                                        "
# echo "---------------------------------------------------------------------------------------------------"
#     generate_map
#     local index=0
#     for client in "${!machine_client_map[@]}"; do
#         partition="${partitions[index]}"
#         start=${partition%,*}  # Extract the first value (before comma)
#         end=${partition#*,}    # Extract the second value (after comma)

#         echo "Connecting to ${machine_client_map[$client]} with partition range $start to $end..."
        
#         ssh "${machine_client_map[$client]}" "cd /home/abhattar/code/color/1server; nohup ./color.sh $start $end 127.0.0.1 > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"

#         ((index++))  # Move to the next partition
#     done
# }


# run_code_1_many() {
#     echo "---------------------------------------------------------------------------------------------------"
#     echo "                $(date)  Executing Code in Clients                                                        "
#     echo "---------------------------------------------------------------------------------------------------"
#     generate_map
    
#     local index=0
#     declare -A server_client_map
#     local server_index=0
#     local num_servers=${#servers[@]}
    
#     # Map clients to servers
#     for client in "${clients[@]}"; do
#         local assigned_server="${servers[$server_index]}"
#         server_client_map["$client"]="$assigned_server"

#         # Move to the next server in a round-robin fashion
#         server_index=$(( (server_index + 1) % num_servers ))
#     done

#     # Execute the code on clients
#     for client in "${!machine_client_map[@]}"; do
#         partition="${partitions[index]}"
#         start=${partition%,*}  # Extract the first value (before comma)
#         end=${partition#*,}    # Extract the second value (after comma)

#         ip="${machine_server_map[${server_client_map[$client]}]#*@}"

#         echo
#         echo
#         echo
#         echo "Connecting to ${machine_client_map[$client]} with partition range $start to $end..."
#         echo "${machine_client_map[$client]}" 
#         echo "cd /home/mmanjee/code/color/sync; nohup ./color.sh $start $end $ip > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
#         ssh "${machine_client_map[$client]}" "cd /home/mmanjee/code/color/sync; nohup ./color.sh $start $end $ip 19> color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
#         # echo "cd /home/abhattar/code/color/1server; nohup ./color.sh $start $end $ip > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
#         ((index++))  # Move to the next partition
#         echo "$index"
#     done
# }



run_code_sync() {
    EXPERIMENT_START_TIME=$(date +%s)  # Add this line
    
    echo "---------------------------------------------------------------------------------------------------"
    echo "                 $(date) Executing Code in Clients                                                        "
    echo "---------------------------------------------------------------------------------------------------"
    generate_map
    
    local index=0
    declare -A server_client_map
    local server_index=0
    local num_servers=${#servers[@]}
    
    # Map clients to servers
    for client in "${clients[@]}"; do
        local assigned_server="${servers[$server_index]}"
        server_client_map["$client"]="$assigned_server"

        # Move to the next server in a round-robin fashion
        server_index=$(( (server_index + 1) % num_servers ))
    done

    # Execute the code on clients
    for client in "${!machine_client_map[@]}"; do
        partition="${partitions[index]}"
        start=${partition%,*}  # Extract the first value (before comma)
        end=${partition#*,}    # Extract the second value (after comma)

        ip="${machine_server_map[${server_client_map[$client]}]#*@}"

        echo
        echo
        echo
        echo "Connecting to ${machine_client_map[$client]} with partition range $start to $end..."
        echo "${machine_client_map[$client]}" 
        echo "cd /home/mmanjee/code/color/sync; nohup ./color.sh $start $end $ip > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
       
        ssh "${machine_client_map[$client]}" "cd /home/mmanjee/code/color/sync; nohup ./color.sh $start $end $ip 0 > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
        # echo "cd /home/abhattar/code/color/1server; nohup ./color.sh $start $end $ip > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
        ((index++))  # Move to the next partition
        echo "$index"
    done
}




close_servers() {
    generate_map
    echo
    echo "------------------------------------"
    echo "$(date) Closing SERVERS:"
    echo "------------------------------------"
    echo

    STARTING_SERVERS_START=$(date +%s)

    server_node_id_counter=0


    
    for key in "${!machine_server_map[@]}"
    do  
        echo "$key"
        destination=$key
         # Extract username from the value
         # Command to execute
        replicas=""
        for replica in ${replicas_map[$key]}; do
            replicas+="--replicaof $replica 6379 "
        done
        replicas="${replicas% }"  # Trim the trailing space
        echo $replicas
        echo "./fall_2025/KeyDB/src/keydb-server ./fall_2025/KeyDB/keydb.conf --multi-master yes --active-replica yes  $replicas;"
        
        # Run SSH command with a single block of shell commands
        
        output=$(ssh -n "$username@$destination" "pkill redis; pkill keydb;")
        
        # Check if the SSH command was successful and print output
        if [ $? -eq 0 ]; then
            echo "Server $destination responded with: $output"
        else
            echo "Failed to close server on $destination. Error: $?"
        fi
    done

   
} 


# run_keydbtester() {
#     echo "---------------------------------------------------------------------------------------------------"
#     echo "                  Executing Code in Clients                                                        "
#     echo "---------------------------------------------------------------------------------------------------"
#     generate_map
    
#     local index=0
#     declare -A server_client_map
#     local server_index=0
#     local num_servers=${#servers[@]}
    

#     # Execute the code on clients
#     for client in "${!machine_client_map[@]}"; do
#         partition="${partitions[index]}"
#         start=${partition%,*}  # Extract the first value (before comma)
#         end=${partition#*,}    # Extract the second value (after comma)

        
#         # echo "Connecting to ${machine_client_map[$client]} with partition range $start to $end..."
#         # echo "${machine_client_map[$client]}" "cd /home/abhattar/code/color;  ./client_tester.sh"
#         ssh "${machine_client_map[$client]}" "cd /home/abhattar/code/color;  ./client_tester.sh"
#         # echo "cd /home/abhattar/code/color/1server; nohup ./color.sh $start $end $ip > color_${start}_${end}.log 2>&1 & echo \$! > color_${start}_${end}.pid"
#         ((index++))  # Move to the next partition
#     done
# }

copy_client_logs() {
    generate_map
    display_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) Copying Logs into main server of clients"
    echo "-----------------------------------------------------------------------------------"
    echo

    target_directory="/home/mmanjee/code/color/sync"
    local_save_directory="/home/mmanjee/final/monitor/client_throughput"

    mkdir -p "$local_save_directory"  # Ensure local directory exists

    for key in "${!machine_client_map[@]}"
    do
        file_to_copy=$key"_throughput"  # Assuming log file is named 'keydb_log.log'
        destination=$key

        echo "Copying logs from $username@$destination..."

        local_time_start=$(date +%s)  # Start time tracking

        # Copy throughput log
        rsync -arzSH "$username@$destination:$target_directory/$file_to_copy.txt" "$local_save_directory/" 2>/dev/null
        
        # Copy execution time log
        rsync -arzSH "$username@$destination:$target_directory/$key.log" "$local_save_directory/" 2>/dev/null

        local_time_end=$(date +%s)  # End time tracking
        local_time_duration=$(( local_time_end - local_time_start ))

        echo "        ... done in $local_time_duration seconds"
        echo
        
        # Clean up old nohup logs after copying (optional)
        ssh -n "$username@$destination" "cd $target_directory && rm -f color_*.log color_*.pid" 2>/dev/null
    done
}


copy_logs() {
    generate_map
    display_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) Copying Logs into main server of servers"
    echo "-----------------------------------------------------------------------------------"
    echo

    target_directory="/home/mmanjee/fall_2025/KeyDB"
    local_save_directory="/home/mmanjee/final/monitor/server_throughput"

    mkdir -p "$local_save_directory"  # Ensure local directory exists

    for key in "${!machine_server_map[@]}"
    do
        file_to_copy=$key  # Assuming log file is named 'keydb_log.log'
        destination=$key

        echo "Copying logs from $username@$destination..."

        local_time_start=$(date +%s)  # Start time tracking

        # Copying file from remote to local
        rsync -arzSH "$username@$destination:$target_directory/$file_to_copy.log" "$local_save_directory/"

        local_time_end=$(date +%s)  # End time tracking
        local_time_duration=$(( local_time_end - local_time_start ))

        echo "        ... done in $local_time_duration seconds"
        echo
    done
}

log_server_throughput() {
    generate_map
    display_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) Logging Server Request Throughput Statistics"
    echo "-----------------------------------------------------------------------------------"
    echo

    local_save_directory="/home/mmanjee/final/monitor/server_throughput"
    mkdir -p "$local_save_directory"  # Ensure local directory exists

    timestamp=$(date '+%Y%m%d_%H%M%S')

    for key in "${!machine_server_map[@]}"
    do
        server_ssh="${machine_server_map[$key]}"
        output_file="${local_save_directory}/${key}_throughput_${timestamp}.log"
        
        echo "Fetching server throughput from $key..."

        {
            echo "=== Server Throughput: $key ==="
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            if [ -n "$EXPERIMENT_START_TIME" ]; then
                EXPERIMENT_END_TIME=$(date +%s)
                EXPERIMENT_DURATION=$((EXPERIMENT_END_TIME - EXPERIMENT_START_TIME))
                echo "Experiment start: $(date -d @$EXPERIMENT_START_TIME '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $EXPERIMENT_START_TIME '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A')"
                echo "Experiment elapsed time: $EXPERIMENT_DURATION seconds"
            fi
            echo ""
            echo "=== Command Statistics ==="
            ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO commandstats" 2>/dev/null || echo "ERROR: Failed to connect to KeyDB"
            echo ""
            echo "=== Overall Stats ==="
            ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO stats | grep -E 'total_commands_processed|instantaneous_ops_per_sec|total_reads_processed|total_writes_processed|keyspace_hits|keyspace_misses|uptime_in_seconds'" 2>/dev/null || echo "ERROR: Failed to fetch stats"
            echo ""
            echo "=== Clients Connected ==="
            ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost INFO clients | grep -E 'connected_clients|blocked_clients'" 2>/dev/null || echo "ERROR: Failed to fetch client info"
            echo ""
            echo "=== Client Connection Details ==="
            echo "All connections:"
            ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost CLIENT LIST" 2>/dev/null | head -20 || echo "ERROR: Failed to fetch client list"
            echo ""
            echo "Application clients only (excluding replication and localhost):"
            ssh -n "$server_ssh" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost CLIENT LIST | grep -v 'flags=[MS]' | grep -v 'addr=127.0.0.1'" 2>/dev/null || echo "No application clients connected"
        } > "$output_file"
        
        echo "        Server stats saved to: $output_file"
        echo
    done

    echo "All server throughput logs saved to: $local_save_directory"
    echo
}

pair_clients_to_servers
run_code_sync

# wait_for_completion
# close_servers
# delete_logs
# run_code_1_many
# copy_logs
# run_code_sync
# sleep 30
# close_servers
# run_keydbtester

EXPECTED_CLIENTS=${#clients[@]}
check_completion() {

    while true; do
        local COMPLETED
        COMPLETED=$($HOME/final/KeyDB/src/keydb-cli -h yangra101 KEYS "*_status" | wc -l)
        echo "Clients completed: $COMPLETED / $EXPECTED_CLIENTS"

        if [[ "$COMPLETED" -eq "$EXPECTED_CLIENTS" ]]; then
            echo "All clients have completed coloring!"
            break
        fi

        sleep 10 # Wait before checking again
    done
    #close_servers
    copy_client_logs
    copy_logs
    log_server_throughput
    
}

check_completion

#yangra10 yangra11 
# run_keydbtester