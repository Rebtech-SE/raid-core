# Optimization Profiles

Optimization profiles control materialization, indexing, denormalization, and refresh strategy across the Inmon EDW. The profile is **locked at Tier 3** during customer customization. When unspecified, default to **Usability**.

## Profile Definitions

### Performance

Optimize for query speed and low latency. Accept higher storage costs and more complex pipelines.

- Pre-compute aggregations at multiple granularities
- Aggressive indexing and clustering
- Denormalize hot joins even in the EDW when query SLAs demand it
- Micro-batch or near real-time refresh
- Best for: real-time dashboards, operational analytics, SLA-bound reports

### Cost

Minimize storage and compute spend. Accept slower queries and simpler pipelines.

- Views instead of materialized tables where possible
- Minimal indexing (primary keys only)
- Strict 3NF everywhere -- no denormalization
- Nightly batch refresh, full refresh where cheaper than CDC
- Best for: archive warehouses, compliance stores, low-query-volume environments

### Usability

Balance query performance with analyst accessibility. Moderate storage and compute.

- Clear, intuitive naming and structure
- Balanced indexing on common filter columns
- Selective denormalization for confusing joins
- Hourly incremental with daily reconciliation
- Best for: most projects, analyst-facing warehouses, teams without dedicated DBA

## Comprehensive Decision Matrix

### EDW Layer

| Design Choice | Performance | Cost | Usability |
|---|---|---|---|
| Materialization | Delta tables with Z-ordering | Delta tables, minimal partitioning | Delta tables with date partitioning |
| Indexing | Composite indexes on all FK + filter columns | PK only | PK + FK + common filter columns |
| Denormalization | Denormalize hot lookup joins | Never denormalize | Denormalize only confusing multi-hop lookups |
| SCD strategy | Full SCD2 on all entities | SCD1 on non-critical, SCD2 on audited | SCD2 on key entities, SCD1 on reference data |
| Compression | Columnar + dictionary encoding | Maximum compression ratio | Columnar default |
| Statistics | Compute on every load | Compute weekly | Compute daily |

### Mart Layer

| Design Choice | Performance | Cost | Usability |
|---|---|---|---|
| Schema type | Star (fully denormalized dims) | Snowflake (normalized dims) | Star |
| Aggregation | Multiple granularities pre-computed | No pre-aggregation | Top 5 report granularities |
| Partitioning | Date + high-cardinality dimension | Date only | Date |
| Refresh | Incremental micro-batch | Nightly full refresh | Hourly incremental |
| Caching | Materialized views for hot queries | No caching | Materialized views for top dashboards |
| History in dims | Full SCD2 with surrogate keys | SCD1 (overwrite) | SCD2 on key attributes, SCD1 on rest |

### ETL / Processing

| Design Choice | Performance | Cost | Usability |
|---|---|---|---|
| Extract | CDC with streaming | Scheduled full extracts | Incremental with watermarks |
| Transform compute | Dedicated cluster, auto-scaling | Shared cluster, spot instances | Standard cluster |
| Parallelism | Max parallelism across subject areas | Sequential to minimize concurrent compute | Moderate parallelism |
| Error handling | Retry + dead letter + alert immediately | Retry + log, alert daily | Retry + dead letter + alert on threshold |
| Monitoring | Real-time pipeline metrics | Daily summary reports | Hourly health checks |

## Profile Application Example: Customer Mart

### Performance Profile

```python
from pyspark.sql import functions as F

# Pre-compute at multiple granularities
customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
orders = spark.table("edw.transaction_order_header")
order_lines = spark.table("edw.transaction_order_line")

# Detailed grain: one row per order line
fact_sales_detail = (
    order_lines.join(orders, "order_id")
    .join(customers, "customer_id")
    .select(
        "order_line_id", "order_id", "order_date",
        "customer_id", "segment", "product_id",
        "quantity", "line_total",
    )
)
fact_sales_detail.write.format("delta") \
    .mode("overwrite") \
    .partitionBy("order_date") \
    .saveAsTable("marts.sales.fact_sales_detail")

# Daily summary grain
fact_sales_daily = fact_sales_detail.groupBy(
    "order_date", "customer_id", "segment", "product_id"
).agg(
    F.sum("quantity").alias("total_quantity"),
    F.sum("line_total").alias("total_revenue"),
    F.countDistinct("order_id").alias("order_count"),
)
fact_sales_daily.write.format("delta") \
    .mode("overwrite") \
    .partitionBy("order_date") \
    .saveAsTable("marts.sales.fact_sales_daily")

# Monthly summary grain
fact_sales_monthly = fact_sales_detail.withColumn(
    "month", F.date_trunc("month", "order_date")
).groupBy("month", "segment").agg(
    F.sum("line_total").alias("total_revenue"),
    F.countDistinct("customer_id").alias("unique_customers"),
)
fact_sales_monthly.write.format("delta") \
    .mode("overwrite") \
    .saveAsTable("marts.sales.fact_sales_monthly")
```

```sql
-- dbt: Performance profile uses multiple materializations
-- models/marts/sales/fct_sales_detail.sql
{{ config(materialized='incremental', unique_key='order_line_id') }}

SELECT
    ol.order_line_id,
    o.order_date,
    c.customer_id,
    c.segment,
    p.product_id,
    ol.quantity,
    ol.line_total
FROM {{ ref('edw_transaction__order_line') }} ol
JOIN {{ ref('edw_transaction__order_header') }} o ON ol.order_id = o.order_id
JOIN {{ ref('edw_customer__customer') }} c ON o.customer_id = c.customer_id AND c._is_current
JOIN {{ ref('edw_product__product') }} p ON ol.product_id = p.product_id AND p._is_current

{% if is_incremental() %}
WHERE o.order_date > (SELECT MAX(order_date) FROM {{ this }})
{% endif %}


-- models/marts/sales/fct_sales_daily.sql
{{ config(materialized='table') }}

SELECT
    order_date,
    customer_id,
    segment,
    product_id,
    SUM(quantity) AS total_quantity,
    SUM(line_total) AS total_revenue,
    COUNT(DISTINCT order_id) AS order_count
FROM {{ ref('fct_sales_detail') }}
GROUP BY order_date, customer_id, segment, product_id
```

### Cost Profile

```python
# Cost profile: single granularity, minimal materialization
fact_sales = (
    order_lines.join(orders, "order_id")
    .select(
        "order_line_id", "order_id", "order_date",
        "customer_id", "product_id",
        "quantity", "line_total",
    )
)
# No partitioning, no extra aggregation tables
fact_sales.write.format("delta") \
    .mode("overwrite") \
    .saveAsTable("marts.sales.fact_sales")
```

```sql
-- dbt: Cost profile uses views where possible
-- models/marts/sales/fct_sales.sql
{{ config(materialized='view') }}

SELECT
    ol.order_line_id,
    o.order_date,
    o.customer_id,
    ol.product_id,
    ol.quantity,
    ol.line_total
FROM {{ ref('edw_transaction__order_line') }} ol
JOIN {{ ref('edw_transaction__order_header') }} o ON ol.order_id = o.order_id
```

### Usability Profile (Default)

```python
# Usability profile: clear naming, date partitioning, moderate aggregation
fact_sales = (
    order_lines.alias("ol")
    .join(orders.alias("o"), "order_id")
    .join(customers.alias("c"), "customer_id")
    .join(products.alias("p"), "product_id")
    .select(
        F.col("ol.order_line_id"),
        F.col("o.order_id"),
        F.col("o.order_date"),
        F.col("c.customer_id"),
        F.col("c.customer_name"),   # denormalize for analyst convenience
        F.col("c.segment").alias("customer_segment"),
        F.col("p.product_id"),
        F.col("p.product_name"),    # denormalize for analyst convenience
        F.col("p.category_id"),
        F.col("ol.quantity"),
        F.col("ol.line_total"),
    )
)
fact_sales.write.format("delta") \
    .mode("overwrite") \
    .partitionBy("order_date") \
    .saveAsTable("marts.sales.fact_sales")
```

```sql
-- dbt: Usability profile as table with clear naming
-- models/marts/sales/fct_sales.sql
{{ config(materialized='table') }}

SELECT
    ol.order_line_id,
    o.order_id,
    o.order_date,
    c.customer_id,
    c.customer_name,
    c.segment AS customer_segment,
    p.product_id,
    p.product_name,
    p.category_id,
    ol.quantity,
    ol.line_total
FROM {{ ref('edw_transaction__order_line') }} ol
JOIN {{ ref('edw_transaction__order_header') }} o ON ol.order_id = o.order_id
JOIN {{ ref('edw_customer__customer') }} c
    ON o.customer_id = c.customer_id AND c._is_current = TRUE
JOIN {{ ref('edw_product__product') }} p
    ON ol.product_id = p.product_id AND p._is_current = TRUE
```

## Composite Profiles

Some projects benefit from mixing profiles across layers. Common combinations:

| Combination | When to Use |
|---|---|
| Cost EDW + Performance Marts | Large historical EDW rarely queried directly; marts serve dashboards with SLAs |
| Usability EDW + Performance Marts | Analysts query EDW for ad-hoc; dashboards need fast marts |
| Cost EDW + Usability Marts | Budget-constrained but analysts need approachable marts |

When using composite profiles, document the choice in the project's CLAUDE.md:

```markdown
## Optimization Profile
- EDW layer: Cost (strict 3NF, nightly batch, minimal indexing)
- Mart layer: Performance (pre-aggregated, micro-batch, Z-ordered)
```

## Platform-Specific Optimization

### Databricks

| Technique | Performance | Cost | Usability |
|---|---|---|---|
| Z-ORDER BY | On all fact table join/filter columns | Skip | On date column only |
| OPTIMIZE | After every load | Weekly | Daily |
| Auto-compaction | Enabled | Disabled | Enabled |
| Photon | Enabled for mart queries | Disabled | Enabled for mart queries |
| Liquid clustering | On high-cardinality filter columns | Skip | On date + primary dimension |

### Snowflake

| Technique | Performance | Cost | Usability |
|---|---|---|---|
| Clustering keys | Multi-column on query patterns | None | Date column |
| Warehouse size | XL for mart builds, M for EDW | XS everywhere | M for mart builds, S for EDW |
| Materialized views | On hot dashboard queries | None | On top 3 dashboards |
| Result caching | Enabled | Enabled | Enabled |
| Auto-suspend | 1 min | 1 min | 5 min |

### Microsoft Fabric

| Technique | Performance | Cost | Usability |
|---|---|---|---|
| V-Order | Enabled on all tables | Skip | Enabled on mart tables |
| Table maintenance | After every load | Weekly | Daily |
| Direct Lake mode | Enabled for all marts | Only for primary mart | For top dashboards |
| Capacity | F64+ | F2-F4 | F8-F16 |

### BigQuery

| Technique | Performance | Cost | Usability |
|---|---|---|---|
| Partitioning | Date + clustering on filter cols | Date only | Date |
| Clustering | Up to 4 columns on query patterns | 1 column | 2 columns |
| Materialized views | On hot queries | None | On top dashboards |
| BI Engine | Enabled, large reservation | Disabled | Small reservation |
| Slot commitment | Annual for predictable cost | On-demand | Flex slots |
