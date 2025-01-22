import telnetlib
import time
import logging
from urllib import urlencode
import urllib2

def read_asterisk_events(host, port, username, password):
	logging.basicConfig(filename='/var/log/agent_service.log',level=logging.INFO,format='%(asctime)s - %(message)s')
	tn = telnetlib.Telnet(host,port)
	tn.read_until(b"Asterisk Call Manager/")
	tn.write("Action: Login\nUsername: {}\nSecret: {}\n\n".format(username,password).encode('ascii'))
	tn.read_until(b"Message: Authentication accepted").decode('ascii')
	logging.info("Service Start")
	while True:
		try:
			#data = tn.read_very_eager().decode('ascii')
			data = tn.read_until(b'\r\n\r\n').decode('ascii')
			if data:
				#print(f"data:{data}")
				process_packet(data)
			time.sleep(0.1)
		except Exception as e:
			#logging.info(f"Exception: {e}")
			pass
	tn.write(b"Action: Logoff\n\n")
	tn.close()
	logging.info("Service Stopped.")

def process_packet(packet):
	if "Event: PeerStatus" in packet:
		details = extract_details(packet)
		logging.info("PS##{}".format(details))
	if "Event: DeviceStateChange" in packet:
		details = extract_details(packet)
		logging.info("DSC##{}".format(details))
		
		#url = 'https://www.w3schools.com/python/demopage.php'
		emp_code = details["Device"].replace("SIP/","")
		emp_status = details["State"]
		res = api_hit(emp_code,emp_status)

def api_hit(emp_code,emp_status):
	url = "https://crmtest.nivabupa.com/api/v1/dialer_call/logout_user"
	payload = {"emp_code": emp_code,"emp_status": emp_status}	
	#logging.info("payload:",payload)
	#payload = {"emp_code": emp_code,"emp_status": Unavailable}	
	headers = { 'Content-Type': 'application/json'}
	payload = str(payload)
	payload = payload.replace("\'","\"")
	req = urllib2.Request(url, payload)
	response = urllib2.urlopen(req)
	data = response.read()
	
	logging.info(data)

	return()

def extract_details(packet):
	details={}
	for line in packet.split('\n'):
		if ": " in line:
			key, value = line.split(": ",1)
			details[key.strip()] = value.strip()
	return details


		
if __name__ == "__main__":
	HOST = "localhost"
	PORT = 5038
	UNAME = "max_mbhi"
	PASS = "mbhi_max"

	read_asterisk_events(HOST,PORT,UNAME,PASS)
