# ETL Patterns

Extract, transform, and load patterns for the Inmon enterprise data warehouse.

## ETL vs ELT in Inmon Context

| Aspect | ETL (Traditional Inmon) | ELT (Modern Inmon) |
|---|---|---|
| Transform location | Dedicated ETL server | Inside the warehouse engine |
| When to use | On-prem warehouses, complex transformations | Cloud warehouses (Databricks, Snowflake, BigQuery) |
| Staging role | Temporary landing zone | Persistent Bronze layer |
| Tool examples | SSIS, Informatica, Talend | dbt, PySpark, SQL |

Modern Inmon implementations typically use **ELT**: land raw data first (staging/Bronze), then transform inside the warehouse into EDW and mart layers. The architectural principles remain the same -- only the execution location changes.

## Staging Area Patterns

The staging area is functionally identical to the Bronze layer in medallion architecture. For detailed staging patterns, see [build-ingestion-pipeline](../../build-ingestion-pipeline/SKILL.md).

Key staging rules for Inmon EDW:

- **Append-only**: Never update or delete staged records
- **Minimal transformation**: Only add audit columns
- **Partition by ingestion date**: For efficient incremental reads
- **Retain long-term**: Staging is your recovery point

Required audit columns:

| Column | Type | Purpose |
|---|---|---|
| `_ingestion_timestamp` | TIMESTAMP | When the record was captured |
| `_source_system` | STRING | Origin system identifier |
| `_batch_id` | STRING | Processing batch identifier |

## Extract Patterns

### Full Extract

Pull the entire source dataset on each run. Simple but expensive.

```python
# PySpark: Full extract
source_df = spark.read.format("jdbc").options(
    url="jdbc:postgresql://source-db:5432/erp",
    dbtable="public.customers",
    user="readonly",
    password=dbutils.secrets.get("erp", "password"),
).load()

source_df \
    .withColumn("_ingestion_timestamp", F.current_timestamp()) \
    .withColumn("_source_system", F.lit("erp")) \
    .withColumn("_batch_id", F.lit(batch_id)) \
    .write.mode("append") \
    .partitionBy("_ingestion_date") \
    .saveAsTable("staging.erp_customers")
```

When to use: small source tables, sources without reliable timestamps, initial loads.

### Incremental Extract (Watermark)

Pull only records changed since the last extract, based on a timestamp or sequence column.

```python
# PySpark: Incremental extract with watermark
max_ts = spark.table("staging.erp_orders") \
    .agg(F.max("_ingestion_timestamp")).collect()[0][0]

new_records = spark.read.format("jdbc").options(
    url="jdbc:postgresql://source-db:5432/erp",
    dbtable=f"(SELECT * FROM public.orders WHERE updated_at > '{max_ts}') AS q",
    user="readonly",
    password=dbutils.secrets.get("erp", "password"),
).load()

new_records \
    .withColumn("_ingestion_timestamp", F.current_timestamp()) \
    .withColumn("_source_system", F.lit("erp")) \
    .withColumn("_batch_id", F.lit(batch_id)) \
    .write.mode("append") \
    .saveAsTable("staging.erp_orders")
```

When to use: large tables with reliable `updated_at` or sequence columns.

### Change Data Capture (CDC)

Capture row-level changes (insert, update, delete) from the source transaction log.

```python
# PySpark: CDC with Debezium-style events
cdc_events = spark.readStream.format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:9092") \
    .option("subscribe", "erp.public.customers") \
    .load()

parsed = cdc_events.select(
    F.from_json(F.col("value").cast("string"), cdc_schema).alias("data")
).select(
    "data.after.*",
    F.col("data.op").alias("_cdc_operation"),
    F.current_timestamp().alias("_ingestion_timestamp"),
    F.lit("erp").alias("_source_system"),
)

parsed.writeStream \
    .format("delta") \
    .outputMode("append") \
    .option("checkpointLocation", "/checkpoints/erp_customers") \
    .toTable("staging.erp_customers_cdc")
```

When to use: real-time requirements, need to capture deletes, source supports CDC.

## Transform Patterns

### Conformance

Standardize data types, formats, and codes across sources before loading into EDW.

```python
from pyspark.sql import functions as F


def conform_customer(source_df, source_system):
    """Conform customer data from any source to EDW standard."""
    return source_df.select(
        # Standardize business key
        F.col("id").cast("string").alias("customer_id"),
        # Standardize name
        F.initcap(F.trim(F.col("name"))).alias("customer_name"),
        # Standardize email
        F.lower(F.trim(F.col("email"))).alias("email"),
        # Map source-specific segments to enterprise codes
        F.when(F.col("tier") == "gold", "premium")
         .when(F.col("tier") == "silver", "standard")
         .otherwise("basic")
         .alias("segment"),
    )
```

```sql
-- dbt: Conformance in staging model
-- models/staging/stg_crm__customers.sql
SELECT
    CAST(id AS VARCHAR) AS customer_id,
    INITCAP(TRIM(name)) AS customer_name,
    LOWER(TRIM(email)) AS email,
    CASE tier
        WHEN 'gold' THEN 'premium'
        WHEN 'silver' THEN 'standard'
        ELSE 'basic'
    END AS segment
FROM {{ source('crm', 'customers') }}
```

### Normalization Decomposition

Break flat source records into normalized EDW entities.

```python
def decompose_order(flat_order_df):
    """Decompose a flat order record into 3NF entities."""

    # Extract customer entity
    customers = flat_order_df.select(
        "customer_id", "customer_name", "customer_email"
    ).dropDuplicates(["customer_id"])

    # Extract product entity
    products = flat_order_df.select(
        "product_id", "product_name", "product_category", "unit_price"
    ).dropDuplicates(["product_id"])

    # Extract order header
    order_headers = flat_order_df.select(
        "order_id", "customer_id", "order_date", "status"
    ).dropDuplicates(["order_id"])

    # Extract order lines
    order_lines = flat_order_df.select(
        "order_line_id", "order_id", "product_id", "quantity", "line_total"
    )

    return {
        "customer": customers,
        "product": products,
        "order_header": order_headers,
        "order_line": order_lines,
    }
```

### Cross-Source Entity Resolution

When multiple source systems describe the same entity, resolve to a single EDW record.

```python
def resolve_customers(crm_df, erp_df):
    """Resolve customer records across CRM and ERP sources."""

    # Match on email (primary) or name+postal_code (fallback)
    matched = crm_df.alias("crm").join(
        erp_df.alias("erp"),
        (F.col("crm.email") == F.col("erp.email"))
        | (
            (F.col("crm.customer_name") == F.col("erp.customer_name"))
            & (F.col("crm.postal_code") == F.col("erp.postal_code"))
        ),
        "full",
    )

    # CRM is master for name/email; ERP is master for financial attributes
    resolved = matched.select(
        F.coalesce(F.col("crm.customer_id"), F.col("erp.customer_id")).alias("customer_id"),
        F.coalesce(F.col("crm.customer_name"), F.col("erp.customer_name")).alias("customer_name"),
        F.coalesce(F.col("crm.email"), F.col("erp.email")).alias("email"),
        F.coalesce(F.col("erp.credit_limit"), F.lit(0)).alias("credit_limit"),
        F.coalesce(F.col("erp.payment_terms"), F.lit("net30")).alias("payment_terms"),
    )

    return resolved
```

## Load Patterns

### Initial Load

First-time load of EDW entities from staging. All records are new.

```python
def initial_load_edw(spark, staged_df, target_table, business_key, tracked_cols, source_system):
    """Initial load: insert all records with SCD2 metadata."""
    hash_expr = F.md5(F.concat_ws("||", *[F.col(c) for c in tracked_cols]))

    initial = staged_df.select(
        F.col(business_key),
        *[F.col(c) for c in tracked_cols],
        hash_expr.alias("_hash"),
        F.lit(True).alias("_is_current"),
        F.current_date().alias("_valid_from"),
        F.to_date(F.lit("9999-12-31")).alias("_valid_to"),
        F.current_timestamp().alias("_edw_load_timestamp"),
        F.lit("initial").alias("_edw_batch_id"),
        F.lit(source_system).alias("_source_system"),
    )

    initial.write.format("delta").saveAsTable(target_table)
```

### Incremental Load with SCD Type 2

Ongoing loads that detect changes and maintain history. See [scd-pattern](../../scd-pattern/SKILL.md) for the complete SCD2 merge implementation.

Key steps:
1. Read new/changed records from staging (since last watermark)
2. Compute hash of tracked columns
3. Compare hash with current EDW records
4. Close changed records (set `_valid_to`, `_is_current = false`)
5. Insert new versions (set `_valid_from`, `_is_current = true`)

```python
# See SKILL.md load_edw_entity() for the full PySpark implementation
# See SKILL.md edw_customer__customer.sql for the full dbt implementation
```

### Reference Data Load

Reference entities (country, currency, category) use simpler load patterns -- typically SCD Type 1 (overwrite).

```python
def load_reference_entity(spark, source_df, target_table, business_key):
    """Load a reference entity with SCD Type 1 (overwrite on match)."""
    enriched = source_df.withColumn("_edw_load_timestamp", F.current_timestamp())

    if spark.catalog.tableExists(target_table):
        from delta.tables import DeltaTable
        target = DeltaTable.forName(spark, target_table)

        target.alias("t").merge(
            enriched.alias("s"),
            f"t.{business_key} = s.{business_key}"
        ).whenMatchedUpdateAll() \
         .whenNotMatchedInsertAll() \
         .execute()
    else:
        enriched.write.format("delta").saveAsTable(target_table)
```

## Error Handling

Failed records during EDW loading should be routed to a dead letter queue rather than failing the entire batch. See [dead-letter-queue](../../dead-letter-queue/SKILL.md) for implementation patterns.

Common EDW load errors:

| Error | Cause | Handling |
|---|---|---|
| FK violation | Referenced entity not yet loaded | Route to DLQ, retry after parent loads |
| Data type mismatch | Source schema changed | Route to DLQ, alert, fix conformance |
| Duplicate business key | Source sent duplicates in same batch | Deduplicate in staging before EDW load |
| Null business key | Bad source data | Route to DLQ, alert source team |

```python
def load_with_error_handling(spark, source_df, target_table, business_key, dlq_table):
    """Load EDW entity with dead letter queue routing."""
    # Validate records
    valid = source_df.filter(
        F.col(business_key).isNotNull()
        & (F.length(F.col(business_key)) > 0)
    )
    invalid = source_df.filter(
        F.col(business_key).isNull()
        | (F.length(F.col(business_key)) == 0)
    )

    # Route invalid to DLQ
    if invalid.count() > 0:
        invalid.withColumn("_error_reason", F.lit("null_or_empty_business_key")) \
            .withColumn("_error_timestamp", F.current_timestamp()) \
            .write.mode("append") \
            .saveAsTable(dlq_table)

    # Load valid records
    if valid.count() > 0:
        # ... proceed with normal EDW load
        pass
```

## Orchestration Dependencies

ETL jobs must execute in strict dependency order. See [data-platform-orchestration](../../data-platform-orchestration/SKILL.md) for scheduling patterns.

### Dependency Graph

```
staging.erp_customers ─────> edw.customer_customer ─────> marts.shared.dim_customer ─> marts.sales.fct_sales
staging.erp_orders ────────> edw.transaction_order_header ──────────────────────────/
staging.erp_order_lines ───> edw.transaction_order_line ───────────────────────────/
staging.erp_products ──────> edw.product_product ──────────> marts.shared.dim_product ──/
```

Rules:
1. All staging jobs run first (can run in parallel across sources)
2. EDW entity loads run after their staging dependencies
3. EDW entities with FK dependencies run after parent entities (e.g., `order_line` after `order_header`)
4. Mart builds run after all referenced EDW entities are current
5. Conformed dimensions build before fact tables that reference them

### Orchestration Pattern

```python
# Pseudocode: DAG definition
dag = {
    "staging": {
        "erp_customers": [],
        "erp_orders": [],
        "erp_order_lines": ["erp_orders"],
        "erp_products": [],
    },
    "edw": {
        "customer_customer": ["staging.erp_customers"],
        "product_product": ["staging.erp_products"],
        "transaction_order_header": ["staging.erp_orders", "edw.customer_customer"],
        "transaction_order_line": ["staging.erp_order_lines", "edw.transaction_order_header", "edw.product_product"],
    },
    "marts": {
        "dim_customer": ["edw.customer_customer"],
        "dim_product": ["edw.product_product"],
        "fct_sales": ["edw.transaction_order_line", "marts.dim_customer", "marts.dim_product"],
    },
}
```

```yaml
# dbt: dependency ordering is handled automatically via ref()
# Just ensure your models reference upstream models correctly:
#
# stg_erp__customers.sql         -> edw_customer__customer.sql -> dim_customer.sql -> fct_sales.sql
# stg_erp__orders.sql            -> edw_transaction__order_header.sql             /
# stg_erp__order_lines.sql       -> edw_transaction__order_line.sql              /
# stg_erp__products.sql          -> edw_product__product.sql  -> dim_product.sql /
```
