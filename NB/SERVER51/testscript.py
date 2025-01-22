import requests

url = "https://crm.nivabupa.com/api/v1/dialer_call/logout_user"

payload="{\"emp_code\": \"P100099\", \"emp_status\": \"UNAVAILABLE\"}"
headers = {
  'Content-Type': 'application/json'
}

response = requests.request("POST", url, headers=headers, data=payload)

print(response.text)

