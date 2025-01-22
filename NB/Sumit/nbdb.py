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
        sql = "select name,secret,callerid from sip_buddies limit 5;"
        cursor.execute(sql)
        result = cursor.fetchall()
        for all in result:
            peersdata = f"{peersdata}[{all['name']}]\nusername={all['name']}\nsecret={all['secret']}\ntype=peer\ncallerid={all['callerid']}\nhost=Dynamic\nqualify=yes\ndisallow=all\nallow=alaw\nallow=ulaw\ncallcounter=yes\nnat=yes\ninsecure=invite\ncontext=agent_login\n\n"

print(peersdata)
