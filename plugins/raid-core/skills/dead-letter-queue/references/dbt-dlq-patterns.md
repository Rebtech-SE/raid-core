# dbt Dead Letter Queue Patterns

Patterns for implementing error handling and DLQ in dbt.

## DLQ Model Structure

### Error Capture Model

```sql
-- models/dlq/stg_dlq_errors.sql
{{
  config(
    materialized='incremental',
    unique_key='error_id'
  )
}}

WITH validation_errors AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['source_table', 'record_id', 'error_timestamp']) }} AS error_id,
        source_table,
        record_id,
        original_record,
        error_type,
        error_message,
        error_timestamp,
        batch_id,
        0 AS retry_count,
        'pending' AS status,
        NULL AS resolved_timestamp,
        NULL AS resolved_by
    FROM {{ ref('validation_failures') }}
)

SELECT * FROM validation_errors

{% if is_incremental() %}
WHERE error_timestamp > (SELECT MAX(error_timestamp) FROM {{ this }})
{% endif %}
```

### Validation with Error Routing

```sql
-- models/intermediate/int_orders_validated.sql
{{
  config(
    materialized='table'
  )
}}

WITH source_data AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

validated AS (
    SELECT
        *,
        -- Validation flags
        order_id IS NOT NULL AS is_valid_id,
        amount >= 0 AS is_valid_amount,
        order_date <= CURRENT_DATE() AS is_valid_date,
        customer_id IN (SELECT customer_id FROM {{ ref('dim_customer') }}) AS is_valid_customer,

        -- Overall validity
        (order_id IS NOT NULL
         AND amount >= 0
         AND order_date <= CURRENT_DATE()
         AND customer_id IN (SELECT customer_id FROM {{ ref('dim_customer') }})) AS is_valid
    FROM source_data
)

SELECT
    order_id,
    customer_id,
    product_id,
    amount,
    order_date,
    status
FROM validated
WHERE is_valid = TRUE
```

### Error Extraction Model

```sql
-- models/dlq/validation_failures.sql
{{
  config(
    materialized='incremental',
    unique_key='error_id'
  )
}}

WITH source_data AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

validated AS (
    SELECT
        *,
        order_id IS NOT NULL AS is_valid_id,
        amount >= 0 AS is_valid_amount,
        order_date <= CURRENT_DATE() AS is_valid_date,
        customer_id IN (SELECT customer_id FROM {{ ref('dim_customer') }} WHERE is_current) AS is_valid_customer
    FROM source_data
),

failures AS (
    SELECT
        'stg_orders' AS source_table,
        COALESCE(CAST(order_id AS VARCHAR), 'NULL') AS record_id,
        TO_JSON(STRUCT(*)) AS original_record,
        CASE
            WHEN NOT is_valid_id THEN 'NULL_ERR'
            WHEN NOT is_valid_amount THEN 'RANGE_ERR'
            WHEN NOT is_valid_date THEN 'RANGE_ERR'
            WHEN NOT is_valid_customer THEN 'FK_ERR'
            ELSE 'UNKNOWN'
        END AS error_type,
        CASE
            WHEN NOT is_valid_id THEN 'order_id is NULL'
            WHEN NOT is_valid_amount THEN 'amount is negative: ' || CAST(amount AS VARCHAR)
            WHEN NOT is_valid_date THEN 'order_date is in future: ' || CAST(order_date AS VARCHAR)
            WHEN NOT is_valid_customer THEN 'customer_id not found: ' || CAST(customer_id AS VARCHAR)
            ELSE 'Unknown validation failure'
        END AS error_message,
        CURRENT_TIMESTAMP() AS error_timestamp,
        '{{ invocation_id }}' AS batch_id
    FROM validated
    WHERE NOT (is_valid_id AND is_valid_amount AND is_valid_date AND is_valid_customer)
)

SELECT * FROM failures

{% if is_incremental() %}
WHERE error_timestamp > (SELECT MAX(error_timestamp) FROM {{ this }})
{% endif %}
```

## DLQ Macro Library

### Validation Macro

```sql
-- macros/validate_and_route.sql
{% macro validate_and_route(source_ref, validations, valid_model, dlq_model) %}
{#
    Validate records and route failures to DLQ.

    Args:
        source_ref: Reference to source model
        validations: List of validation dicts with 'name', 'condition', 'error_type', 'error_message'
        valid_model: Name of model for valid records
        dlq_model: Name of DLQ model for failures
#}

WITH source_data AS (
    SELECT * FROM {{ source_ref }}
),

with_validations AS (
    SELECT
        *,
        {% for v in validations %}
        {{ v.condition }} AS _valid_{{ v.name }}{% if not loop.last %},{% endif %}
        {% endfor %}
    FROM source_data
),

-- Determine overall validity and first failing rule
classified AS (
    SELECT
        *,
        {% for v in validations %}
        _valid_{{ v.name }}{% if not loop.last %} AND {% endif %}
        {% endfor %} AS _is_valid,

        CASE
            {% for v in validations %}
            WHEN NOT _valid_{{ v.name }} THEN '{{ v.error_type }}'
            {% endfor %}
            ELSE NULL
        END AS _error_type,

        CASE
            {% for v in validations %}
            WHEN NOT _valid_{{ v.name }} THEN '{{ v.error_message }}'
            {% endfor %}
            ELSE NULL
        END AS _error_message
    FROM with_validations
)

-- This CTE is used by both valid and DLQ models
SELECT * FROM classified

{% endmacro %}
```

### Usage of Validation Macro

```sql
-- models/intermediate/int_orders_classified.sql
{{
  config(materialized='ephemeral')
}}

{% set validations = [
    {'name': 'not_null_id', 'condition': 'order_id IS NOT NULL', 'error_type': 'NULL_ERR', 'error_message': 'order_id is NULL'},
    {'name': 'positive_amount', 'condition': 'amount >= 0', 'error_type': 'RANGE_ERR', 'error_message': 'amount is negative'},
    {'name': 'valid_date', 'condition': 'order_date <= CURRENT_DATE()', 'error_type': 'RANGE_ERR', 'error_message': 'order_date is in future'}
] %}

{{ validate_and_route(ref('stg_orders'), validations, 'int_orders_valid', 'dlq_orders') }}
```

```sql
-- models/intermediate/int_orders_valid.sql
SELECT
    order_id,
    customer_id,
    product_id,
    amount,
    order_date,
    status
FROM {{ ref('int_orders_classified') }}
WHERE _is_valid = TRUE
```

```sql
-- models/dlq/dlq_orders.sql
{{
  config(
    materialized='incremental',
    unique_key='error_id'
  )
}}

SELECT
    {{ dbt_utils.generate_surrogate_key(['order_id', '_error_type', 'CURRENT_TIMESTAMP()']) }} AS error_id,
    'stg_orders' AS source_table,
    CAST(order_id AS VARCHAR) AS record_id,
    TO_JSON(STRUCT(order_id, customer_id, product_id, amount, order_date, status)) AS original_record,
    _error_type AS error_type,
    _error_message AS error_message,
    CURRENT_TIMESTAMP() AS error_timestamp,
    '{{ invocation_id }}' AS batch_id,
    0 AS retry_count,
    'pending' AS status
FROM {{ ref('int_orders_classified') }}
WHERE _is_valid = FALSE

{% if is_incremental() %}
AND CURRENT_TIMESTAMP() > (SELECT MAX(error_timestamp) FROM {{ this }})
{% endif %}
```

## DLQ Monitoring Models

### Error Summary

```sql
-- models/dlq/dlq_summary.sql
{{
  config(materialized='table')
}}

SELECT
    source_table,
    error_type,
    status,
    COUNT(*) AS error_count,
    MIN(error_timestamp) AS oldest_error,
    MAX(error_timestamp) AS newest_error,
    AVG(retry_count) AS avg_retries,
    CURRENT_TIMESTAMP() AS report_timestamp
FROM {{ ref('stg_dlq_errors') }}
GROUP BY source_table, error_type, status
```

### Pending Errors Alert

```sql
-- models/dlq/dlq_alerts.sql
{{
  config(materialized='table')
}}

WITH pending_summary AS (
    SELECT
        source_table,
        error_type,
        COUNT(*) AS pending_count,
        MIN(error_timestamp) AS oldest_pending,
        DATEDIFF('hour', MIN(error_timestamp), CURRENT_TIMESTAMP()) AS hours_pending
    FROM {{ ref('stg_dlq_errors') }}
    WHERE status = 'pending'
    GROUP BY source_table, error_type
)

SELECT
    source_table,
    error_type,
    pending_count,
    oldest_pending,
    hours_pending,
    CASE
        WHEN error_type IN ('AUTH_ERR', 'SCHEMA_ERR') THEN 'critical'
        WHEN hours_pending > 24 THEN 'high'
        WHEN pending_count > 100 THEN 'high'
        WHEN hours_pending > 6 THEN 'medium'
        ELSE 'low'
    END AS alert_severity
FROM pending_summary
WHERE pending_count > 0
```

## DLQ Recovery Pattern

### Retry Model

```sql
-- models/dlq/dlq_retry_candidates.sql
{{
  config(materialized='view')
}}

SELECT
    error_id,
    source_table,
    record_id,
    original_record,
    error_type,
    retry_count,
    error_timestamp
FROM {{ ref('stg_dlq_errors') }}
WHERE status = 'pending'
  AND retry_count < 3
  AND error_type IN ('TIMEOUT_ERR', 'RATE_LIMIT', 'FK_ERR')
  AND DATEDIFF('minute', error_timestamp, CURRENT_TIMESTAMP()) >= POWER(2, retry_count) * 5
```

### Mark Resolved Macro

```sql
-- macros/mark_dlq_resolved.sql
{% macro mark_dlq_resolved(error_ids, resolved_by='dbt_retry') %}

UPDATE {{ ref('stg_dlq_errors') }}
SET
    status = 'resolved',
    resolved_timestamp = CURRENT_TIMESTAMP(),
    resolved_by = '{{ resolved_by }}'
WHERE error_id IN ({{ error_ids | join(', ') }})

{% endmacro %}
```

## Schema Definition

```yaml
# models/dlq/schema.yml
version: 2

models:
  - name: stg_dlq_errors
    description: Dead letter queue for failed records
    columns:
      - name: error_id
        description: Unique error identifier
        tests:
          - unique
          - not_null

      - name: source_table
        description: Source table where error originated
        tests:
          - not_null

      - name: error_type
        description: Error classification code
        tests:
          - not_null
          - accepted_values:
              values: ['PARSE_ERR', 'SCHEMA_ERR', 'NULL_ERR', 'RANGE_ERR', 'FK_ERR', 'TIMEOUT_ERR', 'RATE_LIMIT', 'AUTH_ERR', 'UNKNOWN']

      - name: status
        description: Current status of error
        tests:
          - not_null
          - accepted_values:
              values: ['pending', 'retrying', 'resolved', 'ignored', 'failed']

  - name: dlq_summary
    description: Aggregated DLQ metrics
    tests:
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 0
```

## DLQ Retry Operation

Run with: `dbt run-operation run_dlq_retries --args '{dlq_table: audit.dlq_errors, target_table: silver.orders}'`

```sql
-- macros/run_dlq_retries.sql
{% macro run_dlq_retries(dlq_table, target_table, max_retries=3) %}

{% set candidates_query %}
    SELECT error_id, original_record, retry_count
    FROM {{ dlq_table }}
    WHERE status = 'pending'
      AND retry_count < {{ max_retries }}
      AND error_type IN ('TIMEOUT_ERR', 'RATE_LIMIT', 'FK_ERR')
      AND DATEDIFF('minute', error_timestamp, CURRENT_TIMESTAMP()) >= POWER(2, retry_count) * 5
{% endset %}

{% if execute %}
    {% set candidates = run_query(candidates_query) %}
    {% set succeeded = [] %}
    {% set failed    = [] %}

    {% for row in candidates %}
        {% set retry_sql %}
            INSERT INTO {{ target_table }}
            SELECT * FROM (VALUES (PARSE_JSON('{{ row["original_record"] }}'))) AS t
        {% endset %}

        {% set ok = run_query(retry_sql) %}
        {% if ok %}
            {% do succeeded.append(row["error_id"]) %}
        {% else %}
            {% do failed.append(row["error_id"]) %}
        {% endif %}
    {% endfor %}

    {% if succeeded | length > 0 %}
        {% do run_query("UPDATE " ~ dlq_table ~ " SET status = 'resolved', resolved_timestamp = CURRENT_TIMESTAMP(), resolved_by = 'dbt_run_dlq_retries' WHERE error_id IN ('" ~ succeeded | join("','") ~ "')") %}
    {% endif %}

    {% if failed | length > 0 %}
        {% do run_query("UPDATE " ~ dlq_table ~ " SET retry_count = retry_count + 1, status = CASE WHEN retry_count + 1 >= " ~ max_retries ~ " THEN 'failed' ELSE 'pending' END WHERE error_id IN ('" ~ failed | join("','") ~ "')") %}
    {% endif %}

    {{ log("DLQ retry: " ~ succeeded | length ~ " resolved, " ~ failed | length ~ " failed", info=True) }}
{% endif %}

{% endmacro %}
```

## DLQ Alert Step

After each dbt run (and after the retry operation), query `dlq_alerts` and send notifications.

### Option A — shell script after dbt run

```bash
#!/bin/bash
# run_pipeline.sh

# 1. Main dbt run
dbt run --select staging+ marts+

# 2. Retry recoverable DLQ rows
dbt run-operation run_dlq_retries \
  --args '{"dlq_table": "audit.dlq_errors", "target_table": "silver.orders"}'

# 3. Refresh alert model
dbt run --select dlq_alerts

# 4. Send alerts for any rows in dlq_alerts
python - <<'EOF'
import subprocess, json, requests, os

WEBHOOK_URL = os.getenv("DLQ_WEBHOOK_URL")  # Teams/Slack webhook

result = subprocess.run(
    ["dbt", "show", "--select", "dlq_alerts", "--output", "json"],
    capture_output=True, text=True
)
rows = json.loads(result.stdout).get("rows", [])

if rows and WEBHOOK_URL:
    lines = ["**DLQ Alert**"]
    for row in rows:
        lines.append(f"[{row['alert_severity'].upper()}] {row['source_table']} / {row['error_type']}: {row['pending_count']} pending ({row['hours_pending']}h)")
    requests.post(WEBHOOK_URL, json={"text": "\n".join(lines)})
EOF
```

### Option B — Fabric / ADF activity

Add a Python notebook activity after the dbt activity that:
1. Queries `SELECT * FROM dlq_alerts WHERE alert_severity IN ('critical', 'high', 'medium')`
2. If any rows exist, posts to the Teams/Slack webhook
3. Raises an exception on `critical` severity to fail the pipeline run

```python
# Fabric notebook: check_dlq_alerts.py
from pyspark.sql import SparkSession
import requests, os

spark       = SparkSession.builder.getOrCreate()
webhook_url = os.getenv("DLQ_WEBHOOK_URL")

alerts_df = spark.table("audit.dlq_alerts")
alerts     = alerts_df.collect()

if alerts:
    lines = ["**DLQ Alert**"]
    for row in alerts:
        lines.append(f"[{row['alert_severity'].upper()}] {row['source_table']} / {row['error_type']}: {row['pending_count']} pending ({row['hours_pending']}h)")
    message = "\n".join(lines)
    if webhook_url:
        requests.post(webhook_url, json={"text": message}, timeout=10)
    else:
        print(message)

    # Fail pipeline run if critical alerts exist
    critical = [r for r in alerts if r["alert_severity"] == "critical"]
    if critical:
        raise Exception(f"Critical DLQ errors require immediate attention: {critical}")
```
