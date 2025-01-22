#!/usr/bin/python

import telnetlib
import re
import sys
import json
import threading
import time
#import requests
import os
import subprocess
import logging
import pymysql.cursors
import http.client
import ast 
import base64

pacing_data = {}
camp_data = {}
pace_lock=threading.Lock()
camp_lock=threading.Lock()

db_config = {
    'host': 'localhost',
    'user': 'root',
    'password': 'ASTERISK',
    'database': 'asterisk'
}


def lead_api(camp_id,lead):
	conn = http.client.HTTPSConnection("crmtest.nivabupa.com")
	payload = f"[{{\"campaign_id\":{camp_id},\"lead_count\":{lead}}}]"
	log.info(f"Lead API payload {payload}" )
	headers = {  'Content-Type': 'application/json'}
	conn.request("POST", "/api/v1/crm/campaign_leads", payload, headers)
	res = conn.getresponse()
	data = res.read()
	alllead = data.decode("utf-8")
	log.info(f"alllead: {alllead}")
	return(alllead)

def api_hit():
	conn = http.client.HTTPSConnection("calling.nivabupa.com")
	payload = ''
	headers = {}
	conn.request("GET", "/queueui/src/ami.php?q=liveUsers", payload, headers)
	res = conn.getresponse()
	data = res.read()
	alld = data.decode("utf-8")
	alldata = ast.literal_eval(alld)
	agent_col =[str(row['resource']) for row in alldata if str(row['state']) == "online"]

	return(agent_col)


# Function to establish a MySQL connection with retry logic
def get_mysql_connection(retries=3, delay=5):
	attempts = 0
	while attempts < retries:
		try:
			conn = pymysql.connect(**db_config)
			return conn
		except pymysql.MySQLError as err:
			attempts += 1
			time.sleep(delay)  # Wait before retrying
	log.info("DB Failed to connect after multiple attempts.")
	return None


def PROG_DIAL(id_):

	log.info(f"thread with id: {id_} started")
	conn_5038 = tel(5038, auth=True)
	connection = get_mysql_connection()
	while (1):

		try:
			with connection.cursor() as cursor:
				#sql = "select name,secret,callerid from sip_buddies limit 5;"
				sql = "SELECT distinct(name),`campaign_id`,`call_type`,`call_method` from queues where `call_method`='Progrrasive';"
				cursor.execute(sql)
				result = cursor.fetchall()
				for all in result:
					print(f"PROG {all[0]},{all[1]}")
            	
		except:
			log.exception('Issue while reading data')
			conn_5038 = tel(5038, auth=True)

		time.sleep(10)

def PRD_DIAL(id_):
	global pacing_data
	log.info(f'thread with id: {id_} started')
	conn_5038 = tel(5038, auth=True)
	connection = get_mysql_connection()
	while (1):

		try:
			with connection.cursor() as cursor:
				#sql = "SELECT distinct(name),`campaign_id`,`call_type`,`call_method` from queues where `call_method`='Predictive';"
				#cursor.execute(sql)
				#result = cursor.fetchall()
				all = ["PREDICTIVE_TESTING",100]

				#for all in result:
				print(all[0],type(all[0]))
				camp_name = str(all[0])
				camp_id = str(all[1])
				if camp_id not in pacing_data:
					with pace_lock:
						pacing_data[camp_id] = 1
				pace = pacing_data[camp_id]
				#log.info(f"BPACE:{pace},{camp_id},{pacing_data}")	
				if int(pace) >= 1:
					sql = f"SELECT * FROM `queue_member_table` where `queue_name` = '{camp_name}';";
					cursor.execute(sql)
					result1 = cursor.fetchall()
					if result1:
						agent_col =[str(row[1]) for row in result1]
						agents1 = ', '.join(agent_col)
						agents = agents1.replace(', ','\',\'')
						#sql = f"SELECT `name` FROM `sip_buddies` where `name` IN ('{agents}') and `unmarked_lead` = 0 and `next_lead` = 0 and `is_loggedin`=1 and length(fullcontact)>0 ;";
						sql = f"SELECT `name` FROM `sip_buddies` where `name` IN ('{agents}') and `unmarked_lead` = 0 and `next_lead` = 0 and `is_loggedin`=1 and length(fullcontact)>0 and  predictive_call= true;";
						cursor.execute(sql)
						result2 = cursor.fetchall()
						if result2:
							avl_agent =[str(row[0]) for row in result2]
							on_agent=api_hit()					
							final_agents = [item for item in avl_agent if item in on_agent]	
							agent_count = len(final_agents)
							callable_agent = ','.join(final_agents)
							log.info(f"PROD, {all[0]},{camp_id}, {agent_count},{callable_agent}")
							
							callable_agent_encode = base64.b64encode(callable_agent.encode('utf-8'))
							agent_count *= int(pace)
							leads_str = lead_api(camp_id,agent_count)
							allleads = json.loads(leads_str)
							campid = allleads["data"][0]["campaign_id"]
							leads = allleads["data"][0]["leads"]
							if leads:
								for dial_lead in leads:
									waittime = 60
									CallerId = "9540581030-275248-1"
									leadid = dial_lead["lead_id"] 
									bnsdid = dial_lead["business_id"]
									mob = dial_lead["mobile_number"][0] 
									b1 = dial_lead["mobile_number"][1] 
									b2 = dial_lead["mobile_number"][2] 

									cmd = f"Action: originate\r\nChannel: LOCAL/{mob}@dial_predictive\r\nWaitTime: {waittime}\r\nExten: {mob}\r\nContext: predictive\r\nCallerId: {CallerId}\r\nAsync: true\r\nVariable: lead_id={leadid}\r\nVariable: business_type={bnsdid}\r\nVariable: mobile_number={mob}\r\nVariable: campaign_id={campid}\r\nVariable: dest_queue={camp_name}\r\nVariable: callable={callable_agent_encode}\r\nVariable: call_method=Predictive\r\nVariable: call_type=\r\nAccount: {camp_name}\r\nPriority: 1\r\n\r\nAsync: true\r\n\r\n"
									log.info(f"{cmd}") 
									conn_5038.write(cmd.encode())
							else:
								log.info(f"{campid}: No Leads available.")
						else:
							log.info(f"{camp_id}: No Agentss available.")
				else:
					log.info(f"{camp_id}: PACING is Zero. Max Call Abdn.")
						
					
		except Exception as err:
			log.exception(f"Exception in Predictive Dial Block. {err}")
			conn_5038 = tel(5038, auth=True)
		time.sleep(10)

def END_EVENT(id_):
	global pacing_data
	global camp_data
	log.info(f"thread with id: {id_} started")
	conn_5038 = tel(5038, auth=True)
	while (1):

		try:
			event = conn_5038.read_until(b'\r\n\r\n')
			event = event.decode('utf-8', errors='ignore')
			if "Event: UserEvent" in event and "UserEvent: PRD_END" in event:
				log.info(f"END_EVENT: {event}")
				str_event = ''.join(event)
				pdata = str_event.split('camp_id: ')[1]
				campid = str(pdata.split('\r\n')[0])
				udata = pdata.split('uid: ')[1]
				uid = udata.split('\r\n')[0]
				sdata = pdata.split('dstatus: ')[1]
				status = sdata.split('\r\n')[0]
				if campid in camp_data:
					camp_data[campid]["total"] = int(camp_data[campid]["total"]) +1
					if str(status) == "ANSWER":
						camp_data[campid]["ans"] = camp_data[campid]["ans"] +1
					else:
						camp_data[campid]["noans"] = camp_data[campid]["noans"] +1
				else:
					camp_data[campid] = {}
					camp_data[campid]["total"] = 1
					if str(status) == "ANSWER":
						camp_data[campid]["ans"] = 1
						camp_data[campid]["noans"] = 0
					else:
						camp_data[campid]["noans"] = 1
						camp_data[campid]["ans"] = 0

            	
		except Exception as err:
			log.exception(f"Exception in Hangup Block. {err}")
			conn_5038 = tel(5038, auth=True)
		time.sleep(0.1)
def PACE_MON(id_):
	global pacing_data
	global camp_data
	
	log.info(f"thread with id: {id_} started")
	while (1):

		try:	
			with camp_lock:
				for campd in camp_data:
					total = camp_data[campd]["total"]
					if total > 10:
						ans = camp_data[campd]["ans"]
						noans = camp_data[campd]["noans"]
						ans_per = (ans/total)*100
						if int(ans_per) < 10:
							with pace_lock:
								pacing_data[campd]=0
						elif int(ans_per) < 30:
							with pace_lock:
								pacing_data[campd]= int(pacing_data[campd]) + 1
						else:
							if pacing_data[campd] > 1:
								with pace_lock:
									pacing_data[campd]= int(pacing_data[campd]) - 1
						camp_data[campd]["total"]=0
						camp_data[campd]["ans"]=0
						camp_data[campd]["noans"]=0
					
			#with pace_lock:
			log.info(f"PACING: {pacing_data}")
			#with camp_lock:
			log.info(f"CAMP_DATA: {camp_data}")
            	
		except:
			log.exception('Issue while Pacing Monitor.')

		time.sleep(7)
# Create new threads
fnc  = {
    'prg_dial': [PROG_DIAL, (1,)],
    'prd_dial': [PRD_DIAL, (2,)],
    'pace_mon': [PACE_MON, (3,)],
    'hang_pack': [END_EVENT, (4,)]
}
log = logging.getLogger('muylooger')
logging.basicConfig(level=logging.DEBUG,format="%(asctime)s : %(levelname)s : %(lineno)s :: %(message)s", filename='/tmp/common_log.txt')
log.info('=========== RESTART SERVICE =========')

def tel(port, auth=False, connection_limit=None):

    while 1:
        try:
            log.debug(f'Connecting to telnet on {port}')
            telnet_conn = telnetlib.Telnet('localhost',port)
            if auth:
                telnet_conn.write(b"action: login\r\nusername: max_mbhi\r\nsecret: mbhi_max\r\nEvent: on\r\n\r\n")
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

