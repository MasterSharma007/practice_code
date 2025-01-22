#!/usr/bin/python

import re
import sys
import time
import os

from datetime import datetime, timedelta

try:
	cur_date = datetime.now()
	yest = cur_date - timedelta(days=1)
	day = yest.strftime("%d_%m_%Y")

	before31 = cur_date - timedelta(days=31)
	day31 = before31.strftime("%d_%m_%Y")

	yesteday_ast_file = f"/var/log/asterisk/full_{day}"
	yesteday_140_file = f"/home/Sumit/BACKUP_140/140_{day}.txt"
	before31_140_file = f"/home/Sumit/BACKUP_140/140_{day31}.txt"

	print(yesteday_ast_file, yesteday_140_file, before31_140_file)
	if os.path.exists(yesteday_ast_file) and not os.path.exists(yesteday_140_file):
		cmd = f"cat {yesteday_ast_file} |grep \"OutH\" |grep \">140-\" > {yesteday_140_file}"
		print(cmd)
		res = os.system(cmd)

	if os.path.exists(before31_140_file):
		print("EXIST")
		cmd = f"rm -rf {before31_140_file}"
		res = os.system(cmd)

except Exception as err:
	print(err)
