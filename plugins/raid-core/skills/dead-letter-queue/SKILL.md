---
name: dead-letter-queue
description: >-
  Use when building fault-tolerant pipelines, handling bad records, or implementing
  retry mechanisms. Triggers include 'dead letter', 'error handling', 'bad records',
  'retry logic', 'error queue', 'failed records', 'quarantine table', 'poison message',
  'DLQ'. Covers error classification, retry logic, recovery procedures, and monitoring
  for data pipelines.
---

# Dead Letter Queue Patterns

Comprehensive patterns for handling errors in data pipelines using dead letter queues (DLQ).

## When to Use This Skill

Use this skill when users ask about:

- **Error handling**: "How do I handle bad records?"
- **DLQ design**: "How do I set up a dead letter queue?"
- **Retry logic**: "How do I retry failed records?"
- **Error recovery**: "How do I reprocess failed data?"
- **Fault tolerance**: "How do I make my pipeline resilient?"
- **Error monitoring**: "How do I track pipeline failures?"

For data quality rules and thresholds, see [data-quality-checks](../data-quality-checks/SKILL.md).
For Fabric-specific execution/testing, see `test-fabric-notebook` (raid-fabric).

## Core Concepts

### What is a Dead Letter Queue?

A DLQ is a holding area for records that cannot be processed successfully. Instead of failing the entire pipeline, bad records are routed to the DLQ for later analysis and remediation.

### When to Use DLQ vs Fail-Fast

| Scenario | Approach | Rationale |
|----------|----------|-----------|
| Schema mismatch | Fail-fast | Likely systemic issue |
| Single bad record | DLQ | Don't block good records |
| External API timeout | Retry + DLQ | Transient, may recover |
| Business rule violation | DLQ | Needs manual review |
| Authentication failure | Fail-fast | Pipeline misconfiguration |

## Quick Decision Tree

```
Record processing fails
|
|-- Is it a configuration/setup error?
|   |-> Fail-fast, fix configuration
|
|-- Is it a transient error (timeout, rate limit)?
|   |-> Retry with backoff
|   |   |-- Still failing after max retries?
|   |       |-> Route to DLQ
|
|-- Is it a data quality issue?
|   |-> Route to DLQ immediately
|   |   - Log error details
|   |   - Continue processing good records
|
|-- Is it an unknown error?
|   |-> Route to DLQ with full context
|       - Preserve original record
|       - Capture stack trace
|
|-- Always pair with a retry pipeline + alerting (see Mandatory sections above)
```

## DLQ Table Design

### Required Columns

| Column | Type | Purpose |
|--------|------|---------|
| `error_id` | STRING (UUID) | Unique error identifier |
| `original_record` | STRING (JSON) | Original data as JSON |
| `source_table` | STRING | Source table/topic |
| `error_type` | STRING | Classification code |
| `error_message` | STRING | Detailed error message |
| `error_timestamp` | TIMESTAMP | When error occurred |
| `batch_id` | STRING | Processing batch ID |
| `retry_count` | INT | Number of retry attempts |
| `status` | STRING | pending/retrying/resolved/ignored |
| `resolved_timestamp` | TIMESTAMP | When resolved (nullable) |
| `resolved_by` | STRING | User/process that resolved |

### PySpark Schema

```python
from pyspark.sql.types import *

dlq_schema = StructType([
    StructField("error_id", StringType(), False),
    StructField("original_record", StringType(), False),
    StructField("source_table", StringType(), False),
    StructField("error_type", StringType(), False),
    StructField("error_message", StringType(), True),
    StructField("error_timestamp", TimestampType(), False),
    StructField("batch_id", StringType(), True),
    StructField("retry_count", IntegerType(), False),
    StructField("status", StringType(), False),
    StructField("resolved_timestamp", TimestampType(), True),
    StructField("resolved_by", StringType(), True)
])
```

### dbt Schema

```sql
-- models/dlq/dlq_errors.sql
{{
  config(
    materialized='incremental',
    unique_key='error_id'
  )
}}

SELECT
    error_id,
    original_record,
    source_table,
    error_type,
    error_message,
    error_timestamp,
    batch_id,
    retry_count,
    status,
    resolved_timestamp,
    resolved_by
FROM {{ ref('stg_dlq_errors') }}

{% if is_incremental() %}
WHERE error_timestamp > (SELECT MAX(error_timestamp) FROM {{ this }})
{% endif %}
```

## Error Classification

### Error Type Taxonomy

| Error Type | Code | Recoverable | Action |
|------------|------|-------------|--------|
| Parse error | `PARSE_ERR` | No | Manual fix |
| Schema mismatch | `SCHEMA_ERR` | No | Schema evolution |
| Null constraint | `NULL_ERR` | No | Data fix |
| Type cast failure | `TYPE_ERR` | No | Source fix |
| Range violation | `RANGE_ERR` | No | Business review |
| FK violation | `FK_ERR` | Maybe | Wait for parent |
| Timeout | `TIMEOUT_ERR` | Yes | Retry |
| Rate limit | `RATE_LIMIT` | Yes | Retry with backoff |
| Auth failure | `AUTH_ERR` | No | Config fix |
| Unknown | `UNKNOWN` | Unknown | Investigation |

### Classification Function

```python
def classify_error(exception: Exception, record: dict = None) -> str:
    """Classify error by type."""
    error_msg = str(exception).lower()

    if "parse" in error_msg or "json" in error_msg or "decode" in error_msg:
        return "PARSE_ERR"
    elif "schema" in error_msg or "column" in error_msg or "field" in error_msg:
        return "SCHEMA_ERR"
    elif "null" in error_msg or "none" in error_msg:
        return "NULL_ERR"
    elif "cast" in error_msg or "convert" in error_msg or "type" in error_msg:
        return "TYPE_ERR"
    elif "range" in error_msg or "bound" in error_msg:
        return "RANGE_ERR"
    elif "foreign" in error_msg or "reference" in error_msg:
        return "FK_ERR"
    elif "timeout" in error_msg:
        return "TIMEOUT_ERR"
    elif "rate" in error_msg or "throttl" in error_msg:
        return "RATE_LIMIT"
    elif "auth" in error_msg or "permission" in error_msg or "credential" in error_msg:
        return "AUTH_ERR"
    else:
        return "UNKNOWN"

def is_recoverable(error_type: str) -> bool:
    """Check if error type is potentially recoverable via retry."""
    recoverable_types = {"TIMEOUT_ERR", "RATE_LIMIT", "FK_ERR"}
    return error_type in recoverable_types
```

## Error Capture Patterns

### PySpark Try/Except Pattern

```python
from pyspark.sql import functions as F
import json
import uuid
from datetime import datetime

def process_with_dlq(
    spark,
    source_df,
    target_table: str,
    dlq_table: str,
    transform_func,
    batch_id: str = None
):
    """
    Process DataFrame with DLQ error handling.

    Args:
        spark: SparkSession
        source_df: Source DataFrame
        target_table: Target table for successful records
        dlq_table: DLQ table for failed records
        transform_func: Transformation function to apply
        batch_id: Optional batch identifier
    """
    batch_id = batch_id or str(uuid.uuid4())
    successful_records = []
    error_records = []

    # Process row by row (for complex transformations)
    for row in source_df.collect():
        try:
            transformed = transform_func(row)
            successful_records.append(transformed)
        except Exception as e:
            error_records.append({
                "error_id": str(uuid.uuid4()),
                "original_record": json.dumps(row.asDict()),
                "source_table": source_df.schema.simpleString(),
                "error_type": classify_error(e),
                "error_message": str(e),
                "error_timestamp": datetime.now(),
                "batch_id": batch_id,
                "retry_count": 0,
                "status": "pending"
            })

    # Write successful records
    if successful_records:
        success_df = spark.createDataFrame(successful_records)
        success_df.write.mode("append").saveAsTable(target_table)

    # Write errors to DLQ
    if error_records:
        error_df = spark.createDataFrame(error_records, schema=dlq_schema)
        error_df.write.mode("append").saveAsTable(dlq_table)

    return {
        "successful": len(successful_records),
        "failed": len(error_records),
        "batch_id": batch_id
    }
```

### Validation-Based Routing

```python
def route_by_validation(
    spark,
    source_df,
    validation_rules: list,
    valid_table: str,
    dlq_table: str,
    batch_id: str = None
):
    """
    Route records based on validation rules.

    validation_rules: [
        {"name": "not_null_id", "condition": "id IS NOT NULL", "error_type": "NULL_ERR"},
        {"name": "positive_amount", "condition": "amount > 0", "error_type": "RANGE_ERR"}
    ]
    """
    batch_id = batch_id or str(uuid.uuid4())

    # Add validation columns
    df_with_validation = source_df
    for rule in validation_rules:
        df_with_validation = df_with_validation.withColumn(
            f"_valid_{rule['name']}",
            F.expr(rule["condition"])
        )

    # Build overall validity condition
    validity_condition = F.lit(True)
    for rule in validation_rules:
        validity_condition = validity_condition & F.col(f"_valid_{rule['name']}")

    # Split valid and invalid
    valid_df = df_with_validation.filter(validity_condition)
    invalid_df = df_with_validation.filter(~validity_condition)

    # Clean up validation columns from valid records
    for rule in validation_rules:
        valid_df = valid_df.drop(f"_valid_{rule['name']}")

    # Write valid records
    valid_df.write.mode("append").saveAsTable(valid_table)

    # Process invalid records into DLQ format
    if invalid_df.count() > 0:
        # Determine which rule failed for each record
        error_records = []
        for row in invalid_df.collect():
            for rule in validation_rules:
                if not row[f"_valid_{rule['name']}"]:
                    # Remove validation columns from original record
                    original = {k: v for k, v in row.asDict().items() if not k.startswith("_valid_")}
                    error_records.append({
                        "error_id": str(uuid.uuid4()),
                        "original_record": json.dumps(original),
                        "source_table": valid_table,
                        "error_type": rule["error_type"],
                        "error_message": f"Failed validation: {rule['name']} ({rule['condition']})",
                        "error_timestamp": datetime.now(),
                        "batch_id": batch_id,
                        "retry_count": 0,
                        "status": "pending"
                    })
                    break  # Only capture first failure per record

        error_df = spark.createDataFrame(error_records, schema=dlq_schema)
        error_df.write.mode("append").saveAsTable(dlq_table)

    return {
        "valid": valid_df.count(),
        "invalid": invalid_df.count() if invalid_df else 0,
        "batch_id": batch_id
    }
```

## Mandatory Retry Pipeline

Every DLQ implementation MUST include a companion retry pipeline. A DLQ without a retry
pipeline is just a quarantine table — rows accumulate and are never recovered.

### What the retry pipeline does

1. Queries DLQ for `status = 'pending'`, `retry_count < max_retries`, recoverable error types
2. Re-applies the same transform/load logic on `original_record`
3. On success: writes to target table, marks DLQ row `status = 'resolved'`
4. On failure: increments `retry_count`; sets `status = 'failed'` when max retries exhausted

### Scheduling

- Run the retry pipeline **after** the main pipeline completes, within the same orchestration DAG
- Typical cadence: every pipeline run (e.g. hourly) — the retry processor is a no-op when there are no candidates
- The exponential backoff delay is enforced inside `get_retry_candidates()` — running hourly is fine

### Implementation

- **PySpark**: Use `DLQRetryProcessor` — see [Retry Pipeline Template](references/pyspark-dlq-patterns.md#retry-pipeline-template)
- **dbt**: Use the `run_dlq_retries` operation — see [DLQ Retry Operation](references/dbt-dlq-patterns.md#dlq-retry-operation)

## Mandatory DLQ Alerting

Every DLQ implementation MUST include alerting. Two alert types are required:

### Per-run alert (immediate)
Fire when the current pipeline run writes any rows to the DLQ. This catches new errors
as they happen, not hours later when a threshold is breached.

### Threshold-based alert (cumulative)
Fire when the DLQ accumulates above safe thresholds. Uses the existing `check_dlq_alerts()`
logic: pending count > 1000, stale records > 7 days, critical error types (`AUTH_ERR`, `SCHEMA_ERR`).

### Alert delivery

Implement `send_dlq_alert()` with the customer's notification channel:
- Teams/Slack webhook (preferred)
- Email via SMTP
- PagerDuty for critical severity
- Fallback: log to console (development only)

### When to alert

| Trigger | Severity | Action |
|---------|----------|--------|
| Any rows written to DLQ this run | high | Notify immediately after pipeline run |
| Pending count > 1000 | high | Notify after each retry pipeline run |
| Stale rows > 7 days | medium | Notify after each retry pipeline run |
| AUTH_ERR or SCHEMA_ERR present | critical | Notify immediately — these don't self-heal |

### Implementation

- **PySpark**: See [DLQ Alert Functions](references/pyspark-dlq-patterns.md#dlq-alert-functions)
- **dbt**: See [DLQ Alert Step](references/dbt-dlq-patterns.md#dlq-alert-step)

## Retry Strategies

### Exponential Backoff

```python
import time
from typing import Callable, Any

def retry_with_backoff(
    func: Callable,
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0
) -> Any:
    """
    Retry function with exponential backoff.

    Args:
        func: Function to retry
        max_retries: Maximum retry attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        exponential_base: Multiplier for each retry
    """
    last_exception = None

    for attempt in range(max_retries + 1):
        try:
            return func()
        except Exception as e:
            last_exception = e

            if attempt == max_retries:
                break

            delay = min(base_delay * (exponential_base ** attempt), max_delay)
            # Add jitter to prevent thundering herd
            delay = delay * (0.5 + random.random())

            print(f"Attempt {attempt + 1} failed, retrying in {delay:.2f}s: {e}")
            time.sleep(delay)

    raise last_exception
```

### DLQ Retry Processing

```python
def process_dlq_retries(
    spark,
    dlq_table: str,
    target_table: str,
    transform_func: Callable,
    max_retries: int = 3
):
    """
    Retry pending DLQ records.
    """
    # Get pending recoverable errors
    pending = spark.table(dlq_table).filter(
        (F.col("status") == "pending") &
        (F.col("retry_count") < max_retries) &
        (F.col("error_type").isin(["TIMEOUT_ERR", "RATE_LIMIT", "FK_ERR"]))
    )

    if pending.count() == 0:
        return {"retried": 0, "succeeded": 0, "failed": 0}

    succeeded = 0
    failed = 0

    for row in pending.collect():
        try:
            # Parse original record
            original = json.loads(row["original_record"])

            # Attempt transformation
            transformed = transform_func(original)

            # Write to target
            spark.createDataFrame([transformed]).write.mode("append").saveAsTable(target_table)

            # Mark as resolved
            spark.sql(f"""
                UPDATE {dlq_table}
                SET status = 'resolved',
                    resolved_timestamp = current_timestamp()
                WHERE error_id = '{row["error_id"]}'
            """)
            succeeded += 1

        except Exception as e:
            # Update retry count
            new_count = row["retry_count"] + 1
            new_status = "pending" if new_count < max_retries else "failed"

            spark.sql(f"""
                UPDATE {dlq_table}
                SET retry_count = {new_count},
                    status = '{new_status}',
                    error_message = '{str(e).replace("'", "''")}'
                WHERE error_id = '{row["error_id"]}'
            """)
            failed += 1

    return {
        "retried": succeeded + failed,
        "succeeded": succeeded,
        "failed": failed
    }
```

## Integration with Medallion Architecture

### Bronze Layer DLQ

```python
# Bronze: Capture parse/schema errors
def bronze_ingest_with_dlq(spark, source_path, bronze_table, dlq_table):
    # Read with permissive mode
    df = spark.read \
        .option("mode", "PERMISSIVE") \
        .option("columnNameOfCorruptRecord", "_corrupt_record") \
        .json(source_path)

    # Split valid and corrupt
    valid = df.filter(F.col("_corrupt_record").isNull()).drop("_corrupt_record")
    corrupt = df.filter(F.col("_corrupt_record").isNotNull())

    # Write valid to Bronze
    valid.write.mode("append").saveAsTable(bronze_table)

    # Write corrupt to DLQ
    if corrupt.count() > 0:
        corrupt_dlq = corrupt.select(
            F.expr("uuid()").alias("error_id"),
            F.col("_corrupt_record").alias("original_record"),
            F.lit(bronze_table).alias("source_table"),
            F.lit("PARSE_ERR").alias("error_type"),
            F.lit("Failed to parse JSON record").alias("error_message"),
            F.current_timestamp().alias("error_timestamp"),
            F.lit(None).alias("batch_id"),
            F.lit(0).alias("retry_count"),
            F.lit("pending").alias("status")
        )
        corrupt_dlq.write.mode("append").saveAsTable(dlq_table)
```

### Silver Layer DLQ

```python
# Silver: Capture validation/transformation errors
def silver_transform_with_dlq(spark, bronze_table, silver_table, dlq_table):
    bronze_df = spark.table(bronze_table)

    validation_rules = [
        {"name": "id_not_null", "condition": "id IS NOT NULL", "error_type": "NULL_ERR"},
        {"name": "valid_amount", "condition": "amount >= 0", "error_type": "RANGE_ERR"},
        {"name": "valid_email", "condition": "email RLIKE '^[^@]+@[^@]+$'", "error_type": "TYPE_ERR"}
    ]

    return route_by_validation(
        spark, bronze_df, validation_rules, silver_table, dlq_table
    )
```

## Monitoring and Alerting

### DLQ Metrics

```sql
-- DLQ summary by status
SELECT
    source_table,
    error_type,
    status,
    COUNT(*) AS error_count,
    MIN(error_timestamp) AS oldest_error,
    MAX(error_timestamp) AS newest_error
FROM dlq.errors
GROUP BY source_table, error_type, status
ORDER BY error_count DESC;

-- Pending errors by age
SELECT
    source_table,
    error_type,
    COUNT(*) AS pending_count,
    DATEDIFF(CURRENT_TIMESTAMP, MIN(error_timestamp)) AS max_age_days
FROM dlq.errors
WHERE status = 'pending'
GROUP BY source_table, error_type
HAVING max_age_days > 1;
```

### Alert Thresholds

```python
def check_dlq_alerts(spark, dlq_table: str) -> list:
    """Generate alerts based on DLQ state."""
    alerts = []

    # Check for growing DLQ
    pending_count = spark.table(dlq_table) \
        .filter(F.col("status") == "pending") \
        .count()

    if pending_count > 1000:
        alerts.append({
            "severity": "high",
            "message": f"DLQ has {pending_count} pending records"
        })

    # Check for stale errors
    stale = spark.table(dlq_table).filter(
        (F.col("status") == "pending") &
        (F.datediff(F.current_timestamp(), F.col("error_timestamp")) > 7)
    ).count()

    if stale > 0:
        alerts.append({
            "severity": "medium",
            "message": f"{stale} DLQ records older than 7 days"
        })

    # Check for critical error types
    critical_types = spark.table(dlq_table) \
        .filter(F.col("status") == "pending") \
        .groupBy("error_type") \
        .count() \
        .filter(F.col("error_type").isin(["AUTH_ERR", "SCHEMA_ERR"]))

    for row in critical_types.collect():
        alerts.append({
            "severity": "critical",
            "message": f"{row['count']} {row['error_type']} errors require immediate attention"
        })

    return alerts
```

## Related Skills

- [medallion-architecture](../medallion-architecture/SKILL.md) - Layer-specific DLQ placement
- [data-quality-checks](../data-quality-checks/SKILL.md) - Validation rules for routing
- [scd-pattern](../scd-pattern/SKILL.md) - Handling SCD merge failures

## References

- [Error Classification](references/error-classification.md) - Complete error taxonomy
- [Retry Patterns](references/retry-patterns.md) - Backoff and circuit breaker patterns
- [dbt DLQ Patterns](references/dbt-dlq-patterns.md) - dbt error routing models
- [PySpark DLQ Patterns](references/pyspark-dlq-patterns.md) - Complete PySpark implementation
