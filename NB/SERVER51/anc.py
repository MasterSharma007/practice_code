import os
import sys

subd = f"/var/lib/asterisk/static-http/config/Recordings/03-01-2025/17/"
files = os.listdir(subd)
print(len(files))
#for sf in files:
#	print(sf)
