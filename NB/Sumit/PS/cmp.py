import psycopg2

connection = psycopg2.connect(
   dbname='mbhi_crm', user='mbhi_user', password='mbhi_password', host='10.1.16.178', port='5432', sslmode='require'
)
#cursor = conn.cursor()

cmpdata = "\n"
with connection:

    with connection.cursor() as cursor:
        sql = "select queue_id,campaign_id,name,context,timeout,call_type,call_method from queues where call_type='Inbound';"
        cursor.execute(sql)
        result = cursor.fetchall()
        for all in result:
            cmpdata = f"{cmpdata}[{all['name']}]\nexten=>s,1,Queue({all['name']},t,,,{all['timeout']})\nexten=>s,n,NoOp(${{DIALSTATUS}})\nexten=>s,n,Hangup()\n\n"

print(cmpdata)
