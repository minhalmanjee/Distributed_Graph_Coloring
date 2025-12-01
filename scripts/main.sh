#!/bin/bash
#./main.sh [graph_file] [num_nodes] [start_node] [end_node] [edges]

#Default Values
DEFAULT_GRAPH="simple_graph.txt" #graph file
DEFAULT_NODES=100000 #number of nodes
DEFAULT_START=0 #start node
DEFAULT_END=99999 #end node
DEFAULT_EDGES=2497952 #number of edges

#send args CLI
#send args CLI
dataset=${1:-$DEFAULT_GRAPH}
number_of_node=${2:-$DEFAULT_NODES}
start_node=${3:-$DEFAULT_START}
end_node=${4:-$DEFAULT_END}
number_of_edges=${5:-$(wc -l < "../graph/$dataset" | tr -d ' ')}



if [ ! -f "../graph/$dataset" ]; then
    echo "graph file not present in ../graph directory"
    echo "current graphs available are:"
    ls -l ../graph/*.txt
    exit 1
fi

clients=("lhotse101" "lhotse102" "nuptse1" "nuptse2" "nuptse3" "manaslu1" "manaslu2" "manaslu3" "manaslu4" "manaslu5" "manaslu6" "manaslu7" "manaslu8" "manaslu9" "manaslu10")

# "manaslu7" "manaslu8" "manaslu9" "manaslu10" "manaslu11" "manaslu12" "lhotse3" "lhotse4" "nuptse1" "nuptse2" "nuptse3" "nuptse4" "nuptse5" "nuptse6")
          
            #  "manaslu2" "manaslu3"
            # "manaslu4" "manaslu5" "manaslu6"
            # "manaslu8" "manaslu9" "manaslu10"
            # "manaslu11" "manaslu12" "lhotse3")

# servers=("yangra4" "yangra2" "yangra3")
servers=("lhotse4" "lhotse3" "nuptse4" "manaslu11" "manaslu12")
username="mmanjee"


partition=${#clients[@]}

# Convert arrays to comma-separated strings
clients_string=$(IFS=','; echo "${clients[*]}")
servers_string=$(IFS=','; echo "${servers[*]}")


echo "================================================"
echo "Graph: $dataset"
echo "Number of Nodes: $number_of_node"
echo "Number of Edges: $number_of_edges"
echo "Start Node: $start_node"
echo "End Node: $end_node"
echo "Number of Edges: $number_of_edges"
echo "================================================"


# Debug: Print variables being passed
# echo "$number_of_node"
# echo "$number_of_edges"
# echo "$servers_string"
# echo "$clients_string"

# Pass variables and arrays to master_run_experiment.sh
bash master_run_experiment.sh $number_of_node $start_node $end_node $partition "$clients_string" "$servers_string" "$username" "$dataset"

#Verification
bash verify_c.sh $number_of_node $start_node $end_node $partition "$clients_string" "$servers_string" "$username"