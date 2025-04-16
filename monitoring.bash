#!/bin/bash

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] PROGRAM_NAME

Monitor CPU and memory usage of a specific program.

Options:
    -h, --help          Show this help message and exit
    
Arguments:
    PROGRAM_NAME        Name of the program to monitor

Examples:
    $(basename "$0") demo         # Monitor demo process
    $(basename "$0") --help        # Show this help message

    $ $(basename "$0") demo
    Found processes:
    1 root      7373  56.9  1.3  7510460 433356 pts/4  Sl+  Apr14 661:13 ./demo
    2 user      8142  12.3  0.5  5123456 125476 pts/2  Sl   Apr14  98:45 ./demo

    Select process number to monitor (1-2): 1
    Monitoring PID: 7373
    Time: 15:30:45    CPU: 58.25%    Memory: 1.32% (433.36 MB)
    Time: 15:30:46    CPU: 57.98%    Memory: 1.32% (433.36 MB)
    ^C
    === CPU Statistics ===
    Average CPU Usage: 58.12%
    Max CPU Usage: 58.25%
    Min CPU Usage: 57.98%

    === Memory Statistics ===
    Average Memory Usage: 1.32% (433.36 MB)
    Max Memory Usage: 1.32% (433.36 MB)
    Min Memory Usage: 1.32% (433.36 MB)

Features:
    - Shows real-time CPU and memory usage
    - Calculates min/max/average statistics
    - Handles multiple processes with same name
    - Supports process selection
    - Saves data to CSV format
    
Press Ctrl+C to stop monitoring and show statistics.
EOF
    exit 0
}

# Parse command line arguments
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

if [ $# -ne 1 ]; then
    echo "Error: Missing program name"
    echo "Try '$(basename "$0") --help' for more information."
    exit 1
fi

program=$1
# Get process list, exclude the script itself and grep
processes=$(ps aux | grep "$program" | grep -v "grep" | grep -v "$0")

if [ -z "$processes" ]; then
    echo "No processes found for $program"
    exit 1
fi

# Show process list
counter=1
echo "Found processes:"
while IFS= read -r line; do
    echo "$counter $line"
    ((counter++))
done <<< "$processes"

# User process selection
read -p "Select process number to monitor (1-$((counter-1))): " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$counter" ]; then
    echo "Invalid selection"
    exit 1
fi

# Get selected PID
pid=$(echo "$processes" | sed -n "${selection}p" | awk '{print $2}')
echo "Monitoring PID: $pid"

# Create temp file for data
temp_file=$(mktemp)
echo "Time,CPU%,Memory%,MemoryMB" > "$temp_file"

# Get system total memory (KB)
total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Function to get CPU usage
declare -A prev_cputime

get_cpu_usage() {
    local pid=$1
    local cpu_usage=0
    local num_cpus=$(nproc)

    # Get first sample with more detailed CPU stats
    local stat1=$(cat /proc/$pid/stat 2>/dev/null)
    [ $? -ne 0 ] && { echo "0.00"; return; }
    
    # Get system CPU stats (all fields)
    local sys_stat1=$(cat /proc/stat | grep '^cpu ')
    
    # Get process stats (including child processes)
    local utime1=$(echo "$stat1" | awk '{print $14}')
    local stime1=$(echo "$stat1" | awk '{print $15}')
    local cutime1=$(echo "$stat1" | awk '{print $16}')
    local cstime1=$(echo "$stat1" | awk '{print $17}')
    [ -z "$utime1" ] || [ -z "$stime1" ] || [ -z "$cutime1" ] || [ -z "$cstime1" ] && { echo "0.00"; return; }
    local proc_time1=$((utime1 + stime1 + cutime1 + cstime1))
    
    # Get detailed system time
    local sys_time1=$(echo "$sys_stat1" | awk '{for(i=2;i<=NF;i++) sum+=$i; print sum}')
    [ -z "$sys_time1" ] && { echo "0.00"; return; }

    # Longer sleep for more accurate measurements
    sleep 1

    # Get second sample
    local stat2=$(cat /proc/$pid/stat 2>/dev/null)
    [ $? -ne 0 ] && { echo "0.00"; return; }
    
    local sys_stat2=$(cat /proc/stat | grep '^cpu ')
    
    # Get process stats again
    local utime2=$(echo "$stat2" | awk '{print $14}')
    local stime2=$(echo "$stat2" | awk '{print $15}')
    local cutime2=$(echo "$stat2" | awk '{print $16}')
    local cstime2=$(echo "$stat2" | awk '{print $17}')
    [ -z "$utime2" ] || [ -z "$stime2" ] || [ -z "$cutime2" ] || [ -z "$cstime2" ] && { echo "0.00"; return; }
    local proc_time2=$((utime2 + stime2 + cutime2 + cstime2))
    
    # Get detailed system time again
    local sys_time2=$(echo "$sys_stat2" | awk '{for(i=2;i<=NF;i++) sum+=$i; print sum}')
    [ -z "$sys_time2" ] && { echo "0.00"; return; }

    # Calculate deltas using bc for floating point
    local proc_delta=$(awk -v p1="$proc_time1" -v p2="$proc_time2" 'BEGIN {print p2 - p1}')
    local sys_delta=$(awk -v s1="$sys_time1" -v s2="$sys_time2" 'BEGIN {print s2 - s1}')

    # Debug output
    {
        echo "DEBUG Values:"
        echo "  proc_time1: $proc_time1"
        echo "  proc_time2: $proc_time2"
        echo "  proc_delta: $proc_delta"
        echo "  sys_time1: $sys_time1"
        echo "  sys_time2: $sys_time2"
        echo "  sys_delta: $sys_delta"
        echo "-------------------"
    } >&2

    # Calculate CPU usage only if we have valid delta
    if [ $(echo "$sys_delta > 0" | bc) -eq 1 ]; then
        cpu_usage=$(echo "scale=2; ($proc_delta * 100) / $sys_delta" | bc)
    fi

    printf "%.2f" "$cpu_usage"
}

# Function to get memory usage
get_memory_info() {
    local pid=$1
    
    # Use ps to get memory info
    local mem_info=$(ps -p "$pid" -o rss --no-headers 2>/dev/null)
    if [ -n "$mem_info" ]; then
        local mem_kb=$(echo "$mem_info" | tr -d ' ' | grep -E '^[0-9]+$')
        if [ -n "$mem_kb" ]; then
            local mem_mb=$(echo "scale=2; $mem_kb / 1024" | bc)
            local mem_percent=$(echo "scale=2; 100 * $mem_kb / $total_memory" | bc)
            echo "$mem_percent $mem_mb"
        else
            echo "0 0"
        fi
    else
        echo "0 0"
    fi
}

# Trap CTRL+C
trap 'cleanup' INT TERM

# Cleanup function
cleanup() {
    echo -e "\nGenerating statistics..."
    awk -F',' '
        BEGIN {
            count = 0
            cpu_sum = 0
            mem_sum = 0
            mem_mb_sum = 0
            max_cpu = 0
            min_cpu = 999999
            max_mem = 0
            min_mem = 999999
            max_mem_mb = 0
            min_mem_mb = 999999
        }
        NR>1 {
            if ($2 != "" && $3 != "" && $4 != "") {
                cpu_sum += $2
                mem_sum += $3
                mem_mb_sum += $4
                count++
                
                if ($2 > max_cpu) max_cpu = $2
                if ($2 < min_cpu && $2 > 0) min_cpu = $2
                if ($3 > max_mem) max_mem = $3
                if ($3 < min_mem && $3 > 0) min_mem = $3
                if ($4 > max_mem_mb) max_mem_mb = $4
                if ($4 < min_mem_mb && $4 > 0) min_mem_mb = $4
            }
        }
        END {
            if (count > 0) {
                printf "\n=== CPU Statistics ===\n"
                printf "Average CPU Usage: %.2f%%\n", cpu_sum/count
                printf "Max CPU Usage: %.2f%%\n", max_cpu
                printf "Min CPU Usage: %.2f%%\n", min_cpu == 999999 ? 0 : min_cpu
                printf "\n=== Memory Statistics ===\n"
                printf "Average Memory Usage: %.2f%% (%.2f MB)\n", mem_sum/count, mem_mb_sum/count
                printf "Max Memory Usage: %.2f%% (%.2f MB)\n", max_mem, max_mem_mb
                printf "Min Memory Usage: %.2f%% (%.2f MB)\n", min_mem == 999999 ? 0 : min_mem, min_mem_mb == 999999 ? 0 : min_mem_mb
                printf "\nTotal Samples: %d\n", count
            } else {
                print "No data collected."
            }
        }
    ' "$temp_file"
    rm -f "$temp_file"
    exit 0
}

# Main monitoring loop
while kill -0 "$pid" 2>/dev/null; do
    if ! ps -p "$pid" >/dev/null 2>&1; then
        echo -e "\nProcess has terminated"
        break
    fi
    
    cpu=$(get_cpu_usage $pid)
    read mem_percent mem_mb <<< $(get_memory_info $pid)
    timestamp=$(date +"%H:%M:%S")

    # Validate CPU value
    if [[ ! "$cpu" =~ ^[0-9]+\.?[0-9]*$ ]] || [ $(echo "$cpu < 0" | bc) -eq 1 ]; then
        cpu="0.00"
    elif [ $(echo "$cpu > 100" | bc) -eq 1 ]; then
        cpu="100.00"
    fi
    
    # Log data even if zero to ensure collection
    echo "$timestamp,$cpu,$mem_percent,$mem_mb" >> "$temp_file"
    # Format output
    # printf "\033[2K\rTime: %s\tCPU: %6.2f%%\tMemory: %6.2f%% (%6.2f MB)" \
    #        "$timestamp" "$cpu" "$mem_percent" "$mem_mb"
    echo -e "Time: $timestamp\tCPU: ${cpu}%\tMemory: ${mem_percent}% (${mem_mb} MB)"
    
    # sleep 1
done

echo "" # New line after monitoring stops

# Show statistics if we have data
if [ -s "$temp_file" ] && [ "$(wc -l < "$temp_file")" -gt 1 ]; then
    cleanup
else
    echo "No data collected. Process may have terminated too quickly."
    rm -f "$temp_file"
    exit 1
fi
