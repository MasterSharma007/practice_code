import http.client



connection = http.client.HTTPSConnection("crm.nivabupa.com")
connection.request("GET", "/api/v1/dialer_call/inbound_idle_time")
response = connection.getresponse()
print("Status: {} and reason: {}".format(response.status, response.reason))

connection.close()

