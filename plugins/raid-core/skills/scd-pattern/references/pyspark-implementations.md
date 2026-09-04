# PySpark SCD Implementations

Complete reference for implementing Slowly Changing Dimensions using PySpark and Delta Lake.

## SCD Type 2: Full Implementation

### Complete Function with All Features

```python
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from delta.tables import DeltaTable
from typing import List, Optional
import uuid

def apply_scd_type2(
    spark: SparkSession,
    source_df: DataFrame,
    target_table: str,
    business_key: str,
    tracked_columns: List[str],
    surrogate_key_col: str = "sk",
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to",
    is_current_col: str = "_is_current",
    hash_col: str = "_hash",
    end_date: str = "9999-12-31"
) -> dict:
    """
    Apply SCD Type 2 pattern to a Delta Lake table.

    Args:
        spark: SparkSession
        source_df: Source DataFrame with current data
        target_table: Target Delta table name (e.g., "gold.dim_customer")
        business_key: Column name for business key
        tracked_columns: List of columns to track for changes
        surrogate_key_col: Name of surrogate key column
        valid_from_col: Name of valid_from column
        valid_to_col: Name of valid_to column
        is_current_col: Name of is_current flag column
        hash_col: Name of hash column
        end_date: End date for current records

    Returns:
        dict with counts: inserted, updated, unchanged
    """
    # Generate hash for change detection
    hash_expr = F.md5(
        F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("NULL")) for c in tracked_columns])
    )

    source_with_hash = source_df.withColumn(hash_col, hash_expr)

    # Check if target exists
    if not spark.catalog.tableExists(target_table):
        # Initial load
        initial_df = source_with_hash.select(
            F.expr("uuid()").alias(surrogate_key_col),
            F.col(business_key),
            *[F.col(c) for c in tracked_columns],
            F.col(hash_col),
            F.current_date().alias(valid_from_col),
            F.to_date(F.lit(end_date)).alias(valid_to_col),
            F.lit(True).alias(is_current_col)
        )

        initial_df.write.format("delta").saveAsTable(target_table)

        return {
            "inserted": initial_df.count(),
            "updated": 0,
            "unchanged": 0
        }

    # Incremental load
    target_delta = DeltaTable.forName(spark, target_table)
    target_df = spark.table(target_table)

    # Get current records
    current_df = target_df.filter(F.col(is_current_col) == True)

    # Classify records
    classified = source_with_hash.alias("src").join(
        current_df.alias("tgt"),
        F.col(f"src.{business_key}") == F.col(f"tgt.{business_key}"),
        "full_outer"
    ).select(
        F.col(f"src.{business_key}").alias("src_key"),
        F.col(f"tgt.{business_key}").alias("tgt_key"),
        *[F.col(f"src.{c}").alias(f"src_{c}") for c in tracked_columns],
        F.col(f"src.{hash_col}").alias("src_hash"),
        F.col(f"tgt.{hash_col}").alias("tgt_hash"),
        F.col(f"tgt.{surrogate_key_col}").alias("tgt_sk"),
        F.col(f"tgt.{valid_from_col}").alias("tgt_valid_from"),
        F.when(
            F.col(f"tgt.{business_key}").isNull(),
            F.lit("INSERT")
        ).when(
            F.col(f"src.{business_key}").isNull(),
            F.lit("DELETE")  # Optional: handle deletes
        ).when(
            F.col(f"src.{hash_col}") != F.col(f"tgt.{hash_col}"),
            F.lit("UPDATE")
        ).otherwise(
            F.lit("UNCHANGED")
        ).alias("action")
    )

    # Count by action
    counts = classified.groupBy("action").count().collect()
    count_dict = {row["action"]: row["count"] for row in counts}

    # Records to insert (new and changed)
    to_insert = classified.filter(
        F.col("action").isin(["INSERT", "UPDATE"])
    ).select(
        F.expr("uuid()").alias(surrogate_key_col),
        F.col("src_key").alias(business_key),
        *[F.col(f"src_{c}").alias(c) for c in tracked_columns],
        F.col("src_hash").alias(hash_col),
        F.current_date().alias(valid_from_col),
        F.to_date(F.lit(end_date)).alias(valid_to_col),
        F.lit(True).alias(is_current_col)
    )

    # Keys to expire
    keys_to_expire = classified.filter(F.col("action") == "UPDATE") \
        .select("tgt_key").distinct().collect()
    keys_list = [row["tgt_key"] for row in keys_to_expire]

    if keys_list:
        # Expire old records
        target_delta.update(
            condition=(
                (F.col(business_key).isin(keys_list)) &
                (F.col(is_current_col) == True)
            ),
            set={
                is_current_col: F.lit(False),
                valid_to_col: F.date_sub(F.current_date(), 1)
            }
        )

    # Insert new records
    if to_insert.count() > 0:
        to_insert.write.mode("append").format("delta").saveAsTable(target_table)

    return {
        "inserted": count_dict.get("INSERT", 0),
        "updated": count_dict.get("UPDATE", 0),
        "unchanged": count_dict.get("UNCHANGED", 0)
    }
```

### Usage Example

```python
# Load source data
customers_df = spark.table("silver.customers_cleansed")

# Apply SCD Type 2
result = apply_scd_type2(
    spark=spark,
    source_df=customers_df,
    target_table="gold.dim_customer",
    business_key="customer_id",
    tracked_columns=["customer_name", "email", "address", "status", "segment"]
)

print(f"Inserted: {result['inserted']}")
print(f"Updated: {result['updated']}")
print(f"Unchanged: {result['unchanged']}")
```

## SCD Type 2: Delta Lake Merge Pattern

Alternative using native Delta merge:

```python
from delta.tables import DeltaTable

def scd2_merge(
    spark: SparkSession,
    source_df: DataFrame,
    target_table: str,
    business_key: str,
    tracked_columns: List[str]
):
    """SCD Type 2 using Delta Lake MERGE."""

    # Add hash and metadata to source
    hash_cols = [F.coalesce(F.col(c).cast("string"), F.lit("")) for c in tracked_columns]
    source_prepared = source_df \
        .withColumn("_hash", F.md5(F.concat_ws("||", *hash_cols))) \
        .withColumn("_valid_from", F.current_date()) \
        .withColumn("_valid_to", F.to_date(F.lit("9999-12-31"))) \
        .withColumn("_is_current", F.lit(True))

    if not spark.catalog.tableExists(target_table):
        source_prepared.write.format("delta").saveAsTable(target_table)
        return

    target = DeltaTable.forName(spark, target_table)

    # Step 1: Identify changed records and close them
    target.alias("tgt").merge(
        source_prepared.alias("src"),
        f"tgt.{business_key} = src.{business_key} AND tgt._is_current = true"
    ).whenMatchedUpdate(
        condition="tgt._hash != src._hash",
        set={
            "_is_current": "false",
            "_valid_to": "date_sub(current_date(), 1)"
        }
    ).execute()

    # Step 2: Insert new versions
    # Get current hashes from target
    current_hashes = spark.table(target_table) \
        .filter(F.col("_is_current") == True) \
        .select(business_key, "_hash")

    # Find records to insert (new or changed)
    to_insert = source_prepared.alias("src").join(
        current_hashes.alias("cur"),
        F.col(f"src.{business_key}") == F.col(f"cur.{business_key}"),
        "left_anti"  # Not in current (new or was just closed)
    )

    # Also add records that were just closed (hash changed)
    changed = source_prepared.alias("src").join(
        spark.table(target_table).filter(F.col("_is_current") == False).alias("closed"),
        (F.col(f"src.{business_key}") == F.col(f"closed.{business_key}")) &
        (F.col("closed._valid_to") == F.date_sub(F.current_date(), 1)),
        "inner"
    ).select("src.*")

    # Union and insert
    to_insert.unionByName(changed).write.mode("append").format("delta").saveAsTable(target_table)
```

## SCD Type 1: Overwrite

```python
def apply_scd_type1(
    spark: SparkSession,
    source_df: DataFrame,
    target_table: str,
    business_key: str,
    update_columns: List[str]
):
    """
    Apply SCD Type 1 (overwrite) pattern.

    Args:
        spark: SparkSession
        source_df: Source DataFrame
        target_table: Target table name
        business_key: Business key column
        update_columns: Columns to update on match
    """
    if not spark.catalog.tableExists(target_table):
        source_df.write.format("delta").saveAsTable(target_table)
        return

    target = DeltaTable.forName(spark, target_table)

    # Build update set
    update_set = {col: f"src.{col}" for col in update_columns}
    update_set["updated_at"] = "current_timestamp()"

    # Build insert values
    all_columns = [business_key] + update_columns
    insert_values = {col: f"src.{col}" for col in all_columns}
    insert_values["created_at"] = "current_timestamp()"
    insert_values["updated_at"] = "current_timestamp()"

    target.alias("tgt").merge(
        source_df.alias("src"),
        f"tgt.{business_key} = src.{business_key}"
    ).whenMatchedUpdate(
        set=update_set
    ).whenNotMatchedInsert(
        values=insert_values
    ).execute()
```

### Usage

```python
apply_scd_type1(
    spark=spark,
    source_df=spark.table("silver.products"),
    target_table="gold.dim_product",
    business_key="product_id",
    update_columns=["product_name", "category", "price"]
)
```

## SCD Type 3: Previous Value

```python
def apply_scd_type3(
    spark: SparkSession,
    source_df: DataFrame,
    target_table: str,
    business_key: str,
    tracked_column: str
):
    """
    Apply SCD Type 3 pattern (current + previous value).

    Args:
        spark: SparkSession
        source_df: Source DataFrame
        target_table: Target table name
        business_key: Business key column
        tracked_column: Column to track (current/previous)
    """
    current_col = f"current_{tracked_column}"
    previous_col = f"previous_{tracked_column}"

    if not spark.catalog.tableExists(target_table):
        initial = source_df.select(
            F.col(business_key),
            F.col(tracked_column).alias(current_col),
            F.lit(None).cast("string").alias(previous_col),
            F.lit(None).cast("date").alias("change_date"),
            F.current_timestamp().alias("updated_at")
        )
        initial.write.format("delta").saveAsTable(target_table)
        return

    target_df = spark.table(target_table)

    result = source_df.alias("src").join(
        target_df.alias("tgt"),
        F.col(f"src.{business_key}") == F.col(f"tgt.{business_key}"),
        "left"
    ).select(
        F.col(f"src.{business_key}"),
        F.col(f"src.{tracked_column}").alias(current_col),
        F.when(
            F.col(f"tgt.{current_col}").isNotNull() &
            (F.col(f"tgt.{current_col}") != F.col(f"src.{tracked_column}")),
            F.col(f"tgt.{current_col}")
        ).otherwise(
            F.col(f"tgt.{previous_col}")
        ).alias(previous_col),
        F.when(
            F.col(f"tgt.{current_col}").isNotNull() &
            (F.col(f"tgt.{current_col}") != F.col(f"src.{tracked_column}")),
            F.current_date()
        ).otherwise(
            F.col("tgt.change_date")
        ).alias("change_date"),
        F.current_timestamp().alias("updated_at")
    )

    result.write.mode("overwrite").format("delta").saveAsTable(target_table)
```

## Point-in-Time Queries

### Query Historical State

```python
def get_as_of_date(
    spark: SparkSession,
    table_name: str,
    as_of_date: str,
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to"
) -> DataFrame:
    """Get records as they were on a specific date."""
    return spark.table(table_name).filter(
        (F.col(valid_from_col) <= F.lit(as_of_date)) &
        (F.col(valid_to_col) >= F.lit(as_of_date))
    )

# Usage
customers_june_2024 = get_as_of_date(
    spark, "gold.dim_customer", "2024-06-15"
)
```

### Get All Versions of a Record

```python
def get_record_history(
    spark: SparkSession,
    table_name: str,
    business_key: str,
    key_value: str,
    valid_from_col: str = "_valid_from"
) -> DataFrame:
    """Get complete history of a single record."""
    return spark.table(table_name) \
        .filter(F.col(business_key) == key_value) \
        .orderBy(F.col(valid_from_col))

# Usage
customer_history = get_record_history(
    spark, "gold.dim_customer", "customer_id", "C12345"
)
customer_history.show()
```

### Join Fact to Dimension at Transaction Time

```python
def join_fact_to_dim_scd2(
    fact_df: DataFrame,
    dim_df: DataFrame,
    fact_key: str,
    dim_key: str,
    fact_date: str,
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to"
) -> DataFrame:
    """Join fact table to SCD Type 2 dimension using transaction date."""
    return fact_df.alias("f").join(
        dim_df.alias("d"),
        (F.col(f"f.{fact_key}") == F.col(f"d.{dim_key}")) &
        (F.col(f"f.{fact_date}") >= F.col(f"d.{valid_from_col}")) &
        (F.col(f"f.{fact_date}") <= F.col(f"d.{valid_to_col}")),
        "inner"
    )

# Usage
sales_with_customer = join_fact_to_dim_scd2(
    fact_df=spark.table("gold.fact_sales"),
    dim_df=spark.table("gold.dim_customer"),
    fact_key="customer_id",
    dim_key="customer_id",
    fact_date="transaction_date"
)
```

## Change Detection Utilities

### Compare Source and Target

```python
def detect_changes(
    source_df: DataFrame,
    target_df: DataFrame,
    business_key: str,
    tracked_columns: List[str]
) -> DataFrame:
    """
    Detect inserts, updates, deletes between source and target.

    Returns DataFrame with columns: business_key, action (INSERT/UPDATE/DELETE/UNCHANGED)
    """
    # Generate hashes
    hash_expr = F.md5(F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in tracked_columns]))

    source_hashed = source_df.select(
        F.col(business_key),
        hash_expr.alias("source_hash")
    )

    target_hashed = target_df.filter(F.col("_is_current") == True).select(
        F.col(business_key),
        F.col("_hash").alias("target_hash")
    )

    return source_hashed.alias("s").join(
        target_hashed.alias("t"),
        F.col(f"s.{business_key}") == F.col(f"t.{business_key}"),
        "full_outer"
    ).select(
        F.coalesce(F.col(f"s.{business_key}"), F.col(f"t.{business_key}")).alias(business_key),
        F.when(F.col("target_hash").isNull(), "INSERT")
         .when(F.col("source_hash").isNull(), "DELETE")
         .when(F.col("source_hash") != F.col("target_hash"), "UPDATE")
         .otherwise("UNCHANGED")
         .alias("action")
    )

# Usage
changes = detect_changes(
    source_df=spark.table("silver.customers"),
    target_df=spark.table("gold.dim_customer"),
    business_key="customer_id",
    tracked_columns=["customer_name", "email", "status"]
)

changes.groupBy("action").count().show()
```

## Performance Optimization

### Partitioning Strategy

```python
# Partition by _is_current for fast current-record queries
df.write \
    .format("delta") \
    .partitionBy("_is_current") \
    .saveAsTable("gold.dim_customer")

# Z-order by business key for efficient lookups
spark.sql("""
    OPTIMIZE gold.dim_customer
    ZORDER BY (customer_id)
""")
```

### Handling Large SCD Tables

```python
# Use broadcast for small dimension lookups
from pyspark.sql.functions import broadcast

fact_df.join(
    broadcast(dim_df.filter(F.col("_is_current") == True)),
    "customer_id"
)

# Cache current records if used multiple times
current_customers = spark.table("gold.dim_customer") \
    .filter(F.col("_is_current") == True) \
    .cache()
```

### Incremental Processing with Watermarks

```python
def get_incremental_source(
    spark: SparkSession,
    source_table: str,
    target_table: str,
    timestamp_col: str
) -> DataFrame:
    """Get only new/changed records since last load."""

    # Get max timestamp from target
    max_ts = spark.table(target_table) \
        .agg(F.max("_valid_from")) \
        .collect()[0][0]

    if max_ts:
        return spark.table(source_table).filter(
            F.col(timestamp_col) > max_ts
        )
    else:
        return spark.table(source_table)
```

## Error Handling

```python
def safe_scd2_apply(
    spark: SparkSession,
    source_df: DataFrame,
    target_table: str,
    business_key: str,
    tracked_columns: List[str]
) -> dict:
    """Apply SCD Type 2 with error handling and rollback."""

    # Create savepoint (Delta time travel)
    if spark.catalog.tableExists(target_table):
        version_before = spark.sql(f"DESCRIBE HISTORY {target_table}") \
            .orderBy(F.col("version").desc()) \
            .first()["version"]
    else:
        version_before = None

    try:
        result = apply_scd_type2(
            spark=spark,
            source_df=source_df,
            target_table=target_table,
            business_key=business_key,
            tracked_columns=tracked_columns
        )
        return {"success": True, "result": result}

    except Exception as e:
        # Rollback to previous version
        if version_before is not None:
            spark.sql(f"""
                RESTORE TABLE {target_table}
                TO VERSION AS OF {version_before}
            """)

        return {"success": False, "error": str(e)}
```
