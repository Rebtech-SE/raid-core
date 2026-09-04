# Gold Layer Patterns

This is the canonical, platform-agnostic source for Gold patterns. Fabric-specific deltas live in
the `fabric-architecture` skill (raid-fabric), Gold Architecture reference.

Patterns for business-ready data structures in the Gold layer.

## Core Principles

1. **Denormalization**: Optimize for read performance
1. **Star Schema**: Fact and dimension tables
1. **Pre-Aggregation**: Compute metrics in advance
1. **Business Logic**: KPIs, calculations, derived metrics

## Star Schema Design

### Fact Tables

Fact tables store measurable business events.

```python
# PySpark - Fact table structure
fact_sales = spark.createDataFrame([
    # Schema definition
], schema="""
    sale_id STRING,
    sk_customer LONG,         -- Surrogate key to dim_customer
    sk_product LONG,          -- Surrogate key to dim_product
    sk_date LONG,             -- Surrogate key to dim_date
    sk_store LONG,            -- Surrogate key to dim_store
    quantity INT,             -- Measure
    unit_price DECIMAL(18,2), -- Measure
    total_amount DECIMAL(18,2), -- Measure
    discount_amount DECIMAL(18,2), -- Measure
    _load_timestamp TIMESTAMP
""")
```

```sql
-- dbt fact table
-- models/marts/core/fct_sales.sql
{{
  config(
    materialized='incremental',
    unique_key='sale_id',
    incremental_strategy='merge'
  )
}}

SELECT
    s.sale_id,
    c.sk_customer,
    p.sk_product,
    d.sk_date,
    st.sk_store,
    s.quantity,
    s.unit_price,
    s.quantity * s.unit_price AS total_amount,
    s.discount_amount,
    CURRENT_TIMESTAMP() AS _load_timestamp
FROM {{ ref('int_sales') }} s
LEFT JOIN {{ ref('dim_customer') }} c
    ON s.customer_id = c.customer_id
    AND c.is_current = TRUE
LEFT JOIN {{ ref('dim_product') }} p
    ON s.product_id = p.product_id
    AND p.is_current = TRUE
LEFT JOIN {{ ref('dim_date') }} d
    ON s.sale_date = d.date_key
LEFT JOIN {{ ref('dim_store') }} st
    ON s.store_id = st.store_id

{% if is_incremental() %}
WHERE s._load_timestamp > (SELECT MAX(_load_timestamp) FROM {{ this }})
{% endif %}
```

### Fact Table Types

| Type                  | Description          | Example                 | Grain         |
| --------------------- | -------------------- | ----------------------- | ------------- |
| Transaction           | One row per event    | `fct_orders`            | Order line    |
| Periodic Snapshot     | State at intervals   | `fct_inventory_daily`   | Product/Day   |
| Accumulating Snapshot | Process milestones   | `fct_order_fulfillment` | Order         |
| Aggregate             | Pre-computed summary | `fct_sales_monthly`     | Product/Month |

### Dimension Tables

```python
# PySpark - Dimension with SCD Type 2
dim_customer = spark.createDataFrame([
    # Schema definition
], schema="""
    sk_customer LONG,           -- Surrogate key
    customer_id STRING,         -- Business key
    customer_name STRING,
    email STRING,
    segment STRING,
    country STRING,
    city STRING,
    _valid_from DATE,
    _valid_to DATE,
    _is_current BOOLEAN,
    _hash STRING
""")
```

```sql
-- dbt dimension table
-- models/marts/core/dim_customer.sql
{{
  config(
    materialized='table'
  )
}}

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'dbt_valid_from']) }} AS sk_customer,
    customer_id,
    customer_name,
    email,
    segment,
    country,
    city,
    dbt_valid_from AS valid_from,
    dbt_valid_to AS valid_to,
    dbt_valid_to IS NULL AS is_current
FROM {{ ref('customer_snapshot') }}
```

## Date Dimension

Every Gold layer needs a date dimension.

```python
# PySpark - Generate date dimension
import pandas as pd
from pyspark.sql import functions as F

def generate_date_dimension(spark, start_date: str, end_date: str):
    """Generate comprehensive date dimension."""

    # Create date range
    dates = pd.date_range(start=start_date, end=end_date, freq='D')
    date_df = spark.createDataFrame(pd.DataFrame({"date_key": dates}))

    return date_df.select(
        # Keys
        F.date_format("date_key", "yyyyMMdd").cast("int").alias("sk_date"),
        F.col("date_key"),

        # Date parts
        F.year("date_key").alias("year"),
        F.quarter("date_key").alias("quarter"),
        F.month("date_key").alias("month"),
        F.weekofyear("date_key").alias("week_of_year"),
        F.dayofmonth("date_key").alias("day_of_month"),
        F.dayofweek("date_key").alias("day_of_week"),
        F.dayofyear("date_key").alias("day_of_year"),

        # Names
        F.date_format("date_key", "MMMM").alias("month_name"),
        F.date_format("date_key", "MMM").alias("month_short"),
        F.date_format("date_key", "EEEE").alias("day_name"),
        F.date_format("date_key", "EEE").alias("day_short"),

        # Fiscal (assuming fiscal year starts in July)
        F.when(F.month("date_key") >= 7, F.year("date_key") + 1)
         .otherwise(F.year("date_key")).alias("fiscal_year"),
        F.when(F.month("date_key") >= 7, F.quarter("date_key") - 2)
         .otherwise(F.quarter("date_key") + 2).alias("fiscal_quarter"),

        # Flags
        (F.dayofweek("date_key").isin([1, 7])).alias("is_weekend"),
        F.lit(False).alias("is_holiday"),  # Populate separately

        # Relative
        (F.col("date_key") == F.current_date()).alias("is_today"),
        F.datediff(F.current_date(), "date_key").alias("days_from_today")
    )

# Usage
dim_date = generate_date_dimension(spark, "2020-01-01", "2030-12-31")
dim_date.write.mode("overwrite").saveAsTable("gold.dim_date")
```

```sql
-- dbt date dimension
-- models/marts/core/dim_date.sql
{{
  config(
    materialized='table'
  )
}}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2020-01-01' as date)",
        end_date="cast('2030-12-31' as date)"
    ) }}
),

dates AS (
    SELECT
        CAST(date_day AS DATE) AS date_key
    FROM date_spine
)

SELECT
    CAST(DATE_FORMAT(date_key, 'yyyyMMdd') AS INT) AS sk_date,
    date_key,
    YEAR(date_key) AS year,
    QUARTER(date_key) AS quarter,
    MONTH(date_key) AS month,
    WEEKOFYEAR(date_key) AS week_of_year,
    DAYOFMONTH(date_key) AS day_of_month,
    DAYOFWEEK(date_key) AS day_of_week,
    DATE_FORMAT(date_key, 'MMMM') AS month_name,
    DATE_FORMAT(date_key, 'EEEE') AS day_name,
    DAYOFWEEK(date_key) IN (1, 7) AS is_weekend,
    FALSE AS is_holiday
FROM dates
```

## Pre-Aggregation Patterns

### Daily Aggregates

```python
# PySpark - Daily sales aggregate
daily_sales = spark.table("gold.fct_sales") \
    .join(spark.table("gold.dim_date"), "sk_date") \
    .groupBy("date_key", "sk_product", "sk_store") \
    .agg(
        F.sum("quantity").alias("total_quantity"),
        F.sum("total_amount").alias("total_revenue"),
        F.sum("discount_amount").alias("total_discount"),
        F.count("sale_id").alias("transaction_count"),
        F.avg("total_amount").alias("avg_transaction_value")
    )

daily_sales.write.mode("overwrite").saveAsTable("gold.fct_sales_daily")
```

```sql
-- dbt daily aggregate
-- models/marts/aggregates/fct_sales_daily.sql
{{
  config(
    materialized='incremental',
    unique_key=['date_key', 'product_id', 'store_id'],
    incremental_strategy='merge'
  )
}}

SELECT
    d.date_key,
    p.product_id,
    s.store_id,
    SUM(f.quantity) AS total_quantity,
    SUM(f.total_amount) AS total_revenue,
    SUM(f.discount_amount) AS total_discount,
    COUNT(f.sale_id) AS transaction_count,
    AVG(f.total_amount) AS avg_transaction_value,
    CURRENT_TIMESTAMP() AS _load_timestamp
FROM {{ ref('fct_sales') }} f
JOIN {{ ref('dim_date') }} d ON f.sk_date = d.sk_date
JOIN {{ ref('dim_product') }} p ON f.sk_product = p.sk_product
JOIN {{ ref('dim_store') }} s ON f.sk_store = s.sk_store
{% if is_incremental() %}
WHERE d.date_key > (SELECT MAX(date_key) FROM {{ this }})
{% endif %}
GROUP BY d.date_key, p.product_id, s.store_id
```

### Rolling Aggregates

```python
# PySpark - Rolling 30-day metrics
from pyspark.sql.window import Window

window_30d = Window \
    .partitionBy("product_id") \
    .orderBy("date_key") \
    .rowsBetween(-29, 0)

rolling_metrics = daily_sales \
    .withColumn("rolling_30d_revenue", F.sum("total_revenue").over(window_30d)) \
    .withColumn("rolling_30d_qty", F.sum("total_quantity").over(window_30d)) \
    .withColumn("rolling_30d_avg_txn", F.avg("avg_transaction_value").over(window_30d))
```

### Period-over-Period Calculations

```python
# PySpark - YoY and MoM growth
from pyspark.sql.window import Window

# Monthly aggregates
monthly = daily_sales.groupBy(
    F.year("date_key").alias("year"),
    F.month("date_key").alias("month")
).agg(
    F.sum("total_revenue").alias("revenue")
)

# Add prior period
window_yoy = Window.partitionBy("month").orderBy("year")
window_mom = Window.orderBy("year", "month")

growth = monthly \
    .withColumn("prior_year_revenue", F.lag("revenue", 1).over(window_yoy)) \
    .withColumn("prior_month_revenue", F.lag("revenue", 1).over(window_mom)) \
    .withColumn("yoy_growth",
        (F.col("revenue") - F.col("prior_year_revenue")) / F.col("prior_year_revenue")) \
    .withColumn("mom_growth",
        (F.col("revenue") - F.col("prior_month_revenue")) / F.col("prior_month_revenue"))
```

```sql
-- dbt YoY growth
-- models/marts/aggregates/monthly_revenue_growth.sql
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', date_key) AS month_start,
        SUM(total_revenue) AS revenue
    FROM {{ ref('fct_sales_daily') }}
    GROUP BY 1
),

with_prior AS (
    SELECT
        month_start,
        revenue,
        LAG(revenue, 12) OVER (ORDER BY month_start) AS prior_year_revenue,
        LAG(revenue, 1) OVER (ORDER BY month_start) AS prior_month_revenue
    FROM monthly
)

SELECT
    month_start,
    revenue,
    prior_year_revenue,
    prior_month_revenue,
    (revenue - prior_year_revenue) / NULLIF(prior_year_revenue, 0) AS yoy_growth,
    (revenue - prior_month_revenue) / NULLIF(prior_month_revenue, 0) AS mom_growth
FROM with_prior
```

## KPI Calculations

### Customer Metrics

```python
# PySpark - Customer KPIs
customer_kpis = spark.table("gold.fct_sales") \
    .join(spark.table("gold.dim_customer").filter(F.col("is_current")), "sk_customer") \
    .groupBy("customer_id", "customer_name", "segment") \
    .agg(
        F.sum("total_amount").alias("lifetime_value"),
        F.count("sale_id").alias("total_orders"),
        F.avg("total_amount").alias("avg_order_value"),
        F.min("sale_date").alias("first_order_date"),
        F.max("sale_date").alias("last_order_date"),
        F.datediff(F.max("sale_date"), F.min("sale_date")).alias("customer_tenure_days")
    ) \
    .withColumn("orders_per_month",
        F.col("total_orders") / F.greatest(F.col("customer_tenure_days") / 30, F.lit(1)))
```

```sql
-- dbt customer KPIs
-- models/marts/kpis/customer_kpis.sql
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    SUM(f.total_amount) AS lifetime_value,
    COUNT(f.sale_id) AS total_orders,
    AVG(f.total_amount) AS avg_order_value,
    MIN(d.date_key) AS first_order_date,
    MAX(d.date_key) AS last_order_date,
    DATEDIFF(MAX(d.date_key), MIN(d.date_key)) AS customer_tenure_days,
    COUNT(f.sale_id) / GREATEST(DATEDIFF(MAX(d.date_key), MIN(d.date_key)) / 30.0, 1) AS orders_per_month
FROM {{ ref('fct_sales') }} f
JOIN {{ ref('dim_customer') }} c ON f.sk_customer = c.sk_customer AND c.is_current = TRUE
JOIN {{ ref('dim_date') }} d ON f.sk_date = d.sk_date
GROUP BY c.customer_id, c.customer_name, c.segment
```

### Product Performance

```python
# PySpark - Product performance
product_performance = spark.table("gold.fct_sales") \
    .join(spark.table("gold.dim_product").filter(F.col("is_current")), "sk_product") \
    .groupBy("product_id", "product_name", "category") \
    .agg(
        F.sum("quantity").alias("units_sold"),
        F.sum("total_amount").alias("total_revenue"),
        F.sum("total_amount") / F.sum("quantity").alias("avg_selling_price"),
        F.countDistinct("sk_customer").alias("unique_customers")
    ) \
    .withColumn("revenue_rank",
        F.dense_rank().over(Window.orderBy(F.desc("total_revenue"))))
```

## Conformed Dimensions

### Shared Dimensions Across Marts

```sql
-- dbt conformed dimension
-- models/marts/core/dim_geography.sql
-- Used by multiple fact tables

SELECT
    {{ dbt_utils.generate_surrogate_key(['country', 'state', 'city']) }} AS sk_geography,
    country,
    state,
    city,
    postal_code,
    region,
    timezone
FROM {{ ref('int_geography') }}
```

### Slowly Changing Dimension in Gold

```sql
-- dbt SCD Type 1 in Gold (for corrections only)
-- models/marts/core/dim_product.sql
{{
  config(
    materialized='incremental',
    unique_key='product_id',
    merge_update_columns=['product_name', 'category', 'subcategory', 'updated_at']
  )
}}

SELECT
    product_id,
    product_name,
    category,
    subcategory,
    brand,
    unit_cost,
    CURRENT_TIMESTAMP() AS updated_at
FROM {{ ref('int_products') }}
```

## Performance Optimization

### Partitioning and Clustering

```python
# PySpark - Optimize fact table
spark.table("gold.fct_sales") \
    .repartition("sk_date") \
    .write \
    .mode("overwrite") \
    .partitionBy("year", "month") \
    .format("delta") \
    .saveAsTable("gold.fct_sales_optimized")

# Z-order for common query patterns
spark.sql("""
    OPTIMIZE gold.fct_sales
    ZORDER BY (sk_customer, sk_product)
""")
```

### Materialized Views / Caching

Materialized views sit between regular views and tables: they store query results physically
but the platform handles refresh. Use them in Gold when:

- The aggregation query is **expensive** (multi-table joins, large scans) but doesn't need exact real-time
- The platform supports **automatic refresh** (Snowflake, BigQuery, Databricks SQL Warehouses)
- You want **table-like read performance** without managing a separate refresh pipeline

Avoid materialized views when:
- The underlying data changes frequently and staleness is unacceptable -- use incremental tables instead
- The platform doesn't support them (e.g., Fabric Lakehouses) -- check Tier 2 skill
- The query is simple enough that a regular view performs well

```python
# PySpark - Cache frequently accessed aggregates
daily_summary = spark.table("gold.fct_sales_daily").cache()
daily_summary.count()  # Materialize cache
```

```sql
-- Snowflake materialized view
CREATE MATERIALIZED VIEW gold.mv_sales_summary AS
SELECT
    date_key,
    SUM(total_revenue) AS revenue,
    COUNT(*) AS transactions
FROM gold.fct_sales_daily
GROUP BY date_key;
```

```sql
-- BigQuery materialized view with refresh
CREATE MATERIALIZED VIEW gold.mv_sales_summary
OPTIONS (enable_refresh = true, refresh_interval_minutes = 30)
AS
SELECT
    date_key,
    SUM(total_revenue) AS revenue,
    COUNT(*) AS transactions
FROM gold.fct_sales_daily
GROUP BY date_key;
```

### Query Hints

```python
# PySpark - Broadcast small dimensions
from pyspark.sql.functions import broadcast

fact_with_dims = spark.table("gold.fct_sales") \
    .join(broadcast(spark.table("gold.dim_date")), "sk_date") \
    .join(broadcast(spark.table("gold.dim_product")), "sk_product")
```
