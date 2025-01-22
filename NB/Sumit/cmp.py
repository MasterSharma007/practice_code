import pymysql.cursors

# Connect to the database
connection = pymysql.connect(host='localhost',
                             user='root',
                             password='ASTERISK',
                             database='asterisk',
                             charset='utf8mb4',
                             cursorclass=pymysql.cursors.DictCursor)
cmpdata = "\n"
with connection:

    with connection.cursor() as cursor:
        sql = "select queue_id,campaign_id,name,context,timeout,call_type,call_method from queues where call_type='Inbound';"
        cursor.execute(sql)
        result = cursor.fetchall()
        for all in result:
            cmpdata = f"{cmpdata}[{all['name']}]\nexten=>s,1,Queue({all['name']},t,,,{all['timeout']})\nexten=>s,n,NoOp(${{DIALSTATUS}})\nexten=>s,n,Hangup()\n\n"

print(cmpdata)
