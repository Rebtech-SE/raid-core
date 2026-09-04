# Bronze Layer Patterns

Comprehensive patterns for raw data ingestion in the Bronze layer.

## Core Principles

1. **Append-only**: Never update or delete records
1. **Preserve source format**: Minimal transformation
1. **Add audit columns**: Track lineage and timing
1. **Partition by ingestion date**: Enable efficient querying and retention

## Required Audit Columns

```python
# PySpark - Standard audit columns
def add_audit_columns(df, source_system: str, batch_id: str):
    return df \
        .withColumn("_ingestion_timestamp", F.current_timestamp()) \
        .withColumn("_ingestion_date", F.current_date()) \
        .withColumn("_source_system", F.lit(source_system)) \
        .withColumn("_batch_id", F.lit(batch_id)) \
        .withColumn("_source_file", F.input_file_name())  # For file sources
```

```sql
-- dbt staging model
SELECT
    *,
    CURRENT_TIMESTAMP() AS _ingestion_timestamp,
    CURRENT_DATE() AS _ingestion_date,
    '{{ var("source_system", "unknown") }}' AS _source_system,
    '{{ invocation_id }}' AS _batch_id
FROM {{ source('raw', 'customers') }}
```

## Ingestion Patterns by Source Type

### File-Based Sources (CSV, JSON, Parquet)

```python
# PySpark - File ingestion with schema inference
def ingest_files(
    spark,
    source_path: str,
    target_table: str,
    file_format: str = "csv",
    source_system: str = "file",
    batch_id: str = None
):
    batch_id = batch_id or str(uuid.uuid4())

    # Read with appropriate options
    if file_format == "csv":
        df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .option("mode", "PERMISSIVE") \
            .option("columnNameOfCorruptRecord", "_corrupt_record") \
            .csv(source_path)
    elif file_format == "json":
        df = spark.read \
            .option("mode", "PERMISSIVE") \
            .option("columnNameOfCorruptRecord", "_corrupt_record") \
            .json(source_path)
    elif file_format == "parquet":
        df = spark.read.parquet(source_path)

    # Add audit columns
    df = add_audit_columns(df, source_system, batch_id)

    # Append to Bronze
    df.write \
        .mode("append") \
        .format("delta") \
        .partitionBy("_ingestion_date") \
        .saveAsTable(target_table)

    return {"records": df.count(), "batch_id": batch_id}
```

### API Sources (REST, GraphQL)

```python
# PySpark - API ingestion with raw payload preservation
import requests
import json

def ingest_api(
    spark,
    api_url: str,
    target_table: str,
    source_system: str,
    batch_id: str = None,
    headers: dict = None
):
    batch_id = batch_id or str(uuid.uuid4())

    # Fetch from API
    response = requests.get(api_url, headers=headers)
    response.raise_for_status()
    data = response.json()

    # Handle list or single object
    records = data if isinstance(data, list) else [data]

    # Create DataFrame preserving raw payload
    df = spark.createDataFrame([
        {
            "_raw_payload": json.dumps(record),
            **record  # Also extract fields for queryability
        }
        for record in records
    ])

    # Add audit columns
    df = add_audit_columns(df, source_system, batch_id)

    # Append to Bronze
    df.write \
        .mode("append") \
        .format("delta") \
        .partitionBy("_ingestion_date") \
        .saveAsTable(target_table)

    return {"records": len(records), "batch_id": batch_id}
```

### Database Sources (JDBC, CDC)

```python
# PySpark - JDBC ingestion
def ingest_jdbc(
    spark,
    jdbc_url: str,
    table_name: str,
    target_table: str,
    source_system: str,
    batch_id: str = None,
    incremental_column: str = None,
    last_value = None
):
    batch_id = batch_id or str(uuid.uuid4())

    # Build query
    if incremental_column and last_value:
        query = f"(SELECT * FROM {table_name} WHERE {incremental_column} > '{last_value}') AS t"
    else:
        query = table_name

    df = spark.read \
        .format("jdbc") \
        .option("url", jdbc_url) \
        .option("dbtable", query) \
        .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver") \
        .load()

    # Add audit columns
    df = add_audit_columns(df, source_system, batch_id)

    # Append to Bronze
    df.write \
        .mode("append") \
        .format("delta") \
        .partitionBy("_ingestion_date") \
        .saveAsTable(target_table)

    return {"records": df.count(), "batch_id": batch_id}
```

### Streaming Sources (Kafka, Event Hub)

```python
# PySpark Structured Streaming
def ingest_streaming(
    spark,
    kafka_bootstrap: str,
    topic: str,
    target_table: str,
    source_system: str,
    checkpoint_path: str
):
    stream_df = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_bootstrap) \
        .option("subscribe", topic) \
        .option("startingOffsets", "earliest") \
        .load()

    # Parse and add audit columns
    parsed_df = stream_df.select(
        F.col("key").cast("string").alias("_message_key"),
        F.col("value").cast("string").alias("_raw_payload"),
        F.col("timestamp").alias("_kafka_timestamp"),
        F.col("partition").alias("_kafka_partition"),
        F.col("offset").alias("_kafka_offset"),
        F.current_timestamp().alias("_ingestion_timestamp"),
        F.current_date().alias("_ingestion_date"),
        F.lit(source_system).alias("_source_system")
    )

    # Write stream to Bronze
    query = parsed_df.writeStream \
        .format("delta") \
        .outputMode("append") \
        .option("checkpointLocation", checkpoint_path) \
        .partitionBy("_ingestion_date") \
        .table(target_table)

    return query
```

## dbt Bronze Patterns

### Source Definition

```yaml
# models/staging/_sources.yml
version: 2

sources:
  - name: raw_salesforce
    description: Raw Salesforce data landed by ingestion pipeline
    database: raw_database
    schema: salesforce

    tables:
      - name: accounts
        description: Raw account records
        loaded_at_field: _ingestion_timestamp
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
        columns:
          - name: id
            description: Salesforce Account ID
            tests:
              - not_null
          - name: _ingestion_timestamp
            description: When record was loaded
```

### Staging Model (Bronze -> Silver first step)

```sql
-- models/staging/stg_salesforce__accounts.sql
{{
  config(
    materialized='view'  -- Views for staging: thin transforms (rename, cast, filter) don't need physical storage
  )
}}

WITH source AS (
    SELECT * FROM {{ source('raw_salesforce', 'accounts') }}
),

-- Optional: Get latest record per key if source has duplicates
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY _ingestion_timestamp DESC
        ) AS _rn
    FROM source
)

SELECT
    -- Business columns
    id AS account_id,
    name AS account_name,
    type AS account_type,
    industry,
    annual_revenue,
    created_date,
    last_modified_date,

    -- Preserve audit columns
    _ingestion_timestamp,
    _source_system,
    _batch_id

FROM deduplicated
WHERE _rn = 1
```

## Error Handling in Bronze

### Corrupt Record Handling

```python
# PySpark - Handle corrupt records
def ingest_with_error_handling(
    spark,
    source_path: str,
    target_table: str,
    error_table: str,
    source_system: str,
    batch_id: str
):
    # Read with PERMISSIVE mode
    df = spark.read \
        .option("mode", "PERMISSIVE") \
        .option("columnNameOfCorruptRecord", "_corrupt_record") \
        .json(source_path)

    # Split valid and corrupt
    valid_df = df.filter(F.col("_corrupt_record").isNull()).drop("_corrupt_record")
    corrupt_df = df.filter(F.col("_corrupt_record").isNotNull())

    # Add audit columns
    valid_df = add_audit_columns(valid_df, source_system, batch_id)
    corrupt_df = add_audit_columns(corrupt_df, source_system, batch_id) \
        .withColumn("_error_type", F.lit("PARSE_ERROR"))

    # Write valid to Bronze
    valid_df.write.mode("append").format("delta").saveAsTable(target_table)

    # Write corrupt to error table
    if corrupt_df.count() > 0:
        corrupt_df.write.mode("append").format("delta").saveAsTable(error_table)

    return {
        "valid_records": valid_df.count(),
        "corrupt_records": corrupt_df.count()
    }
```

### Schema Validation

```python
# Validate incoming schema matches expected
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

def validate_schema(df, expected_schema: StructType) -> tuple:
    """
    Returns (is_valid, missing_columns, extra_columns)
    """
    actual_cols = set(df.columns)
    expected_cols = set(f.name for f in expected_schema.fields)

    missing = expected_cols - actual_cols
    extra = actual_cols - expected_cols

    return (len(missing) == 0, list(missing), list(extra))
```

## Partitioning Strategies

### By Ingestion Date (Recommended)

```python
df.write \
    .partitionBy("_ingestion_date") \
    .format("delta") \
    .saveAsTable("bronze.events")
```

### By Source System (Multi-source tables)

```python
df.write \
    .partitionBy("_source_system", "_ingestion_date") \
    .format("delta") \
    .saveAsTable("bronze.all_customers")
```

### Retention Management

```sql
-- Delta Lake vacuum (keep 30 days)
VACUUM bronze.events RETAIN 720 HOURS;

-- Delete old partitions (if needed)
DELETE FROM bronze.events
WHERE _ingestion_date < DATE_SUB(CURRENT_DATE(), 365);
```

## Monitoring and Observability

### Record Counts

```python
def log_ingestion_metrics(
    spark,
    table_name: str,
    batch_id: str,
    record_count: int,
    start_time,
    end_time
):
    metrics = spark.createDataFrame([{
        "table_name": table_name,
        "batch_id": batch_id,
        "record_count": record_count,
        "start_time": start_time,
        "end_time": end_time,
        "duration_seconds": (end_time - start_time).total_seconds()
    }])

    metrics.write.mode("append").saveAsTable("audit.ingestion_log")
```

### Freshness Checks

```sql
-- Check data freshness
SELECT
    '_ingestion_date' AS partition_column,
    MAX(_ingestion_timestamp) AS latest_record,
    TIMESTAMPDIFF(HOUR, MAX(_ingestion_timestamp), CURRENT_TIMESTAMP()) AS hours_since_last
FROM bronze.events
HAVING hours_since_last > 24;
```
