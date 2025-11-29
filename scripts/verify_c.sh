#!/bin/bash

# Wrapper script to use C verification program (much faster than bash script)

if [ $# -lt 7 ]; then
    echo "Usage: $0 <number_of_node> <start_node> <end_node> <partition> <clients_string> <servers_string> <username>"
    exit 1
fi

number_of_node=$1
start_node=$2
end_node=$3
partition=$4
clients_string=$5
servers_string=$6
username=$7

IFS=',' read -r -a servers <<< "$servers_string"

# Use first server for verification
first_server="${servers[0]}"

echo "================================================"
echo "VERIFICATION (Using C Program)"
echo "================================================"
echo "Server: $first_server"
echo "Node range: $start_node to $end_node"
echo ""

# Check if verify executable exists
VERIFY_BIN="$HOME/final/Distributed_Graph_Coloring/color/sync/verify"
if [ ! -f "$VERIFY_BIN" ]; then
    echo "ERROR: Verify program not found at $VERIFY_BIN"
    echo "Please compile it first: cd ~/final/Distributed_Graph_Coloring/color/sync && gcc -o verify verify.c -lhiredis"
    exit 1
fi

# Copy verify.c to server and compile it there
echo "Copying verify.c to server and compiling..."
scp -q "$HOME/final/Distributed_Graph_Coloring/color/sync/verify.c" "${username}@${first_server}.uwyo.edu:~/fall_2025/color/sync/verify.c" 2>/dev/null || {
    echo "ERROR: Failed to copy verify.c to server"
    exit 1
}

# Compile on server
ssh -n "${username}@${first_server}.uwyo.edu" "
    cd ~/fall_2025/color/sync 2>/dev/null || cd ~/fall_2025 2>/dev/null
    if [ ! -f verify.c ]; then
        echo 'ERROR: verify.c not found on server'
        exit 1
    fi
    echo 'Compiling verify.c...'
    gcc -o verify verify.c -lhiredis -I/usr/include/hiredis -L/usr/lib -Wl,-rpath,/usr/lib 2>&1
    if [ \$? -ne 0 ]; then
        echo 'ERROR: Compilation failed'
        exit 1
    fi
    echo 'Compilation successful'
" || {
    echo "ERROR: Failed to compile verify.c on server"
    exit 1
}

echo ""
echo "Running C verification program..."
echo ""

# Run verification on server
ssh -n "${username}@${first_server}.uwyo.edu" "
    cd ~/fall_2025/color/sync 2>/dev/null || cd ~/fall_2025 2>/dev/null
    if [ ! -f ./verify ]; then
        echo 'ERROR: Verify program not found'
        exit 1
    fi
    ./verify localhost $start_node $end_node $username
"

