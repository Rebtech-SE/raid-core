---
name: inmon-data-warehouse
description: >-
  Triggers: 'Inmon', 'EDW', '3NF warehouse', 'enterprise data warehouse', 'top-down',
  'subject area model', 'conformed dimensions', 'data mart derivation'. Inmon enterprise
  data warehouse methodology with 3NF normalized EDW, subject area modeling, conformed
  dimensions, and data mart derivation. Includes optimization profiles
  (Performance/Cost/Usability) locked per-project at Tier 3.
---

# Inmon Data Warehouse

Enterprise data warehouse methodology following Bill Inmon's top-down approach: build a single normalized (3NF) enterprise data warehouse first, then derive dimensional data marts for business consumption.

## When to Use This Skill

Use this skill when users ask about:

- **Enterprise data warehouse**: "How do I build an enterprise-wide data warehouse?"
- **Top-down design**: "Should I model the whole enterprise first?"
- **3NF warehouse**: "How do I normalize my warehouse?"
- **Subject areas**: "How do I decompose the enterprise model into subject areas?"
- **Conformed dimensions**: "How do I share dimensions across data marts?"
- **Data mart derivation**: "How do I build star schema marts from a normalized warehouse?"
- **Inmon vs Kimball/medallion**: "Which warehouse methodology should I use?"

## Optimization Profile Selector

The optimization profile controls materialization, indexing, and denormalization decisions throughout the warehouse. The profile is **locked at Tier 3** during customer customization. When unspecified, default to **Usability**.

| Design Choice | Performance | Cost | Usability |
|---|---|---|---|
| **Materialization** | Materialized views, pre-computed aggregates | Views where possible, materialize only hot paths | Tables with clear naming, moderate materialization |
| **Indexing** | Aggressive: composite indexes, covering indexes, columnstore | Minimal: primary keys and critical FKs only | Balanced: PK + FK + common filter columns |
| **Denormalization** | Denormalize hot joins into EDW where query SLAs demand | Strict 3NF everywhere, denormalize nothing | Selective: denormalize lookup joins that confuse analysts |
| **Aggregation** | Pre-aggregate at multiple granularities | Single granularity, aggregate on read | Pre-aggregate top 5 most-used report granularities |
| **Refresh strategy** | Micro-batch / near real-time CDC | Nightly batch, full refresh where cheaper than CDC | Hourly incremental with daily full reconciliation |
| **Storage format** | Columnar with Z-ordering / clustering on query patterns | Row-oriented or default format, compress aggressively | Columnar with partition pruning on date |

See [optimization-profiles.md](references/optimization-profiles.md) for full decision matrix with code examples per profile.

## Inmon vs Medallion Decision Tree

```
What does the organization need?
|
|-- Enterprise-wide single source of truth?
|   |-- Regulated industry / audit requirements?
|   |   |-> Inmon EDW (3NF + derived marts)
|   |
|   |-- Multiple business domains sharing dimensions?
|       |-> Inmon EDW (conformed dimensions)
|
|-- Fast, iterative analytics for a single team?
|   |-> Medallion (Bronze/Silver/Gold)
|
|-- Both enterprise governance AND agile team delivery?
    |-> Hybrid: shared staging, parallel EDW + Silver, unified marts
    |   See: migration-from-medallion.md
```

When in doubt: start with medallion for speed, introduce Inmon EDW layer when cross-domain conformance becomes painful.

## Core Principles

### 1. Top-Down: Enterprise Model First

Design the enterprise data model before building any mart. The EDW reflects the entire business -- not a single department's view. This prevents data silos and conflicting definitions.

Steps:
1. Identify enterprise subject areas (see below)
2. Model entities and relationships across subject areas
3. Define conformed dimensions and business keys
4. Build the normalized EDW
5. Derive departmental data marts from the EDW

### 2. 3NF Normalized EDW

The enterprise data warehouse is normalized to third normal form (3NF). This eliminates redundancy and ensures a single version of truth.

**Decomposition example** -- an order system flattened in the source becomes six normalized tables in the EDW:

```
Source (flat):
  order_id, order_date, customer_name, customer_email,
  customer_address, product_name, product_category,
  quantity, unit_price, total

EDW (3NF):
  customer (customer_id, customer_name, email)
  address (address_id, customer_id, street, city, postal_code, country)
  product_category (category_id, category_name)
  product (product_id, product_name, category_id, unit_price)
  order_header (order_id, customer_id, order_date)
  order_line (order_line_id, order_id, product_id, quantity, line_total)
```

Each entity stores one fact about one thing. Updates to a customer's email affect exactly one row in one table.

See [enterprise-modeling.md](references/enterprise-modeling.md) for normalization rules and subject area templates.

### 3. Subject Areas

Partition the enterprise model into coherent subject areas. Each subject area groups related entities and has clear ownership.

| Subject Area | Core Entities | Typical Owner |
|---|---|---|
| **Customer** | customer, contact, address, segment | CRM / Sales |
| **Product** | product, category, supplier, pricing | Product / Merchandising |
| **Transaction** | order, order_line, invoice, payment | Finance / Operations |
| **Organization** | department, employee, role, hierarchy | HR / Corporate |
| **Geography** | region, country, city, location | Operations / Logistics |
| **Time** | calendar, fiscal_period, holiday | Shared / BI team |

Subject areas can reference entities from other areas (e.g., `order` references `customer`), but each entity belongs to exactly one area.

### 4. Time-Variant Data

The EDW tracks how data changes over time. Every key entity must support historical tracking via SCD Type 2.

Required temporal columns on historized entities:

| Column | Type | Purpose |
|---|---|---|
| `_valid_from` | DATE | When this version became valid |
| `_valid_to` | DATE | When this version was superseded (9999-12-31 for current) |
| `_is_current` | BOOLEAN | Fast filter for current state |

These are the framework-wide SCD column names, not Inmon-specific ones: `_valid_from`,
`_valid_to`, `_is_current`, `_hash` are defined by [scd-pattern](../scd-pattern/SKILL.md)
and recorded in `.raid/config.yaml` under `conventions.scd_columns`. An EDW uses the same
names as any other RAID layer -- do not substitute Inmon-literature spellings
(`_effective_date` / `_expiry_date`), which would fork the convention and break the shared
SCD tooling and reviewers.

Implementation details: see [scd-pattern](../scd-pattern/SKILL.md). The SCD skill defines
merge logic, hash-based change detection, and testing patterns. What this skill adds on top
is the EDW metadata set below (`_edw_load_timestamp`, `_edw_batch_id`).

### 5. Non-Volatile

Data in the EDW is never destructively updated. When a value changes:
- The old row is closed (`_valid_to` = today - 1, `_is_current` = false)
- A new row is inserted with the updated value (`_valid_from` = today, `_is_current` = true)

Corrections follow the same pattern: insert a corrected version, close the incorrect one. This preserves full audit trail.

### 6. Conformed Dimensions

Dimensions shared across data marts must have identical structure, keys, and business definitions. A `dim_customer` used by the Sales mart and the Marketing mart is the same table -- not two copies with different logic.

Rules:
- One physical dimension table in the EDW, consumed by all marts
- Business key (`customer_id`) is defined once and used everywhere
- Surrogate keys are generated in the EDW, not in individual marts
- Attribute definitions (e.g., "active customer") are centrally governed

## Architecture Overview

```
+------------+    +-----------+    +------------------+    +------------------+
|            |    |           |    |                  |    |                  |
|  Sources   |--->|  Staging  |--->|   EDW (3NF)      |--->|   Data Marts     |
|            |    |  (Bronze) |    |  Normalized      |    |  (Star/Snowflake)|
|            |    |           |    |  Subject Areas   |    |  Per department  |
+------------+    +-----------+    +------------------+    +------------------+
  ERP, CRM,       Append-only      customer, product,      dim_customer,
  APIs, files     raw capture       order, org, geo, time   fact_sales, ...
```

### Layer Naming Conventions

| Layer | Databricks | Snowflake | Fabric | dbt |
|---|---|---|---|---|
| **Staging** | `staging.{source}_{entity}` | `RAW.{SOURCE}_{ENTITY}` | `staging_{source}_{entity}` | `stg_{source}__{entity}` |
| **EDW** | `edw.{subject_area}_{entity}` | `EDW.{SUBJECT_AREA}_{ENTITY}` | `edw_{subject_area}_{entity}` | `edw_{subject_area}__{entity}` |
| **Marts** | `marts.{domain}.fact_{x}` | `MARTS.{DOMAIN}.FACT_{X}` | `mart_{domain}_fact_{x}` | `mart_{domain}__fct_{x}` |

## Quick Decision Tree

```
What are you building?
|
|-- Ingesting from an external source?
|   |-> Staging layer (same as Bronze)
|   |   See: build-ingestion-pipeline skill
|
|-- Normalizing and conforming enterprise data?
|   |-> EDW layer (3NF)
|   |   - Decompose into subject area entities
|   |   - Add temporal columns for SCD Type 2
|   |   - Enforce referential integrity
|
|-- Building reports or analytics for a department?
|   |-> Data Mart (star/snowflake schema)
|   |   - Derive from EDW, never from staging
|   |   - Use conformed dimensions
|   |   - Apply optimization profile
|
|-- Need both enterprise conformance AND agile marts?
    |-> Hybrid pattern
        See: migration-from-medallion.md
```

## Staging Area

The staging area is functionally identical to the Bronze layer in medallion architecture. It captures raw data from source systems with no transformation.

- Append-only writes with audit columns (`_ingestion_timestamp`, `_source_system`, `_batch_id`)
- No deduplication, no cleansing, no type casting
- Partitioned by ingestion date for efficient incremental reads

For staging patterns and implementation, see [build-ingestion-pipeline](../build-ingestion-pipeline/SKILL.md).

## Enterprise Data Warehouse (3NF)

### Modeling Example

Decompose a source order system into normalized EDW entities:

**customer** (Subject Area: Customer)
| Column | Type | Notes |
|---|---|---|
| `customer_id` | STRING | Business key |
| `customer_name` | STRING | |
| `email` | STRING | |
| `segment` | STRING | |
| `_valid_from` | DATE | SCD Type 2 |
| `_valid_to` | DATE | SCD Type 2 |
| `_is_current` | BOOLEAN | SCD Type 2 |
| `_edw_load_timestamp` | TIMESTAMP | When loaded into EDW |
| `_edw_batch_id` | STRING | Processing batch |
| `_source_system` | STRING | Origin system |

**address** (Subject Area: Customer)
| Column | Type | Notes |
|---|---|---|
| `address_id` | STRING | Business key |
| `customer_id` | STRING | FK to customer |
| `address_type` | STRING | billing / shipping |
| `street` | STRING | |
| `city` | STRING | |
| `postal_code` | STRING | |
| `country` | STRING | FK to geography |
| `_valid_from` | DATE | SCD Type 2 |
| `_valid_to` | DATE | SCD Type 2 |
| `_is_current` | BOOLEAN | SCD Type 2 |

**product** (Subject Area: Product)
| Column | Type | Notes |
|---|---|---|
| `product_id` | STRING | Business key |
| `product_name` | STRING | |
| `category_id` | STRING | FK to product_category |
| `unit_price` | DECIMAL(18,2) | |
| `_valid_from` | DATE | SCD Type 2 |
| `_valid_to` | DATE | SCD Type 2 |
| `_is_current` | BOOLEAN | SCD Type 2 |

**product_category** (Subject Area: Product)
| Column | Type | Notes |
|---|---|---|
| `category_id` | STRING | Business key |
| `category_name` | STRING | |

**order_header** (Subject Area: Transaction)
| Column | Type | Notes |
|---|---|---|
| `order_id` | STRING | Business key |
| `customer_id` | STRING | FK to customer |
| `order_date` | DATE | |
| `status` | STRING | |
| `_edw_load_timestamp` | TIMESTAMP | |

**order_line** (Subject Area: Transaction)
| Column | Type | Notes |
|---|---|---|
| `order_line_id` | STRING | Business key |
| `order_id` | STRING | FK to order_header |
| `product_id` | STRING | FK to product |
| `quantity` | INT | |
| `line_total` | DECIMAL(18,2) | |

### Required Metadata Columns

Every EDW table must include:

| Column | Type | Purpose |
|---|---|---|
| `_edw_load_timestamp` | TIMESTAMP | When record was loaded into EDW |
| `_edw_batch_id` | STRING | Processing batch identifier |
| `_source_system` | STRING | Origin system identifier |
| `_hash` | STRING | MD5/SHA256 of business columns for change detection |

Historized entities additionally require `_valid_from`, `_valid_to`, `_is_current` (see Core Principles > Time-Variant Data).

### PySpark Implementation

```python
from pyspark.sql import functions as F
from delta.tables import DeltaTable


def load_edw_entity(
    spark,
    source_df,
    target_table: str,
    business_key: str,
    tracked_columns: list,
    batch_id: str,
    source_system: str,
):
    """Load a staging record set into a 3NF EDW entity with SCD Type 2."""
    hash_expr = F.md5(F.concat_ws("||", *[F.col(c) for c in tracked_columns]))

    enriched = source_df.select(
        F.col(business_key),
        *[F.col(c) for c in tracked_columns],
        hash_expr.alias("_hash"),
        F.lit(source_system).alias("_source_system"),
        F.lit(batch_id).alias("_edw_batch_id"),
        F.current_timestamp().alias("_edw_load_timestamp"),
    )

    if spark.catalog.tableExists(target_table):
        target = DeltaTable.forName(spark, target_table)
        current = spark.table(target_table).filter(F.col("_is_current") == True)

        # Identify changed and new records
        changes = enriched.alias("s").join(
            current.alias("t"),
            F.col(f"s.{business_key}") == F.col(f"t.{business_key}"),
            "left",
        ).filter(
            F.col(f"t.{business_key}").isNull()
            | (F.col("s._hash") != F.col("t._hash"))
        ).select("s.*")

        if changes.count() == 0:
            return

        # Close existing records
        changed_keys = [
            row[business_key] for row in changes.filter(
                F.col("_hash").isNotNull()
            ).select(business_key).collect()
        ]
        if changed_keys:
            target.update(
                condition=(
                    F.col(business_key).isin(changed_keys)
                    & (F.col("_is_current") == True)
                ),
                set={
                    "_is_current": F.lit(False),
                    "_valid_to": F.date_sub(F.current_date(), 1),
                },
            )

        # Insert new versions
        new_rows = changes.withColumn("_is_current", F.lit(True)) \
            .withColumn("_valid_from", F.current_date()) \
            .withColumn("_valid_to", F.to_date(F.lit("9999-12-31")))

        new_rows.write.mode("append").saveAsTable(target_table)
    else:
        # Initial load
        initial = enriched \
            .withColumn("_is_current", F.lit(True)) \
            .withColumn("_valid_from", F.current_date()) \
            .withColumn("_valid_to", F.to_date(F.lit("9999-12-31")))
        initial.write.format("delta").saveAsTable(target_table)
```

### dbt/SQL Implementation

```sql
-- models/edw/customer/edw_customer__customer.sql
{{
  config(
    materialized='incremental',
    unique_key='_surrogate_key',
    tags=['edw', 'customer']
  )
}}

WITH source AS (
    SELECT
        customer_id,
        customer_name,
        email,
        segment,
        MD5(CONCAT_WS('||', customer_name, email, segment)) AS _hash,
        '{{ var("source_system", "unknown") }}' AS _source_system,
        '{{ var("batch_id", "manual") }}' AS _edw_batch_id,
        CURRENT_TIMESTAMP() AS _edw_load_timestamp
    FROM {{ ref('stg_crm__customers') }}
),

{% if is_incremental() %}
current_records AS (
    SELECT * FROM {{ this }}
    WHERE _is_current = TRUE
),

changes AS (
    SELECT
        s.*,
        CASE
            WHEN c.customer_id IS NULL THEN 'INSERT'
            WHEN c._hash != s._hash THEN 'UPDATE'
            ELSE 'NO_CHANGE'
        END AS _change_type
    FROM source s
    LEFT JOIN current_records c ON s.customer_id = c.customer_id
),

closed AS (
    SELECT
        c._surrogate_key,
        c.customer_id,
        c.customer_name,
        c.email,
        c.segment,
        c._hash,
        c._source_system,
        c._edw_batch_id,
        c._edw_load_timestamp,
        c._valid_from,
        CURRENT_DATE - INTERVAL '1 day' AS _valid_to,
        FALSE AS _is_current
    FROM current_records c
    INNER JOIN changes ch ON c.customer_id = ch.customer_id
    WHERE ch._change_type = 'UPDATE'
),

new_records AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['customer_id', '_edw_load_timestamp']) }}
            AS _surrogate_key,
        customer_id,
        customer_name,
        email,
        segment,
        _hash,
        _source_system,
        _edw_batch_id,
        _edw_load_timestamp,
        CURRENT_DATE AS _valid_from,
        DATE '9999-12-31' AS _valid_to,
        TRUE AS _is_current
    FROM changes
    WHERE _change_type IN ('INSERT', 'UPDATE')
)

SELECT * FROM closed
UNION ALL
SELECT * FROM new_records

{% else %}

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', '_edw_load_timestamp']) }}
        AS _surrogate_key,
    customer_id,
    customer_name,
    email,
    segment,
    _hash,
    _source_system,
    _edw_batch_id,
    _edw_load_timestamp,
    CURRENT_DATE AS _valid_from,
    DATE '9999-12-31' AS _valid_to,
    TRUE AS _is_current
FROM source

{% endif %}
```

## Data Marts

Data marts are derived from the EDW -- never from staging. Each mart serves a specific business domain using star or snowflake schema.

### Derivation Process

1. **Scope**: Identify the business domain and its questions (e.g., "Sales mart: revenue by product, region, time")
2. **Facts**: Select transactional entities from the EDW that answer those questions
3. **Dimensions**: Identify conformed dimensions needed (customer, product, time, geography)
4. **Grain**: Define the fact table grain (one row per order line, per day, etc.)
5. **Measures**: Define additive, semi-additive, and non-additive measures

### Optimization Impact on Mart Design

| Design Choice | Performance | Cost | Usability |
|---|---|---|---|
| **Schema type** | Star (fully denormalized dims) | Snowflake (normalized dims save storage) | Star (simple joins for analysts) |
| **Aggregation tables** | Multiple granularities pre-computed | No pre-aggregation, compute on read | Top 5 report granularities pre-computed |
| **Dimension loading** | Full SCD Type 2 with surrogate keys | SCD Type 1 (overwrite, save storage) | SCD Type 2 on key attributes, Type 1 on rest |
| **Partitioning** | By date + high-cardinality filter | By date only | By date |
| **Refresh** | Incremental micro-batch | Nightly full refresh | Hourly incremental |

See [data-mart-patterns.md](references/data-mart-patterns.md) for complete mart derivation examples.

### PySpark Implementation

```python
from pyspark.sql import functions as F


def build_sales_mart(spark, optimization_profile="usability"):
    """Derive a sales fact table from EDW entities."""

    # Read current-state EDW entities
    customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
    products = spark.table("edw.product_product").filter(F.col("_is_current"))
    orders = spark.table("edw.transaction_order_header")
    order_lines = spark.table("edw.transaction_order_line")

    # Build fact table at order-line grain
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
            F.col("c.segment").alias("customer_segment"),
            F.col("p.product_id"),
            F.col("p.category_id"),
            F.col("ol.quantity"),
            F.col("ol.line_total"),
        )
    )

    # Materialization depends on optimization profile
    if optimization_profile == "performance":
        fact_sales.write.format("delta") \
            .mode("overwrite") \
            .partitionBy("order_date") \
            .option("overwriteSchema", "true") \
            .saveAsTable("marts.sales.fact_sales")
    elif optimization_profile == "cost":
        fact_sales.write.format("delta") \
            .mode("overwrite") \
            .saveAsTable("marts.sales.fact_sales")
    else:  # usability (default)
        fact_sales.write.format("delta") \
            .mode("overwrite") \
            .partitionBy("order_date") \
            .saveAsTable("marts.sales.fact_sales")


def build_dim_customer(spark):
    """Build conformed customer dimension from EDW."""
    customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
    addresses = spark.table("edw.customer_address").filter(F.col("_is_current"))

    dim_customer = (
        customers.alias("c")
        .join(
            addresses.alias("a"),
            (F.col("c.customer_id") == F.col("a.customer_id"))
            & (F.col("a.address_type") == "billing"),
            "left",
        )
        .select(
            F.col("c.customer_id"),
            F.col("c.customer_name"),
            F.col("c.email"),
            F.col("c.segment"),
            F.col("a.city"),
            F.col("a.country"),
        )
    )

    dim_customer.write.format("delta") \
        .mode("overwrite") \
        .saveAsTable("marts.sales.dim_customer")
```

### dbt/SQL Implementation

```sql
-- models/marts/sales/mart_sales__fct_sales.sql
{{
  config(
    materialized='table',
    tags=['mart', 'sales']
  )
}}

SELECT
    ol.order_line_id,
    o.order_id,
    o.order_date,
    c.customer_id,
    c.segment AS customer_segment,
    p.product_id,
    p.category_id,
    ol.quantity,
    ol.line_total
FROM {{ ref('edw_transaction__order_line') }} ol
INNER JOIN {{ ref('edw_transaction__order_header') }} o
    ON ol.order_id = o.order_id
INNER JOIN {{ ref('edw_customer__customer') }} c
    ON o.customer_id = c.customer_id
    AND c._is_current = TRUE
INNER JOIN {{ ref('edw_product__product') }} p
    ON ol.product_id = p.product_id
    AND p._is_current = TRUE
```

```sql
-- models/marts/sales/mart_sales__dim_customer.sql
{{
  config(
    materialized='table',
    tags=['mart', 'sales']
  )
}}

SELECT
    c.customer_id,
    c.customer_name,
    c.email,
    c.segment,
    a.city,
    a.country
FROM {{ ref('edw_customer__customer') }} c
LEFT JOIN {{ ref('edw_customer__address') }} a
    ON c.customer_id = a.customer_id
    AND a.address_type = 'billing'
    AND a._is_current = TRUE
WHERE c._is_current = TRUE
```

## ETL Discipline

The Inmon approach follows strict ETL ordering:

1. **Extract**: Pull from sources into staging (see [build-ingestion-pipeline](../build-ingestion-pipeline/SKILL.md))
2. **Transform**: Normalize, conform, and historize into EDW
3. **Load**: Derive marts from EDW

Key rules:
- Marts never read from staging -- always from EDW
- EDW transformations enforce referential integrity
- Failed records route to dead letter queue (see [dead-letter-queue](../dead-letter-queue/SKILL.md))
- Dependencies flow strictly left-to-right: staging -> EDW -> marts

See [etl-patterns.md](references/etl-patterns.md) for extract/transform/load patterns.

## Anti-Patterns

### EDW Anti-Patterns

| Anti-Pattern | Problem | Solution |
|---|---|---|
| Denormalized EDW | Redundant data, update anomalies | Normalize to 3NF; denormalize only in marts |
| Source-coupled schema | EDW breaks when source schema changes | Map source to stable enterprise model |
| No temporal tracking | Lose history, fail audits | SCD Type 2 on all key entities |
| Per-mart dimensions | Conflicting definitions, duplicated logic | Conformed dimensions in EDW |
| Direct source-to-mart | Skip EDW, lose conformance | Always route through EDW |
| Over-normalized (4NF+) | Excessive joins, diminishing returns | Stop at 3NF unless specific need |

### Mart Anti-Patterns

| Anti-Pattern | Problem | Solution |
|---|---|---|
| 3NF in mart | Slow queries, analyst confusion | Use star or snowflake schema |
| Reading from staging | Bypasses conformance and history | Always derive from EDW |
| Mart-specific dimensions | Inconsistent across marts | Use conformed dimensions from EDW |
| No grain definition | Ambiguous row meaning | Document grain explicitly |
| Over-aggregation | Lose ability to drill down | Keep finest useful grain in fact table |

## Related Skills

- [scd-pattern](../scd-pattern/SKILL.md) - SCD Type 2 implementation for temporal tracking in the EDW
- [data-quality-checks](../data-quality-checks/SKILL.md) - Validation at each warehouse layer
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Error handling for ETL failures
- [data-platform-orchestration](../data-platform-orchestration/SKILL.md) - Scheduling ETL dependencies across layers
- [medallion-architecture](../medallion-architecture/SKILL.md) - Alternative bottom-up approach; hybrid coexistence guidance
- [build-ingestion-pipeline](../build-ingestion-pipeline/SKILL.md) - Staging / Bronze layer patterns

## References

- [Enterprise Modeling](references/enterprise-modeling.md) - Normalization rules, subject area decomposition, entity design patterns
- [Data Mart Patterns](references/data-mart-patterns.md) - Star/snowflake construction, fact types, mart derivation
- [Optimization Profiles](references/optimization-profiles.md) - Performance/Cost/Usability decision matrices with code
- [ETL Patterns](references/etl-patterns.md) - Extract, transform, load patterns for Inmon EDW
- [Migration from Medallion](references/migration-from-medallion.md) - Hybrid architecture and migration strategies
