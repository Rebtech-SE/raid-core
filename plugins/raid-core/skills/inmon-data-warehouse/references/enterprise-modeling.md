# Enterprise Modeling

Normalization rules, subject area decomposition, and entity design patterns for the Inmon enterprise data warehouse.

## Normalization Rules

### First Normal Form (1NF)

Every column contains atomic (indivisible) values. No repeating groups.

**Before (violates 1NF):**

| order_id | products |
|---|---|
| 1 | Widget, Gadget, Gizmo |

**After (1NF):**

| order_id | product |
|---|---|
| 1 | Widget |
| 1 | Gadget |
| 1 | Gizmo |

Or better -- decompose into a separate `order_line` table.

### Second Normal Form (2NF)

Satisfies 1NF, and every non-key column depends on the entire primary key (not just part of it).

**Before (violates 2NF):** composite key is (order_id, product_id)

| order_id | product_id | product_name | quantity |
|---|---|---|---|
| 1 | P1 | Widget | 3 |

`product_name` depends only on `product_id`, not the full key.

**After (2NF):**

`order_line`: order_id, product_id, quantity
`product`: product_id, product_name

### Third Normal Form (3NF)

Satisfies 2NF, and no non-key column depends on another non-key column (no transitive dependencies).

**Before (violates 3NF):**

| customer_id | customer_name | city | country |
|---|---|---|---|
| C1 | Acme Corp | Stockholm | Sweden |

`country` depends on `city`, not directly on `customer_id`.

**After (3NF):**

`customer`: customer_id, customer_name, address_id
`address`: address_id, city, country_code
`country`: country_code, country_name

### When to Stop

Stop at 3NF for the EDW. Higher normal forms (BCNF, 4NF, 5NF) add complexity with diminishing returns. If a specific anomaly arises, normalize that entity further on a case-by-case basis.

## Subject Area Decomposition

### Methodology

1. **Identify business domains**: Interview stakeholders, review org chart, catalog source systems
2. **Group entities**: Assign each entity to exactly one subject area based on ownership and cohesion
3. **Define boundaries**: Subject areas can reference other areas via foreign keys, but each entity has a single home
4. **Assign owners**: Each subject area has a business owner responsible for definitions

### Standard Subject Areas

#### Customer

Entities that describe who the business interacts with.

```
customer
  |-- contact (1:N)
  |-- address (1:N)
  |-- segment (N:1)
  |-- customer_account (1:N)
```

#### Product

Entities that describe what the business sells or delivers.

```
product
  |-- product_category (N:1)
  |-- supplier (N:M via product_supplier)
  |-- pricing (1:N, temporal)
```

#### Transaction

Entities that describe business events.

```
order_header
  |-- order_line (1:N)
  |-- invoice (1:1 or 1:N)
  |-- payment (1:N)
  |-- shipment (1:N)
```

#### Organization

Entities that describe the business itself.

```
department
  |-- employee (1:N)
  |-- role (N:M via employee_role)
  |-- hierarchy (self-referencing)
```

#### Geography

Entities that describe locations.

```
country
  |-- region (1:N)
  |-- city (N:1 to region)
  |-- location (specific addresses, facilities)
```

#### Time

Shared calendar and fiscal period entities.

```
calendar_date (one row per date)
  |-- fiscal_period (N:1)
  |-- holiday (1:N per country)
```

## Entity Design Patterns

### Hub Entities

Hub entities are the core business objects -- they have a business key and descriptive attributes. They are the central nodes in the subject area graph.

Examples: `customer`, `product`, `order_header`, `employee`

Rules:
- Single business key (or composite business key defined once)
- All descriptive attributes belong here
- SCD Type 2 for temporal tracking
- No redundant data from other entities

```python
# PySpark: Hub entity DDL
from pyspark.sql.types import StructType, StructField, StringType, DateType, BooleanType, TimestampType

customer_schema = StructType([
    StructField("customer_id", StringType(), False),        # Business key
    StructField("customer_name", StringType(), True),
    StructField("email", StringType(), True),
    StructField("segment", StringType(), True),
    StructField("_valid_from", DateType(), False),       # SCD2
    StructField("_valid_to", DateType(), False),          # SCD2
    StructField("_is_current", BooleanType(), False),        # SCD2
    StructField("_hash", StringType(), False),               # Change detection
    StructField("_edw_load_timestamp", TimestampType(), False),
    StructField("_edw_batch_id", StringType(), False),
    StructField("_source_system", StringType(), False),
])
```

```sql
-- dbt: Hub entity schema definition
-- models/edw/customer/edw_customer__customer.yml
version: 2

models:
  - name: edw_customer__customer
    description: "Enterprise customer entity (SCD Type 2)"
    columns:
      - name: customer_id
        description: "Business key"
        tests:
          - not_null
          - unique:
              where: "_is_current = TRUE"
      - name: _valid_from
        tests: [not_null]
      - name: _valid_to
        tests: [not_null]
      - name: _is_current
        tests: [not_null]
```

### Link / Bridge Entities

Link entities resolve many-to-many relationships between hub entities.

Examples: `product_supplier` (product N:M supplier), `employee_role` (employee N:M role)

Rules:
- Composite key from the two (or more) hub business keys
- May include relationship attributes (e.g., `is_primary_supplier`)
- SCD Type 2 if the relationship has temporal significance

```python
# PySpark: Link entity
product_supplier_schema = StructType([
    StructField("product_id", StringType(), False),      # FK to product
    StructField("supplier_id", StringType(), False),     # FK to supplier
    StructField("is_primary", BooleanType(), True),
    StructField("_valid_from", DateType(), False),
    StructField("_valid_to", DateType(), False),
    StructField("_is_current", BooleanType(), False),
    StructField("_edw_load_timestamp", TimestampType(), False),
])
```

```sql
-- dbt: Link entity
-- models/edw/product/edw_product__product_supplier.sql
{{ config(materialized='incremental', unique_key=['product_id', 'supplier_id', '_valid_from']) }}

SELECT
    product_id,
    supplier_id,
    is_primary,
    MD5(CONCAT_WS('||', is_primary::TEXT)) AS _hash,
    CURRENT_DATE AS _valid_from,
    DATE '9999-12-31' AS _valid_to,
    TRUE AS _is_current,
    CURRENT_TIMESTAMP() AS _edw_load_timestamp
FROM {{ ref('stg_erp__product_suppliers') }}
```

### Reference Entities

Reference entities hold stable lookup values that rarely change. They typically do not need SCD Type 2.

Examples: `country`, `currency`, `product_category`, `status_code`

Rules:
- Simple structure: code + description
- SCD Type 1 (overwrite) is usually sufficient
- Loaded once and updated infrequently
- Shared across subject areas via FK

```python
# PySpark: Reference entity (no SCD2)
category_schema = StructType([
    StructField("category_id", StringType(), False),
    StructField("category_name", StringType(), True),
    StructField("_edw_load_timestamp", TimestampType(), False),
    StructField("_source_system", StringType(), False),
])
```

```sql
-- dbt: Reference entity
-- models/edw/product/edw_product__category.sql
{{ config(materialized='incremental', unique_key='category_id') }}

SELECT
    category_id,
    category_name,
    CURRENT_TIMESTAMP() AS _edw_load_timestamp,
    '{{ var("source_system", "unknown") }}' AS _source_system
FROM {{ ref('stg_erp__product_categories') }}
```

## Conformed Dimension Design

### Principles

Conformed dimensions ensure that all data marts use the same definition of shared entities. A `dim_customer` in the Sales mart and the Marketing mart is the same table with the same attributes and business rules.

### Design Process

1. **Identify shared entities**: Which dimensions are used by more than one mart?
2. **Define in EDW**: Build the dimension entity in the EDW with full 3NF
3. **Derive for marts**: Create a single `dim_*` table that all marts reference
4. **Govern centrally**: Changes to dimension definitions go through the EDW, not individual marts

### Example: Conformed Customer Dimension

```python
# Built once in the EDW, consumed by all marts
def build_conformed_dim_customer(spark):
    """Build the conformed customer dimension from EDW entities."""
    customers = spark.table("edw.customer_customer").filter(F.col("_is_current"))
    addresses = spark.table("edw.customer_address").filter(
        (F.col("_is_current")) & (F.col("address_type") == "billing")
    )
    segments = spark.table("edw.customer_segment")

    return (
        customers.alias("c")
        .join(addresses.alias("a"), "customer_id", "left")
        .join(segments.alias("s"), "segment", "left")
        .select(
            F.col("c.customer_id"),
            F.col("c.customer_name"),
            F.col("c.email"),
            F.col("c.segment"),
            F.col("s.segment_description"),
            F.col("a.city"),
            F.col("a.postal_code"),
            F.col("a.country"),
        )
    )

# Write to a shared location -- all marts reference this
dim_customer = build_conformed_dim_customer(spark)
dim_customer.write.format("delta") \
    .mode("overwrite") \
    .saveAsTable("marts.shared.dim_customer")
```

```sql
-- dbt: Conformed dimension shared across marts
-- models/marts/shared/dim_customer.sql
{{ config(materialized='table', tags=['conformed', 'dimension']) }}

SELECT
    c.customer_id,
    c.customer_name,
    c.email,
    c.segment,
    s.segment_description,
    a.city,
    a.postal_code,
    a.country
FROM {{ ref('edw_customer__customer') }} c
LEFT JOIN {{ ref('edw_customer__address') }} a
    ON c.customer_id = a.customer_id
    AND a.address_type = 'billing'
    AND a._is_current = TRUE
LEFT JOIN {{ ref('edw_customer__segment') }} s
    ON c.segment = s.segment
WHERE c._is_current = TRUE
```

## Subject Area Templates

### Customer Subject Area

```sql
-- models/edw/customer/edw_customer__customer.sql
-- See SKILL.md for full SCD2 implementation

-- models/edw/customer/edw_customer__address.sql
{{ config(materialized='incremental', unique_key='_surrogate_key') }}
-- SCD2 on address changes (same pattern as customer)

-- models/edw/customer/edw_customer__contact.sql
{{ config(materialized='incremental', unique_key='contact_id') }}
-- SCD1: contacts are overwritten (Type 1)

-- models/edw/customer/edw_customer__segment.sql
{{ config(materialized='table') }}
-- Reference entity: segment lookup (full refresh)
```

### Product Subject Area

```sql
-- models/edw/product/edw_product__product.sql
-- SCD2 on product attributes (name, price, category)

-- models/edw/product/edw_product__category.sql
-- Reference entity: category lookup

-- models/edw/product/edw_product__supplier.sql
-- SCD2 on supplier attributes

-- models/edw/product/edw_product__product_supplier.sql
-- Link entity: product-supplier relationship (SCD2)

-- models/edw/product/edw_product__pricing.sql
-- Temporal entity: price history by product (SCD2)
```

### Transaction Subject Area

```sql
-- models/edw/transaction/edw_transaction__order_header.sql
{{ config(materialized='incremental', unique_key='order_id') }}
-- Transaction entities are typically insert-only (no SCD2)
-- New orders are appended; status changes tracked via order_status_history

SELECT
    order_id,
    customer_id,
    order_date,
    status,
    CURRENT_TIMESTAMP() AS _edw_load_timestamp,
    '{{ var("batch_id", "manual") }}' AS _edw_batch_id,
    '{{ var("source_system", "unknown") }}' AS _source_system
FROM {{ ref('stg_erp__orders') }}

{% if is_incremental() %}
WHERE order_date > (SELECT MAX(order_date) FROM {{ this }})
{% endif %}


-- models/edw/transaction/edw_transaction__order_line.sql
{{ config(materialized='incremental', unique_key='order_line_id') }}

SELECT
    order_line_id,
    order_id,
    product_id,
    quantity,
    line_total,
    CURRENT_TIMESTAMP() AS _edw_load_timestamp
FROM {{ ref('stg_erp__order_lines') }}

{% if is_incremental() %}
WHERE order_id IN (
    SELECT order_id FROM {{ ref('stg_erp__orders') }}
    WHERE order_date > (SELECT MAX(order_date) FROM {{ ref('edw_transaction__order_header') }})
)
{% endif %}
```
