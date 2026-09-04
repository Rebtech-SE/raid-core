---
name: medallion-architecture
description: >-
  Use for general Bronze/Silver/Gold patterns and tier decisions; for Fabric-specific
  implementation use fabric-architecture. Triggers: 'medallion', 'bronze silver gold',
  'data lake layers', 'raw to curated', 'data tier design', 'lakehouse architecture',
  'bronze layer', 'silver layer', 'gold layer'. Platform-agnostic guide for implementing
  medallion architecture across data platforms.
---

# Medallion Architecture Guide

Platform-agnostic guide for implementing Bronze/Silver/Gold data lake architecture across Databricks, Snowflake, Microsoft Fabric, BigQuery, and other modern data platforms.

## When to Use This Skill

Use this skill when users ask about:

- **Architecture design**: "How should I organize my data lake?"
- **Layer decisions**: "Should this go in Bronze or Silver?"
- **Data flow**: "How does data move through the layers?"
- **Best practices**: "What are medallion architecture patterns?"
- **Platform setup**: "How do I implement medallion in Databricks/Snowflake/Fabric?"
- **Anti-patterns**: "What mistakes should I avoid?"

**Note**: This skill is **platform-agnostic**. For Microsoft Fabric-specific implementation (lakehouses, Fabric notebooks, mssparkutils), see `fabric-architecture` (raid-fabric).

## Core Principles

### Separate DDL and DML Notebooks

**CRITICAL**: Always create separate notebooks for schema creation vs data loading:

| Notebook Type | Purpose | When to Run | Naming |
|---------------|---------|-------------|--------|
| **DDL** | CREATE TABLE, define schema, set partitioning | Once, or on schema changes | `{tier}_{entity}_ddl` |
| **DML** | INSERT, MERGE, load/transform data | Scheduled (daily, hourly) | `{tier}_{entity}_load` |

This separation ensures:
- Schema changes are versioned independently from data loads
- Table structure can be deployed without running data pipelines
- Data loads can be scheduled separately from schema migrations
- Easier troubleshooting when issues arise

### Immutability at Bronze

Raw data is append-only. Never modify or delete Bronze records. This provides:
- Complete audit trail
- Ability to reprocess from source
- Recovery from transformation bugs

### Progressive Quality Improvement

Each layer adds quality guarantees:

```
Bronze (Raw)     -> Silver (Cleansed)    -> Gold (Business)
-----------------------------------------------------------
As-is from source  Validated, deduplicated  Aggregated, KPIs
Minimal processing Type-safe, standardized  Star schema
Append-only        SCD Type 2 history       Pre-computed metrics
```

### Clear Layer Boundaries

Each layer has one responsibility:
- **Bronze**: Capture (no transformation)
- **Silver**: Conform (standardize, validate, historize)
- **Gold**: Consume (aggregate, denormalize, serve)

## Quick Decision Tree

```
What are you building?
|
|-- Creating table structure?
|   |-> DDL Notebook
|   |   - CREATE TABLE IF NOT EXISTS
|   |   - Define schema and columns
|   |   - Set partitioning
|   |   - Run once or on schema changes
|
|-- Loading or transforming data?
|   |-> DML Notebook
|   |   - Requires DDL to run first
|   |   - INSERT, MERGE, UPDATE
|   |   - Run on schedule
|
|-- Which tier?
    |
    |-- Ingesting from external source?
    |   |-> Bronze
    |   |   - DDL: Create table with audit columns
    |   |   - DML: Append-only load
    |
    |-- Cleaning or standardizing data?
    |   |-> Silver
    |   |   - DDL: Create table with SCD Type 2 columns
    |   |   - DML: Merge with change detection
    |
    |-- Creating business metrics or reports?
        |-> Gold
            - DDL: Create star schema tables
            - DML: Aggregate into fact tables
```

## Layer Overview

| Aspect | Bronze | Silver | Gold |
|--------|--------|--------|------|
| **Purpose** | Capture raw data | Clean and conform | Business consumption |
| **Data Quality** | As-is | Validated | Curated |
| **Schema** | Source schema | 3NF (normalized) | Star (denormalized) |
| **Updates** | Append-only | Merge/SCD | Overwrite/Merge |
| **Consumers** | Silver layer | Gold layer, apps | BI, analysts, APIs |
| **Retention** | Long (years) | Medium | Short to medium |
| **Processing** | Minimal | Heavy | Moderate |

## Materialization Strategy

Each layer has a default materialization approach. The right choice depends on transformation complexity, query frequency, and platform constraints. This section provides platform-agnostic defaults -- platform-specific limitations (e.g., Fabric lakehouses only support tables, not views) are locked down in Tier 2/3 skills.

### Defaults by Layer

| Layer | Default | Rationale |
|-------|---------|-----------|
| **Bronze** | Table | Physical storage required -- data lands from external sources |
| **Silver** | Table | SCD Type 2 and merge operations require persistent storage |
| **Gold** | Table | BI tools and analysts need predictable query performance |

In dbt projects, staging models (the thin Bronze-to-Silver step) default to **views** since they only rename, cast, and filter -- the data already exists in the source tables.

### When to Use Views

Views avoid duplicating data and reduce storage cost. Use them when **all** of these apply:

1. **Transformation is thin** -- column renames, type casts, simple filters, or light enrichment
2. **Not queried directly by BI tools** -- only consumed by one or two downstream models
3. **No history tracking** -- SCD and merge patterns require physical tables
4. **Compute cost is acceptable** -- the view re-executes on every query, so the underlying query must be cheap

Typical view candidates:
- dbt staging models (`stg_*`) that sit on top of raw/Bronze tables
- Convenience wrappers that expose a cleaner interface over a table without transforming data
- Union-all views that combine partitioned source tables into a single logical entity

### When to Materialize as Tables

Use physical tables (or `incremental` in dbt) when **any** of these apply:

1. **Heavy transformations** -- multi-table joins, window functions, complex aggregations
2. **Queried frequently** -- BI dashboards, ad-hoc analyst queries, API-serving layers
3. **SLA-bound** -- downstream consumers expect consistent query times
4. **History tracking** -- SCD Type 2, append-only audit trails
5. **Incremental processing** -- merge/upsert patterns that build on previous state

### Materialized Views

Some platforms (Snowflake, BigQuery, Databricks) support materialized views that auto-refresh. Use these when:

- The query is expensive but doesn't need exact real-time data
- The platform handles refresh scheduling natively
- You want table-like performance without managing a separate refresh pipeline

Materialized views are a good fit for Gold-layer aggregations in streaming/near-real-time architectures. Availability and behavior vary by platform -- Tier 2/3 skills define when to use them.

### Decision Summary

```
Is the transformation just renames/casts/filters?
  YES -> View (especially dbt staging models)
  NO  -> Does it involve SCD, merge, or incremental logic?
           YES -> Table (incremental)
           NO  -> Is it queried directly by BI tools or analysts?
                    YES -> Table
                    NO  -> Is the underlying query cheap to re-execute?
                             YES -> View
                             NO  -> Table
```

### Platform Constraints

Some platforms restrict where views can be created. These constraints are **defined in Tier 2/3 skills**, not here. Common examples:

- **Fabric Lakehouses**: Tables only (Delta) -- views require a Fabric Warehouse or SQL Analytics Endpoint
- **BigQuery**: Views are free to create but cost compute on every query; materialized views have refresh cost
- **Snowflake**: Full support for views, materialized views, and tables in all layers
- **Databricks**: Views supported in Unity Catalog; materialized views available in SQL Warehouses

When building for a specific platform, always check the Tier 2 skill for materialization rules before defaulting to views.

### Where Transformation Logic Lives (models vs procedures vs functions)

Materialization decides *what shape* the output takes; this decides *where the logic
sits*. The rule: **on a dbt/notebook engagement, transformation logic lives in
version-controlled models/notebooks** -- diffed in PRs, covered by tests, visible in
lineage, re-runnable. Logic buried in warehouse-side objects is invisible to all of
that and drifts from the repo.

For reusable or imperative logic, pick the **earliest rung** on this ladder that works:

| Rung | Use for | Why first |
|------|---------|-----------|
| **dbt macro** | Reusable transform logic inside models (e.g. a standard cleaning expression, surrogate-key hash) | Compile-time reuse; stays in git, no runtime object |
| **View** | Shared thin read logic over a table (no parameters) | Declarative, in the model DAG |
| **Inline TVF** | *Parameterized* reusable read logic, typically on the consumption/serving layer | Still declarative and inlineable; lives outside the DAG, so keep it consumption-side |
| **Scalar UDF** | Rarely -- a per-row expression that genuinely can't be a macro/column | Often a row-by-row performance trap; some platforms (Fabric) require it inlineable. Prefer a macro or computed column |
| **Stored procedure** | Imperative/transactional operations an orchestrator invokes: watermark bumps, partition/maintenance routines, multi-statement DML with explicit transactions where no dbt/notebook runtime fits | Last resort for *transforms* -- if a proc reshapes data on a dbt engagement, it should almost certainly be a model |

Sniff test in review: a `CREATE PROCEDURE` containing joins/CASE logic that produces
analytical output is a transform wearing the wrong clothes -- flag it for conversion to
a model. Operational procs (no analytical output, invoked by the pipeline) are fine.
Platform mechanics (proc/TVF/UDF syntax and limits) live in the Tier 2 skills.

## Bronze Layer

### Purpose

Capture raw data exactly as received from source systems. Bronze is your insurance policy - you can always rebuild downstream layers.

### Required Audit Columns

| Column | Type | Purpose |
|--------|------|---------|
| `_ingestion_timestamp` | TIMESTAMP | When record was loaded |
| `_source_system` | STRING | Source identifier |
| `_batch_id` | STRING | Processing batch identifier |
| `_raw_data` | STRING (optional) | Original payload (JSON/XML) |

### Patterns

**Append-Only Writes**:
```python
# PySpark
source_df \
    .withColumn("_ingestion_timestamp", F.current_timestamp()) \
    .withColumn("_source_system", F.lit("salesforce")) \
    .withColumn("_batch_id", F.lit(batch_id)) \
    .write \
    .mode("append") \
    .format("delta") \
    .partitionBy("_ingestion_date") \
    .saveAsTable("bronze.customers_raw")
```

```sql
-- dbt (sources)
-- models/staging/stg_customers.sql
SELECT
    *,
    CURRENT_TIMESTAMP() AS _ingestion_timestamp,
    'salesforce' AS _source_system,
    '{{ var("batch_id") }}' AS _batch_id
FROM {{ source('raw', 'customers') }}
```

### What NOT to Do in Bronze

- Data cleansing or transformation
- Filtering out "bad" records
- Changing data types (except for storage efficiency)
- Deduplication
- Business logic

### Naming Conventions

| Platform | Pattern | Example |
|----------|---------|---------|
| Databricks | `bronze.{source}_{entity}` | `bronze.salesforce_accounts` |
| Snowflake | `RAW.{SOURCE}_{ENTITY}` | `RAW.SALESFORCE_ACCOUNTS` |
| Fabric | `bronze_{source}_{entity}` | `bronze_salesforce_accounts` |
| dbt | `stg_{source}__{entity}` | `stg_salesforce__accounts` |

**See**: [Bronze Patterns](references/bronze-patterns.md)

## Silver Layer

### Purpose

Clean, conform, and standardize data. Silver is where you apply business rules and create a single source of truth.

### Key Transformations

1. **Data Cleansing**: Handle nulls, standardize formats
2. **Deduplication**: Remove exact duplicates, handle late-arriving data
3. **Type Standardization**: Consistent data types across sources
4. **SCD Type 2**: Track historical changes (see [scd-pattern](../scd-pattern/SKILL.md))
5. **Referential Integrity**: Foreign key validation

### Required Columns (SCD Type 2)

| Column | Type | Purpose |
|--------|------|---------|
| `_valid_from` | DATE | Start of validity |
| `_valid_to` | DATE | End of validity (9999-12-31 for current) |
| `_is_current` | BOOLEAN | Current record flag |
| `_hash` | STRING | Change detection hash |
| `_load_timestamp` | TIMESTAMP | When processed |

### Patterns

**Deduplication**:
```python
# PySpark - Keep latest by updated_at
from pyspark.sql.window import Window

window = Window.partitionBy("customer_id").orderBy(F.desc("updated_at"))
deduplicated = df.withColumn("rn", F.row_number().over(window)) \
    .filter(F.col("rn") == 1) \
    .drop("rn")
```

```sql
-- dbt
SELECT *
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC
        ) AS rn
    FROM {{ ref('stg_customers') }}
)
WHERE rn = 1
```

**Data Cleansing**:
```python
# PySpark
cleaned = df \
    .withColumn("email", F.lower(F.trim(F.col("email")))) \
    .withColumn("phone", F.regexp_replace(F.col("phone"), "[^0-9]", "")) \
    .withColumn("country_code", F.upper(F.col("country_code"))) \
    .withColumn("status", F.coalesce(F.col("status"), F.lit("unknown")))
```

### What NOT to Do in Silver

- Denormalization (save for Gold)
- Pre-aggregation (save for Gold)
- Business metric calculations (save for Gold)
- Star schema design (save for Gold)

### Naming Conventions

| Platform | Pattern | Example |
|----------|---------|---------|
| Databricks | `silver.{entity}` | `silver.customers` |
| Snowflake | `CONFORMED.{ENTITY}` | `CONFORMED.CUSTOMERS` |
| Fabric | `silver_{entity}` | `silver_customers` |
| dbt | `int_{entity}` or `{entity}_conformed` | `int_customers` |

**See**: [Silver Patterns](references/silver-patterns.md)

## Gold Layer

### Purpose

Serve business users with optimized, denormalized structures. Gold is where analytics happens.

### Key Structures

**Star Schema**:
- Fact tables: Measurable events (transactions, clicks, orders)
- Dimension tables: Descriptive context (customers, products, dates)

**Pre-Aggregations**:
- Daily/weekly/monthly rollups
- KPI calculations
- Running totals and averages

### Fact Table Patterns

| Type | Description | Example |
|------|-------------|---------|
| Transactional | One row per event | `fact_orders` |
| Periodic Snapshot | State at regular intervals | `fact_inventory_daily` |
| Accumulating Snapshot | Track process milestones | `fact_order_fulfillment` |
| Aggregate | Pre-computed summaries | `fact_sales_monthly` |

### Dimension Table Patterns

| Type | Description | When to Use |
|------|-------------|-------------|
| SCD Type 1 | Overwrite | Corrections, non-critical attributes |
| SCD Type 2 | Full history | Audit, trend analysis |
| Junk | Combined low-cardinality flags | Yes/No attributes |
| Degenerate | In fact table | Order numbers, transaction IDs |
| Date | Calendar dimension | All date-based analysis |

### Required Date Dimension

Every Gold layer needs a date dimension:

```python
# PySpark date dimension
from pyspark.sql.types import DateType
import pandas as pd

dates = pd.date_range(start="2020-01-01", end="2030-12-31", freq="D")
date_df = spark.createDataFrame(pd.DataFrame({"date_key": dates}))

date_dim = date_df.select(
    F.col("date_key"),
    F.year("date_key").alias("year"),
    F.month("date_key").alias("month"),
    F.dayofmonth("date_key").alias("day"),
    F.quarter("date_key").alias("quarter"),
    F.dayofweek("date_key").alias("day_of_week"),
    F.weekofyear("date_key").alias("week_of_year"),
    F.date_format("date_key", "EEEE").alias("day_name"),
    F.date_format("date_key", "MMMM").alias("month_name"),
    (F.dayofweek("date_key").isin([1, 7])).alias("is_weekend"),
    F.lit(False).alias("is_holiday")  # Populate separately
)
```

### Naming Conventions

| Platform | Pattern | Example |
|----------|---------|---------|
| Databricks | `gold.fact_{process}`, `gold.dim_{entity}` | `gold.fact_sales`, `gold.dim_customer` |
| Snowflake | `MARTS.FACT_{PROCESS}`, `MARTS.DIM_{ENTITY}` | `MARTS.FACT_SALES` |
| Fabric | `fact_{process}`, `dim_{entity}` | `fact_sales`, `dim_customer` |
| dbt | `fct_{process}`, `dim_{entity}` | `fct_sales`, `dim_customer` |

**See**: [Gold Patterns](references/gold-patterns.md)

## Cross-Platform Implementation

### Databricks (Delta Lake)

```
catalog/
  bronze/
    salesforce_accounts
    erp_orders
  silver/
    accounts
    orders
  gold/
    dim_customer
    dim_product
    fact_sales
```

### Snowflake

```
database/
  RAW/           -- Bronze
    SALESFORCE/
      ACCOUNTS
    ERP/
      ORDERS
  CONFORMED/     -- Silver
    ACCOUNTS
    ORDERS
  MARTS/         -- Gold
    DIM_CUSTOMER
    FACT_SALES
```

### Microsoft Fabric

```
workspace/
  Bronze_Lakehouse/
    Tables/
      salesforce_accounts
      erp_orders
  Silver_Lakehouse/
    Tables/
      accounts
      orders
  Gold_Lakehouse/
    Tables/
      dim_customer
      fact_sales
```

### dbt Project Structure

```
dbt_project/
  models/
    staging/         -- Bronze -> Silver (first step)
      stg_salesforce__accounts.sql
      stg_erp__orders.sql
    intermediate/    -- Silver (complex transformations)
      int_accounts_deduped.sql
      int_orders_enriched.sql
    marts/           -- Gold
      core/
        dim_customer.sql
        dim_product.sql
        fct_sales.sql
      marketing/
        fct_campaigns.sql
```

**See**: [dbt Examples](references/dbt-examples.md)

## Anti-Patterns

### Bronze Anti-Patterns

| Anti-Pattern | Problem | Solution |
|-------------|---------|----------|
| Transforming data | Lose original source | Keep raw, transform in Silver |
| Deleting records | Lose audit trail | Append-only, soft delete |
| Filtering bad data | Hide data quality issues | Route to error table, process in Silver |
| Complex schemas | Hard to maintain | Preserve source schema |

### Silver Anti-Patterns

| Anti-Pattern | Problem | Solution |
|-------------|---------|----------|
| Star schema | Wrong layer responsibility | Save denormalization for Gold |
| Pre-aggregation | Limits downstream flexibility | Aggregate in Gold |
| Skipping Bronze | No recovery option | Always land raw first |
| No SCD | Lose history | Implement Type 2 for key entities |

### Gold Anti-Patterns

| Anti-Pattern | Problem | Solution |
|-------------|---------|----------|
| 3NF structure in Gold | Slow queries, complex joins | Use star schema; for enterprise-wide 3NF see [inmon-data-warehouse](../inmon-data-warehouse/SKILL.md) |
| No date dimension | Inconsistent date logic | Create shared date dim |
| Too many aggregations | Storage bloat | Focus on most-used metrics |
| Raw data | Wrong layer | Aggregate from Silver |

## Data Flow Patterns

### Batch Processing

```
Source -> Bronze -> Silver -> Gold
  |         |         |         |
  |      append    merge     merge/overwrite
  |         |         |         |
Daily    Daily    Daily      Daily
```

### Streaming (Near Real-Time)

```
Source -> Bronze -> Silver -> Gold
  |         |         |         |
  |     micro-batch  merge   materialized view
  |         |         |         |
Continuous  Minutes  Minutes   Auto-refresh
```

### Hybrid (Lambda)

```
                  -> Gold (real-time)
                 /
Source -> Bronze
                 \
                  -> Silver -> Gold (batch)
```

## Incremental Processing

### Bronze (Append)

```python
# Always append, never update
df.write.mode("append").saveAsTable("bronze.events")
```

### Silver (Merge with SCD)

```python
# Use watermark for incremental
max_ts = spark.table("silver.events") \
    .agg(F.max("_load_timestamp")).collect()[0][0]

new_records = spark.table("bronze.events") \
    .filter(F.col("_ingestion_timestamp") > max_ts)

# Apply SCD Type 2
apply_scd_type2(new_records, "silver.events", ...)
```

### Gold (Full or Incremental)

```python
# Full refresh for aggregates
spark.table("silver.orders") \
    .groupBy("customer_id", "order_date") \
    .agg(...) \
    .write.mode("overwrite").saveAsTable("gold.fact_orders_daily")

# Incremental for fact tables
# Similar to Silver merge pattern
```

## Related Skills

- [scd-pattern](../scd-pattern/SKILL.md) - SCD Type 2 implementation for Silver layer
- [data-quality-checks](../data-quality-checks/SKILL.md) - Validation at each layer
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Error handling in Bronze
- `fabric-architecture` (raid-fabric) - Fabric-specific implementation details
- [data-platform-orchestration](../data-platform-orchestration/SKILL.md) - Scheduling, dependencies, retries, backfills
- [inmon-data-warehouse](../inmon-data-warehouse/SKILL.md) - Alternative top-down EDW approach; coexistence guidance

## References

- [Bronze Patterns](references/bronze-patterns.md) - Ingestion patterns and source handling
- [Silver Patterns](references/silver-patterns.md) - Cleansing, deduplication, SCD
- [Gold Patterns](references/gold-patterns.md) - Star schema, aggregations, KPIs
- [dbt Examples](references/dbt-examples.md) - Complete dbt project structure
