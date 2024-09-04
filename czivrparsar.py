#!/usr/bin/python

import telnetlib
import re
import sys
import json
import threading
import time
import requests
import os
import subprocess
import logging

session_data = {}
lock=threading.Lock()

def READ_DATA(id_):

    print(f'thread with id: {id_} started')
    conn = tel(9230)
    while (1):

        try:
            event = conn.read_until(b'\n')
            event = event.decode('utf-8')

            if event and "#" in event:
                re_data = event.split('#')

                if re_data[0] == "CZASRBOT" and re_data[5].strip() != "CZASREOS":
                    log.info(f"INSERT BLOCK EVENT====> {event}")
                    nid = str(re_data[3]).replace(".","")

                    data = re_data[1]+'_'+nid

                    with lock:
                        if data not in session_data:
                            re_data[5] = re_data[5].strip()
                            dt = json.loads(re_data[5])

                            if (dt["result"]["final"]):
                                transcript = (dt["result"]["hypotheses"][0]["transcript"])
                                session_data[data] = transcript
                                #session_data[data] = re_data[5]

                        else:
                            re_data[5] = re_data[5].strip()
                            dt = json.loads(re_data[5])

                            if (dt["result"]["final"]):
                                transcript = (dt["result"]["hypotheses"][0]["transcript"])
                                session_data[data] = session_data[data]+" "+transcript
                                #session_data[data] = session_data[data]+" "+re_data[5]

                    log.info(f"INSERT BLOCK DICT==> {session_data}\n")


                else:
                    log.info(f"OTHER EVENT : {event}")

        except:
            log.exception('Issue while reading data')
            conn = tel(9230)


def EOS_DATA(id_):

    print(f'thread with id: {id_} started')
    conn = tel(9230)
    conn_5038 = tel(5038, auth=True)
    while (1):

        try:
            event = conn.read_until(b'\n')
            event = event.decode('utf-8')

            if event and "#" in event:

                re_data = event.split('#')
                nid = str(re_data[3]).replace(".","")
                data = re_data[1]+'_'+nid

                if re_data[0] == "CZASRBOT" and data in session_data and re_data[5].strip() == "CZASREOS":
                    #cmd = "Action: DialogFlow\r\nVariables: cricket=bot_file,year=sid,matchtype=SUCCESS,winner=\""+str(session_data[data])+"\",botdisconnect=\r\nchannel: "+str(re_data[4])+"\r\nWaitExit: 1\r\n\r\n"
                    cmd = "Action: DialogFlow\r\nVariables: cricket=bot_file,year="+nid+",matchtype=SUCCESS,winner=\""+str(session_data[data])+"\",botdisconnect=\r\nchannel: "+str(re_data[4])+"\r\nWaitExit: 1\r\n\r\n"
                    log.info(f"DELETE BLOCK PACKET===> {cmd}\n")
                    conn_5038.write(cmd.encode())
                    del session_data[data]

        except:
            log.exception('Issue while reading data')
            conn = tel(9230)
            conn_5038 = tel(5038, auth=True)



# Create new threads
fnc  = {
    'read': [READ_DATA, (1,)],
    'delete': [EOS_DATA, (2,)]
}
log = logging.getLogger('muylooger')
logging.basicConfig(level=logging.DEBUG,format="%(asctime)s : %(levelname)s : %(lineno)s :: %(message)s", filename='/var/log/czentrix/ivrbot/common_log.txt')
log.info('=========== RESTART SERVICE =========')

def tel(port, auth=False, connection_limit=None):

    while 1:
        try:
            log.debug(f'Connecting to telnet on {port}')
            telnet_conn = telnetlib.Telnet('localhost',port)
            if auth:
                telnet_conn.write(b"action: login\r\nusername: dial\r\nsecret: 1234\r\n\r\n")
                telnet_conn.read_until(b"Authentication accepted")
                log.info('Auth accepted\nConnection created with port: {port}')

        except:
            log.exception('Reconnection issue')
            time.sleep(3)

        else:
            return telnet_conn

while 1:

    THLIST = [x.name for x in threading.enumerate()]

    for fname, fargs in fnc.items():
        if fname not in THLIST:
            thr = threading.Thread(target=fargs[0], args=fargs[1], name=fname)
            thr.start()

    log.info(f"Threads list===>{THLIST}")
    time.sleep(5)


