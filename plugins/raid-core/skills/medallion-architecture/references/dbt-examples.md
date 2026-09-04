# dbt Medallion Architecture Examples

Complete dbt project structure for implementing medallion architecture.

## Project Structure

```
dbt_project/
  dbt_project.yml
  packages.yml

  models/
    staging/                    # Bronze -> Silver (first step)
      _sources.yml             # Source definitions
      _staging.yml             # Staging model docs
      stg_salesforce__accounts.sql
      stg_salesforce__opportunities.sql
      stg_erp__orders.sql
      stg_erp__products.sql

    intermediate/              # Silver (complex transformations)
      _int.yml
      int_accounts_deduped.sql
      int_orders_enriched.sql
      int_customers_unified.sql

    marts/                     # Gold
      core/                    # Core business entities
        _core.yml
        dim_customer.sql
        dim_product.sql
        dim_date.sql
        fct_orders.sql
        fct_sales.sql

      marketing/               # Marketing-specific
        _marketing.yml
        fct_campaigns.sql
        dim_campaign.sql

      finance/                 # Finance-specific
        _finance.yml
        fct_revenue_daily.sql
        fct_ar_aging.sql

  snapshots/                   # SCD Type 2
    customer_snapshot.sql
    product_snapshot.sql

  macros/
    generate_schema_name.sql
    clean_string.sql

  tests/
    generic/
      test_no_orphans.sql
```

## Configuration Files

### dbt_project.yml

```yaml
name: 'medallion_project'
version: '1.0.0'
config-version: 2

profile: 'medallion'

model-paths: ["models"]
snapshot-paths: ["snapshots"]
macro-paths: ["macros"]
test-paths: ["tests"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

vars:
  # Default date range
  start_date: '2020-01-01'
  end_date: '2030-12-31'

models:
  medallion_project:
    # Staging (Bronze -> Silver): views because these are thin transformations
    # (renames, casts, filters) -- data already exists in source tables.
    # See SKILL.md "Materialization Strategy" for the full decision framework.
    staging:
      +materialized: view
      +schema: staging
      +tags: ['staging', 'bronze_to_silver']

    # Intermediate (Silver): tables because these involve heavy joins,
    # deduplication, SCD, and incremental merge logic.
    intermediate:
      +materialized: table
      +schema: silver
      +tags: ['intermediate', 'silver']

    # Marts (Gold): tables for predictable BI query performance.
    # Individual models may override to 'incremental' for large fact tables.
    marts:
      +materialized: table
      +schema: gold
      +tags: ['marts', 'gold']

      core:
        +tags: ['core']

      marketing:
        +tags: ['marketing']

      finance:
        +tags: ['finance']

snapshots:
  medallion_project:
    +target_schema: snapshots
    +strategy: check
```

### packages.yml

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.1.1

  - package: calogica/dbt_expectations
    version: 0.10.0

  - package: dbt-labs/codegen
    version: 0.12.1
```

## Source Definitions

### models/staging/\_sources.yml

```yaml
version: 2

sources:
  - name: raw_salesforce
    description: Raw Salesforce data
    database: "{{ env_var('RAW_DATABASE', 'raw') }}"
    schema: salesforce

    freshness:
      warn_after: {count: 12, period: hour}
      error_after: {count: 24, period: hour}

    loaded_at_field: _ingestion_timestamp

    tables:
      - name: accounts
        description: Salesforce Account objects
        columns:
          - name: id
            description: Salesforce Account ID
            tests:
              - not_null
          - name: _ingestion_timestamp
            description: When record was ingested

      - name: opportunities
        description: Salesforce Opportunity objects
        columns:
          - name: id
            tests:
              - not_null

  - name: raw_erp
    description: Raw ERP data
    database: "{{ env_var('RAW_DATABASE', 'raw') }}"
    schema: erp

    tables:
      - name: orders
        description: ERP Order records

      - name: products
        description: ERP Product master
```

## Staging Models (Bronze -> Silver)

### stg_salesforce\_\_accounts.sql

```sql
-- models/staging/stg_salesforce__accounts.sql
{{
  config(
    materialized='view',
    tags=['staging', 'salesforce']
  )
}}

WITH source AS (
    SELECT * FROM {{ source('raw_salesforce', 'accounts') }}
),

-- Deduplicate within the raw data
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY _ingestion_timestamp DESC
        ) AS _rn
    FROM source
),

renamed AS (
    SELECT
        -- Keys
        id AS account_id,

        -- Attributes (cleaned)
        TRIM(name) AS account_name,
        LOWER(TRIM(type)) AS account_type,
        UPPER(TRIM(industry)) AS industry,
        CAST(annual_revenue AS DECIMAL(18,2)) AS annual_revenue,
        CAST(number_of_employees AS INT) AS employee_count,

        -- Dates
        CAST(created_date AS DATE) AS created_date,
        CAST(last_modified_date AS TIMESTAMP) AS updated_at,

        -- Standardized address
        TRIM(billing_street) AS billing_street,
        TRIM(billing_city) AS billing_city,
        UPPER(TRIM(billing_state)) AS billing_state,
        TRIM(billing_postal_code) AS billing_postal_code,
        UPPER(TRIM(billing_country)) AS billing_country,

        -- Audit
        _ingestion_timestamp,
        _source_system,
        _batch_id

    FROM deduplicated
    WHERE _rn = 1
)

SELECT * FROM renamed
```

### stg_erp\_\_orders.sql

```sql
-- models/staging/stg_erp__orders.sql
{{
  config(
    materialized='view',
    tags=['staging', 'erp']
  )
}}

WITH source AS (
    SELECT * FROM {{ source('raw_erp', 'orders') }}
),

renamed AS (
    SELECT
        -- Keys
        order_id,
        customer_id,
        product_id,

        -- Measures
        CAST(quantity AS INT) AS quantity,
        CAST(unit_price AS DECIMAL(18,2)) AS unit_price,
        CAST(discount_percent AS DECIMAL(5,2)) AS discount_percent,

        -- Calculated
        CAST(quantity * unit_price AS DECIMAL(18,2)) AS gross_amount,
        CAST(quantity * unit_price * (1 - COALESCE(discount_percent, 0) / 100) AS DECIMAL(18,2)) AS net_amount,

        -- Dates
        CAST(order_date AS DATE) AS order_date,
        CAST(ship_date AS DATE) AS ship_date,

        -- Status
        UPPER(TRIM(status)) AS status,

        -- Audit
        _ingestion_timestamp

    FROM source
)

SELECT * FROM renamed
```

## Intermediate Models (Silver)

### int_customers_unified.sql

```sql
-- models/intermediate/int_customers_unified.sql
{{
  config(
    materialized='incremental',
    unique_key='customer_id',
    incremental_strategy='merge',
    tags=['intermediate', 'customers']
  )
}}

WITH salesforce_customers AS (
    SELECT
        account_id AS customer_id,
        account_name AS customer_name,
        billing_street AS address_street,
        billing_city AS address_city,
        billing_state AS address_state,
        billing_postal_code AS address_postal_code,
        billing_country AS address_country,
        annual_revenue,
        employee_count,
        industry,
        'salesforce' AS source_system,
        _ingestion_timestamp
    FROM {{ ref('stg_salesforce__accounts') }}
    WHERE account_type = 'customer'
),

erp_customers AS (
    SELECT
        customer_id,
        customer_name,
        address_line_1 AS address_street,
        city AS address_city,
        state AS address_state,
        postal_code AS address_postal_code,
        country AS address_country,
        NULL AS annual_revenue,
        NULL AS employee_count,
        NULL AS industry,
        'erp' AS source_system,
        _ingestion_timestamp
    FROM {{ ref('stg_erp__customers') }}
),

-- Union and deduplicate (prefer Salesforce)
unified AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY
                CASE source_system WHEN 'salesforce' THEN 1 ELSE 2 END,
                _ingestion_timestamp DESC
        ) AS _rn
    FROM (
        SELECT * FROM salesforce_customers
        UNION ALL
        SELECT * FROM erp_customers
    )
)

SELECT
    customer_id,
    customer_name,
    address_street,
    address_city,
    address_state,
    address_postal_code,
    address_country,
    annual_revenue,
    employee_count,
    industry,
    source_system,
    CURRENT_TIMESTAMP() AS _load_timestamp
FROM unified
WHERE _rn = 1

{% if is_incremental() %}
AND _ingestion_timestamp > (SELECT MAX(_load_timestamp) FROM {{ this }})
{% endif %}
```

## Snapshot Models (SCD Type 2)

### customer_snapshot.sql

```sql
-- snapshots/customer_snapshot.sql
{% snapshot customer_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='check',
      check_cols=[
          'customer_name',
          'address_city',
          'address_state',
          'address_country',
          'industry'
      ],
      invalidate_hard_deletes=True
    )
}}

SELECT
    customer_id,
    customer_name,
    address_street,
    address_city,
    address_state,
    address_postal_code,
    address_country,
    annual_revenue,
    employee_count,
    industry
FROM {{ ref('int_customers_unified') }}

{% endsnapshot %}
```

## Mart Models (Gold)

### dim_customer.sql

```sql
-- models/marts/core/dim_customer.sql
{{
  config(
    materialized='table',
    tags=['core', 'dimension']
  )
}}

WITH snapshot_data AS (
    SELECT * FROM {{ ref('customer_snapshot') }}
),

enriched AS (
    SELECT
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'dbt_valid_from']) }} AS sk_customer,

        -- Business key
        customer_id,

        -- Attributes
        customer_name,
        address_street,
        address_city,
        address_state,
        address_postal_code,
        address_country,

        -- Derived
        CASE
            WHEN annual_revenue >= 1000000 THEN 'Enterprise'
            WHEN annual_revenue >= 100000 THEN 'Mid-Market'
            ELSE 'SMB'
        END AS customer_segment,

        annual_revenue,
        employee_count,
        industry,

        -- SCD columns
        dbt_valid_from AS valid_from,
        dbt_valid_to AS valid_to,
        dbt_valid_to IS NULL AS is_current

    FROM snapshot_data
)

SELECT * FROM enriched
```

### dim_date.sql

```sql
-- models/marts/core/dim_date.sql
{{
  config(
    materialized='table',
    tags=['core', 'dimension', 'reference']
  )
}}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('start_date') ~ "' as date)",
        end_date="cast('" ~ var('end_date') ~ "' as date)"
    ) }}
)

SELECT
    CAST(DATE_FORMAT(date_day, 'yyyyMMdd') AS INT) AS sk_date,
    CAST(date_day AS DATE) AS date_key,

    -- Standard date parts
    YEAR(date_day) AS year,
    QUARTER(date_day) AS quarter,
    MONTH(date_day) AS month,
    WEEKOFYEAR(date_day) AS week_of_year,
    DAYOFMONTH(date_day) AS day_of_month,
    DAYOFWEEK(date_day) AS day_of_week,
    DAYOFYEAR(date_day) AS day_of_year,

    -- Names
    DATE_FORMAT(date_day, 'MMMM') AS month_name,
    DATE_FORMAT(date_day, 'MMM') AS month_short_name,
    DATE_FORMAT(date_day, 'EEEE') AS day_name,
    DATE_FORMAT(date_day, 'EEE') AS day_short_name,

    -- Fiscal year (July start)
    CASE
        WHEN MONTH(date_day) >= 7 THEN YEAR(date_day) + 1
        ELSE YEAR(date_day)
    END AS fiscal_year,

    -- Fiscal quarter
    CASE
        WHEN MONTH(date_day) BETWEEN 7 AND 9 THEN 1
        WHEN MONTH(date_day) BETWEEN 10 AND 12 THEN 2
        WHEN MONTH(date_day) BETWEEN 1 AND 3 THEN 3
        ELSE 4
    END AS fiscal_quarter,

    -- Flags
    DAYOFWEEK(date_day) IN (1, 7) AS is_weekend,
    FALSE AS is_holiday,
    date_day = CURRENT_DATE() AS is_today,
    date_day < CURRENT_DATE() AS is_past,

    -- Period identifiers
    DATE_FORMAT(date_day, 'yyyy-MM') AS year_month,
    DATE_FORMAT(date_day, 'yyyy') || '-Q' || QUARTER(date_day) AS year_quarter

FROM date_spine
```

### fct_orders.sql

```sql
-- models/marts/core/fct_orders.sql
{{
  config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge',
    tags=['core', 'fact']
  )
}}

WITH orders AS (
    SELECT * FROM {{ ref('stg_erp__orders') }}
    {% if is_incremental() %}
    WHERE _ingestion_timestamp > (SELECT MAX(_load_timestamp) FROM {{ this }})
    {% endif %}
),

with_dimensions AS (
    SELECT
        o.order_id,

        -- Dimension keys
        c.sk_customer,
        p.sk_product,
        d.sk_date,

        -- Degenerate dimensions
        o.order_id AS order_number,

        -- Measures
        o.quantity,
        o.unit_price,
        o.discount_percent,
        o.gross_amount,
        o.net_amount,

        -- Dates (for partitioning)
        o.order_date,
        o.ship_date,

        -- Status
        o.status,

        -- Audit
        CURRENT_TIMESTAMP() AS _load_timestamp

    FROM orders o
    LEFT JOIN {{ ref('dim_customer') }} c
        ON o.customer_id = c.customer_id
        AND c.is_current = TRUE
    LEFT JOIN {{ ref('dim_product') }} p
        ON o.product_id = p.product_id
        AND p.is_current = TRUE
    LEFT JOIN {{ ref('dim_date') }} d
        ON o.order_date = d.date_key
)

SELECT * FROM with_dimensions
```

## Schema Tests

### \_core.yml

```yaml
# models/marts/core/_core.yml
version: 2

models:
  - name: dim_customer
    description: Customer dimension with SCD Type 2 history
    columns:
      - name: sk_customer
        description: Surrogate key
        tests:
          - unique
          - not_null

      - name: customer_id
        description: Business key
        tests:
          - not_null

      - name: is_current
        description: Current record flag
        tests:
          - not_null

    tests:
      # Only one current per business key
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - customer_id
          where: "is_current = true"

  - name: fct_orders
    description: Order fact table
    columns:
      - name: order_id
        tests:
          - unique
          - not_null

      - name: sk_customer
        tests:
          - relationships:
              to: ref('dim_customer')
              field: sk_customer

      - name: sk_product
        tests:
          - relationships:
              to: ref('dim_product')
              field: sk_product

      - name: sk_date
        tests:
          - relationships:
              to: ref('dim_date')
              field: sk_date
```

## Custom Macros

### generate_schema_name.sql

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(custom_schema_name, node) %}
    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name }}
    {%- endif -%}
{% endmacro %}
```

### clean_string.sql

```sql
-- macros/clean_string.sql
{% macro clean_string(column_name) %}
    TRIM(REGEXP_REPLACE({{ column_name }}, '\\s+', ' '))
{% endmacro %}

{% macro standardize_email(column_name) %}
    LOWER(TRIM({{ column_name }}))
{% endmacro %}
```

## Running the Project

```bash
# Install packages
dbt deps

# Run staging models
dbt run --select staging

# Run snapshots
dbt snapshot

# Run intermediate models
dbt run --select intermediate

# Run marts
dbt run --select marts

# Run everything
dbt run

# Run with tests
dbt build

# Run specific mart
dbt run --select +fct_orders+
```
