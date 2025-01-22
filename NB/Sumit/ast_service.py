import telnetlib
import time
import logging
#import requests
import http.client
#conn = http.client.HTTPSConnection("crmtest.nivabupa.com")
def read_asterisk_events(host, port, username, password):
	tn = telnetlib.Telnet(host,port)
	tn.read_until(b"Asterisk Call Manager/")
	tn.write(f"Action: Login\nUsername: {username}\nSecret: {password}\n\n".encode('ascii'))
	tn.read_until(b"Message: Authentication accepted").decode('ascii')
	while True:
		try:
			#data = tn.read_very_eager().decode('ascii')
			data = tn.read_until(b'\r\n\r\n').decode('ascii')
			if data:
				#print(f"data:{data}")
				process_packet(data)
			time.sleep(0.1)
		except Exception as e:
			print(f"Exception: {e}")
			pass
	tn.write(b"Action: Logoff\n\n")
	tn.close()
	print("Service Stopped.")

def process_packet(packet):
	if "Event: PeerStatus" in packet:
		details = extract_details(packet)
		print(f"##PS##{details}####{type(details)}")
	if "Event: DeviceStateChange" in packet:
		details = extract_details(packet)
		print(f"##DSC##{details}##{type(details)}##")
		
		#url = 'https://www.w3schools.com/python/demopage.php'
		emp_code = details["Device"].replace("SIP/","")
		emp_status = details["State"]
		print(emp_code,emp_status)
		res = api_hit(emp_code,emp_status)
		print(res)

def api_hit():
	print("##############")
	conn = http.client.HTTPSConnection("https://calling.nivabupa.com/queueui/src/ami.php?q=liveUsers")
	print("##############")
	conn.request("GET", "/")
	res = conn.getresponse()
	print(res)
	data = res.read()
	print(data.decode("utf-8"))
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
