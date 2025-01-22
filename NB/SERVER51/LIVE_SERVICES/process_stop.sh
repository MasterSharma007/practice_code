#!/bin/bash

# List of script names to terminate
scripts=("previous_rec.py" "upload_recording.py")

# Loop through each script and kill its process
for script in "${scripts[@]}"; do
    echo "Killing all instances of $script..."
    
    # Find the process ID (PID) and kill it
    pids=$(ps aux | grep "$script" | grep -v "grep" | awk '{print $2}')
    
    if [ -n "$pids" ]; then
        echo "Killing PIDs: $pids"
        kill -9 $pids
        echo "$script terminated successfully."
    else
        echo "No running process found for $script."
    fi
done

