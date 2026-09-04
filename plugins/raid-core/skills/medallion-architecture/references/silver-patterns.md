# Silver Layer Patterns

This is the canonical, platform-agnostic source for Silver patterns. Fabric-specific deltas live in
the `fabric-architecture` skill (raid-fabric), Silver Architecture reference.

Patterns for data cleansing, conforming, and historical tracking in the Silver layer.

## Core Responsibilities

1. **Data Cleansing**: Standardize formats, handle nulls, fix errors
1. **Deduplication**: Remove duplicates, handle late-arriving data
1. **Type Standardization**: Consistent types across sources
1. **Historical Tracking**: SCD Type 2 for key entities
1. **Schema Conformance**: Normalized 3NF structure

## Data Cleansing Patterns

### String Standardization

```python
# PySpark cleansing functions
from pyspark.sql import functions as F

def clean_string_columns(df, columns: list):
    """Trim, lowercase, and normalize whitespace."""
    for col_name in columns:
        df = df.withColumn(
            col_name,
            F.lower(F.trim(F.regexp_replace(F.col(col_name), r'\s+', ' ')))
        )
    return df

def standardize_email(df, column: str):
    """Lowercase and validate email format."""
    return df.withColumn(
        column,
        F.when(
            F.col(column).rlike(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'),
            F.lower(F.trim(F.col(column)))
        ).otherwise(F.lit(None))
    )

def standardize_phone(df, column: str):
    """Remove non-numeric characters from phone."""
    return df.withColumn(
        column,
        F.regexp_replace(F.col(column), r'[^0-9]', '')
    )
```

```sql
-- dbt cleansing
SELECT
    customer_id,
    LOWER(TRIM(email)) AS email,
    REGEXP_REPLACE(phone, '[^0-9]', '') AS phone,
    UPPER(TRIM(country_code)) AS country_code,
    INITCAP(TRIM(customer_name)) AS customer_name
FROM {{ ref('stg_customers') }}
```

### Null Handling

```python
# PySpark null handling
def handle_nulls(df, defaults: dict):
    """Replace nulls with default values."""
    for col_name, default_value in defaults.items():
        df = df.withColumn(
            col_name,
            F.coalesce(F.col(col_name), F.lit(default_value))
        )
    return df

# Usage
df = handle_nulls(df, {
    "status": "unknown",
    "country": "US",
    "amount": 0.0
})
```

```sql
-- dbt null handling
SELECT
    customer_id,
    COALESCE(status, 'unknown') AS status,
    COALESCE(country, 'US') AS country,
    COALESCE(amount, 0) AS amount
FROM {{ ref('stg_orders') }}
```

### Date Standardization

```python
# PySpark date handling
def standardize_dates(df, date_columns: list, source_formats: list = None):
    """Convert various date formats to standard DATE type."""
    formats = source_formats or [
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "dd-MM-yyyy",
        "yyyy/MM/dd"
    ]

    for col_name in date_columns:
        # Try each format
        date_expr = F.lit(None).cast("date")
        for fmt in formats:
            date_expr = F.coalesce(
                F.to_date(F.col(col_name), fmt),
                date_expr
            )
        df = df.withColumn(col_name, date_expr)

    return df
```

### Code/Reference Standardization

```python
# PySpark - Standardize codes with lookup
def standardize_with_lookup(df, column: str, lookup_table: str, lookup_key: str, lookup_value: str):
    """Map non-standard codes to standard values."""
    lookup_df = spark.table(lookup_table)

    return df.join(
        lookup_df.select(
            F.col(lookup_key).alias("_lookup_key"),
            F.col(lookup_value).alias("_standard_value")
        ),
        F.upper(F.trim(F.col(column))) == F.col("_lookup_key"),
        "left"
    ).withColumn(
        column,
        F.coalesce(F.col("_standard_value"), F.col(column))
    ).drop("_lookup_key", "_standard_value")
```

## Deduplication Patterns

### Exact Duplicate Removal

```python
# PySpark - Remove exact duplicates
df_deduplicated = df.dropDuplicates()

# Remove duplicates on specific columns
df_deduplicated = df.dropDuplicates(["customer_id", "order_date"])
```

### Keep Latest Record

```python
# PySpark - Keep latest by timestamp
from pyspark.sql.window import Window

def keep_latest(df, partition_cols: list, order_col: str):
    """Keep only the latest record per partition."""
    window = Window.partitionBy(*partition_cols).orderBy(F.desc(order_col))

    return df \
        .withColumn("_rn", F.row_number().over(window)) \
        .filter(F.col("_rn") == 1) \
        .drop("_rn")

# Usage
df = keep_latest(df, ["customer_id"], "updated_at")
```

```sql
-- dbt - Keep latest
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC
        ) AS rn
    FROM {{ ref('stg_customers') }}
)
SELECT * FROM ranked WHERE rn = 1
```

### Keep First Record

```python
# PySpark - Keep first occurrence
def keep_first(df, partition_cols: list, order_col: str):
    """Keep only the first record per partition."""
    window = Window.partitionBy(*partition_cols).orderBy(F.asc(order_col))

    return df \
        .withColumn("_rn", F.row_number().over(window)) \
        .filter(F.col("_rn") == 1) \
        .drop("_rn")
```

### Merge Duplicates

```python
# PySpark - Merge duplicate records (take non-null values)
def merge_duplicates(df, key_cols: list, value_cols: list):
    """Merge duplicates taking first non-null value for each column."""
    agg_exprs = [F.first(col, ignorenulls=True).alias(col) for col in value_cols]

    return df.groupBy(*key_cols).agg(*agg_exprs)
```

## SCD Type 2 Implementation

See [scd-pattern](../../scd-pattern/SKILL.md) for complete SCD implementation.

### Quick Reference

```python
# Required columns for SCD Type 2
scd2_columns = [
    "_valid_from",      # DATE - Start of validity
    "_valid_to",        # DATE - End (9999-12-31 for current)
    "_is_current",      # BOOLEAN - Current record flag
    "_hash",            # STRING - Change detection hash
    "_load_timestamp"   # TIMESTAMP - When processed
]

# Hash generation
hash_cols = ["name", "email", "address", "status"]
df = df.withColumn(
    "_hash",
    F.md5(F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in hash_cols]))
)
```

## Schema Conformance

### Column Renaming and Type Casting

```python
# PySpark - Conform schema
def conform_schema(df, column_mapping: dict, type_casting: dict):
    """
    Rename columns and cast types.

    column_mapping: {"source_col": "target_col"}
    type_casting: {"column": "type"}
    """
    # Rename
    for source, target in column_mapping.items():
        if source in df.columns:
            df = df.withColumnRenamed(source, target)

    # Cast types
    for column, dtype in type_casting.items():
        if column in df.columns:
            df = df.withColumn(column, F.col(column).cast(dtype))

    return df

# Usage
df = conform_schema(
    df,
    column_mapping={
        "cust_id": "customer_id",
        "cust_name": "customer_name",
        "amt": "amount"
    },
    type_casting={
        "amount": "decimal(18,2)",
        "order_date": "date",
        "is_active": "boolean"
    }
)
```

```sql
-- dbt schema conformance
SELECT
    CAST(cust_id AS VARCHAR(50)) AS customer_id,
    CAST(cust_name AS VARCHAR(200)) AS customer_name,
    CAST(amt AS DECIMAL(18,2)) AS amount,
    CAST(order_dt AS DATE) AS order_date,
    CAST(active_flag AS BOOLEAN) AS is_active
FROM {{ ref('stg_orders') }}
```

### Multi-Source Conformance

```python
# PySpark - Combine multiple sources into unified schema
def unify_sources(spark, source_configs: list):
    """
    Unify multiple sources into single schema.

    source_configs: [
        {"table": "bronze.source_a", "mapping": {...}, "source_id": "A"},
        {"table": "bronze.source_b", "mapping": {...}, "source_id": "B"}
    ]
    """
    unified_df = None

    for config in source_configs:
        df = spark.table(config["table"])

        # Apply mapping
        for source_col, target_col in config["mapping"].items():
            if source_col in df.columns:
                df = df.withColumnRenamed(source_col, target_col)

        # Add source identifier
        df = df.withColumn("_source_id", F.lit(config["source_id"]))

        # Union
        if unified_df is None:
            unified_df = df
        else:
            # Align schemas before union
            unified_df = unified_df.unionByName(df, allowMissingColumns=True)

    return unified_df
```

## Validation Patterns

### Data Quality Checks

```python
# PySpark - Validation with routing
def validate_and_route(df, rules: list, error_table: str):
    """
    Apply validation rules and route failures to error table.

    rules: [
        {"name": "not_null_id", "condition": "id IS NOT NULL", "severity": "critical"},
        {"name": "valid_amount", "condition": "amount >= 0", "severity": "warning"}
    ]
    """
    # Add validation columns
    for rule in rules:
        df = df.withColumn(
            f"_valid_{rule['name']}",
            F.expr(rule["condition"])
        )

    # Separate valid and invalid
    valid_condition = F.lit(True)
    for rule in rules:
        if rule["severity"] == "critical":
            valid_condition = valid_condition & F.col(f"_valid_{rule['name']}")

    valid_df = df.filter(valid_condition)
    invalid_df = df.filter(~valid_condition)

    # Clean up validation columns from valid records
    for rule in rules:
        valid_df = valid_df.drop(f"_valid_{rule['name']}")

    # Write invalid to error table
    if invalid_df.count() > 0:
        invalid_df \
            .withColumn("_error_timestamp", F.current_timestamp()) \
            .write.mode("append").saveAsTable(error_table)

    return valid_df
```

### Referential Integrity

```python
# PySpark - Check foreign key references
def check_referential_integrity(
    df,
    fk_column: str,
    reference_table: str,
    reference_column: str
):
    """Check if all FK values exist in reference table."""
    ref_df = spark.table(reference_table).select(
        F.col(reference_column).alias("_ref_key")
    ).distinct()

    # Find orphans
    orphans = df.join(
        ref_df,
        F.col(fk_column) == F.col("_ref_key"),
        "left_anti"
    )

    return {
        "total_records": df.count(),
        "orphan_records": orphans.count(),
        "orphan_keys": [row[fk_column] for row in orphans.select(fk_column).distinct().limit(100).collect()]
    }
```

## dbt Silver Patterns

### Intermediate Model

```sql
-- models/intermediate/int_customers_cleansed.sql
{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    incremental_strategy='merge'
  )
}}

WITH source AS (
    SELECT * FROM {{ ref('stg_salesforce__accounts') }}
    {% if is_incremental() %}
    WHERE _ingestion_timestamp > (SELECT MAX(_load_timestamp) FROM {{ this }})
    {% endif %}
),

cleansed AS (
    SELECT
        customer_id,
        -- Cleanse name
        INITCAP(TRIM(customer_name)) AS customer_name,
        -- Standardize email
        LOWER(TRIM(email)) AS email,
        -- Standardize phone
        REGEXP_REPLACE(phone, '[^0-9]', '') AS phone,
        -- Standardize status
        UPPER(TRIM(status)) AS status,
        -- Coalesce nulls
        COALESCE(country, 'US') AS country,
        -- Audit
        _ingestion_timestamp,
        CURRENT_TIMESTAMP() AS _load_timestamp
    FROM source
),

deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY _ingestion_timestamp DESC
        ) AS _rn
    FROM cleansed
)

SELECT
    customer_id,
    customer_name,
    email,
    phone,
    status,
    country,
    _load_timestamp
FROM deduplicated
WHERE _rn = 1
```

### SCD Type 2 with dbt Snapshots

```sql
-- snapshots/customer_snapshot.sql
{% snapshot customer_snapshot %}
{{
    config(
      target_schema='silver',
      unique_key='customer_id',
      strategy='check',
      check_cols=['customer_name', 'email', 'status', 'country']
    )
}}

SELECT
    customer_id,
    customer_name,
    email,
    status,
    country
FROM {{ ref('int_customers_cleansed') }}

{% endsnapshot %}
```

## Performance Optimization

### Partition Pruning

```python
# Filter on partition column first
df = spark.table("silver.orders") \
    .filter(F.col("order_date") >= "2024-01-01") \
    .filter(F.col("status") == "completed")  # Non-partition filter second
```

### Z-Ordering

```sql
-- Optimize for common query patterns
OPTIMIZE silver.customers
ZORDER BY (customer_id);

OPTIMIZE silver.orders
ZORDER BY (customer_id, order_date);
```

### Caching Frequently Joined Tables

```python
# Cache reference tables
customers_df = spark.table("silver.customers").cache()
products_df = spark.table("silver.products").cache()

# Use in multiple joins
orders_enriched = orders_df \
    .join(customers_df, "customer_id") \
    .join(products_df, "product_id")
```
