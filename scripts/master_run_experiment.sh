#!/bin/bash

# Assign arguments to variables
number_of_node=$1
start_node=$2
end_node=$3
num_partitions=$4
clients_string=$5
servers_string=$6
username=$7
dataset=$8



declare -A partitions
declare -A machine_client_map
declare -A machine_server_map

path_to_dataset="../graph/$dataset"


get_partition(){
    range=$((end_node - start_node + 1))
    partition_size=$((range / num_partitions))
    remaining=$((range % num_partitions))

    # Create the associative array
    

    current_start=$start_node

    for ((i = 1; i <= num_partitions; i++)); do
        # Determine the end of the current partition
        current_end=$((current_start + partition_size - 1))
        if ((remaining > 0)); then
            current_end=$((current_end + 1))
            remaining=$((remaining - 1))
        fi
        
        # Assign to the associative array
        partitions["Partition_$i"]="$current_start,$current_end"
        
        # Update the start node for the next partition
        current_start=$((current_end + 1))
    done

    # Output the partitions
    echo "Partitions:"
    for key in "${!partitions[@]}"; do
        echo "$key: ${partitions[$key]}"
    done

    echo 
    echo 
}

get_partition

IFS=',' read -r -a clients <<< "$clients_string"
IFS=',' read -r -a servers <<< "$servers_string"


display_map(){
    for key in "${!machine_server_map[@]}"; do
        echo " server $key : ${machine_server_map[$key]}"
    done

    for key in "${!machine_client_map[@]}"; do
        echo " client $key : ${machine_client_map[$key]}"
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
    
}



test_ssh(){
        generate_map
        echo "Attempting to SSH into each server and checking if redis is running on port 6379..."
        for key in "${!machine_server_map[@]}"; do
            echo "Connecting to ${machine_server_map[$key]}..."
            ssh "${machine_server_map[$key]}" "ss -tuln | grep ':6379'"
        done

        echo "Attempting to SSH into each client and checking if redis is running on port 6379..."
        for key in "${!machine_client_map[@]}"; do
            echo "Connecting to ${machine_client_map[$key]}..."
            ssh "${machine_client_map[$key]}" "cd fall_2024; ls -la"
        done


    }






bash master_start_other_machines.sh "${username}" "${dataset}" "${servers_string}" "${clients_string}" 




bash master_run_code.sh "${username}" "${dataset}" "${servers_string}" "${clients_string}"  "${partitions[@]}"