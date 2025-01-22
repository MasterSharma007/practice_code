import psycopg2

conn = psycopg2.connect(
   dbname='mbhi_crm', user='mbhi_user', password='mbhi_password', host='10.1.16.178', port='5432', sslmode='require'
#   database="postgres", user='postgres', password='password', host='127.0.0.1', port= '5432'
)
cursor = conn.cursor()

#cursor.execute("select version()")
cursor.execute("select * from auth_user limit 1;")

data = cursor.fetchone()
print("Connection established to: ",data)

conn.close()
#Connection established to: (
#   'PostgreSQL 11.5, compiled by Visual C++ build 1914, 64-bit',
#)
