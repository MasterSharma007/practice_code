import http.client

conn = http.client.HTTPSConnection("crmtest.nivabupa.com")
payload = "{\r\n    \"emp_code\": \"P12345\",\r\n    \"emp_status\": \"YES\"\r\n}"
headers = {
  'Content-Type': 'application/json'
}
print(f"{type(payload)}###{type(headers)}")
conn.request("POST", "/api/v1/dialer_call/logout_user", payload, headers)
res = conn.getresponse()
data = res.read()
print(data.decode("utf-8"))
