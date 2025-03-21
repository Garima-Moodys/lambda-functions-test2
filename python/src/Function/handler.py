import json
import boto3
import pyodbc
import os
from openpyxl import Workbook
from io import BytesIO

# Getting database credentials from env variables
curr_server = os.getenv('DB_SERVER')
curr_database = os.getenv('DB_NAME')
curr_user_id = os.getenv('DB_USER')
curr_pass=os.getenv('DB_PASSWORD')

def handler(event, context):
    try: 
        # Making connection string
        conn_str = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={curr_server};DATABASE={curr_database};UID={curr_user_id};PWD={curr_pass}"

        # Establish a connection to SQL Server
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor() # Creating a cursor object to interact with the database

        # Executing the stored procedure
        cursor.execute("{CALL dbo.Dummy_sp}")
        rows=cursor.fetchall()

        # Creating a workbook
        wb=Workbook()
        ws=wb.active
        ws.title="Stored procedure Dummy_sp data" # Naming the worksheet

        # Adding the column headers
        columns = [desc[0] for desc in cursor.description]
        ws.append(columns)

        # Processing the rows and replacing None (NULL values) with a placeholder ('NULL')
        for row in rows:
            row_data = [value if value is not None else 'NULL' for value in row]
            ws.append(row_data)

        # Saving the workbook to a BytesIO stream (in-memory file)
        excel_file=BytesIO()
        wb.save(excel_file)
        excel_file.seek(0)
        
        # Uploading the file to S3
        s3 = boto3.client('s3')
        bucket_name = os.getenv('s3_bucket_name')
        file_name='stored_procedure_results.xlsx'

        try:
            s3.put_object(Body=excel_file, Bucket=bucket_name, Key=file_name)
            print(f"File uploaded successfully to {bucket_name}/{file_name}")
        except Exception as s3_error:
            print(f"Error uploading file to S3: {str(s3_error)}")
            return {
                'statusCode': 500,
                'body': f"Error uploading file to S3: {str(s3_error)}"
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': f"Error: {str(e)}"
        }
    finally:
        conn.close()        # Ensuring the database connection is closed regardless of success or failure
        excel_file.close()  # Closing the BytesIO stream to free resources
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Connection successful and file uploaded successfully"
        }),
    }



    
   
