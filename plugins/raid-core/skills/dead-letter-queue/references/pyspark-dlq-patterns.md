# PySpark Dead Letter Queue Patterns

Complete PySpark implementation for dead letter queue handling.

## Core DLQ Manager

```python
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
from dataclasses import dataclass
from typing import List, Dict, Callable, Optional, Any
from datetime import datetime
import json
import uuid

@dataclass
class DLQConfig:
    """Configuration for DLQ behavior."""
    dlq_table: str
    max_retries: int = 3
    retry_delay_minutes: int = 5
    enable_auto_retry: bool = True
    recoverable_error_types: List[str] = None

    def __post_init__(self):
        if self.recoverable_error_types is None:
            self.recoverable_error_types = ["TIMEOUT_ERR", "RATE_LIMIT", "FK_ERR"]

class DLQManager:
    """Manage dead letter queue operations."""

    DLQ_SCHEMA = StructType([
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

    def __init__(self, spark: SparkSession, config: DLQConfig):
        self.spark = spark
        self.config = config
        self._ensure_dlq_table()

    def _ensure_dlq_table(self):
        """Create DLQ table if it doesn't exist."""
        if not self.spark.catalog.tableExists(self.config.dlq_table):
            empty_df = self.spark.createDataFrame([], self.DLQ_SCHEMA)
            empty_df.write.format("delta").saveAsTable(self.config.dlq_table)

    def write_error(
        self,
        record: Dict,
        source_table: str,
        error_type: str,
        error_message: str,
        batch_id: str = None
    ):
        """Write a single error to DLQ."""
        error_record = {
            "error_id": str(uuid.uuid4()),
            "original_record": json.dumps(record) if isinstance(record, dict) else str(record),
            "source_table": source_table,
            "error_type": error_type,
            "error_message": error_message[:4000] if error_message else None,  # Truncate long messages
            "error_timestamp": datetime.now(),
            "batch_id": batch_id,
            "retry_count": 0,
            "status": "pending",
            "resolved_timestamp": None,
            "resolved_by": None
        }

        error_df = self.spark.createDataFrame([error_record], self.DLQ_SCHEMA)
        error_df.write.mode("append").format("delta").saveAsTable(self.config.dlq_table)

    def write_errors_batch(self, errors: List[Dict]):
        """Write multiple errors to DLQ efficiently."""
        if not errors:
            return

        error_df = self.spark.createDataFrame(errors, self.DLQ_SCHEMA)
        error_df.write.mode("append").format("delta").saveAsTable(self.config.dlq_table)

    def get_pending_errors(self, source_table: str = None) -> DataFrame:
        """Get all pending errors."""
        df = self.spark.table(self.config.dlq_table).filter(F.col("status") == "pending")

        if source_table:
            df = df.filter(F.col("source_table") == source_table)

        return df

    def get_retry_candidates(self) -> DataFrame:
        """Get errors eligible for retry."""
        min_retry_time = F.expr(f"""
            error_timestamp + INTERVAL {self.config.retry_delay_minutes} * POWER(2, retry_count) MINUTES
        """)

        return self.spark.table(self.config.dlq_table).filter(
            (F.col("status") == "pending") &
            (F.col("retry_count") < self.config.max_retries) &
            (F.col("error_type").isin(self.config.recoverable_error_types)) &
            (F.current_timestamp() >= min_retry_time)
        )

    def mark_resolved(self, error_ids: List[str], resolved_by: str = "auto"):
        """Mark errors as resolved."""
        from delta.tables import DeltaTable

        dlq_table = DeltaTable.forName(self.spark, self.config.dlq_table)
        dlq_table.update(
            condition=F.col("error_id").isin(error_ids),
            set={
                "status": F.lit("resolved"),
                "resolved_timestamp": F.current_timestamp(),
                "resolved_by": F.lit(resolved_by)
            }
        )

    def increment_retry(self, error_ids: List[str]):
        """Increment retry count for errors."""
        from delta.tables import DeltaTable

        dlq_table = DeltaTable.forName(self.spark, self.config.dlq_table)
        dlq_table.update(
            condition=F.col("error_id").isin(error_ids),
            set={
                "retry_count": F.col("retry_count") + 1,
                "status": F.when(
                    F.col("retry_count") + 1 >= self.config.max_retries,
                    F.lit("failed")
                ).otherwise(F.lit("pending"))
            }
        )

    def mark_failed(self, error_ids: List[str]):
        """Mark errors as permanently failed."""
        from delta.tables import DeltaTable

        dlq_table = DeltaTable.forName(self.spark, self.config.dlq_table)
        dlq_table.update(
            condition=F.col("error_id").isin(error_ids),
            set={"status": F.lit("failed")}
        )

    def get_summary(self) -> Dict:
        """Get DLQ statistics."""
        summary = self.spark.table(self.config.dlq_table) \
            .groupBy("source_table", "error_type", "status") \
            .agg(
                F.count("*").alias("count"),
                F.min("error_timestamp").alias("oldest"),
                F.max("error_timestamp").alias("newest"),
                F.avg("retry_count").alias("avg_retries")
            ).collect()

        return {
            "by_source_type_status": [row.asDict() for row in summary],
            "total_pending": self.spark.table(self.config.dlq_table)
                .filter(F.col("status") == "pending").count(),
            "total_failed": self.spark.table(self.config.dlq_table)
                .filter(F.col("status") == "failed").count()
        }
```

## Process with DLQ Pattern

```python
class DLQProcessor:
    """Process data with automatic DLQ handling."""

    def __init__(
        self,
        spark: SparkSession,
        dlq_manager: DLQManager,
        source_table: str,
        target_table: str
    ):
        self.spark = spark
        self.dlq = dlq_manager
        self.source_table = source_table
        self.target_table = target_table

    def process_batch(
        self,
        source_df: DataFrame,
        transform_func: Callable[[Dict], Dict],
        batch_id: str = None
    ) -> Dict:
        """
        Process batch with DLQ error handling.

        Args:
            source_df: Source DataFrame
            transform_func: Function to transform each record
            batch_id: Optional batch identifier

        Returns:
            Processing statistics
        """
        batch_id = batch_id or str(uuid.uuid4())
        successful = []
        errors = []

        for row in source_df.collect():
            record = row.asDict()
            try:
                transformed = transform_func(record)
                successful.append(transformed)
            except Exception as e:
                error_type = classify_error(e)
                errors.append({
                    "error_id": str(uuid.uuid4()),
                    "original_record": json.dumps(record),
                    "source_table": self.source_table,
                    "error_type": error_type,
                    "error_message": str(e),
                    "error_timestamp": datetime.now(),
                    "batch_id": batch_id,
                    "retry_count": 0,
                    "status": "pending",
                    "resolved_timestamp": None,
                    "resolved_by": None
                })

        # Write successful records
        if successful:
            success_df = self.spark.createDataFrame(successful)
            success_df.write.mode("append").saveAsTable(self.target_table)

        # Write errors to DLQ
        if errors:
            self.dlq.write_errors_batch(errors)

        return {
            "batch_id": batch_id,
            "total_records": source_df.count(),
            "successful": len(successful),
            "failed": len(errors)
        }

    def process_with_validation(
        self,
        source_df: DataFrame,
        validation_rules: List[Dict],
        transform_func: Callable[[Dict], Dict] = None,
        batch_id: str = None
    ) -> Dict:
        """
        Process with validation-based routing.

        Args:
            source_df: Source DataFrame
            validation_rules: List of {"name", "condition", "error_type"}
            transform_func: Optional transformation function
            batch_id: Optional batch identifier

        Returns:
            Processing statistics
        """
        batch_id = batch_id or str(uuid.uuid4())

        # Add validation columns
        df = source_df
        for rule in validation_rules:
            df = df.withColumn(f"_valid_{rule['name']}", F.expr(rule["condition"]))

        # Build validity condition
        validity_cols = [f"_valid_{rule['name']}" for rule in validation_rules]
        validity_condition = F.lit(True)
        for col in validity_cols:
            validity_condition = validity_condition & F.col(col)

        # Split valid and invalid
        valid_df = df.filter(validity_condition)
        invalid_df = df.filter(~validity_condition)

        # Clean up validation columns
        for col in validity_cols:
            valid_df = valid_df.drop(col)

        # Apply transformation if provided
        if transform_func:
            transformed = []
            for row in valid_df.collect():
                try:
                    transformed.append(transform_func(row.asDict()))
                except Exception as e:
                    # Handle transformation errors
                    pass
            if transformed:
                valid_df = self.spark.createDataFrame(transformed)

        # Write valid records
        valid_count = valid_df.count()
        if valid_count > 0:
            valid_df.write.mode("append").saveAsTable(self.target_table)

        # Process invalid records to DLQ
        invalid_count = invalid_df.count()
        if invalid_count > 0:
            errors = []
            for row in invalid_df.collect():
                # Find first failing rule
                for rule in validation_rules:
                    if not row[f"_valid_{rule['name']}"]:
                        # Build original record without validation columns
                        original = {k: v for k, v in row.asDict().items() if not k.startswith("_valid_")}
                        errors.append({
                            "error_id": str(uuid.uuid4()),
                            "original_record": json.dumps(original),
                            "source_table": self.source_table,
                            "error_type": rule.get("error_type", "VALIDATION_ERR"),
                            "error_message": f"Failed validation: {rule['name']}",
                            "error_timestamp": datetime.now(),
                            "batch_id": batch_id,
                            "retry_count": 0,
                            "status": "pending",
                            "resolved_timestamp": None,
                            "resolved_by": None
                        })
                        break

            self.dlq.write_errors_batch(errors)

        return {
            "batch_id": batch_id,
            "total_records": source_df.count(),
            "valid": valid_count,
            "invalid": invalid_count
        }
```

## Retry Processor

```python
class DLQRetryProcessor:
    """Process DLQ retries."""

    def __init__(
        self,
        spark: SparkSession,
        dlq_manager: DLQManager,
        target_table: str
    ):
        self.spark = spark
        self.dlq = dlq_manager
        self.target_table = target_table

    def process_retries(
        self,
        transform_func: Callable[[Dict], Dict]
    ) -> Dict:
        """
        Process retry candidates from DLQ.

        Args:
            transform_func: Transformation function to apply

        Returns:
            Retry statistics
        """
        candidates = self.dlq.get_retry_candidates()
        candidate_count = candidates.count()

        if candidate_count == 0:
            return {"candidates": 0, "succeeded": 0, "failed": 0}

        succeeded = []
        failed = []

        for row in candidates.collect():
            error_id = row["error_id"]
            try:
                original = json.loads(row["original_record"])
                transformed = transform_func(original)
                succeeded.append((error_id, transformed))
            except Exception as e:
                failed.append(error_id)

        # Write successful retries
        if succeeded:
            success_records = [t[1] for t in succeeded]
            success_ids = [t[0] for t in succeeded]

            self.spark.createDataFrame(success_records) \
                .write.mode("append").saveAsTable(self.target_table)

            self.dlq.mark_resolved(success_ids, resolved_by="retry_processor")

        # Update failed retry counts
        if failed:
            self.dlq.increment_retry(failed)

        return {
            "candidates": candidate_count,
            "succeeded": len(succeeded),
            "failed": len(failed)
        }
```

## Usage Example

```python
# Initialize
spark = SparkSession.builder.getOrCreate()

config = DLQConfig(
    dlq_table="audit.dlq_errors",
    max_retries=3,
    retry_delay_minutes=5
)

dlq_manager = DLQManager(spark, config)

# Process with validation
processor = DLQProcessor(
    spark=spark,
    dlq_manager=dlq_manager,
    source_table="bronze.orders",
    target_table="silver.orders"
)

validation_rules = [
    {"name": "not_null_id", "condition": "order_id IS NOT NULL", "error_type": "NULL_ERR"},
    {"name": "positive_amount", "condition": "amount >= 0", "error_type": "RANGE_ERR"},
    {"name": "valid_date", "condition": "order_date <= CURRENT_DATE()", "error_type": "RANGE_ERR"}
]

source_df = spark.table("bronze.orders")
result = processor.process_with_validation(source_df, validation_rules)

print(f"Processed: {result['total_records']}, Valid: {result['valid']}, Invalid: {result['invalid']}")

# Process retries
retry_processor = DLQRetryProcessor(spark, dlq_manager, "silver.orders")
retry_result = retry_processor.process_retries(transform_func=lambda x: x)

print(f"Retries: {retry_result['succeeded']} succeeded, {retry_result['failed']} failed")

# Get summary
summary = dlq_manager.get_summary()
print(f"DLQ Status: {summary['total_pending']} pending, {summary['total_failed']} failed")
```

## Error Classification Helper

```python
def classify_error(exception: Exception) -> str:
    """Classify exception into error type."""
    msg = str(exception).lower()

    if any(kw in msg for kw in ["parse", "json", "decode"]):
        return "PARSE_ERR"
    elif any(kw in msg for kw in ["schema", "column", "field"]):
        return "SCHEMA_ERR"
    elif any(kw in msg for kw in ["null", "none"]):
        return "NULL_ERR"
    elif any(kw in msg for kw in ["range", "bound", "negative"]):
        return "RANGE_ERR"
    elif any(kw in msg for kw in ["foreign", "reference"]):
        return "FK_ERR"
    elif any(kw in msg for kw in ["timeout"]):
        return "TIMEOUT_ERR"
    elif any(kw in msg for kw in ["rate", "throttl"]):
        return "RATE_LIMIT"
    elif any(kw in msg for kw in ["auth", "permission"]):
        return "AUTH_ERR"
    else:
        return "UNKNOWN"
```

## DLQ Alert Functions

```python
import requests

def send_dlq_alert(alerts: list, webhook_url: str = None):
    """
    Send DLQ alerts to configured channel.

    Args:
        alerts: List of {"severity": str, "message": str} dicts
        webhook_url: Teams or Slack incoming webhook URL. If None, logs to console.
    """
    if not alerts:
        return

    critical = [a for a in alerts if a["severity"] == "critical"]
    high     = [a for a in alerts if a["severity"] == "high"]
    other    = [a for a in alerts if a["severity"] not in ("critical", "high")]

    lines = ["**DLQ Alert**"]
    for a in critical + high + other:
        lines.append(f"[{a['severity'].upper()}] {a['message']}")

    message = "\n".join(lines)

    if webhook_url:
        # Works for Teams (text) and Slack (text)
        payload = {"text": message}
        try:
            resp = requests.post(webhook_url, json=payload, timeout=10)
            resp.raise_for_status()
        except Exception as e:
            print(f"Failed to send DLQ alert to webhook: {e}")
            print(message)
    else:
        print(message)


def alert_on_new_dlq_rows(batch_result: dict, webhook_url: str = None):
    """
    Fire an immediate alert if the current batch wrote any rows to DLQ.
    Call this right after process_batch() or process_with_validation() returns.

    Args:
        batch_result: Dict returned by DLQProcessor.process_batch/process_with_validation
        webhook_url: Notification channel webhook
    """
    failed = batch_result.get("failed", batch_result.get("invalid", 0))
    if failed > 0:
        send_dlq_alert([{
            "severity": "high",
            "message": (
                f"{failed} new rows written to DLQ "
                f"(batch: {batch_result.get('batch_id', 'unknown')})"
            )
        }], webhook_url)
```

## Retry Pipeline Template

Drop this alongside your main pipeline notebook and schedule it to run after.

```python
# retry_pipeline.py  (or a Fabric/Databricks notebook cell)
from pyspark.sql import SparkSession

# ---- Configuration (set per pipeline) ----------------------------------------
DLQ_TABLE           = "audit.dlq_errors"   # same table written by main pipeline
TARGET_TABLE        = "silver.orders"      # table to write recovered records into
MAX_RETRIES         = 3
RETRY_DELAY_MINUTES = 5                    # base backoff; actual = DELAY * 2^retry_count
ALERT_WEBHOOK_URL   = None                 # Set to Teams/Slack webhook URL
# -------------------------------------------------------------------------------

spark = SparkSession.builder.getOrCreate()

config = DLQConfig(
    dlq_table=DLQ_TABLE,
    max_retries=MAX_RETRIES,
    retry_delay_minutes=RETRY_DELAY_MINUTES
)

dlq_manager     = DLQManager(spark, config)
retry_processor = DLQRetryProcessor(spark, dlq_manager, TARGET_TABLE)


def transform_func(record: dict) -> dict:
    """
    Re-apply the same transformation as the main pipeline.
    Paste the transform logic from the main pipeline here.
    """
    # TODO: paste transform logic from main pipeline
    return record


# 1. Process retries
result = retry_processor.process_retries(transform_func)
print(f"DLQ retry: {result['succeeded']} recovered, {result['failed']} still failing, {result['candidates']} candidates")

# 2. Threshold-based alerts (cumulative state)
threshold_alerts = check_dlq_alerts(spark, DLQ_TABLE)
send_dlq_alert(threshold_alerts, ALERT_WEBHOOK_URL)

# 3. Summary
summary = dlq_manager.get_summary()
print(f"DLQ totals: {summary['total_pending']} pending, {summary['total_failed']} permanently failed")
```

### Wiring into orchestration

```
[Main Ingestion Notebook]   -> on error: writes to DLQ, calls alert_on_new_dlq_rows()
         |
         v  (runs unconditionally)
[DLQ Retry Notebook]        -> retries recoverable rows, sends threshold alerts
```
