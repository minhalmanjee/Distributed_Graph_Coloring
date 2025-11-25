#!/bin/bash

clients=("lhotse101" "lhotse102" "nuptse1" "nuptse2") #4 clients 

# "manaslu7" "manaslu8" "manaslu9" "manaslu10" "manaslu11" "manaslu12" "lhotse3" "lhotse4" "nuptse1" "nuptse2" "nuptse3" "nuptse4" "nuptse5" "nuptse6")
          
            #  "manaslu2" "manaslu3"
            # "manaslu4" "manaslu5" "manaslu6"
            # "manaslu8" "manaslu9" "manaslu10"
            # "manaslu11" "manaslu12" "lhotse3")

# servers=("yangra4" "yangra2" "yangra3")
servers=("lhotse4" "lhotse3")
username="mmanjee"
dataset="simple_graph.txt"

number_of_node=5
number_of_edges=10
start_node=0
end_node=4
# end_node=3223585
# end_node=1134889
partition=4

# Convert arrays to comma-separated strings
clients_string=$(IFS=','; echo "${clients[*]}")
servers_string=$(IFS=','; echo "${servers[*]}")

# Debug: Print variables being passed
# echo "$number_of_node"
# echo "$number_of_edges"
# echo "$servers_string"
# echo "$clients_string"

# Pass variables and arrays to master_run_experiment.sh
bash master_run_experiment.sh $number_of_node $start_node $end_node $partition "$clients_string" "$servers_string" "$username" "$dataset"