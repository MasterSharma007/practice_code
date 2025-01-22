#!/usr/bin/python

import re
import sys
import time
import os
import subprocess
from datetime import datetime, timedelta


subd = "/var/spool/asterisk/monitor/"
files = os.listdir(subd)
a=1
try:
	for sf in files:
		if sf.startswith("REC"):
			#print(sf)
			wav_file = f"/var/spool/asterisk/monitor/{sf}"
			result = subprocess.run(
				["sox", "--i", "-D", wav_file],
        			stdout=subprocess.PIPE,
        			stderr=subprocess.PIPE,
        			check=True
    				)
			duration = float(result.stdout.strip())
			if duration > 100:
				#print(f"Duration of '{sf}' is {duration:.2f} seconds.")
				a = a+duration
				#cmd = f"mv /var/spool/asterisk/monitor/{sf} /var/spool/asterisk/monitor/STEREO/"
				print(a)	
				#res = subprocess.run([cmd], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
			else:
				cmd = f"rm -rf {wav_file}"
				print(cmd)	
				os.system(cmd)
			

	print(a)
except Exception as err:
	print("ERROR",err)

