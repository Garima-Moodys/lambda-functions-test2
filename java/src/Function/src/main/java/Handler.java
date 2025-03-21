import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.amazonaws.services.s3.model.PutObjectRequest;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.apache.poi.ss.usermodel.*;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;

import java.io.*;
import java.sql.*;
import java.util.*;

public class Handler implements RequestHandler<Map<String, Object>, String> {

    @Override
    public String handleRequest(Map<String, Object> event, Context context) {
        // Define environment variables
        String dbServer = System.getenv("DB_SERVER");
        String dbName = System.getenv("DB_NAME");
        String dbUser = System.getenv("DB_USER");
        String dbPassword = System.getenv("DB_PASSWORD");
        String s3BucketName = System.getenv("s3_bucket_name");

        try {
            // Establish database connection
            String connectionUrl = String.format("jdbc:sqlserver://%s:1433;databaseName=%s;user=%s;password=%s",dbServer,dbName, dbUser, dbPassword);
            Connection connection = DriverManager.getConnection(connectionUrl);

            // Execute the stored procedure
            CallableStatement stmt = connection.prepareCall("{CALL dbo.Dummy_sp}");
            ResultSet resultSet = stmt.executeQuery();

            // Create an Excel workbook and sheet
            XSSFWorkbook workbook = new XSSFWorkbook();
            Sheet sheet = workbook.createSheet("Stored procedure Dummy_sp data");

            // Create the header row
            ResultSetMetaData metaData = resultSet.getMetaData();
            Row headerRow = sheet.createRow(0);
            int columnCount = metaData.getColumnCount();
            for (int i = 1; i <= columnCount; i++) {
                headerRow.createCell(i - 1).setCellValue(metaData.getColumnLabel(i));
            }

            // Add data rows
            int rowNum = 1;
            while (resultSet.next()) {
                Row row = sheet.createRow(rowNum++);
                for (int i = 1; i <= columnCount; i++) {
                    Object value = resultSet.getObject(i);
                    if (value == null) {
                        row.createCell(i - 1).setCellValue("NULL");
                    } else {
                        row.createCell(i - 1).setCellValue(value.toString());
                    }
                }
            }

            // Write the Excel file to a ByteArrayOutputStream (in-memory)
            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            workbook.write(byteArrayOutputStream);
            byteArrayOutputStream.flush();

            // Upload the file to S3
            AmazonS3 s3Client = AmazonS3ClientBuilder.defaultClient();
            String fileName = "stored_procedure_results.xlsx";
            InputStream inputStream = new ByteArrayInputStream(byteArrayOutputStream.toByteArray());

            PutObjectRequest putObjectRequest = new PutObjectRequest(s3BucketName, fileName, inputStream, null);
            s3Client.putObject(putObjectRequest);

            System.out.println("File uploaded successfully to " + s3BucketName + "/" + fileName);

            // Closing resources
            resultSet.close();
            stmt.close();
            connection.close();
            byteArrayOutputStream.close();
            workbook.close();

            return "File uploaded successfully to " + s3BucketName + "/" + fileName;

        } catch (Exception e) {
            e.printStackTrace();
            return "Error: " + e.getMessage();
        }
    }
}
