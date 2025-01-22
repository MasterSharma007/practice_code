#!/usr/lib/python

import urllib
import subprocess
import logging
import time
from urllib import urlencode
import urllib2
import json
logging.basicConfig(filename='/var/log/agent_live_status.log',level=logging.INFO,format='%(asctime)s - %(message)s')
url = 'http://crm.nivabupa.com/api/v1/dialer_call/inbound_idle_time'

logging.info("Service Start")



def api_hit(emp_code,emp_status):
	try:
		url = "http://crm.nivabupa.com/api/v1/dialer_call/logout_user"
		#logging.info(type(emp_code))
		payload = {"emp_code": emp_code,"emp_status": emp_status}
		json_data = json.dumps(payload)
		req = urllib2.Request(url,data=json_data)
		req.add_header('Content-Type', 'application/json')
		
		logging.info(payload)
		response = urllib2.urlopen(req)
		data = response.read()

		logging.info(data)

		return()
        except Exception as e:
                return e
		#continue


def check_preer_status(peer):
        try:
		command = ['asterisk', '-rx', 'sip show peer {}'.format(peer)]	
		result = subprocess.check_output(command)
		result = result.encode('utf-8') if isinstance(result, bytes) else result
		if "not found" in result :
			return 'PEER_NOT_FOUND'
		else:
			return 'PEER_FOUND'
        except Exception as e:
                return e

while True:
	response = urllib.urlopen(url)
	resp = response.read()
	data = resp.replace('{"callable":"','').replace('"}','')

	for peer in data.split(','):
		status = check_preer_status(peer)
		if "PEER_NOT_FOUND" in status:
			logging.info("NOT_AVAILABLE PEER {}".format(peer))
			res = api_hit(peer,"UNAVAILABLE")
	time.sleep(60)
