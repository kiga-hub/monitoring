# Process Monitor Script

A Bash script for monitoring CPU and memory usage of specific processes in real-time.

## Features

- Real-time monitoring of process CPU and memory usage
- Statistical analysis (min/max/average) of resource usage
- Support for multiple processes with the same name
- Process selection interface
- CSV format data logging
- Clean exit with statistics summary (Ctrl+C)

## Requirements

- Unix/Linux operating system
- Bash shell
- Core utilities: ps, awk, grep, bc

## Usage

### Basic Command

```bash
./monitor.sh PROGRAM_NAME
```

### Options

- `-h, --help`: Display help message and exit

### Examples

1. Monitor a process named "demo":
```bash
./monitor.sh demo
```

2. Show help information:
```bash
./monitor.sh --help
```

### Sample Output

```plaintext
Found processes:
1 root      7373  56.9  1.3  7510460 433356 pts/4  Sl+  Apr14 661:13 ./demo
2 user      8142  12.3  0.5  5123456 125476 pts/2  Sl   Apr14  98:45 ./demo

Select process number to monitor (1-2): 1
Monitoring PID: 7373
Time: 15:30:45    CPU: 58.25%    Memory: 1.32% (433.36 MB)
Time: 15:30:46    CPU: 57.98%    Memory: 1.32% (433.36 MB)

=== CPU Statistics ===
Average CPU Usage: 58.12%
Max CPU Usage: 58.25%
Min CPU Usage: 57.98%

=== Memory Statistics ===
Average Memory Usage: 1.32% (433.36 MB)
Max Memory Usage: 1.32% (433.36 MB)
Min Memory Usage: 1.32% (433.36 MB)
```

## Data Collection

The script collects the following metrics:
- Timestamp
- CPU usage percentage
- Memory usage percentage
- Memory usage in MB

All data is temporarily stored in CSV format and automatically cleaned up after monitoring ends.

## Statistics

When monitoring is terminated (Ctrl+C), the script displays:
- CPU usage: average, maximum, minimum
- Memory usage: average (MB), maximum (MB), minimum (MB)
- Total number of samples collected

## Important Notes

1. Sufficient permissions are required to read process information
2. Script exits with error for non-existent process names
3. Monitoring automatically stops if target process terminates


This README provides comprehensive documentation of the script's functionality, usage, and features. You can customize the License and Author sections according to your needs.
