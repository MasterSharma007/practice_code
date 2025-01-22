#!/usr/bin/python

import sys
import paramiko
import re
import configparser
import ast
import json
import time

config = configparser.ConfigParser()
config.read('config.ini')
contexts = config.sections()

final_data = {}

def check_status(conn):
	stdin, stdout, stderr = context.exec_command(f' asterisk -rx "sip show peer {conn}" |tail -n +2 |grep "Status"')
	conn_data = stdout.read().decode()
	if conn_data:
		if "OK" in conn_data:
			cmd = f"asterisk -rx \"core show channels\" |grep \"^SIP/{conn}\" |wc -l"
			stdin, stdout, stderr = context.exec_command(cmd)
			count = stdout.read().decode()
			count = count.replace('\n','')

			return("OK",count)
		else:
			return("RED",0)
	else:
		return("NOT_CONFIGURED",0)

try:
   
    object_list = {}
    for context in contexts:
        ip = config.get(context,'IP')
        usr = config.get(context,'USERNAME')
        paswd = config.get(context,'PASSWORD')
        sip = config.get(context,'SIP')
        gsm = config.get(context,'GSM')
        context_obj = paramiko.SSHClient()
        context_obj.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        context_obj.connect(ip,username=usr,password=paswd)
        object_list[context] = context_obj,sip,gsm 
         
    while(1):
        for ser, context_data in object_list.items():
            context = context_data[0]
            sip = context_data[1]
            gsm = context_data[2]
            #print(ser,context,sip,context_data,gsm)
            final_data1 = {}
            stdin, stdout, stderr = context.exec_command(' asterisk -rx "dahdi show status" |tail -n +2')
            pri_data = stdout.read().decode()
            pri = pri_data.split('\n')
            count=1
            for n in pri:
                if n:
                    spri = re.split('\\s+',n)
                    if spri[3] == "OK":
                        cmd = f"asterisk -rx \"core show channels\" |grep \"^DAHDI/i{count}\" |wc -l"
                        stdin, stdout, stderr = context.exec_command(cmd)
                        chcount = stdout.read().decode()
                        #print(ser, spri[0]," is RUNNING FINE. Busy channels are:", chcount)
                        chcount = chcount.replace('\n','')
                        final_data1[f"PRI_{spri[0]}"] = chcount
                                        
                    else:
                        #print(ser,spri[0]," is NOT RUNNING ." )
                        final_data1[f"PRI_{spri[0]}"] = spri[3]
                count+=1
            if sip:
                if "," in sip:
                    for ssip in (sip.split(",")):
                        status,count = check_status(ssip)
                        if status == "OK":
                            final_data1[f"SIP_{ssip}"] = count
                        else:
                            final_data1[f"SIP_{ssip}"] = status
                else:
                    status,count = check_status(sip)
                    if status == "OK":
                        final_data1[f"SIP_{sip}"] = count
                    else:
                        final_data1[f"SIP_{sip}"] = status
            if gsm:
                if "," in gsm:
                    for sgsm in (gsm.split(",")):
                        status,count = check_status(sgsm)
                        if status == "OK":
                            final_data1[f"GSM_{sgsm}"] = count
                        else:
                            final_data1[f"GSM_{sgsm}"] = status
                else:
                    status,count = check_status(gsm)
                    if status == "OK":
                        final_data1[f"GSM_{gsm}"] = count
                    else:
                        final_data1[f"GSM_{gsm}"] = gsmcount

            final_data[ser] = final_data1

        final_json = json.dumps(final_data)
        #print(final_json)
        with open('/var/www/html/data.json','w') as fwrite:
            fwrite.write(final_json)
        time.sleep(1)

except Exception as err:
    print(err)
    
