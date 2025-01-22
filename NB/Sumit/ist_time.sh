#!/usr/bin/bash
server_datetime=$(date +%Y-%m-%d%H:%M:%S)
ist_datetime=$(TZ=Asia/Kolkata date +%Y-%m-%d%H:%M:%S)


if [ "$server_datetime" == "$ist_datetime" ]; then
	echo $server_datetime,"====" ,$ist_datetime
	echo "match"
else
	echo $server_datetime,"====" ,$ist_datetime
fi
