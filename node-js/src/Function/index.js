const AWS = require("aws-sdk");
const sql = require("mssql");
const ExcelJS = require("exceljs");

// Define the S3 client
const s3 = new AWS.S3();

exports.handler = async (event) => {
  // Get environment variables
  const dbServer = process.env.DB_SERVER;
  const dbName = process.env.DB_NAME;
  const dbUser = process.env.DB_USER;
  const dbPassword = process.env.DB_PASSWORD;
  const s3BucketName = process.env.S3_BUCKET_NAME;

  // Database connection configuration
  const config = {
    user: dbUser,
    password: dbPassword,
    server: dbServer,
    database: dbName,
    options: {
      encrypt: true, // Enable encryption for SQL Server
      trustServerCertificate: true, // Change to true if using self-signed certs
    },
  };

  try {
    // Connect to SQL Server
    await sql.connect(config);

    // Execute the stored procedure
    const result = await sql.query`EXEC dbo.Dummy_sp`;

    // Create an Excel workbook and add data
    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet("Stored Procedure Data");

    // Add headers
    const columns = Object.keys(result.recordset[0]);
    sheet.addRow(columns);

    // Add rows
    result.recordset.forEach((row) => {
      sheet.addRow(Object.values(row));
    });

    // Convert the Excel workbook to a buffer
    const buffer = await workbook.xlsx.writeBuffer();

    // Upload the file to S3
    const fileName = "stored_procedure_results.xlsx";
    const params = {
      Bucket: s3BucketName,
      Key: fileName,
      Body: buffer,
      ContentType:
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    };

    await s3.putObject(params).promise();
    console.log(`File uploaded successfully to ${s3BucketName}/${fileName}`);

    return {
      statusCode: 200,
      body: `File uploaded successfully to ${s3BucketName}/${fileName}`,
    };
  } catch (error) {
    console.error("Error:", error);
    return {
      statusCode: 500,
      body: `Error: ${error.message}`,
    };
  } finally {
    // Close the database connection
    await sql.close();
  }
};
