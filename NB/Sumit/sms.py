import requests

url="https://http.myvfirst.com/smpp/api/sendsms/token?action=generate"

payload="" 
headers={'Authorization':'Basic bWF4YnVwYW90YzpRMEVMSzk4Nw=='}
response=requests.request("POST",url,headers=headers,data=payload)
if response.status_code==200:
	res = response.json()
	token = res["token"]
	print(token)
