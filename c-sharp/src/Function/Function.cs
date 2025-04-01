using System;
using System.Data;
using System.IO;
using Microsoft.Data.SqlClient;
using Amazon.S3;
using Amazon.S3.Model;
using OfficeOpenXml;
using Newtonsoft.Json;
using Amazon.Lambda.Core;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

public class Function
{
    public string Handler(object obj, ILambdaContext context)
    {
        ExcelPackage.LicenseContext = LicenseContext.NonCommercial; 
        
        SqlConnection con = null;
        SqlCommand cmd = null;
        SqlDataReader reader = null;
        ExcelPackage package = null;
        MemoryStream stream = null;

        try
        {
            string server = Environment.GetEnvironmentVariable("server") ?? throw new ArgumentNullException("server");
            string database = Environment.GetEnvironmentVariable("database") ?? throw new ArgumentNullException("database");
            string userid = Environment.GetEnvironmentVariable("userid") ?? throw new ArgumentNullException("userid");
            string loandqPwd = Environment.GetEnvironmentVariable("password") ?? throw new ArgumentNullException("password");
            string bucketName = Environment.GetEnvironmentVariable("s3_bucket_name") ?? throw new ArgumentNullException("s3_bucket_name");

            con = new SqlConnection($"Server=tcp:{server},1433;Database={database};User Id={userid};Password={loandqPwd};Min Pool Size=1;Max Pool Size=50;TrustServerCertificate=True;");
 
            con.Open();

            cmd = new SqlCommand("dbo.Dummy_sp", con)
            {
                CommandType = CommandType.StoredProcedure
            };

            reader = cmd.ExecuteReader();

            //excel package
            package = new ExcelPackage();
            var worksheet = package.Workbook.Worksheets.Add("Stored procedure Dummy_sp data");

            for (int i = 0; i < reader.FieldCount; i++)
            {
                worksheet.Cells[1, i + 1].Value = reader.GetName(i);
            }

            int rowIndex = 2;
            while (reader.Read())
            {
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    worksheet.Cells[rowIndex, i + 1].Value = reader.IsDBNull(i) ? "NULL" : reader.GetValue(i).ToString();
                }
                rowIndex++;
            }

            stream = new MemoryStream();
            package.SaveAs(stream);
            byte[] fileContent = stream.ToArray();

            var s3Client = new AmazonS3Client();
            string fileName = "stored_procedure_results.xlsx";

            var putRequest = new PutObjectRequest
            {
                BucketName = bucketName,
                Key = fileName,
                InputStream = new MemoryStream(fileContent)
            };

            try
            {
                // Using PutObjectAsync with await is a better practice, but if you want to keep sync:
                s3Client.PutObjectAsync(putRequest).Wait();
                Console.WriteLine($"File uploaded successfully to {bucketName}/{fileName}");
            }
            catch (AmazonS3Exception s3Error)
            {
                Console.WriteLine($"Error uploading file to S3: {s3Error.Message}");
                return CreateResponse(500, $"Error uploading file to S3: {s3Error.Message}");
            }
        }
        catch (SqlException sqlEx)
        {
            Console.WriteLine($"SQL Error: {sqlEx.Message}");
            return CreateResponse(500, $"SQL Error: {sqlEx.Message}");
        }
        catch (Exception e)
        {
            Console.WriteLine($"Error: {e.Message}");
            return CreateResponse(500, $"Error: {e.Message}");
        }
        finally
        {
            reader?.Dispose();
            cmd?.Dispose();
            con?.Dispose();
            package?.Dispose();
            stream?.Dispose();
        }

        return CreateResponse(200, "Connection successful and file uploaded successfully");
    }

    private static string CreateResponse(int statusCode, string message)
    {
        var response = new
        {
            statusCode,
            body = JsonConvert.SerializeObject(new { message })
        };
        return JsonConvert.SerializeObject(response);
    }
}
