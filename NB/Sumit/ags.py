import subprocess

def check_preer_status(peer):
	try:
		result = subprocess.run(['asterisk', '-rx', 'sip show peer {}'.format(peer)], capture_output=true,text=True)
		if result.returncode ==0 and 'Status' in result.stdout:
			status_line = [line for line in result.stdout.splitlines() if 'Status' in line]
			if status_line:
				return status_line[0].strip()
	except Eception as e:
		return e

peer =
status = check_preer_status(peer)
print peer
print status
