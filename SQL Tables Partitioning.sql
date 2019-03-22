/* --------------------------------------------------
-- Create helper function GetNums
-- GetNums is used to insert test data
-------------------------------------------------- */
-- Drop helper function if it already exists
IF OBJECT_ID('GetNums') IS NOT NULL
	DROP FUNCTION GetNums;
GO

-- Create helper function
CREATE FUNCTION GetNums(@n AS BIGINT) RETURNS TABLE AS RETURN
  WITH
  L0   AS(SELECT 1 AS c UNION ALL SELECT 1),
  L1   AS(SELECT 1 AS c FROM L0 AS A CROSS JOIN L0 AS B),
  L2   AS(SELECT 1 AS c FROM L1 AS A CROSS JOIN L1 AS B),
  L3   AS(SELECT 1 AS c FROM L2 AS A CROSS JOIN L2 AS B),
  L4   AS(SELECT 1 AS c FROM L3 AS A CROSS JOIN L3 AS B),
  L5   AS(SELECT 1 AS c FROM L4 AS A CROSS JOIN L4 AS B),
  Nums AS(SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n FROM L5)
  SELECT TOP (@n) n FROM Nums ORDER BY n;
GO

/* ------------------------------------------------------------
-- Create example Partitioned Table (Heap)
-- The Partition Column is a DATE column
-- The Partition Function is RANGE RIGHT
-- The Partition Scheme maps all partitions to [PRIMARY]
------------------------------------------------------------ */

-- Drop objects if they already exist
IF EXISTS (SELECT * FROM sys.tables WHERE name = N'Sales')
	DROP TABLE Sales;
IF EXISTS (SELECT * FROM sys.partition_schemes WHERE name = N'psSales')
	DROP PARTITION SCHEME psSales;
IF EXISTS (SELECT * FROM sys.partition_functions WHERE name = N'pfSales')
	DROP PARTITION FUNCTION pfSales;

-- Create the Partition Function 
CREATE PARTITION FUNCTION pfSales (DATE)
AS RANGE RIGHT FOR VALUES 
('2013-01-01', '2014-01-01', '2015-01-01');

-- Create the Partition Scheme
CREATE PARTITION SCHEME psSales
AS PARTITION pfSales 
ALL TO ([Primary]);

-- Create the Partitioned Table (Heap) on the Partition Scheme
CREATE TABLE Sales (
	SalesDate DATE,
	Quantity INT
) ON psSales(SalesDate);

-- Insert test data
INSERT INTO Sales(SalesDate, Quantity)
SELECT DATEADD(DAY,dates.n-1,'2012-01-01') AS SalesDate, qty.n AS Quantity
FROM GetNums(DATEDIFF(DD,'2012-01-01','2016-01-01')) dates
CROSS JOIN GetNums(1000) AS qty;

-- View Partitioned Table information
SELECT
	OBJECT_SCHEMA_NAME(pstats.object_id) AS SchemaName
	,OBJECT_NAME(pstats.object_id) AS TableName
	,ps.name AS PartitionSchemeName
	,ds.name AS PartitionFilegroupName
	,pf.name AS PartitionFunctionName
	,CASE pf.boundary_value_on_right WHEN 0 THEN 'Range Left' ELSE 'Range Right' END AS PartitionFunctionRange
	,CASE pf.boundary_value_on_right WHEN 0 THEN 'Upper Boundary' ELSE 'Lower Boundary' END AS PartitionBoundary
	,prv.value AS PartitionBoundaryValue
	,c.name AS PartitionKey
	,CASE 
		WHEN pf.boundary_value_on_right = 0 
		THEN c.name + ' > ' + CAST(ISNULL(LAG(prv.value) OVER(PARTITION BY pstats.object_id ORDER BY pstats.object_id, pstats.partition_number), 'Infinity') AS VARCHAR(100)) + ' and ' + c.name + ' <= ' + CAST(ISNULL(prv.value, 'Infinity') AS VARCHAR(100)) 
		ELSE c.name + ' >= ' + CAST(ISNULL(prv.value, 'Infinity') AS VARCHAR(100))  + ' and ' + c.name + ' < ' + CAST(ISNULL(LEAD(prv.value) OVER(PARTITION BY pstats.object_id ORDER BY pstats.object_id, pstats.partition_number), 'Infinity') AS VARCHAR(100))
	END AS PartitionRange
	,pstats.partition_number AS PartitionNumber
	,pstats.row_count AS PartitionRowCount
	,p.data_compression_desc AS DataCompression
FROM sys.dm_db_partition_stats AS pstats
INNER JOIN sys.partitions AS p ON pstats.partition_id = p.partition_id
INNER JOIN sys.destination_data_spaces AS dds ON pstats.partition_number = dds.destination_id
INNER JOIN sys.data_spaces AS ds ON dds.data_space_id = ds.data_space_id
INNER JOIN sys.partition_schemes AS ps ON dds.partition_scheme_id = ps.data_space_id
INNER JOIN sys.partition_functions AS pf ON ps.function_id = pf.function_id
INNER JOIN sys.indexes AS i ON pstats.object_id = i.object_id AND pstats.index_id = i.index_id AND dds.partition_scheme_id = i.data_space_id AND i.type <= 1 /* Heap or Clustered Index */
INNER JOIN sys.index_columns AS ic ON i.index_id = ic.index_id AND i.object_id = ic.object_id AND ic.partition_ordinal > 0
INNER JOIN sys.columns AS c ON pstats.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.partition_range_values AS prv ON pf.function_id = prv.function_id AND pstats.partition_number = (CASE pf.boundary_value_on_right WHEN 0 THEN prv.boundary_id ELSE (prv.boundary_id+1) END)
WHERE pstats.object_id = OBJECT_ID('Sales')
ORDER BY TableName, PartitionNumber;