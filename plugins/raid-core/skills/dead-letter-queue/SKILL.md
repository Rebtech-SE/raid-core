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
|-- Always pair with a retry pipeline + alerting (see Mandatory sections below)
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

### The two invariants

Every capture pattern below holds both, and a pipeline that breaks either one is
silently losing data:

1. **Every input row lands somewhere.** `rows_in == rows_loaded + rows_quarantined`,
   checked per batch. A row that is neither loaded nor quarantined is the defect this
   skill exists to prevent -- the usual culprits are a validation predicate that
   evaluates to NULL (it is neither true nor false, so it passes neither the "valid" nor
   the "invalid" filter), an `except: pass`, and `mode("DROPMALFORMED")`.
2. **Every quarantined row can be replayed.** It keeps the whole original record, the
   reason, and the batch it came from, in the DLQ schema above -- a bare dump of bad
   rows into a table with no reason is not a quarantine, because nobody can tell why a
   row is there or push it back through once the cause is fixed.

### `write_to_dlq` -- the one write path

All DataFrame-level routing goes through this helper, so every quarantined row has the
same shape whichever check rejected it:

```python
from pyspark.sql import functions as F

def write_to_dlq(
    df,
    error_type: str,
    error_message: str,
    source_table: str,
    batch_id: str,
    dlq_table: str,
):
    """Append every row of df to the DLQ with its reason. Returns the row count."""
    count = df.count()
    if count == 0:
        return 0
    (
        df.select(
            F.expr("uuid()").alias("error_id"),
            # ignoreNullFields=false: to_json omits NULL fields by default, and a
            # quarantined row is often there *because* a field is NULL -- the record
            # must say so, and a replay must find the key.
            F.to_json(
                F.struct(*[F.col(c) for c in df.columns]), {"ignoreNullFields": "false"}
            ).alias("original_record"),
            F.lit(source_table).alias("source_table"),
            F.lit(error_type).alias("error_type"),
            F.lit(error_message).cast("string").alias("error_message"),
            F.current_timestamp().alias("error_timestamp"),
            F.lit(batch_id).cast("string").alias("batch_id"),
            F.lit(0).alias("retry_count"),
            F.lit("pending").alias("status"),
            F.lit(None).cast("timestamp").alias("resolved_timestamp"),
            F.lit(None).cast("string").alias("resolved_by"),
        )
        .write.mode("append").format("delta").saveAsTable(dlq_table)
    )
    return count
```

Cast every literal: an uncast `F.lit(None)` is a void-typed column, and Delta refuses to
create a table with one.

### PySpark Try/Except Pattern

```python
from pyspark.sql import functions as F
import json
import uuid
from datetime import datetime

def process_with_dlq(
    spark,
    source_df,
    source_table: str,
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
        source_table: Name of the table/topic source_df was read from
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
                # default=str: dates, timestamps and decimals are not JSON-serializable
                "original_record": json.dumps(row.asDict(), default=str),
                "source_table": source_table,
                "error_type": classify_error(e),
                "error_message": str(e),
                "error_timestamp": datetime.now(),
                "batch_id": batch_id,
                "retry_count": 0,
                "status": "pending",
                "resolved_timestamp": None,
                "resolved_by": None
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
    source_table: str,
    valid_table: str,
    dlq_table: str,
    batch_id: str = None
):
    """
    Route records based on validation rules. Each failing row is quarantined once,
    under the first rule it fails.

    validation_rules: [
        {"name": "not_null_id", "condition": "id IS NOT NULL", "error_type": "NULL_ERR"},
        {"name": "positive_amount", "condition": "amount > 0", "error_type": "RANGE_ERR"}
    ]
    """
    batch_id = batch_id or str(uuid.uuid4())
    flags = [f"_valid_{rule['name']}" for rule in validation_rules]

    # A predicate over a NULL column evaluates to NULL, not false -- `amount > 0` on a
    # NULL amount. Such a row passes neither filter(valid) nor filter(~valid) and
    # vanishes. coalesce() makes it fail the rule instead.
    checked = source_df
    for rule, flag in zip(validation_rules, flags):
        checked = checked.withColumn(
            flag, F.coalesce(F.expr(rule["condition"]), F.lit(False))
        )

    all_valid = F.lit(True)
    for flag in flags:
        all_valid = all_valid & F.col(flag)

    valid_df = checked.filter(all_valid).drop(*flags)
    remaining = checked.filter(~all_valid)

    quarantined = 0
    for rule, flag in zip(validation_rules, flags):
        quarantined += write_to_dlq(
            remaining.filter(~F.col(flag)).drop(*flags),
            error_type=rule["error_type"],
            error_message=f"Failed validation: {rule['name']} ({rule['condition']})",
            source_table=source_table,
            batch_id=batch_id,
            dlq_table=dlq_table,
        )
        remaining = remaining.filter(F.col(flag))

    valid_count = valid_df.count()
    valid_df.write.mode("append").saveAsTable(valid_table)

    # Invariant 1: every input row landed somewhere.
    total = source_df.count()
    if total != valid_count + quarantined:
        raise RuntimeError(
            f"Row accounting broken for batch {batch_id}: {total} in, "
            f"{valid_count} loaded, {quarantined} quarantined"
        )

    return {"valid": valid_count, "invalid": quarantined, "batch_id": batch_id}
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
import random
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

### Replaying Rows After a Fix

The retry pipeline only takes recoverable types. A `PARSE_ERR`, `NULL_ERR` or
`RANGE_ERR` row fails the same way every time until someone fixes the source, the
parser or the rule -- so it needs its own path back, run by hand once the cause is fixed.
Without one, the quarantine can be inspected but not recovered, and the rows are lost
in all but name.

```python
from delta.tables import DeltaTable

def replay_dlq(
    spark,
    dlq_table: str,
    target_table: str,
    transform_func: Callable,
    condition: str,
    replayed_by: str,
):
    """
    Push quarantined rows matching `condition` (e.g. "batch_id = '...'" or
    "error_type = 'NULL_ERR' AND source_table = 'bronze.orders'") back through the load,
    whatever their error type.

    transform_func receives the stored original_record string -- JSON for rows captured
    by write_to_dlq, the raw unparsed text for PARSE_ERR rows -- and returns a dict
    matching target_table, or raises if the row is still bad.
    """
    rows = (
        spark.table(dlq_table)
        .filter(F.col("status").isin("pending", "failed"))
        .filter(condition)
        .collect()
    )

    loaded, resolved_ids, still_failing = [], [], 0
    for row in rows:
        try:
            loaded.append(transform_func(row["original_record"]))
            resolved_ids.append(row["error_id"])
        except Exception:
            still_failing += 1  # stays in the DLQ untouched, for the next attempt

    if loaded:
        # Load first, then mark resolved: a crash in between re-replays the rows
        # (dedupe on the target's key), it never marks unloaded rows resolved.
        # The target's own schema, not inference: inference reads a Python int as
        # bigint, and Delta will not append bigint into an int column.
        target_schema = spark.table(target_table).schema
        spark.createDataFrame(loaded, target_schema).write.mode("append").saveAsTable(target_table)
        DeltaTable.forName(spark, dlq_table).update(
            condition=F.col("error_id").isin(resolved_ids),
            set={
                "status": F.lit("resolved"),
                "resolved_timestamp": F.current_timestamp(),
                "resolved_by": F.lit(replayed_by),
            },
        )

    return {"matched": len(rows), "resolved": len(resolved_ids), "still_failing": still_failing}
```

Rows nobody will ever fix are closed with `status = 'ignored'` and a `resolved_by`, not
deleted -- the DLQ is the record that they existed.

## Integration with Medallion Architecture

### Bronze Layer DLQ

```python
# Bronze: Capture parse/schema errors
def bronze_ingest_with_dlq(spark, source_path, schema, bronze_table, dlq_table, batch_id):
    # PERMISSIVE keeps malformed lines instead of failing the read (FAILFAST) or
    # dropping them (DROPMALFORMED). An explicit schema must include the corrupt-record
    # column, or Spark has nowhere to put the raw line.
    df = (
        spark.read
        .schema(StructType(schema.fields + [StructField("_corrupt_record", StringType())]))
        .option("mode", "PERMISSIVE")
        .option("columnNameOfCorruptRecord", "_corrupt_record")
        .json(source_path)
        .cache()  # Spark refuses to query only the corrupt-record column of an uncached read
    )

    # Split valid and corrupt
    valid = df.filter(F.col("_corrupt_record").isNull()).drop("_corrupt_record")
    corrupt = df.filter(F.col("_corrupt_record").isNotNull())

    # Write valid to Bronze
    valid.write.mode("append").saveAsTable(bronze_table)

    # Write corrupt to DLQ. The raw line is the original record: there is nothing
    # parsed to serialise, and the raw text is what a replay needs.
    corrupt.select(
        F.expr("uuid()").alias("error_id"),
        F.col("_corrupt_record").alias("original_record"),
        F.lit(source_path).alias("source_table"),
        F.lit("PARSE_ERR").alias("error_type"),
        F.lit("Failed to parse JSON record").alias("error_message"),
        F.current_timestamp().alias("error_timestamp"),
        F.lit(batch_id).cast("string").alias("batch_id"),
        F.lit(0).alias("retry_count"),
        F.lit("pending").alias("status"),
        F.lit(None).cast("timestamp").alias("resolved_timestamp"),
        F.lit(None).cast("string").alias("resolved_by"),
    ).write.mode("append").format("delta").saveAsTable(dlq_table)
```

### Silver Layer DLQ

```python
# Silver: Capture validation/transformation errors
def silver_transform_with_dlq(spark, bronze_table, silver_table, dlq_table, batch_id):
    bronze_df = spark.table(bronze_table)

    validation_rules = [
        {"name": "id_not_null", "condition": "id IS NOT NULL", "error_type": "NULL_ERR"},
        {"name": "valid_amount", "condition": "amount >= 0", "error_type": "RANGE_ERR"},
        {"name": "valid_email", "condition": "email RLIKE '^[^@]+@[^@]+$'", "error_type": "TYPE_ERR"}
    ]

    return route_by_validation(
        spark, bronze_df, validation_rules,
        source_table=bronze_table, valid_table=silver_table,
        dlq_table=dlq_table, batch_id=batch_id,
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
