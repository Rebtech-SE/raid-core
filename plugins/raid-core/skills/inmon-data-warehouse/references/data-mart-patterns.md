# Data Mart Patterns

Patterns for deriving dimensional data marts from the Inmon 3NF enterprise data warehouse.

## Mart Derivation from EDW

### Scoping a Mart

Each data mart serves a single business domain. Scope it by answering:

1. **Who uses it?** Sales team, marketing analysts, finance controllers
2. **What questions does it answer?** Revenue by product/region/time, customer lifetime value, inventory levels
3. **What EDW entities does it need?** Map questions to EDW subject areas
4. **What is the grain?** One row per order line, per day, per customer-month

### Derivation Steps

```
EDW (3NF)                          Data Mart (Star Schema)
---------                          ----------------------
customer ----+
address  ----+---> dim_customer
segment  ----+

product  ----+---> dim_product
category ----+

calendar --------> dim_date

order_header -+
order_line ---+--> fact_sales
```

1. **Select EDW entities** that relate to the mart's domain
2. **Denormalize dimensions**: Flatten 3NF entities into wide dimension tables
3. **Build fact tables**: Join transactional entities with dimension keys at the defined grain
4. **Add measures**: Aggregate, calculate, and derive metrics
5. **Add surrogate keys**: Generate mart-level keys for dimension tables

## Star Schema Construction

### Fact Table Types

#### Transactional Fact

One row per business event. Finest grain, most flexible for analysis.

```sql
-- models/marts/sales/fct_sales.sql
{{ config(materialized='table') }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['ol.order_line_id']) }} AS sales_key,
    o.order_date AS date_key,
    c.customer_id AS customer_key,
    p.product_id AS product_key,
    ol.quantity,
    ol.line_total AS revenue,
    p.unit_price * ol.quantity AS gross_amount,
    ol.line_total - (p.unit_price * ol.quantity) AS discount_amount
FROM {{ ref('edw_transaction__order_line') }} ol
JOIN {{ ref('edw_transaction__order_header') }} o ON ol.order_id = o.order_id
JOIN {{ ref('edw_customer__customer') }} c
    ON o.customer_id = c.customer_id AND c._is_current = TRUE
JOIN {{ ref('edw_product__product') }} p
    ON ol.product_id = p.product_id AND p._is_current = TRUE
```

```python
from pyspark.sql import functions as F

order_lines = spark.table("edw.transaction_order_line")
orders = spark.table("edw.transaction_order_header")
customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
products = spark.table("edw.product_product").filter(F.col("_is_current"))

fact_sales = (
    order_lines.alias("ol")
    .join(orders.alias("o"), "order_id")
    .join(customers.alias("c"), "customer_id")
    .join(products.alias("p"), "product_id")
    .select(
        F.monotonically_increasing_id().alias("sales_key"),
        F.col("o.order_date").alias("date_key"),
        F.col("c.customer_id").alias("customer_key"),
        F.col("p.product_id").alias("product_key"),
        F.col("ol.quantity"),
        F.col("ol.line_total").alias("revenue"),
    )
)
```

#### Periodic Snapshot Fact

One row per entity per time period. Captures state at regular intervals.

```sql
-- models/marts/inventory/fct_inventory_daily.sql
{{ config(materialized='incremental', unique_key=['date_key', 'product_key', 'location_key']) }}

SELECT
    CURRENT_DATE AS date_key,
    p.product_id AS product_key,
    l.location_id AS location_key,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_on_hand - i.quantity_reserved AS quantity_available,
    i.reorder_point,
    CASE WHEN i.quantity_on_hand <= i.reorder_point THEN TRUE ELSE FALSE END AS below_reorder
FROM {{ ref('edw_inventory__stock_level') }} i
JOIN {{ ref('edw_product__product') }} p ON i.product_id = p.product_id AND p._is_current
JOIN {{ ref('edw_geography__location') }} l ON i.location_id = l.location_id
WHERE i._is_current = TRUE
```

#### Accumulating Snapshot Fact

Tracks a process through milestones. Updated as the process progresses.

```sql
-- models/marts/fulfillment/fct_order_fulfillment.sql
{{ config(materialized='incremental', unique_key='order_key') }}

SELECT
    o.order_id AS order_key,
    o.customer_id AS customer_key,
    o.order_date,
    s.ship_date,
    d.delivery_date,
    r.return_date,
    DATEDIFF('day', o.order_date, s.ship_date) AS days_to_ship,
    DATEDIFF('day', s.ship_date, d.delivery_date) AS days_to_deliver,
    DATEDIFF('day', o.order_date, d.delivery_date) AS days_to_fulfill
FROM {{ ref('edw_transaction__order_header') }} o
LEFT JOIN {{ ref('edw_fulfillment__shipment') }} s ON o.order_id = s.order_id
LEFT JOIN {{ ref('edw_fulfillment__delivery') }} d ON s.shipment_id = d.shipment_id
LEFT JOIN {{ ref('edw_fulfillment__return') }} r ON o.order_id = r.order_id
```

## Snowflake Schema (Cost Profile)

For the Cost optimization profile, use snowflake schema to save storage by keeping dimensions normalized.

```
fact_sales
  |-- dim_customer (customer_id, customer_name, segment_id, address_id)
  |     |-- dim_segment (segment_id, segment_name, segment_description)
  |     |-- dim_address (address_id, city, country_id)
  |           |-- dim_country (country_id, country_name, region)
  |-- dim_product (product_id, product_name, category_id)
  |     |-- dim_category (category_id, category_name)
  |-- dim_date (date_key, year, month, day, quarter)
```

Trade-off: more joins at query time, but less storage and fewer update anomalies.

```sql
-- Cost profile: normalized dimension
-- models/marts/sales/dim_customer.sql
{{ config(materialized='view') }}  -- view to save storage

SELECT
    c.customer_id,
    c.customer_name,
    c.segment AS segment_id,
    a.address_id
FROM {{ ref('edw_customer__customer') }} c
LEFT JOIN {{ ref('edw_customer__address') }} a
    ON c.customer_id = a.customer_id
    AND a.address_type = 'billing'
    AND a._is_current = TRUE
WHERE c._is_current = TRUE

-- Separate segment dimension (normalized)
-- models/marts/sales/dim_segment.sql
{{ config(materialized='view') }}

SELECT DISTINCT
    segment AS segment_id,
    segment_description
FROM {{ ref('edw_customer__segment') }}
```

## Conformed Dimensions Across Marts

The same dimension table is shared across all marts. Build it once in a shared location.

```
marts/
  shared/               <-- Conformed dimensions live here
    dim_customer.sql
    dim_product.sql
    dim_date.sql
  sales/
    fct_sales.sql        <-- References shared dims
  marketing/
    fct_campaigns.sql    <-- References same shared dims
  finance/
    fct_revenue.sql      <-- References same shared dims
```

dbt `ref()` ensures all marts point to the same physical dimension table.

## Materialization Strategies per Profile

| Artifact | Performance | Cost | Usability |
|---|---|---|---|
| Conformed dims | Table, refresh hourly | View | Table, refresh daily |
| Transactional facts | Incremental, micro-batch | View on EDW | Table, hourly incremental |
| Snapshot facts | Table, refresh at snapshot time | Table, refresh nightly | Table, refresh daily |
| Aggregate facts | Table, multiple granularities | Skip (aggregate on read) | Table, top reports only |

## Complete Sales Mart Example

### dbt Project Structure

```
models/marts/
  shared/
    dim_customer.sql
    dim_product.sql
    dim_date.sql
    dim_customer.yml
    dim_product.yml
  sales/
    fct_sales.sql
    fct_sales_daily.sql      -- (Performance profile only)
    fct_sales_monthly.sql    -- (Performance profile only)
    fct_sales.yml
    sales_mart.yml           -- source/model tests
```

### dim_customer.sql

```sql
{{ config(materialized='table', tags=['conformed', 'dimension']) }}

SELECT
    c.customer_id,
    c.customer_name,
    c.email,
    c.segment,
    a.city,
    a.postal_code,
    a.country
FROM {{ ref('edw_customer__customer') }} c
LEFT JOIN {{ ref('edw_customer__address') }} a
    ON c.customer_id = a.customer_id
    AND a.address_type = 'billing'
    AND a._is_current = TRUE
WHERE c._is_current = TRUE
```

### dim_product.sql

```sql
{{ config(materialized='table', tags=['conformed', 'dimension']) }}

SELECT
    p.product_id,
    p.product_name,
    p.unit_price,
    pc.category_id,
    pc.category_name
FROM {{ ref('edw_product__product') }} p
LEFT JOIN {{ ref('edw_product__category') }} pc
    ON p.category_id = pc.category_id
WHERE p._is_current = TRUE
```

### fct_sales.sql

```sql
{{ config(materialized='table', tags=['fact', 'sales']) }}

SELECT
    ol.order_line_id AS sales_key,
    o.order_date AS date_key,
    c.customer_id AS customer_key,
    p.product_id AS product_key,
    ol.quantity,
    ol.line_total AS revenue
FROM {{ ref('edw_transaction__order_line') }} ol
JOIN {{ ref('edw_transaction__order_header') }} o ON ol.order_id = o.order_id
JOIN {{ ref('dim_customer') }} c ON o.customer_id = c.customer_id
JOIN {{ ref('dim_product') }} p ON ol.product_id = p.product_id
```

### PySpark Complete Example

```python
from pyspark.sql import functions as F


def build_sales_mart(spark, profile="usability"):
    """Build the complete sales mart from EDW entities."""

    # -- Conformed Dimensions --
    customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
    addresses = spark.table("edw.customer_address").filter(
        (F.col("_is_current")) & (F.col("address_type") == "billing")
    )
    products = spark.table("edw.product_product").filter(F.col("_is_current"))
    categories = spark.table("edw.product_category")

    dim_customer = (
        customers.join(addresses, "customer_id", "left")
        .select("customer_id", "customer_name", "email", "segment", "city", "country")
    )
    dim_customer.write.format("delta").mode("overwrite") \
        .saveAsTable("marts.shared.dim_customer")

    dim_product = (
        products.join(categories, "category_id", "left")
        .select("product_id", "product_name", "unit_price", "category_id", "category_name")
    )
    dim_product.write.format("delta").mode("overwrite") \
        .saveAsTable("marts.shared.dim_product")

    # -- Fact Table --
    orders = spark.table("edw.transaction_order_header")
    order_lines = spark.table("edw.transaction_order_line")

    fact_sales = (
        order_lines.alias("ol")
        .join(orders.alias("o"), "order_id")
        .select(
            F.col("ol.order_line_id").alias("sales_key"),
            F.col("o.order_date").alias("date_key"),
            F.col("o.customer_id").alias("customer_key"),
            F.col("ol.product_id").alias("product_key"),
            F.col("ol.quantity"),
            F.col("ol.line_total").alias("revenue"),
        )
    )

    write_opts = fact_sales.write.format("delta").mode("overwrite")
    if profile in ("performance", "usability"):
        write_opts = write_opts.partitionBy("date_key")
    write_opts.saveAsTable("marts.sales.fact_sales")

    # Performance profile: additional aggregation tables
    if profile == "performance":
        fact_sales_daily = fact_sales.groupBy("date_key", "customer_key", "product_key").agg(
            F.sum("quantity").alias("total_quantity"),
            F.sum("revenue").alias("total_revenue"),
        )
        fact_sales_daily.write.format("delta").mode("overwrite") \
            .partitionBy("date_key") \
            .saveAsTable("marts.sales.fact_sales_daily")
```
