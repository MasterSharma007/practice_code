import pymysql.cursors

# Connect to the database
connection = pymysql.connect(host='localhost',
                             user='root',
                             password='ASTERISK',
                             database='asterisk',
                             charset='utf8mb4',
                             cursorclass=pymysql.cursors.DictCursor)
peersdata = "\n"
with connection:

    with connection.cursor() as cursor:
        sql = "select a.name,a.musicclass, a.strategy, a.queue_minutes, a.retry, a.wrapuptime, a.joinempty, a.maxlen, b.queue_name,GROUP_CONCAT(c.name SEPARATOR ',') as agents from queues as a, queue_member_table as b, sip_buddies as c where a.name=b.queue_name and  c.name=b.membername and a.call_type = 'Inbound' group by a.name;"
        cursor.execute(sql)
        result = cursor.fetchall()
        for all in result:
            peersdata = f"{peersdata}[{all['name']}]\nmusiconhold={all['musicclass']}\nstrategy={all['strategy']}\ntimeout={all['queue_minutes']}\nretry={all['retry']}\nwrapuptime={all['wrapuptime']}\njoinempty={all['joinempty']}\nmaxlen={all['maxlen']}\nsetinterfacevar=yes\n"
            for agent in all['agents'].split(','):
                 peersdata = f"{peersdata}member=>Local/{agent}@{all['name']},0,{agent},SIP/{agent},yes\n"
            peersdata = f"{peersdata}\n"	
print(peersdata)
