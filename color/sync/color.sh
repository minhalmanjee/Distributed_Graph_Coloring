#!/bin/bash

# Capture the start time
start_time=$(date +%s)
hostname=$(hostname)
number1=$1
number2=$2
ip_address=$3
number_of_replicas=${4:-0}

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

# Log detailed timing information
{
    echo "=== Client Timing Information ==="
    echo "Start time: $(date -d @$start_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $start_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A')"
    echo "End time: $(date -d @$end_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $end_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A')"
    echo "Execution time: $elapsed_time seconds"
    echo "Hostname: $hostname"
    echo "Partition: nodes $number1 to $number2"
    echo "Server IP: $ip_address"
    echo "Replicas: $number_of_replicas"
} >> "$log_file"

# Calculate throughput from throughput log
throughput_file="${hostname}_throughput.txt"
if [ -f "$throughput_file" ]; then
    total_reads=$(grep -c "Read command" "$throughput_file" 2>/dev/null || echo "0")
    total_writes=$(grep -c "Write command" "$throughput_file" 2>/dev/null || echo "0")
    total_waits=$(grep -c "Wait command" "$throughput_file" 2>/dev/null || echo "0")
    total_ops=$((total_reads + total_writes))
    
    if [ "$elapsed_time" -gt 0 ]; then
        # Use awk for floating point division if available, otherwise use bc
        if command -v awk >/dev/null 2>&1; then
            read_throughput=$(awk "BEGIN {printf \"%.2f\", $total_reads / $elapsed_time}")
            write_throughput=$(awk "BEGIN {printf \"%.2f\", $total_writes / $elapsed_time}")
            total_throughput=$(awk "BEGIN {printf \"%.2f\", $total_ops / $elapsed_time}")
        elif command -v bc >/dev/null 2>&1; then
            read_throughput=$(echo "scale=2; $total_reads / $elapsed_time" | bc)
            write_throughput=$(echo "scale=2; $total_writes / $elapsed_time" | bc)
            total_throughput=$(echo "scale=2; $total_ops / $elapsed_time" | bc)
        else
            read_throughput="N/A (bc/awk not available)"
            write_throughput="N/A (bc/awk not available)"
            total_throughput="N/A (bc/awk not available)"
        fi
    else
        read_throughput="N/A"
        write_throughput="N/A"
        total_throughput="N/A"
    fi
    
    {
        echo ""
        echo "=== Client Throughput Statistics ==="
        echo "Total GET operations: $total_reads"
        echo "Total PUT operations: $total_writes"
        echo "Total WAIT operations: $total_waits"
        echo "Total operations: $total_ops"
        echo "GET throughput: $read_throughput ops/sec"
        echo "PUT throughput: $write_throughput ops/sec"
        echo "Total throughput: $total_throughput ops/sec"
    } >> "$log_file"
fi

# Optionally, print a message about where the log file is saved
echo "Log saved to $log_file"