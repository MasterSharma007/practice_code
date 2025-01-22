#!/usr/bin/bash

#0 0 */6 * *
current_date_time=$(date)
NEW_expration_DATE=$(date -d "+4 days")

filename='/home/Sumit/full'
#filename='/var/log/asterisk/full'
echo "File log removed on $current_date_time and will be remove on $NEW_expration_DATE" > "$filename"
