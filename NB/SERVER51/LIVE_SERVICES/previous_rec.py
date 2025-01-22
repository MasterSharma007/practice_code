#!/usr/bin/python

import re
import sys
import time
import os
import subprocess
from datetime import datetime, timedelta


try:
	
	cur_date = datetime.now()
	before3 = cur_date - timedelta(days=10)
	day = before3.strftime("%d-%m-%Y")
	#print(day,type(day))
	subd = f"/var/lib/asterisk/static-http/config/Recordings/"
	dirs = os.listdir(subd)
	date_format = "%d-%m-%Y"
	#print(dirs)
	for sf in dirs:
		#print(sf,type(sf))
		if datetime.strptime(sf,date_format) < datetime.strptime(day,date_format):
			print(sf)
			subd1 = f"/var/lib/asterisk/static-http/config/Recordings/{sf}/"
			subdirs = os.listdir(subd1)
			for sf1 in subdirs:
				#print(sf1)
				subd2 = f"/var/lib/asterisk/static-http/config/Recordings/{sf}/{sf1}/"
				files = files = os.listdir(subd2)
				for sf2 in files:
					#print(sf2)
					cmd = f"aws s3 ls s3://max-callrecords/recordings/{sf}/{sf1}/{sf2}"
					#print(cmd)
					res = os.system(cmd)
					if res == 256:
						print(f"NOT_EXIST")
						cmd = f"aws s3 --region ap-south-1 --endpoint-url https://bucket.vpce-01e414640e8a4ff76-rp1v14wv.s3.ap-south-1.vpce.amazonaws.com/ mv /var/lib/asterisk/static-http/config/Recordings/{sf}/{sf1}/{sf2} s3://max-callrecords/recordings/{sf}/{sf1}/{sf2}"
						#print(cmd)
						res1 = os.system(cmd)
						if not res1:
							cmd = f"rm -rf /var/lib/asterisk/static-http/config/Recordings/{sf}/{sf1}/{sf2}"
							print(cmd)
							res2 = os.system(cmd)
					else:
						print(f"EXIST")
						cmd = f"rm -rf /var/lib/asterisk/static-http/config/Recordings/{sf}/{sf1}/{sf2}"
						#print(cmd)
						res2 = os.system(cmd)
						
					time.sleep(0.1)
				time.sleep(0.1)
			cmd1 = f"rm -rf /var/lib/asterisk/static-http/config/Recordings/{sf}"
			res3 = os.system(cmd1)
		time.sleep(1)
except Exception as err:
	print("ERROR",err)

#cur_date = datetime.now()
#before3 = cur_date - timedelta(days=10)
#day = before3.strftime("%d-%m-%Y")
#print(day)
#day = "09-01-2025"
#day = "03-01-2025"
#parent_directory = f"/var/lib/asterisk/static-http/config/Recordings/{day}"
#subfolders = [os.path.join(parent_directory, name) for name in os.listdir(parent_directory) if os.path.isdir(os.path.join(parent_directory, name))]
#dd = os.path.basename(folder.rstrip('/'))



