---
name: scd-pattern
description: >-
  Use when tracking historical changes to dimension data, implementing time-travel
  queries, or deciding between SCD types. Triggers include 'SCD Type 1', 'SCD Type 2',
  'slowly changing dimension', 'track history', 'historical changes', 'dimension
  versioning', 'snapshot', 'point-in-time query'. Guide for implementing Slowly Changing
  Dimensions (Type 1, 2, 3) across data platforms.
---

# Slowly Changing Dimension (SCD) Patterns

Guide for implementing SCD patterns in data warehouses across platforms (Databricks, Snowflake, Fabric, BigQuery) using dbt and PySpark.

## When to Use This Skill

Use this skill when users ask about:

- **Type selection**: "Should I use SCD Type 1 or Type 2?"
- **History tracking**: "How do I track changes to customer data over time?"
- **Implementation**: "How do I implement SCD Type 2 in dbt/PySpark?"
- **Point-in-time queries**: "How do I query what the data looked like on a specific date?"
- **Snapshots**: "How do I set up dbt snapshots?"
- **Change detection**: "How do I detect changes between loads?"

**Note**: This skill is **platform-agnostic**. For Microsoft Fabric-specific SCD implementation, see `fabric-architecture` (raid-fabric) and its Silver Architecture reference.

## SCD Type Decision Tree

```
Do you need to track historical changes?
|
|-- No --> SCD Type 1 (Overwrite)
|         - Simplest approach
|         - Only current state
|         - Use for: error corrections, non-critical attributes
|
|-- Yes --> How much history do you need?
    |
    |-- Only current + previous value --> SCD Type 3
    |   - Add previous_value column
    |   - Limited history (1 prior value)
    |   - Use for: simple before/after comparisons
    |
    |-- Full history --> SCD Type 2
        |
        |-- What query patterns?
            |
            |-- Point-in-time queries --> Date range approach
            |   - _valid_from, _valid_to columns
            |   - WHERE query_date BETWEEN _valid_from AND _valid_to
            |
            |-- Current state only --> Flag approach
            |   - _is_current boolean
            |   - WHERE _is_current = true
            |
            |-- Both --> Combined approach (recommended)
                - _valid_from, _valid_to, _is_current, _hash
```

## Quick Reference: SCD Type Comparison

| Aspect | Type 1 | Type 2 | Type 3 |
|--------|--------|--------|--------|
| **History** | None | Full | Limited (1 prior) |
| **Storage** | Low | High (grows with changes) | Medium |
| **Complexity** | Simple | Complex | Medium |
| **Query Speed** | Fast | Slower (more rows) | Fast |
| **Use Case** | Corrections | Compliance, analytics | Quick comparison |
| **dbt Method** | incremental/merge | snapshot | incremental |

## SCD Type 1: Overwrite

### When to Use

- Error corrections to source data
- Attributes that don't require history (e.g., fixing typos)
- Non-business-critical fields
- Storage-constrained environments
- Real-time/operational reporting

### Required Columns

No special columns required - just update in place.

### dbt Implementation

```sql
-- models/marts/dim_customer.sql
{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    merge_update_columns=['customer_name', 'email', 'address', 'updated_at']
  )
}}

SELECT
    customer_id,
    customer_name,
    email,
    address,
    updated_at
FROM {{ ref('stg_customers') }}

{% if is_incremental() %}
WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

### PySpark Implementation

```python
from delta.tables import DeltaTable

# Load source and target
source_df = spark.read.table("silver.customers_cleansed")
target_table = DeltaTable.forName(spark, "gold.dim_customer")

# Merge with overwrite (Type 1)
target_table.alias("target").merge(
    source_df.alias("source"),
    "target.customer_id = source.customer_id"
).whenMatchedUpdate(
    set={
        "customer_name": "source.customer_name",
        "email": "source.email",
        "address": "source.address",
        "updated_at": "current_timestamp()"
    }
).whenNotMatchedInsert(
    values={
        "customer_id": "source.customer_id",
        "customer_name": "source.customer_name",
        "email": "source.email",
        "address": "source.address",
        "created_at": "current_timestamp()",
        "updated_at": "current_timestamp()"
    }
).execute()
```

## SCD Type 2: Full History

### When to Use

- Regulatory/compliance requirements (audit trails)
- Historical trend analysis
- Point-in-time reporting ("what did the data look like on date X?")
- Fact table foreign key integrity (preserving relationships)
- Slowly changing reference data (products, customers, employees)

### Required Columns

| Column | Type | Purpose |
|--------|------|---------|
| `_valid_from` | DATE/TIMESTAMP | Start of validity period |
| `_valid_to` | DATE/TIMESTAMP | End of validity period (9999-12-31 for current) |
| `_is_current` | BOOLEAN | Quick filter for current records |
| `_hash` | STRING | Change detection (MD5/SHA256 of business columns) |
| `_surrogate_key` | INT/STRING | Unique row identifier (optional but recommended) |

### dbt Snapshot Implementation

```sql
-- snapshots/customer_snapshot.sql
{% snapshot customer_snapshot %}

{{
    config(
      target_database='analytics',
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='check',
      check_cols=['customer_name', 'email', 'address', 'status'],
      -- OR use timestamp strategy:
      -- strategy='timestamp',
      -- updated_at='updated_at',
    )
}}

SELECT
    customer_id,
    customer_name,
    email,
    address,
    status,
    updated_at
FROM {{ source('raw', 'customers') }}

{% endsnapshot %}
```

This creates columns: `dbt_scd_id`, `dbt_updated_at`, `dbt_valid_from`, `dbt_valid_to`

### Proven shape: dbt snapshot with a derived change timestamp (field-validated on Fabric Warehouse)

dbt's native snapshot works on Fabric Warehouse - no hand-rolled SCD2 merge needed
(validated live, 2026-06, despite the managed runtime's old adapter and the
no-NOT-NULL-on-snapshot-sources guardrail). The working shape generalizes to any platform:

- **Timestamp strategy on a derived `_change_ts`**, where
  `_change_ts = GREATEST(InsertedDateTime, LastUpdatedDatetime, DeactivatedDateTime)` -
  one expression covering **every mutable timestamp column** the source has. The third
  column is load-bearing: if deactivation does not touch `LastUpdatedDatetime` in the
  source, a 2-column expression never versions deactivations and SCD2 silently misses an
  entire change class. **The same expression must hold in three places** - the ingest
  watermark, the staging view, and the snapshot - or they disagree silently. When the
  source later adds a new "thing happened" timestamp column, add it to the GREATEST in
  all three places in the same change. (Caution: T-SQL GREATEST ignores NULLs; standard
  SQL semantics NULL the result - wrap with COALESCE when portability matters.)
- **dbt 1.9 `snapshot_meta_column_names`** maps dbt's meta columns straight to a naming
  contract (`dbt_valid_from -> _valid_from`, `dbt_scd_id -> _hash`, etc.) - no rename
  layer needed. Derive `_is_current` downstream (`CASE WHEN _valid_to IS NULL`).
- **Source the snapshot from an unconstrained staging VIEW** (dedup latest row per
  business key by `_change_ts`, tiebreak on `_ingestion_timestamp`) - satisfies adapters
  that reject NOT NULL constraints on snapshot sources.
- Guard with the integrity-test trio: exactly-one-current per key, no window overlaps,
  window adjacency (no gaps) - see "Testing SCD Implementations" below.

### dbt Incremental with Custom SCD Type 2

```sql
-- models/marts/dim_customer_scd2.sql
{{
  config(
    materialized='incremental',
    unique_key='_surrogate_key'
  )
}}

WITH source_data AS (
    SELECT
        customer_id,
        customer_name,
        email,
        address,
        status,
        MD5(CONCAT_WS('||', customer_name, email, address, status)) AS _hash,
        CURRENT_DATE AS _load_date
    FROM {{ ref('stg_customers') }}
),

{% if is_incremental() %}
-- Get current records from target
current_records AS (
    SELECT * FROM {{ this }}
    WHERE _is_current = TRUE
),

-- Find changed records
changes AS (
    SELECT
        s.*,
        CASE
            WHEN c.customer_id IS NULL THEN 'INSERT'
            WHEN c._hash != s._hash THEN 'UPDATE'
            ELSE 'NO_CHANGE'
        END AS _change_type
    FROM source_data s
    LEFT JOIN current_records c ON s.customer_id = c.customer_id
),

-- Close out changed records (set _is_current = false, _valid_to = today)
closed_records AS (
    SELECT
        c._surrogate_key,
        c.customer_id,
        c.customer_name,
        c.email,
        c.address,
        c.status,
        c._hash,
        c._valid_from,
        CURRENT_DATE - INTERVAL '1 day' AS _valid_to,
        FALSE AS _is_current
    FROM current_records c
    INNER JOIN changes ch ON c.customer_id = ch.customer_id
    WHERE ch._change_type = 'UPDATE'
),

-- New records (inserts and updates get new rows)
new_records AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['customer_id', '_load_date']) }} AS _surrogate_key,
        customer_id,
        customer_name,
        email,
        address,
        status,
        _hash,
        _load_date AS _valid_from,
        DATE '9999-12-31' AS _valid_to,
        TRUE AS _is_current
    FROM changes
    WHERE _change_type IN ('INSERT', 'UPDATE')
)

SELECT * FROM closed_records
UNION ALL
SELECT * FROM new_records

{% else %}
-- Initial load
SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', '_load_date']) }} AS _surrogate_key,
    customer_id,
    customer_name,
    email,
    address,
    status,
    _hash,
    _load_date AS _valid_from,
    DATE '9999-12-31' AS _valid_to,
    TRUE AS _is_current
FROM source_data
{% endif %}
```

### PySpark Implementation

```python
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from delta.tables import DeltaTable

def apply_scd_type2(
    spark,
    source_df,
    target_table_name: str,
    business_key: str,
    tracked_columns: list,
    surrogate_key_col: str = "_surrogate_key"
):
    """
    Apply SCD Type 2 merge pattern to a Delta table.

    Args:
        spark: SparkSession
        source_df: DataFrame with source data
        target_table_name: Full table name (e.g., "gold.dim_customer")
        business_key: Column name for business key (e.g., "customer_id")
        tracked_columns: List of columns to track for changes
        surrogate_key_col: Name of surrogate key column
    """
    # Generate hash for change detection
    hash_expr = F.md5(F.concat_ws("||", *[F.col(c) for c in tracked_columns]))

    source_with_hash = source_df.withColumn("_hash", hash_expr)

    # Check if target exists
    if spark.catalog.tableExists(target_table_name):
        target_table = DeltaTable.forName(spark, target_table_name)

        # Get current records
        current_df = spark.table(target_table_name).filter(F.col("_is_current") == True)

        # Identify changes
        changes_df = source_with_hash.alias("s").join(
            current_df.alias("t"),
            F.col(f"s.{business_key}") == F.col(f"t.{business_key}"),
            "left"
        ).select(
            F.col(f"s.{business_key}"),
            *[F.col(f"s.{c}") for c in tracked_columns],
            F.col("s._hash"),
            F.col("t._hash").alias("_existing_hash"),
            F.col(f"t.{surrogate_key_col}").alias("_existing_sk")
        )

        # Records to close (hash changed)
        to_close = changes_df.filter(
            (F.col("_existing_hash").isNotNull()) &
            (F.col("_hash") != F.col("_existing_hash"))
        )

        # Records to insert (new or changed)
        to_insert = changes_df.filter(
            (F.col("_existing_hash").isNull()) |
            (F.col("_hash") != F.col("_existing_hash"))
        ).select(
            F.col(business_key),
            *[F.col(c) for c in tracked_columns],
            F.col("_hash"),
            F.lit(True).alias("_is_current"),
            F.current_date().alias("_valid_from"),
            F.to_date(F.lit("9999-12-31")).alias("_valid_to"),
            F.expr(f"uuid()").alias(surrogate_key_col)
        )

        # Close existing records
        if to_close.count() > 0:
            close_keys = [row[business_key] for row in to_close.collect()]
            target_table.update(
                condition=(F.col(business_key).isin(close_keys)) & (F.col("_is_current") == True),
                set={
                    "_is_current": F.lit(False),
                    "_valid_to": F.date_sub(F.current_date(), 1)
                }
            )

        # Insert new/changed records
        to_insert.write.mode("append").saveAsTable(target_table_name)

    else:
        # Initial load
        initial_df = source_with_hash.select(
            F.col(business_key),
            *[F.col(c) for c in tracked_columns],
            F.col("_hash"),
            F.lit(True).alias("_is_current"),
            F.current_date().alias("_valid_from"),
            F.to_date(F.lit("9999-12-31")).alias("_valid_to"),
            F.expr("uuid()").alias(surrogate_key_col)
        )
        initial_df.write.format("delta").saveAsTable(target_table_name)

# Usage
apply_scd_type2(
    spark=spark,
    source_df=spark.table("silver.customers_cleansed"),
    target_table_name="gold.dim_customer",
    business_key="customer_id",
    tracked_columns=["customer_name", "email", "address", "status"]
)
```

### Point-in-Time Queries

```sql
-- Get customer state as of a specific date
SELECT *
FROM dim_customer
WHERE '2024-06-15' BETWEEN _valid_from AND _valid_to;

-- Get all versions of a customer
SELECT *
FROM dim_customer
WHERE customer_id = 'C001'
ORDER BY _valid_from;

-- Join fact to dimension at transaction time
SELECT
    f.transaction_id,
    f.transaction_date,
    f.amount,
    d.customer_name,
    d.status
FROM fact_sales f
INNER JOIN dim_customer d
    ON f.customer_id = d.customer_id
    AND f.transaction_date BETWEEN d._valid_from AND d._valid_to;
```

## SCD Type 3: Previous Value

### When to Use

- Simple before/after comparisons
- Storage is limited
- Only need to track one prior value
- Quick reporting on recent changes

### Required Columns

| Column | Purpose |
|--------|---------|
| `current_value` | Current attribute value |
| `previous_value` | Prior attribute value (NULL if never changed) |
| `change_date` | When the value last changed |

### dbt Implementation

```sql
-- models/marts/dim_customer_scd3.sql
{{
  config(
    materialized='incremental',
    unique_key='customer_id'
  )
}}

WITH source_data AS (
    SELECT
        customer_id,
        status AS current_status,
        updated_at
    FROM {{ ref('stg_customers') }}
)

{% if is_incremental() %}

SELECT
    s.customer_id,
    s.current_status,
    CASE
        WHEN t.current_status != s.current_status THEN t.current_status
        ELSE t.previous_status
    END AS previous_status,
    CASE
        WHEN t.current_status != s.current_status THEN s.updated_at
        ELSE t.status_change_date
    END AS status_change_date,
    s.updated_at
FROM source_data s
LEFT JOIN {{ this }} t ON s.customer_id = t.customer_id

{% else %}

SELECT
    customer_id,
    current_status,
    CAST(NULL AS VARCHAR) AS previous_status,
    CAST(NULL AS DATE) AS status_change_date,
    updated_at
FROM source_data

{% endif %}
```

### PySpark Implementation

```python
from pyspark.sql import functions as F

def apply_scd_type3(
    spark,
    source_df,
    target_table_name: str,
    business_key: str,
    tracked_column: str
):
    """Apply SCD Type 3 pattern (current + previous value)."""

    if spark.catalog.tableExists(target_table_name):
        target_df = spark.table(target_table_name)

        # Join source with target
        result_df = source_df.alias("s").join(
            target_df.alias("t"),
            F.col(f"s.{business_key}") == F.col(f"t.{business_key}"),
            "left"
        ).select(
            F.col(f"s.{business_key}"),
            F.col(f"s.{tracked_column}").alias(f"current_{tracked_column}"),
            F.when(
                F.col(f"t.current_{tracked_column}") != F.col(f"s.{tracked_column}"),
                F.col(f"t.current_{tracked_column}")
            ).otherwise(
                F.col(f"t.previous_{tracked_column}")
            ).alias(f"previous_{tracked_column}"),
            F.when(
                F.col(f"t.current_{tracked_column}") != F.col(f"s.{tracked_column}"),
                F.current_date()
            ).otherwise(
                F.col("t.change_date")
            ).alias("change_date"),
            F.current_timestamp().alias("updated_at")
        )

        result_df.write.mode("overwrite").saveAsTable(target_table_name)
    else:
        # Initial load
        initial_df = source_df.select(
            F.col(business_key),
            F.col(tracked_column).alias(f"current_{tracked_column}"),
            F.lit(None).cast("string").alias(f"previous_{tracked_column}"),
            F.lit(None).cast("date").alias("change_date"),
            F.current_timestamp().alias("updated_at")
        )
        initial_df.write.format("delta").saveAsTable(target_table_name)
```

## Hybrid Approaches

### Type 2 + Type 1 Combination

Track history for critical attributes, overwrite for non-critical:

```sql
-- Track status changes (Type 2), overwrite address (Type 1)
{% snapshot customer_status_snapshot %}
{{
    config(
      unique_key='customer_id',
      strategy='check',
      check_cols=['status']  -- Only track status changes
    )
}}
SELECT customer_id, status FROM {{ source('raw', 'customers') }}
{% endsnapshot %}

-- Separate model for Type 1 attributes
-- models/dim_customer_current.sql
SELECT
    s.customer_id,
    s.dbt_valid_from,
    s.dbt_valid_to,
    c.address,  -- Type 1: always current
    c.email     -- Type 1: always current
FROM {{ ref('customer_status_snapshot') }} s
LEFT JOIN {{ source('raw', 'customers') }} c
    ON s.customer_id = c.customer_id
```

### Mini-Dimensions

For rapidly changing attributes, separate into mini-dimension:

```python
# Main dimension (Type 2, changes slowly)
dim_customer_df = spark.table("silver.customers").select(
    "customer_id", "customer_name", "address"
)

# Mini-dimension (Type 1, changes frequently)
dim_customer_profile_df = spark.table("silver.customers").select(
    "customer_id",
    "loyalty_tier",
    "credit_score",
    "last_activity_date"
)
```

## Testing SCD Implementations

### Key Tests

1. **Uniqueness of current records**: Only one `_is_current = true` per business key
2. **No overlapping date ranges**: Valid periods don't overlap
3. **No gaps in history**: Valid periods are contiguous
4. **Hash consistency**: Hash matches computed value

### Zero-taint proof: demonstrating SCD2 before the source produces a natural change

On a one-shot initial load there is often no convenient source change to observe, and
synthetic rows would taint the platform. The zero-taint method (works with timestamp
strategy, which compares only the change timestamp - not column values):

1. ALTER the staging view in the warehouse to wrap the dbt-compiled query with a CASE
   bumping `_change_ts` only, for **one probe business key**.
2. Run `dbt snapshot` -> verify: v1 closed exactly at v2's `_valid_from`, exactly one
   current row for the probe key, total row count +1.
3. Restore the view with `dbt run --select <staging view>`.
4. Re-snapshot to confirm idempotency (0 new rows).

The only residue is one extra business-identical version for the probe key - no synthetic
data, no business-value changes. Guard the result with the integrity-test trio above.
Reuse on any engagement where SCD2 must be demonstrated before the source changes
naturally.

### dbt Tests

```yaml
# schema.yml
models:
  - name: dim_customer_scd2
    columns:
      - name: customer_id
        tests:
          - unique:
              where: "_is_current = true"
      - name: _valid_from
        tests:
          - not_null
      - name: _valid_to
        tests:
          - not_null
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - customer_id
            - _valid_from
      # Custom test for no overlapping periods
      - no_overlapping_periods:
          partition_by: customer_id
          valid_from: _valid_from
          valid_to: _valid_to
```

### PySpark Tests

```python
def test_scd2_constraints(spark, table_name: str, business_key: str):
    """Validate SCD Type 2 table integrity."""
    df = spark.table(table_name)
    errors = []

    # Test 1: Only one current record per business key
    current_counts = df.filter(F.col("_is_current") == True) \
        .groupBy(business_key).count() \
        .filter(F.col("count") > 1)
    if current_counts.count() > 0:
        errors.append(f"Multiple current records found for {current_counts.count()} keys")

    # Test 2: _valid_from <= _valid_to
    invalid_ranges = df.filter(F.col("_valid_from") > F.col("_valid_to"))
    if invalid_ranges.count() > 0:
        errors.append(f"Invalid date ranges: {invalid_ranges.count()} records")

    # Test 3: Current records have _valid_to = 9999-12-31
    bad_current = df.filter(
        (F.col("_is_current") == True) &
        (F.col("_valid_to") != F.to_date(F.lit("9999-12-31")))
    )
    if bad_current.count() > 0:
        errors.append(f"Current records with wrong _valid_to: {bad_current.count()}")

    # Test 4: No overlapping periods per business key
    window = Window.partitionBy(business_key).orderBy("_valid_from")
    with_next = df.withColumn("_next_valid_from", F.lead("_valid_from").over(window))
    overlaps = with_next.filter(
        F.col("_valid_to") >= F.col("_next_valid_from")
    )
    if overlaps.count() > 0:
        errors.append(f"Overlapping periods: {overlaps.count()} records")

    return {"passed": len(errors) == 0, "errors": errors}
```

## Anti-Patterns

### 1. Using SCD Type 2 for Rapidly Changing Data

**Problem**: SCD Type 2 on frequently changing attributes causes table bloat.

**Example**: Tracking `last_login_date` with SCD Type 2 creates a new row every login.

**Solution**: Use Type 1 for volatile attributes, or mini-dimensions.

### 2. Missing Change Detection (Hash)

**Problem**: Without hash, you compare all columns every time - slow and error-prone.

**Solution**: Always compute hash of tracked columns for efficient change detection.

```python
# Bad: Compare all columns
source_df.join(target_df, ...).filter(
    (source_df.col1 != target_df.col1) |
    (source_df.col2 != target_df.col2) | ...
)

# Good: Compare hash
source_df.join(target_df, ...).filter(
    source_df._hash != target_df._hash
)
```

### 3. Not Handling Late-Arriving Data

**Problem**: Data arrives out of order, breaking historical accuracy.

**Solution**: Use `_load_date` from source, not `current_date()` for `_valid_from`.

### 4. Overlapping Valid Periods

**Problem**: Multiple records claim to be valid for the same date.

**Solution**: Close previous record with `_valid_to = new_valid_from - 1 day`.

### 5. Using Natural Keys Instead of Surrogate Keys

**Problem**: Natural keys can change, breaking fact table relationships.

**Solution**: Always use surrogate keys for fact table foreign keys.

## Related Skills

- [medallion-architecture](../medallion-architecture/SKILL.md) - SCD Type 2 is typically implemented in the Silver layer
- [data-quality-checks](../data-quality-checks/SKILL.md) - Validating SCD implementations
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Handling SCD merge failures
- [inmon-data-warehouse](../inmon-data-warehouse/SKILL.md) - SCD Type 2 is foundational to Inmon EDW temporal tracking

## References

- [dbt Implementations](references/dbt-implementations.md) - Complete dbt snapshot and incremental patterns
- [PySpark Implementations](references/pyspark-implementations.md) - Delta Lake merge patterns
- [Testing Patterns](references/testing-patterns.md) - Comprehensive SCD validation tests
