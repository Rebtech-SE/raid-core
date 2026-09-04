# dbt SCD Implementations

Complete reference for implementing Slowly Changing Dimensions in dbt.

## dbt Snapshots (Recommended for Type 2)

### Basic Snapshot Setup

```sql
-- snapshots/customers_snapshot.sql
{% snapshot customers_snapshot %}

{{
    config(
      target_database='analytics',
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='check',
      check_cols=['customer_name', 'email', 'address', 'status']
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

### Snapshot Strategies

#### Check Strategy (Recommended)

Tracks changes to specified columns:

```sql
{{
    config(
      strategy='check',
      check_cols=['name', 'email', 'status']  -- Only track these
    )
}}
```

**Pros**: Control over which columns trigger versioning
**Cons**: Slower for wide tables (compares all check_cols)

#### Timestamp Strategy

Uses a timestamp column to detect changes:

```sql
{{
    config(
      strategy='timestamp',
      updated_at='modified_timestamp'
    )
}}
```

**Pros**: Fast (single column comparison)
**Cons**: Requires reliable `updated_at` column in source

### Snapshot Output Columns

dbt automatically creates:

| Column           | Description                               |
| ---------------- | ----------------------------------------- |
| `dbt_scd_id`     | Unique identifier for each version        |
| `dbt_updated_at` | When dbt detected the change              |
| `dbt_valid_from` | Start of validity period                  |
| `dbt_valid_to`   | End of validity period (NULL for current) |

### Running Snapshots

```bash
# Run all snapshots
dbt snapshot

# Run specific snapshot
dbt snapshot --select customers_snapshot

# Run snapshots for tag
dbt snapshot --select tag:customer_data
```

## Incremental Models for SCD Type 2

For more control than snapshots, use incremental models.

### Complete SCD Type 2 Incremental Model

```sql
-- models/marts/dim_customer.sql
{{
  config(
    materialized='incremental',
    unique_key='sk_customer',
    incremental_strategy='merge'
  )
}}

{%- set tracked_cols = ['customer_name', 'email', 'address', 'status'] -%}
{%- set hash_cols = tracked_cols | join("', '") -%}

WITH source_data AS (
    SELECT
        customer_id,
        customer_name,
        email,
        address,
        status,
        {{ dbt_utils.generate_surrogate_key(tracked_cols) }} AS row_hash,
        CURRENT_DATE AS load_date
    FROM {{ ref('stg_customers') }}
),

{% if is_incremental() %}

-- Existing current records
existing_current AS (
    SELECT *
    FROM {{ this }}
    WHERE is_current = TRUE
),

-- Classify source records
classified AS (
    SELECT
        s.customer_id,
        s.customer_name,
        s.email,
        s.address,
        s.status,
        s.row_hash,
        s.load_date,
        e.sk_customer AS existing_sk,
        e.row_hash AS existing_hash,
        CASE
            WHEN e.customer_id IS NULL THEN 'NEW'
            WHEN e.row_hash != s.row_hash THEN 'CHANGED'
            ELSE 'UNCHANGED'
        END AS record_status
    FROM source_data s
    LEFT JOIN existing_current e
        ON s.customer_id = e.customer_id
),

-- Records to expire (close out)
expired_records AS (
    SELECT
        existing_sk AS sk_customer,
        customer_id,
        customer_name,
        email,
        address,
        status,
        existing_hash AS row_hash,
        (SELECT MIN(valid_from) FROM {{ this }} WHERE sk_customer = classified.existing_sk) AS valid_from,
        load_date - INTERVAL '1 day' AS valid_to,
        FALSE AS is_current
    FROM classified
    WHERE record_status = 'CHANGED'
),

-- New version records
new_records AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'load_date']) }} AS sk_customer,
        customer_id,
        customer_name,
        email,
        address,
        status,
        row_hash,
        load_date AS valid_from,
        DATE '9999-12-31' AS valid_to,
        TRUE AS is_current
    FROM classified
    WHERE record_status IN ('NEW', 'CHANGED')
)

-- Union expired and new
SELECT * FROM expired_records
UNION ALL
SELECT * FROM new_records

{% else %}

-- Initial load
SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'load_date']) }} AS sk_customer,
    customer_id,
    customer_name,
    email,
    address,
    status,
    row_hash,
    load_date AS valid_from,
    DATE '9999-12-31' AS valid_to,
    TRUE AS is_current
FROM source_data

{% endif %}
```

### Schema Definition

```yaml
# models/marts/schema.yml
version: 2

models:
  - name: dim_customer
    description: Customer dimension with SCD Type 2 history
    columns:
      - name: sk_customer
        description: Surrogate key (unique per version)
        tests:
          - unique
          - not_null
      - name: customer_id
        description: Business key
        tests:
          - not_null
      - name: valid_from
        description: Start of validity period
        tests:
          - not_null
      - name: valid_to
        description: End of validity period
        tests:
          - not_null
      - name: is_current
        description: Flag for current record
        tests:
          - not_null
          - accepted_values:
              values: [true, false]
```

## SCD Type 1: Simple Merge

```sql
-- models/marts/dim_product.sql
{{
  config(
    materialized='incremental',
    unique_key='product_id',
    incremental_strategy='merge',
    merge_update_columns=['product_name', 'category', 'price', 'updated_at']
  )
}}

SELECT
    product_id,
    product_name,
    category,
    price,
    CURRENT_TIMESTAMP AS updated_at
FROM {{ ref('stg_products') }}

{% if is_incremental() %}
WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

## SCD Type 3: Previous Value Tracking

```sql
-- models/marts/dim_customer_type3.sql
{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    incremental_strategy='merge'
  )
}}

WITH source AS (
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
        WHEN t.current_status IS DISTINCT FROM s.current_status
        THEN t.current_status
        ELSE t.previous_status
    END AS previous_status,
    CASE
        WHEN t.current_status IS DISTINCT FROM s.current_status
        THEN CURRENT_DATE
        ELSE t.status_changed_date
    END AS status_changed_date,
    s.updated_at
FROM source s
LEFT JOIN {{ this }} t ON s.customer_id = t.customer_id

{% else %}

SELECT
    customer_id,
    current_status,
    CAST(NULL AS {{ dbt.type_string() }}) AS previous_status,
    CAST(NULL AS DATE) AS status_changed_date,
    updated_at
FROM source

{% endif %}
```

## Hybrid SCD: Type 2 + Type 1

Track some columns with history, others without:

```sql
-- snapshots/customer_status_snapshot.sql
-- Only track status changes (Type 2)
{% snapshot customer_status_snapshot %}
{{
    config(
      unique_key='customer_id',
      strategy='check',
      check_cols=['status']
    )
}}
SELECT customer_id, status FROM {{ source('raw', 'customers') }}
{% endsnapshot %}

-- models/marts/dim_customer_hybrid.sql
-- Combine snapshot with Type 1 attributes
SELECT
    snap.dbt_scd_id AS sk_customer,
    snap.customer_id,
    snap.status,
    snap.dbt_valid_from AS valid_from,
    snap.dbt_valid_to AS valid_to,
    snap.dbt_valid_to IS NULL AS is_current,
    -- Type 1 attributes (always current value)
    curr.customer_name,
    curr.email,
    curr.address,
    curr.phone
FROM {{ ref('customer_status_snapshot') }} snap
LEFT JOIN {{ ref('stg_customers') }} curr
    ON snap.customer_id = curr.customer_id
```

## dbt Macros for SCD

### Hash Generation Macro

```sql
-- macros/generate_row_hash.sql
{% macro generate_row_hash(columns) %}
    {{ dbt_utils.generate_surrogate_key(columns) }}
{% endmacro %}
```

### SCD Type 2 Merge Macro

```sql
-- macros/scd_type2_merge.sql
{% macro scd_type2_merge(source_relation, unique_key, tracked_columns) %}

{%- set hash_cols = tracked_columns | join("', '") -%}

WITH source_data AS (
    SELECT
        *,
        {{ dbt_utils.generate_surrogate_key(tracked_columns) }} AS _row_hash,
        CURRENT_DATE AS _load_date
    FROM {{ source_relation }}
),

{% if is_incremental() %}

current_records AS (
    SELECT * FROM {{ this }} WHERE is_current = TRUE
),

changes AS (
    SELECT
        s.*,
        c._row_hash AS _existing_hash,
        c.sk AS _existing_sk,
        CASE
            WHEN c.{{ unique_key }} IS NULL THEN 'INSERT'
            WHEN c._row_hash != s._row_hash THEN 'UPDATE'
            ELSE 'NO_CHANGE'
        END AS _action
    FROM source_data s
    LEFT JOIN current_records c ON s.{{ unique_key }} = c.{{ unique_key }}
),

to_expire AS (
    SELECT
        _existing_sk AS sk,
        {{ unique_key }},
        {% for col in tracked_columns %}
        {{ col }},
        {% endfor %}
        _existing_hash AS _row_hash,
        valid_from,
        _load_date - INTERVAL '1 day' AS valid_to,
        FALSE AS is_current
    FROM changes
    WHERE _action = 'UPDATE'
),

to_insert AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([unique_key, '_load_date']) }} AS sk,
        {{ unique_key }},
        {% for col in tracked_columns %}
        {{ col }},
        {% endfor %}
        _row_hash,
        _load_date AS valid_from,
        DATE '9999-12-31' AS valid_to,
        TRUE AS is_current
    FROM changes
    WHERE _action IN ('INSERT', 'UPDATE')
)

SELECT * FROM to_expire
UNION ALL
SELECT * FROM to_insert

{% else %}

SELECT
    {{ dbt_utils.generate_surrogate_key([unique_key, '_load_date']) }} AS sk,
    {{ unique_key }},
    {% for col in tracked_columns %}
    {{ col }},
    {% endfor %}
    _row_hash,
    _load_date AS valid_from,
    DATE '9999-12-31' AS valid_to,
    TRUE AS is_current
FROM source_data

{% endif %}

{% endmacro %}
```

Usage:

```sql
-- models/marts/dim_customer.sql
{{ config(materialized='incremental', unique_key='sk') }}

{{ scd_type2_merge(
    source_relation=ref('stg_customers'),
    unique_key='customer_id',
    tracked_columns=['customer_name', 'email', 'address', 'status']
) }}
```

## Project Structure

```
dbt_project/
  snapshots/
    customers_snapshot.sql
    products_snapshot.sql
  models/
    staging/
      stg_customers.sql
      stg_products.sql
    marts/
      dim_customer.sql        # SCD Type 2 from snapshot
      dim_product.sql         # SCD Type 1
      dim_customer_type3.sql  # SCD Type 3
      schema.yml
  macros/
    generate_row_hash.sql
    scd_type2_merge.sql
```

## Common Issues and Solutions

### Issue: Snapshot Not Detecting Changes

**Cause**: `check_cols` missing columns or wrong `updated_at` column.

**Solution**: Verify strategy and columns match source:

```sql
-- Debug: Check what columns changed
SELECT
    s.customer_id,
    s.customer_name AS source_name,
    t.customer_name AS snapshot_name,
    s.email AS source_email,
    t.email AS snapshot_email
FROM {{ source('raw', 'customers') }} s
LEFT JOIN {{ ref('customers_snapshot') }} t
    ON s.customer_id = t.customer_id
    AND t.dbt_valid_to IS NULL
WHERE s.customer_name != t.customer_name
   OR s.email != t.email
```

### Issue: Duplicate Current Records

**Cause**: Race condition or missing `unique_key` in incremental.

**Solution**: Add uniqueness test and verify merge logic:

```yaml
tests:
  - dbt_utils.unique_combination_of_columns:
      combination_of_columns:
        - customer_id
      where: "is_current = true"
```

### Issue: Hash Mismatch After Reload

**Cause**: Null handling or column ordering differs.

**Solution**: Use `COALESCE` and consistent column order:

```sql
{{ dbt_utils.generate_surrogate_key([
    'customer_id',
    "COALESCE(customer_name, '')",
    "COALESCE(email, '')"
]) }}
```
