#!/bin/bash



  # Clients array (3 elements)
username=$1 # Username (single string)
dataset=$2             # The last argument is the username
servers_string=$3  # Servers array (just 1 element)
clients_string=$4 



IFS=',' read -r -a clients <<< "$clients_string"
IFS=',' read -r -a servers <<< "$servers_string"



#get_ip_normal(){ 
#    ip address | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.*.*.*' | grep -v '192.168.*.*' | grep -v '172.*.*.*'
#}


echo "------------------------------------------------------------------"
echo "              INSIDE START OTHER MACHINES                   "
echo "-------------------------------------------------------------------"
echo "Servers: ${servers[@]}"
echo "Clients: ${clients[@]}"
echo "Username: $username"
echo "Dataset: $dataset"

base_target_directory="$(pwd)"
base_target_directory="${base_target_directory%/*}"   
base_target_directory="$(basename $base_target_directory)"
echo "  base target directory =$base_target_directory"

compileTarFilename="keydb.tar.gz"

# Declare an associative array for machine_map
declare -A machine_server_map
declare -A machine_client_map
declare -A replicas_map 


display_map(){
    for key in "${!machine_server_map[@]}"; do
        echo " server $key : ${machine_server_map[$key]}"
    done

    for key in "${!machine_client_map[@]}"; do
        echo " client $key : ${machine_client_map[$key]}"
    done

    echo "Replica Mapping:"
    for key in "${!replicas_map[@]}"; do
        echo " $key replicates from: ${replicas_map[$key]}"
    done
}

generate_map(){

   server_node_id_counter=0
    for server in "${servers[@]}"; do
        machine_server_map["$server"]="${username}@$server.uwyo.edu"
    done

    client_node_id_counter=0
    for client in "${clients[@]}"; do
        machine_client_map["$client"]="${username}@$client.uwyo.edu"
    done

    # Generate replication map
    for server in "${servers[@]}"; do
        replicas_map["$server"]=""
        for replica in "${servers[@]}"; do
            if [[ "$server" != "$replica" ]]; then
                replicas_map["$server"]+="$replica "
            fi
        done
    done

    display_map


}

# Call generate_map to populate and display the mappings



test_ssh(){
    generate_map
echo "Attempting to SSH into each client..."
    for key in "${!machine_client_map[@]}"; do
        echo "Connecting to ${machine_client_map[$key]}..."
        ssh "${machine_client_map[$key]}" "ip addr"  
    done
echo "Attempting to SSH into each server..."

    for key in "${!machine_server_map[@]}"; do
        echo "Connecting to ${machine_server_map[$key]}..."
        ssh "${machine_server_map[$key]}" "ip addr"  
    done
}

# test_ssh


sync_graph_main_server(){
    generate_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) COPYING UPDATED GRAPH TO MAIN SERVER:"
    echo "-----------------------------------------------------------------------------------"
    echo
    for destination in "${!machine_server_map[@]}"; do
        echo "Syncing graph to $destination..."
        ssh $username@$destination "cd ~/fall_2025/graph; rm -rf *"
        rsync -arzSH "../graph/$dataset" "$username@$destination:~/fall_2025/graph/$dataset"

        if [ $? -eq 0 ]; then
            echo "Graph synced to $destination."
        else
            echo "Failed to sync graph to $destination."
        fi
    done
    echo ""

   
}


copy_code_to_server_machines(){

    generate_map
    
    cd ../KeyDB
    make clean
    cd ../scripts
  

    COPY_START=$(date +%s)
    echo
    echo
    echo "compressing code"
    cd ../../$base_target_directory
    echo
    echo "  compressing $base_target_directory"

    subdirlist="$(ls --ignore=results* --ignore=config_repository --ignore=config_data_repository --ignore=all_config_data_repository --ignore=graph_dataset --ignore=*.tar.xz --ignore=*.tar.gz .)"
    echo "  subdirlist:"
    for sd in $subdirlist
    do
        echo "      $sd"
    done

    echo
    echo "  + removing tar file $compileTarFilename"
    rm -f $compileTarFilename
    tar -zcf $compileTarFilename $subdirlist
    
    COMPRESS_END=$(date +%s)
    COMPRESS_DURATION=$(( $COMPRESS_END - $COPY_START ))
    echo "      ... done ($COMPRESS_DURATION seconds)"
    echo

    echo "--------------------------------------------------------------------------"
    echo "                        Copying into Servers                              "    
    echo "--------------------------------------------------------------------------"
    
    for key in "${!machine_server_map[@]}"
    do
        value=${machine_map[$key]}
        destination=$key
        
        role_list=${value#*@}
        target_directory="fall_2025"
        echo "        target_directory = $target_directory"
        

        ssh $username@$destination "mkdir -p $target_directory; cd $target_directory; rm -rf *"


        local_time_start=$(date +%s)


        #copying file to the nodes
        echo "        rsync-ing $compileTarFilename to $username@$destination ..."
        rsync -arzSH $compileTarFilename $username@$destination:~/$target_directory/  
        local_time_end=$(date +%s)
        local_time_duration=$(( $local_time_end - $local_time_start ))
        echo "        ... done in $local_time_duration seconds"
        
        #uncompressing files in the node
        local_time_start=$(date +%s)
        echo "        uncompressing ..."
        ssh $username@$destination "cd $target_directory; tar -zxf $compileTarFilename; cd KeyDB; make all"
        local_time_end=$(date +%s)
        local_time_duration=$(( $local_time_end - $local_time_start ))
        echo "        ... done in $local_time_duration seconds"
        echo
    done
  
    echo




}

start_servers() {
    generate_map
    echo
    echo "------------------------------------------------------------------------------------------------------------------------------------"
    echo "$(date) STARTING SERVERS:"
    echo "------------------------------------------------------------------------------------------------------------------------------------"
    echo

    STARTING_SERVERS_START=$(date +%s)

    server_node_id_counter=0
    
    for key in "${!machine_server_map[@]}"
    do  
        echo "$key"
        destination=$key
        replicas=""
        for replica in ${replicas_map[$key]}; do
            replicas+="--replicaof $replica 6379 "
        done
        replicas="${replicas% }"  # Trim the trailing space
        echo $replicas
         echo "STARTING SERVERS: in $destination"
        
        # Start server in daemon mode
        ssh -n "$username@$destination" "./fall_2025/KeyDB/src/keydb-server ./fall_2025/KeyDB/keydb.conf --multi-master yes --active-replica yes --logfile ./fall_2025/KeyDB/$key.log --daemonize yes $replicas"
        
        # Check if server started successfully
        if [ $? -eq 0 ]; then
            echo "Server $destination started successfully"
        else
            echo "Failed to start server on $destination."
        fi
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
        # echo $replicas
        # echo "./fall_2024/KeyDB/src/keydb-server ./fall_2024/KeyDB/keydb.conf --multi-master yes --active-replica yes  $replicas;"
        
        # Run SSH command with a single block of shell commands
        
        output=$(ssh -n "$username@$destination" "pkill redis; pkill -9 keydb;")
        # ssh -n "$username@$destination" " ./fall_2024/KeyDB/src/keydb-server ./fall_2024/KeyDB/keydb.conf ; " 
        
        # # Check if the SSH command was successful and print output
        if [ $? -eq 0 ]; then
            echo "Server $destination responded with: $output"
        else
            echo "Failed to close server on $destination."
        fi
    done
}   
# Add this log function BEFORE store_graph_in_servers()
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOGFILE"
}   

store_graph_in_servers() {
    generate_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) STORE GRAPH DATASET ON  SERVERS:"
    echo "-----------------------------------------------------------------------------------"
    echo

    STORING_GRAPH_IN_SERVERS_START=$(date +%s)

    # Step 1: Generate protocol file once locally using Ruby (as per KeyDB documentation)
    local protocol_file="/tmp/graph_protocol_${RANDOM}.txt"
    
    # Use absolute path to graph file (same structure as servers: ~/fall_2025/graph/)
    local graph_file="$HOME/final/Distributed_Graph_Coloring/graph/$dataset"
    
    echo "Generating KeyDB protocol file using Python (matching documentation pattern)..."
    echo "Graph file: $graph_file"
    
    if [ ! -f "$graph_file" ]; then
        echo "ERROR: Graph file not found: $graph_file"
        exit 1
    fi
    
    # Generate protocol file using Python (matching KeyDB documentation pattern)
    # Python equivalent of Ruby gen_redis_proto function from documentation
    local python_script="/tmp/gen_protocol_${RANDOM}.py"
    cat > "$python_script" << 'PYTHON_EOF'
import sys

def gen_redis_proto(*cmd):
    proto = ""
    proto += "*" + str(len(cmd)) + "\r\n"
    for arg in cmd:
        proto += "$" + str(len(str(arg))) + "\r\n"
        proto += str(arg) + "\r\n"
    return proto

# Read CSV graph file and generate protocol
nodes = {}
edges = []

with open(sys.argv[1], 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        
        parts = line.split(',')
        if len(parts) != 2:
            continue
        
        n1 = parts[0].strip()
        n2 = parts[1].strip()
        if not n1 or not n2:
            continue
        
        nodes[n1] = True
        nodes[n2] = True
        edges.append((n1, n2))

# Generate SET commands for node colors
for node in nodes:
    sys.stdout.write(gen_redis_proto("SET", "node_" + node + "_color", "0"))

# Generate SADD commands for neighbor relationships
for n1, n2 in edges:
    sys.stdout.write(gen_redis_proto("SADD", "node_" + n1 + "_neighbours", n2))
    sys.stdout.write(gen_redis_proto("SADD", "node_" + n2 + "_neighbours", n1))
PYTHON_EOF
    
    python3 "$python_script" "$graph_file" > "$protocol_file"
    rm -f "$python_script"
    
    if [ ! -f "$protocol_file" ] || [ ! -s "$protocol_file" ]; then
        echo "ERROR: Failed to generate protocol file"
        exit 1
    fi
    
    local file_size=$(wc -c < "$protocol_file")
    echo "Protocol file generated: $file_size bytes"
    echo ""
    
    # Step 2: Copy protocol file to all servers and load using cat | keydb-cli --pipe
    for destination in "${!machine_server_map[@]}"; do
        echo "Loading graph on $destination..."
        
        # Copy protocol file to server
        echo "  Copying protocol file to $destination..."
        scp -q "$protocol_file" "$username@$destination:/tmp/graph_protocol.txt" || {
            echo "ERROR: Failed to copy protocol file to $destination"
            continue
        }
        
        # Load using exactly as documentation: cat data.txt | keydb-cli --pipe
        ssh -n "$username@$destination" "
            cd ~/fall_2025 || exit 1
            
            # Verify KeyDB is ready
            if ! ./KeyDB/src/keydb-cli -h localhost PING > /dev/null 2>&1; then
                echo \"ERROR: KeyDB on $destination is not ready\"
                exit 1
            fi
            
            # Get initial key count
            initial_keys=\$(./KeyDB/src/keydb-cli -h localhost DBSIZE 2>/dev/null | grep -o '[0-9]*')
            echo \"  Initial keys: \$initial_keys\"
            
            # Load using exactly as documentation shows: cat data.txt | keydb-cli --pipe
            echo \"  Loading protocol file into KeyDB...\"
            cat /tmp/graph_protocol.txt | ./KeyDB/src/keydb-cli -h localhost --pipe
            
            # Get final key count
            final_keys=\$(./KeyDB/src/keydb-cli -h localhost DBSIZE 2>/dev/null | grep -o '[0-9]*')
            echo \"  Final keys: \$final_keys\"
            
            # Verify keys were actually added (or at least present)
            if [ \"\$final_keys\" -eq \"0\" ]; then
                echo \"ERROR: No keys present on $destination after loading!\"
                exit 1
            fi
            
            # Clean up protocol file on server
            rm -f /tmp/graph_protocol.txt
        " || {
            echo "ERROR: Failed to load graph on $destination"
            continue
        }
        
        echo "Graph loaded on $destination"
        echo ""
    done
    
    # Clean up local protocol file
    rm -f "$protocol_file"

    STORING_GRAPH_IN_SERVERS_END=$(date +%s)
    STORING_GRAPH_IN_SERVERS_DURATION=$(( $STORING_GRAPH_IN_SERVERS_END - $STORING_GRAPH_IN_SERVERS_START ))
    echo "Graph stored in servers in $STORING_GRAPH_IN_SERVERS_DURATION seconds"
}

# store_graph_in_servers() {
#     generate_map
#     echo
#     echo "---------------------------------------------------------------------------------"
#     echo "$(date) STORE GRAPH DATASET ON  SERVERS:"
#     echo "-----------------------------------------------------------------------------------"
#     echo

#     STARTING_SERVERS_START=$(date +%s)

#     server_node_id_counter=0
  
   
#     # echo "./fall_2024/KeyDB/src/keydb-cli add_graph $path" 
#     # ssh -n "$username@yangra4" "./fall_2024/KeyDB/src/keydb-cli ping" /home/abhattar/Desktop/project_fall_sem/graph/edge_graph_youtube_connection_n1134890.txt
# #/home/abhattar/Desktop/project_fall_sem/graph/edge_graph_dblp_coauthorship_n317080.txt
#     ssh -n "$username@lhotse4" "./fall_2025/KeyDB/src/keydb-cli add_graph /home/mmanjee/fall_2025/graph/simple_graph.txt" 
# }

copy_code_to_client_machines(){

    generate_map
    base_target_directory="$(pwd)"
    base_target_directory="${base_target_directory%/*}"   
    base_target_directory="$(basename $base_target_directory)"
    echo "  base target directory =$base_target_directory"

    compileTarFilename="code.tar.gz"
    
  

    COPY_START=$(date +%s)
    echo
    echo
    echo "compressing code"
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    echo
    echo "  compressing $base_target_directory"
    
    subdirlist="$(ls --ignore=results* --ignore=config_repository --ignore=config_data_repository --ignore=all_config_data_repository --ignore=graph_dataset --ignore=*.tar.xz --ignore=*.tar.gz .)"
    echo "  subdirlist:"
    for sd in $subdirlist
    do
        echo "      $sd"
    done
    sd="color"
    echo
    echo "  + removing tar file $compileTarFilename"
    rm -f $compileTarFilename
    tar -zcf $compileTarFilename $sd
    
    COMPRESS_END=$(date +%s)
    COMPRESS_DURATION=$(( $COMPRESS_END - $COPY_START ))
    echo "      ... done ($COMPRESS_DURATION seconds)"
    echo


    echo
    echo "----------------------------------------------------------------------------------------------------------------"
    echo $(date) " COPYING CODE TO Client"
    echo "----------------------------------------------------------------------------------------------------------------"
    echo

    for key in "${!machine_client_map[@]}"
    do
        value=${machine_map[$key]}
        destination=$key
       
        role_list=${value#*@}
        target_directory="code"
        echo "        target_directory = $target_directory"
        echo " here here  $username@$destination"

        ssh $username@$destination "mkdir -p $target_directory; cd $target_directory; rm -rf *"


        local_time_start=$(date +%s)


        #copying file to the nodes
        echo "        rsync-ing $compileTarFilename to $username@$destination ..."
        rsync -arzSH $compileTarFilename $username@$destination:~/$target_directory/  
        local_time_end=$(date +%s)
        local_time_duration=$(( $local_time_end - $local_time_start ))
        echo "        ... done in $local_time_duration seconds"
        
        #uncompressing files in the node
        local_time_start=$(date +%s)
        echo "        uncompressing ..."
        ssh $username@$destination "cd $target_directory; tar -zxf $compileTarFilename;"

        local_time_end=$(date +%s)
        local_time_duration=$(( $local_time_end - $local_time_start ))
        echo "        ... done in $local_time_duration seconds"
        echo
    done
    



}


delete_logs(){
    generate_map
    echo "--------------------------------------------------------------------------"
    echo "                       Deleting Logs on Servers                           "    
    echo "--------------------------------------------------------------------------"
    
    for key in "${!machine_server_map[@]}"
    do
        value=${machine_map[$key]}
        destination=$key
        
        role_list=${value#*@}
        target_directory="fall_2025"
        echo "Deleting Logs on $key"
        

        ssh $username@$destination "cd ~/fall_2025/KeyDB; rm $key.log"


       
        if [ $? -eq 0 ]; then
            echo "Logs deleted on $destination."
        else
            echo "Failed to delete logs on $destination."
        fi
    done

}


copy_logs() {
    generate_map
    display_map
    echo
    echo "---------------------------------------------------------------------------------"
    echo "$(date) Copying Logs into main server"
    echo "-----------------------------------------------------------------------------------"
    echo

    target_directory="~/fall_2025/KeyDB"
    local_save_directory="/home/mmanjee/final/monitor"

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


delete_database(){
    generate_map
    echo "--------------------------------------------------------------------------"
    echo "                       Deleting RDB Files on Servers                      "    
    echo "--------------------------------------------------------------------------"
    
    for key in "${!machine_server_map[@]}"
    do
        destination=$key
        
        echo "Deleting RDB files on $key"
        
        # Delete RDB files from common locations
        ssh $username@$destination "
            # Delete from KeyDB directory
            rm -f ~/fall_2025/KeyDB/*.rdb 2>/dev/null
            # Delete from current directory (if KeyDB was run from there)
            rm -f ~/*.rdb 2>/dev/null
            # Also clear in-memory database if server is running (optional)
            ~/fall_2025/KeyDB/src/keydb-cli -h localhost FLUSHALL 2>/dev/null || true
            echo 'RDB files deleted on $key'
        "
    done
}



close_servers #stop old servers
delete_database #delete old database
delete_logs #delete old logs

#copy_code_to_server_machines
sync_graph_main_server
copy_code_to_client_machines

start_servers

# Wait for servers to be ready but load graph BEFORE full replication sync
echo "Waiting for KeyDB servers to be ready..."
generate_map
for destination in "${!machine_server_map[@]}"; do
    echo "Checking $destination..."
    for i in {1..30}; do
        if ssh -n "$username@$destination" "cd ~/fall_2025 && ./KeyDB/src/keydb-cli -h localhost PING > /dev/null 2>&1"; then
            echo "$destination is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "WARNING: $destination did not become ready after 15 seconds"
        fi
        sleep 5
    done
done

# Load graph IMMEDIATELY after servers are ready (before replication fully syncs)
echo "Loading graph on all servers..."
store_graph_in_servers

# Wait for replication to sync - let it sync naturally without checking
echo "Waiting for replication to sync loaded graph..."
echo "Replication will sync automatically - allowing time for propagation..."
sleep 600