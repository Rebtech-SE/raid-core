---
name: build-ingestion-pipeline
description: >-
  Triggers include 'ingest data', 'load data from', 'API ingestion', 'database extract',
  'file ingestion', 'set up data pipeline', 'dlt source', 'PySpark ingestion'. Guides
  building data ingestion pipelines with dlt, PySpark, or Data Pipelines: selects the
  right tool for the source type and data volume, implements audit columns, handles
  incremental loading, and configures error handling.
---

# Data Ingestion Skill

Guide users through building data ingestion pipelines for Microsoft Fabric. This skill helps select the right ingestion tool, implement proper patterns, and deploy to the Bronze layer.

## Agentic Workflow

When users need to ingest data, follow this decision process:

1. **Identify the source type** (API, database, files, streaming)
2. **Assess data volume** (small/medium vs large)
3. **Select the right tool** (dlt, PySpark, or Data Pipelines)
4. **Generate ingestion code** using patterns from this skill
5. **Add audit columns** for lineage tracking
6. **Deploy** using create-fabric-notebook skill if needed

## Tool Selection Matrix

```
                        Is data volume > 1GB per load?
                                    |
                    +---------------+---------------+
                    |                               |
                   YES                              NO
                    |                               |
              Use PySpark                  Is it an API/SaaS source?
                    |                               |
                    |               +---------------+---------------+
                    |               |                               |
                    |              YES                              NO
                    |               |                               |
                    |           Use dlt                      Is it a database?
                    |                                               |
                    |                               +---------------+---------------+
                    |                               |                               |
                    |                              YES                              NO
                    |                               |                               |
                    |                        Use dlt               Use dlt or simple Python
                    |                        (small)
                    |                          OR
                    |                       PySpark
                    |                       (large)
                    |
        Is it streaming (Kafka/Event Hub)?
                    |
                   YES
                    |
        Use PySpark Structured Streaming
```

## Quick Reference: When to Use Each Tool

| Source Type | Volume | Tool | Why |
|-------------|--------|------|-----|
| REST API | Any | **dlt** | Handles pagination, rate limiting, schema |
| SaaS (Salesforce, HubSpot) | Any | **dlt** | Verified sources with auth |
| SQL Database | < 100MB | **dlt** | Simple, incremental loading |
| SQL Database | > 100MB | **PySpark** | Distributed JDBC reads |
| Azure Blob/ADLS | Any | **PySpark** | Native integration |
| OneLake | Any | **PySpark** | Native integration |
| Kafka/Event Hub | Any | **PySpark** | Structured Streaming |
| SharePoint | Any | **dlt** | Graph API integration |
| Excel files | Small | **pandas** | Simple parsing |
| Excel files | Large | **PySpark** | Spark-Excel package |
| S3 (cross-cloud) | Any | **PySpark** | S3A connector |
| Local CSV to Fabric | Any | **fab CLI** | `fab cp` + `fab table load` / COPY INTO |

## Core Patterns

### Pattern 1: dlt for APIs

```python
import dlt
import requests

@dlt.source(name="my_api")
def api_source(api_key: str):

    @dlt.resource(
        write_disposition="merge",  # or "append", "replace"
        primary_key="id"
    )
    def records():
        url = "https://api.example.com/data"
        headers = {"Authorization": f"Bearer {api_key}"}

        while url:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            data = response.json()

            for record in data["results"]:
                yield {
                    **record,
                    "_source_system": "my_api",
                }

            # Handle pagination
            url = data.get("next_url")

    return records

# Run pipeline
pipeline = dlt.pipeline(
    pipeline_name="my_api_ingest",
    destination="filesystem",  # or lakehouse destination
    dataset_name="bronze"
)

load_info = pipeline.run(api_source(api_key="xxx"))
```

### Pattern 2: dlt with Incremental Loading

```python
@dlt.resource(primary_key="id")
def orders(
    last_updated: dlt.sources.incremental[datetime] = dlt.sources.incremental(
        cursor_path="updated_at",
        initial_value=datetime(2024, 1, 1)
    )
):
    # dlt automatically tracks and filters based on last_updated
    since = last_updated.last_value.isoformat()
    url = f"https://api.example.com/orders?since={since}"

    response = requests.get(url)
    yield from response.json()["orders"]
```

### Pattern 3: PySpark for Azure Storage

```python
from pyspark.sql import functions as F
import uuid

# Configuration
storage_account = "mystorageaccount"
container = "landing"
source_path = f"abfss://{container}@{storage_account}.dfs.core.windows.net/data/*.csv"
target_table = "bronze.my_table"
batch_id = str(uuid.uuid4())

# Read with corrupt record handling
df = spark.read \
    .option("header", "true") \
    .option("inferSchema", "true") \
    .option("mode", "PERMISSIVE") \
    .option("columnNameOfCorruptRecord", "_corrupt_record") \
    .csv(source_path)

# Add audit columns
df = df \
    .withColumn("_ingestion_timestamp", F.current_timestamp()) \
    .withColumn("_ingestion_date", F.current_date()) \
    .withColumn("_source_system", F.lit("azure_storage")) \
    .withColumn("_batch_id", F.lit(batch_id)) \
    .withColumn("_source_file", F.input_file_name())

# Write to Bronze
df.write \
    .mode("append") \
    .format("delta") \
    .partitionBy("_ingestion_date") \
    .saveAsTable(target_table)
```

### Pattern 4: PySpark for OneLake (Cross-Workspace)

```python
# Build OneLake path
source_workspace = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
source_lakehouse = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
source_table = "raw_events"

onelake_path = f"abfss://{source_workspace}@onelake.dfs.fabric.microsoft.com/{source_lakehouse}/Tables/{source_table}"

# Read from OneLake
df = spark.read.format("delta").load(onelake_path)

# Add audit columns and write
df = df \
    .withColumn("_ingestion_timestamp", F.current_timestamp()) \
    .withColumn("_ingestion_date", F.current_date()) \
    .withColumn("_source_system", F.lit("onelake"))

df.write \
    .mode("append") \
    .format("delta") \
    .partitionBy("_ingestion_date") \
    .saveAsTable("bronze.events")
```

### Pattern 5: PySpark for Large Database Tables

```python
# For tables > 100MB, use PySpark with parallelization
jdbc_url = "jdbc:sqlserver://server.database.windows.net:1433;database=mydb"

df = spark.read \
    .format("jdbc") \
    .option("url", jdbc_url) \
    .option("dbtable", "dbo.large_table") \
    .option("user", dbutils.secrets.get("scope", "db-user")) \
    .option("password", dbutils.secrets.get("scope", "db-pass")) \
    .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver") \
    .option("fetchsize", "10000") \
    .option("partitionColumn", "id") \
    .option("lowerBound", "1") \
    .option("upperBound", "1000000") \
    .option("numPartitions", "10") \
    .load()
```

### Pattern 6: Fabric CLI (`fab`) for CSV File Loads

Use the `fab` CLI (`pip install ms-fabric-cli`, then `fab auth login`) when loading local CSV files into Fabric. This is ideal for:
- Staging data for dbt transformations
- Loading seed data
- Programmatic data loads from scripts or CI pipelines

```bash
# Upload local CSV to lakehouse Files
fab cp data/sales.csv "MyWorkspace.Workspace/MyLakehouse.Lakehouse/Files/staging/sales.csv"

# Load file into a lakehouse table (append is the default mode)
fab table load "MyWorkspace.Workspace/MyLakehouse.Lakehouse/Tables/raw_sales" \
  --file "MyWorkspace.Workspace/MyLakehouse.Lakehouse/Files/staging/sales.csv" \
  --mode overwrite --format format=csv,header=true
```

For Warehouse targets, stage the file in OneLake with `fab cp` and load with `COPY INTO` or a pipeline Copy activity -- see `set-up-dbt-on-fabric` (raid-fabric). Full command syntax in `fabric-cli-core` (raid-fabric).

**When to use the fab CLI vs PySpark:**
- **fab CLI**: File uploads, dbt staging data, local dev, CI pipelines
- **PySpark**: Large volumes (>1GB), complex transformations, Fabric notebook execution

## Required Audit Columns

All Bronze ingestion MUST include these audit columns:

| Column | Type | Description |
|--------|------|-------------|
| `_ingestion_timestamp` | timestamp | When record was loaded |
| `_ingestion_date` | date | Partition key |
| `_source_system` | string | Origin identifier |
| `_batch_id` | string | Unique batch ID |
| `_source_file` | string | Source file (file sources only) |

### PySpark Implementation

```python
def add_audit_columns(df, source_system: str, batch_id: str = None):
    batch_id = batch_id or str(uuid.uuid4())
    return df \
        .withColumn("_ingestion_timestamp", F.current_timestamp()) \
        .withColumn("_ingestion_date", F.current_date()) \
        .withColumn("_source_system", F.lit(source_system)) \
        .withColumn("_batch_id", F.lit(batch_id)) \
        .withColumn("_source_file", F.input_file_name())
```

### dlt Implementation

```python
@dlt.resource
def records():
    for record in fetch_data():
        yield {
            **record,
            "_source_system": "my_source",
            # dlt adds _dlt_load_id automatically
        }
```

## Write Dispositions

| Disposition | dlt | PySpark | Use Case |
|-------------|-----|---------|----------|
| **Append** | `write_disposition="append"` | `.mode("append")` | Event logs, transactions |
| **Replace** | `write_disposition="replace"` | `.mode("overwrite")` | Full refresh, lookups |
| **Merge** | `write_disposition="merge"` | Delta MERGE | Dimensions, entities |

## Error Handling

### Corrupt Records (PySpark)

```python
# Read with PERMISSIVE mode
df = spark.read \
    .option("mode", "PERMISSIVE") \
    .option("columnNameOfCorruptRecord", "_corrupt_record") \
    .json(source_path)

# Separate valid and corrupt
valid_df = df.filter(F.col("_corrupt_record").isNull())
corrupt_df = df.filter(F.col("_corrupt_record").isNotNull())

# Write corrupt to quarantine
if corrupt_df.count() > 0:
    corrupt_df.write.mode("append").saveAsTable("bronze.quarantine")
```

### dlt Error Handling

dlt handles retries automatically. Check for failures:

```python
load_info = pipeline.run(source)

if load_info.has_failed_jobs:
    for package in load_info.load_packages:
        print(f"Failed: {package.state}")
```

## Workflow: Building an Ingestion Pipeline

When a user asks to ingest data, follow these steps:

### Step 1: Gather Requirements

Ask:
1. "What is the source?" (API, database, files, etc.)
2. "What is the approximate data volume per load?"
3. "Is this a one-time load or recurring?"
4. "Do you need incremental loading?"

### Step 2: Select Tool

Based on answers, recommend:
- **dlt** for APIs, SaaS, small databases
- **PySpark** for large files, OneLake, large databases
- **Data Pipelines** for simple copy operations or orchestration

### Step 3: Generate Code

Use patterns from this skill to generate:
- Source configuration
- Read logic with appropriate options
- Audit column addition
- Write to Bronze table

### Step 4: Add to Notebook

If deploying to Fabric:
1. Use `create-fabric-notebook` (raid-fabric) to wrap code in notebook format
2. Add proper metadata block
3. Configure lakehouse dependencies

### Step 5: Test and Deploy

```bash
# Deploy notebook into the right medallion folder (never workspace root)
fab import "MyWorkspace.Workspace/Bronze.Folder/ingest_sales.Notebook" -i path/to/notebook.py --format py -f

# Execute to test (synchronous; non-zero exit on failure)
fab job run "MyWorkspace.Workspace/Bronze.Folder/ingest_sales.Notebook"
```

See `fabric-cli-core` (raid-fabric) for fab command details, or dispatch the `fabric-cli-expert` agent.

## Examples

See working examples at:
- `rebtech/examples/ingestion/dlt_api_ingestion.py` - REST API via dlt
- `rebtech/examples/ingestion/dlt_database_ingestion.py` - Database via dlt
- `rebtech/examples/ingestion/pyspark_azure_storage_ingestion.py` - ADLS/Blob via PySpark
- `rebtech/examples/ingestion/pyspark_onelake_ingestion.py` - OneLake via PySpark

## Related Documentation

| Document | Purpose |
|----------|---------|
| `rebtech/docs/ingestion/INGESTION_GUIDE.md` | Complete ingestion guide |
| `.claude/skills/medallion-architecture/references/bronze-patterns.md` | Bronze layer patterns |
| `.claude/skills/dead-letter-queue/SKILL.md` | Error handling patterns |
| `.claude/skills/create-fabric-notebook/SKILL.md` | Notebook creation |
| `.claude/skills/set-up-dbt-on-fabric/SKILL.md` | **Warehouse ingestion for dbt** - fab CLI file loads, Pipeline COPY, COPY INTO |

## Related Skills

- `create-fabric-notebook` (raid-fabric) - Create and deploy notebooks
- [medallion-architecture](../medallion-architecture/SKILL.md) - Tier patterns
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Error handling
- [data-quality-checks](../data-quality-checks/SKILL.md) - Post-ingestion validation

## Quick Decision Tree

```
User says: "I need to ingest data from [SOURCE]"

1. Is it an API or SaaS platform?
   -> Use dlt (see Pattern 1)

2. Is it a database?
   -> Volume < 100MB? Use dlt (see dlt_database_ingestion.py)
   -> Volume > 100MB? Use PySpark JDBC (see Pattern 5)

3. Is it files in Azure Storage?
   -> Use PySpark (see Pattern 3)

4. Is it OneLake data?
   -> Use PySpark (see Pattern 4)

5. Is it streaming (Kafka/Event Hub)?
   -> Use PySpark Structured Streaming

6. Is it SharePoint/M365?
   -> Use dlt with Graph API

7. Is it a local CSV to load to Fabric staging?
   -> Use the fab CLI (see Pattern 6)
   -> Ideal for: dbt staging data, seed data, CI pipelines

Always add audit columns and partition by _ingestion_date!
```
