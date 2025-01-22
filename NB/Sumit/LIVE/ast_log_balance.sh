#!/usr/bin/bash

logdate=$(date --date="yesterday" '+%d_%m_%Y')
deldate=$(date -d "3 days ago" '+%d_%m_%Y')

logfile=/var/log/asterisk/full_$logdate
delfile=/var/log/asterisk/full_$deldate
filename='/var/log/asterisk/full'

if [! -f $logfile ];then
	touch $logfile
fi

cp $filename $logfile 
> $filename

if [ -f $delfile ];then
	rm $delfile
fi

echo $logfile, $delfile
