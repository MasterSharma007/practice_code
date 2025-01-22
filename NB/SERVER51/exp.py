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
        print(day,type(day))
        subd = f"/var/lib/asterisk/static-http/config/Recordings/"
        dirs = os.listdir(subd)
        date_format = "%d-%m-%Y"
        for sf in dirs:
                #print(sf,type(sf))
                if datetime.strptime(sf,date_format) > datetime.strptime(day,date_format):
                        print(sf)
except Exception as err:
	print(err)
