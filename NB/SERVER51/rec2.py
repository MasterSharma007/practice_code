#!/usr/bin/python

import re
import sys
#import json
import threading
import time
import os
import subprocess
#import ast
#import base64

def PROG_DIAL(id_,fil):

	print(f"thread with id: {id_} started, {fil}")
	while (1):
		subd = f"/var/lib/asterisk/static-http/config/Recordings/{fil}/"
		files = os.listdir(subd)
		#print("START", id_,len(files))
		for sf in files:
			try:
				cmd = f"aws s3 ls s3://max-callrecords/recordings/{fil}/{sf}"
				#print(cmd)
				res = os.system(cmd)
				#res = subprocess.run([cmd],stdout=subprocess.PIPE, stderr=subprocess.PIPE,universal_newlines=True)
				#print(cmd)
				#print("RESULT",id_,cmd,res.returncode,res.stdout)
				print("RESULT",id_,cmd,res,type(res))
				if res == 256:
					print(f"{fil}/{sf}")
					cmd = f"aws s3 --region ap-south-1 --endpoint-url https://bucket.vpce-01e414640e8a4ff76-rp1v14wv.s3.ap-south-1.vpce.amazonaws.com/ mv /var/lib/asterisk/static-http/config/Recordings/{fil}/{sf} s3://max-callrecords/recordings/{fil}/{sf}"
					print(cmd)
					res1 = os.system(cmd)
					if not res1:
						cmd = f"rm -rf /var/lib/asterisk/static-http/config/Recordings/{fil}/{sf}"
						res2 = os.system(cmd)
			except Exception as err:
				print("ERROR",cmd ,err)
			time.sleep(1)
		time.sleep(2000000)

func = {}
day = "12-01-2025"
#day = "03-01-2025"
parent_directory = f"/var/lib/asterisk/static-http/config/Recordings/{day}"
subfolders = [os.path.join(parent_directory, name) for name in os.listdir(parent_directory) if os.path.isdir(os.path.join(parent_directory, name))]
i=1
data = {'08':PROG_DIAL,'09':PROG_DIAL,'10':PROG_DIAL,'11':PROG_DIAL,'12':PROG_DIAL,'13':PROG_DIAL,'14':PROG_DIAL,'15':PROG_DIAL,'16':PROG_DIAL,'17':PROG_DIAL,'18':PROG_DIAL,'19':PROG_DIAL,'20':PROG_DIAL,'21':PROG_DIAL}
for folder in subfolders:
        dd = os.path.basename(folder.rstrip('/'))
        func[dd] = []
        func[dd].append(data[dd])
        func[dd].append((i,))
        i+=1

#print(func)
while 1:
	
	THLIST = [x.name for x in threading.enumerate()]

	for fname, fargs in func.items():
		if fname not in THLIST:
			cday = f"{day}/{fname}"
			thr = threading.Thread(target=fargs[0], args=(fargs[1],cday), name=fname)
			thr.start()

	time.sleep(5)


