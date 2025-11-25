#!/bin/bash

# Capture the start time
start_time=$(date +%s)
hostname=$(hostname)
number1=$1
number2=$2
ip_address=$3
 number_of_replicas=${4:-1}

echo "$number_of_replicas"
# Get the hostname
hostname=$(hostname)
# Define the log file path using the hostname
log_file="${hostname}.log"

color_log_file="${hostname}_color.log"
# Run the program


gcc -o color color.c -lhiredis
echo $number1 $number2 $ip_address $color_log_file $hostname $number_of_replicas
./color $number1 $number2 $ip_address $color_log_file $hostname $number_of_replicas



# Capture the end time
end_time=$(date +%s)

# Calculate the elapsed time
elapsed_time=$((end_time - start_time))

# Get the hostname of the computer (used as the log file name)

# echo "here"
# # Log the elapsed time to the log file
echo "Execution time: $elapsed_time seconds" >> "$log_file"

# # Optionally, print a message about where the log file is saved
echo "Log saved to $log_file"