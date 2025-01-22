import time
# Get the current time in seconds since the epoch and adjust for IST (UTC+5:30)
current_time_seconds = time.time() + (5.5 * 3600)
# Convert current time in seconds to a struct_time
current_time_struct = time.gmtime(current_time_seconds)
# Extract hour, minute, and second
current_hour = current_time_struct.tm_hour
current_minute = current_time_struct.tm_min
current_second = current_time_struct.tm_sec
# Define the start and end times in 24-hour format (example: 09:00:00 to 17:00:00)
start_time = (9, 0, 0)   # (Hour, Minute, Second)
end_time = (23, 0, 0)    # (Hour, Minute, Second)
# Check if current time is within the range
if start_time <= (current_hour, current_minute, current_second) <= end_time:
    print("Current time is within the declared time range.")
else:
    print("Current time is outside the declared time range.")

