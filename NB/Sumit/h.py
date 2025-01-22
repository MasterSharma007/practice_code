import http.client
import ast
conn = http.client.HTTPSConnection("calling.nivabupa.com")
payload = ''
headers = {}
conn.request("GET", "/queueui/src/ami.php?q=liveUsers", payload, headers)
res = conn.getresponse()
data = res.read()
#print(data,type(data))
#print(data.decode("utf-8"))
alld = data.decode("utf-8")
#print(alld,type(alld))

alldata = ast.literal_eval(alld)
#print(alldata,type(alldata))

for ss in alldata:
	print(ss['resource'],ss['state'])
agent_col =[str(row['resource']) for row in alldata if str(row['state']) == "online"]


print(agent_col)
