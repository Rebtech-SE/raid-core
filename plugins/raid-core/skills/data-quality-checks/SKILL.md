---
name: data-quality-checks
description: >-
  Use when implementing data quality rules, building quality dashboards, or setting up
  alerting. Triggers include 'data quality', 'validation rules', 'completeness check',
  'null check', 'duplicate detection', 'referential integrity', 'quality score', 'data
  validation'. Covers completeness, accuracy, consistency, timeliness and validity
  patterns across dbt-expectations, Great Expectations, and PySpark.
---

# Data Quality Checks

Comprehensive patterns for validating data quality across data platforms using dbt and PySpark.

## When to Use This Skill

Use this skill when users ask about:

- **Validation rules**: "How do I check for null values?"
- **Quality dimensions**: "What types of quality checks should I implement?"
- **dbt testing**: "How do I use dbt-expectations?"
- **Quality scoring**: "How do I calculate a data quality score?"
- **Alerting**: "How do I alert when data quality fails?"
- **Monitoring**: "How do I track quality trends over time?"

**Note**: This skill is **platform-agnostic**. For Microsoft Fabric-specific validation execution via the `fab` CLI and SQL endpoint, see `test-fabric-notebook` (raid-fabric). For error handling patterns, see [dead-letter-queue](../dead-letter-queue/SKILL.md).

## Data Quality Dimensions

The five core dimensions of data quality:

| Dimension | Description | Example Checks |
|-----------|-------------|----------------|
| **Completeness** | Data is not missing | Null checks, required fields |
| **Accuracy** | Data is correct | Range validation, pattern matching |
| **Consistency** | Data agrees across sources | Duplicate detection, referential integrity |
| **Timeliness** | Data is current | Freshness checks, SLA monitoring |
| **Validity** | Data conforms to rules | Format validation, business rules |

## Quick Decision Tree

```
What are you validating?
|
|-- Null/missing values?
|   |-> Completeness checks
|   |   - not_null test
|   |   - expect_column_values_to_not_be_null
|
|-- Value ranges or correctness?
|   |-> Accuracy checks
|   |   - accepted_values
|   |   - expect_column_values_to_be_between
|
|-- Duplicates or orphan records?
|   |-> Consistency checks
|   |   - unique
|   |   - relationships
|
|-- Data freshness?
|   |-> Timeliness checks
|   |   - freshness
|   |   - expect_column_max_to_be_between
|
|-- Format or pattern compliance?
    |-> Validity checks
        - expect_column_values_to_match_regex
        - custom business rules
```

## Severity Levels

Classify checks by business impact:

| Severity | Action | Example |
|----------|--------|---------|
| **Critical** | Block pipeline, alert immediately | Primary key null, negative amounts |
| **High** | Alert, investigate | Foreign key orphans, invalid dates |
| **Medium** | Log warning, queue for review | Missing optional fields |
| **Low** | Track metrics only | Minor format inconsistencies |

## Where DQ Checks Go: Gate vs Test

DQ checks serve two different jobs. Conflating them is the most common mistake in this skill's history (surfaced by the May 2026 bakeoff):

| Job | When it runs | Operates on | Failure action | Where it lives |
|---|---|---|---|---|
| **In-load gate** | Inside the production load notebook, before `saveAsTable` / `MERGE` / `INSERT` | The in-memory `DataFrame` about to be written | `raise` -- halt before write so the target is never corrupted | Same notebook as the transformation, after the transform, before the write |
| **Post-execution test** | After a notebook has run in a test/CI/sandbox context | The materialized table | Mark the test failed, alert | A separate test notebook or CI step (see `test-fabric-notebook` skill) |

### Anti-pattern: post-write DQ as a gate

Do NOT structure a production load like this:

```python
# WRONG: bad data is already in silver.products by the time the raise fires
df.write.mode("overwrite").saveAsTable("silver.products")
result = validator.validate_data_quality("silver.products", ...)
if not result.success:
    raise AssertionError(...)   # too late
```

If the assertion raises, `silver.products` is already overwritten with the bad data. Any downstream notebook scheduled before the pipeline-fail propagates will read corruption. The pipeline-level retry will re-run from a now-corrupt source.

### Correct: gate the DataFrame before write

```python
# RIGHT: cache once, assert on the DataFrame, write only if all checks pass
df = transform(raw).cache()
assert_not_null(df, ["product_id", "price"])
assert_unique(df, ["product_id"])
assert_predicate(df, F.col("price") >= 0, "non-negative price")
df.write.mode("overwrite").saveAsTable("silver.products")
df.unpersist()
```

`.cache()` matters -- every assertion triggers a Spark action, and you do not want to re-scan bronze for each check.

### Alternative: staging-table swap

If you need to validate against the materialized table (e.g., to use platform validators that take a table name, not a DataFrame):

```python
# Write to a staging table, validate, then swap into place atomically
df.write.mode("overwrite").saveAsTable("silver.products__staging")
result = validator.validate_data_quality("silver.products__staging", ...)
if not result.success:
    raise AssertionError(...)
spark.sql("DROP TABLE IF EXISTS silver.products")
spark.sql("ALTER TABLE silver.products__staging RENAME TO silver.products")
```

This preserves "validate the materialized artefact" semantics while keeping `silver.products` clean across runs.

### Fabric implementation

For the Fabric-specific implementation of the gate pattern -- including the recommended `validate_before_overwrite()` helper -- see the `fabric-architecture` skill (raid-fabric, Pre-Write Validation Gate).

## Completeness Checks

Verify data is not missing.

### dbt Implementation

```yaml
# schema.yml
models:
  - name: customers
    columns:
      - name: customer_id
        tests:
          - not_null
          - unique

      - name: email
        tests:
          - not_null:
              where: "status = 'active'"
```

```yaml
# Using dbt-expectations
      - name: customer_name
        tests:
          - dbt_expectations.expect_column_values_to_not_be_null:
              row_condition: "status = 'active'"
```

### PySpark Implementation

```python
from pyspark.sql import functions as F

def check_completeness(df, columns: list, threshold: float = 1.0):
    """
    Check completeness for specified columns.

    Args:
        df: DataFrame to check
        columns: List of columns to validate
        threshold: Minimum required completeness (0.0 to 1.0)

    Returns:
        dict with completeness metrics per column
    """
    total_rows = df.count()
    results = {}

    for col in columns:
        non_null_count = df.filter(F.col(col).isNotNull()).count()
        completeness = non_null_count / total_rows if total_rows > 0 else 0

        results[col] = {
            "total_rows": total_rows,
            "non_null_count": non_null_count,
            "null_count": total_rows - non_null_count,
            "completeness": completeness,
            "passed": completeness >= threshold
        }

    return results

# Usage
results = check_completeness(df, ["customer_id", "email", "phone"], threshold=0.99)
for col, metrics in results.items():
    print(f"{col}: {metrics['completeness']:.2%} complete - {'PASS' if metrics['passed'] else 'FAIL'}")
```

## Accuracy Checks

Verify data values are correct.

### dbt Implementation

```yaml
# Accepted values
columns:
  - name: status
    tests:
      - accepted_values:
          values: ['active', 'inactive', 'pending', 'closed']

  - name: country_code
    tests:
      - accepted_values:
          values: ['US', 'CA', 'UK', 'DE', 'FR']
          quote: true
```

```yaml
# Range validation with dbt-expectations
columns:
  - name: amount
    tests:
      - dbt_expectations.expect_column_values_to_be_between:
          min_value: 0
          max_value: 1000000
          strictly: false

  - name: discount_percent
    tests:
      - dbt_expectations.expect_column_values_to_be_between:
          min_value: 0
          max_value: 100
```

### PySpark Implementation

```python
def check_value_range(df, column: str, min_val=None, max_val=None, allowed_values=None):
    """Check if values fall within expected range or set."""
    total = df.count()

    if allowed_values:
        invalid = df.filter(~F.col(column).isin(allowed_values))
    else:
        conditions = []
        if min_val is not None:
            conditions.append(F.col(column) < min_val)
        if max_val is not None:
            conditions.append(F.col(column) > max_val)

        if conditions:
            invalid = df.filter(F.reduce(lambda a, b: a | b, conditions))
        else:
            invalid = df.filter(F.lit(False))

    invalid_count = invalid.count()

    return {
        "total": total,
        "invalid_count": invalid_count,
        "valid_percent": (total - invalid_count) / total if total > 0 else 0,
        "passed": invalid_count == 0,
        "sample_invalid": invalid.limit(5).collect() if invalid_count > 0 else []
    }

# Usage
result = check_value_range(df, "amount", min_val=0, max_val=1000000)
result = check_value_range(df, "status", allowed_values=["active", "inactive", "pending"])
```

## Consistency Checks

Verify data agrees and doesn't conflict.

### Duplicate Detection

```yaml
# dbt - Unique check
columns:
  - name: order_id
    tests:
      - unique

# Unique combination
tests:
  - dbt_utils.unique_combination_of_columns:
      combination_of_columns:
        - customer_id
        - order_date
        - product_id
```

```python
# PySpark - Duplicate detection
def check_duplicates(df, key_columns: list):
    """Check for duplicate records on key columns."""
    total = df.count()
    distinct = df.select(*key_columns).distinct().count()
    duplicates = total - distinct

    # Get sample duplicates
    if duplicates > 0:
        dupe_keys = df.groupBy(*key_columns).count() \
            .filter(F.col("count") > 1) \
            .limit(10)
    else:
        dupe_keys = None

    return {
        "total_rows": total,
        "distinct_keys": distinct,
        "duplicate_rows": duplicates,
        "duplicate_percent": duplicates / total if total > 0 else 0,
        "passed": duplicates == 0,
        "sample_duplicates": dupe_keys.collect() if dupe_keys else []
    }

# Usage
result = check_duplicates(df, ["customer_id", "order_date"])
```

### Referential Integrity

```yaml
# dbt - Foreign key validation
columns:
  - name: customer_id
    tests:
      - relationships:
          to: ref('dim_customer')
          field: customer_id
          where: "is_current = true"
```

```python
# PySpark - Orphan detection
def check_referential_integrity(
    df,
    fk_column: str,
    reference_df,
    ref_column: str
):
    """Check if all FK values exist in reference table."""
    ref_keys = reference_df.select(F.col(ref_column).alias("_ref_key")).distinct()

    orphans = df.join(
        ref_keys,
        F.col(fk_column) == F.col("_ref_key"),
        "left_anti"
    )

    orphan_count = orphans.count()
    total = df.count()

    return {
        "total_records": total,
        "orphan_records": orphan_count,
        "integrity_percent": (total - orphan_count) / total if total > 0 else 0,
        "passed": orphan_count == 0,
        "sample_orphans": orphans.select(fk_column).distinct().limit(10).collect()
    }

# Usage
result = check_referential_integrity(
    orders_df, "customer_id",
    customers_df.filter(F.col("is_current")), "customer_id"
)
```

**Detecting orphans is only half the job -- route them.** A referential-integrity
check that returns a count and stops leaves the failing rows nowhere: they are either
silently dropped by the next inner join, or they block the load with no record of
which rows were at fault. Failed rows go to the dead-letter queue with the reason
attached, classified `FK_ERR` -- see [dead-letter-queue](../dead-letter-queue/SKILL.md)
for the taxonomy and the recovery path. FK violations are often *recoverable*: a
late-arriving parent makes the row loadable on a later run, which is exactly why the
row must be kept rather than discarded.

```python
# Route orphans to the DLQ instead of dropping or failing on them
orphans = df.join(ref_keys, F.col(fk_column) == F.col("_ref_key"), "left_anti")

write_to_dlq(
    orphans,
    error_type="FK_ERR",
    error_detail=f"{fk_column} not found in {ref_table}",
    source_table=source_table,
    batch_id=batch_id,
)

clean = df.join(ref_keys, F.col(fk_column) == F.col("_ref_key"), "left_semi")
```

```yaml
# dbt - persist failing rows instead of only failing the run.
# store_failures writes each test's failing rows to a table in the DLQ schema,
# so the test name itself records why the row was rejected.
data_tests:
  <project_name>:
    +store_failures: true
    +schema: dlq
```

Either mechanism satisfies the usual requirement that a record failing validation is
**quarantined with its reason recorded**, rather than dropped or left to break the
load. Pick one per project and apply it consistently -- a pipeline where some checks
quarantine and others silently drop is worse than either, because the row counts stop
meaning anything.

## Timeliness Checks

Verify data is current and fresh.

### dbt Implementation

```yaml
# Source freshness
sources:
  - name: raw_data
    tables:
      - name: orders
        loaded_at_field: _ingestion_timestamp
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
```

```yaml
# Column-level freshness with dbt-expectations
columns:
  - name: updated_at
    tests:
      - dbt_expectations.expect_column_max_to_be_between:
          min_value: "{{ modules.datetime.datetime.now() - modules.datetime.timedelta(hours=24) }}"
          row_condition: "status = 'active'"
```

### PySpark Implementation

```python
from datetime import datetime, timedelta

def check_freshness(df, timestamp_column: str, max_age_hours: int = 24):
    """Check if data is fresh (within max age)."""
    cutoff = datetime.now() - timedelta(hours=max_age_hours)

    max_timestamp = df.agg(F.max(timestamp_column)).collect()[0][0]
    min_timestamp = df.agg(F.min(timestamp_column)).collect()[0][0]

    is_fresh = max_timestamp >= cutoff if max_timestamp else False
    hours_since_last = (datetime.now() - max_timestamp).total_seconds() / 3600 if max_timestamp else None

    return {
        "max_timestamp": max_timestamp,
        "min_timestamp": min_timestamp,
        "cutoff_timestamp": cutoff,
        "hours_since_last": hours_since_last,
        "is_fresh": is_fresh,
        "passed": is_fresh
    }

# Usage
result = check_freshness(df, "updated_at", max_age_hours=24)
```

## Validity Checks

Verify data conforms to expected formats and rules.

### Pattern Matching

```yaml
# dbt-expectations regex validation
columns:
  - name: email
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

  - name: phone
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^[0-9]{10,15}$"
          row_condition: "phone IS NOT NULL"

  - name: postal_code
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^[0-9]{5}(-[0-9]{4})?$"
          row_condition: "country = 'US'"
```

```python
# PySpark pattern validation
def check_pattern(df, column: str, pattern: str, description: str = None):
    """Check if values match regex pattern."""
    total = df.count()
    matching = df.filter(F.col(column).rlike(pattern)).count()
    non_matching = total - matching

    return {
        "column": column,
        "pattern": pattern,
        "description": description,
        "total": total,
        "matching": matching,
        "non_matching": non_matching,
        "match_percent": matching / total if total > 0 else 0,
        "passed": non_matching == 0
    }

# Common patterns
EMAIL_PATTERN = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
PHONE_PATTERN = r"^[0-9]{10,15}$"
US_ZIP_PATTERN = r"^[0-9]{5}(-[0-9]{4})?$"
UUID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

# Usage
result = check_pattern(df, "email", EMAIL_PATTERN, "Email format validation")
```

### Business Rules

```python
# PySpark - Custom business rule validation
def check_business_rules(df, rules: list):
    """
    Validate custom business rules.

    rules: [
        {"name": "positive_amount", "condition": "amount > 0", "severity": "critical"},
        {"name": "valid_date_range", "condition": "end_date >= start_date", "severity": "high"}
    ]
    """
    results = []
    total = df.count()

    for rule in rules:
        # Count violations
        violations = df.filter(~F.expr(rule["condition"]))
        violation_count = violations.count()

        results.append({
            "rule_name": rule["name"],
            "condition": rule["condition"],
            "severity": rule["severity"],
            "total_rows": total,
            "violation_count": violation_count,
            "compliance_percent": (total - violation_count) / total if total > 0 else 0,
            "passed": violation_count == 0,
            "sample_violations": violations.limit(5).collect() if violation_count > 0 else []
        })

    return results

# Usage
rules = [
    {"name": "positive_amount", "condition": "amount > 0", "severity": "critical"},
    {"name": "valid_discount", "condition": "discount_percent BETWEEN 0 AND 100", "severity": "high"},
    {"name": "future_ship_date", "condition": "ship_date >= order_date", "severity": "high"},
    {"name": "active_has_email", "condition": "status != 'active' OR email IS NOT NULL", "severity": "medium"}
]

results = check_business_rules(df, rules)
```

## Comprehensive Quality Framework

### Quality Check Suite

```python
from dataclasses import dataclass
from typing import List, Dict, Any
from enum import Enum

class Severity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"

@dataclass
class QualityCheckResult:
    check_name: str
    check_type: str
    severity: Severity
    passed: bool
    metric_value: float
    threshold: float
    details: Dict[str, Any]

class DataQualityChecker:
    def __init__(self, df):
        self.df = df
        self.results: List[QualityCheckResult] = []

    def check_not_null(self, column: str, severity: Severity = Severity.HIGH):
        """Check column for null values."""
        total = self.df.count()
        nulls = self.df.filter(F.col(column).isNull()).count()
        completeness = (total - nulls) / total if total > 0 else 0

        self.results.append(QualityCheckResult(
            check_name=f"not_null_{column}",
            check_type="completeness",
            severity=severity,
            passed=nulls == 0,
            metric_value=completeness,
            threshold=1.0,
            details={"null_count": nulls, "total_rows": total}
        ))
        return self

    def check_unique(self, columns: List[str], severity: Severity = Severity.HIGH):
        """Check for duplicate values."""
        total = self.df.count()
        distinct = self.df.select(*columns).distinct().count()
        uniqueness = distinct / total if total > 0 else 0

        self.results.append(QualityCheckResult(
            check_name=f"unique_{'_'.join(columns)}",
            check_type="consistency",
            severity=severity,
            passed=total == distinct,
            metric_value=uniqueness,
            threshold=1.0,
            details={"total_rows": total, "distinct_rows": distinct}
        ))
        return self

    def check_range(self, column: str, min_val=None, max_val=None, severity: Severity = Severity.MEDIUM):
        """Check values are within range."""
        conditions = []
        if min_val is not None:
            conditions.append(F.col(column) >= min_val)
        if max_val is not None:
            conditions.append(F.col(column) <= max_val)

        if conditions:
            combined = conditions[0]
            for c in conditions[1:]:
                combined = combined & c
            valid = self.df.filter(combined).count()
        else:
            valid = self.df.count()

        total = self.df.count()
        validity = valid / total if total > 0 else 0

        self.results.append(QualityCheckResult(
            check_name=f"range_{column}",
            check_type="accuracy",
            severity=severity,
            passed=valid == total,
            metric_value=validity,
            threshold=1.0,
            details={"min": min_val, "max": max_val, "valid_count": valid}
        ))
        return self

    def get_results(self) -> List[QualityCheckResult]:
        return self.results

    def get_summary(self) -> Dict[str, Any]:
        total_checks = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total_checks - passed

        critical_failures = sum(1 for r in self.results if not r.passed and r.severity == Severity.CRITICAL)

        return {
            "total_checks": total_checks,
            "passed": passed,
            "failed": failed,
            "pass_rate": passed / total_checks if total_checks > 0 else 0,
            "critical_failures": critical_failures,
            "overall_passed": critical_failures == 0
        }

# Usage
checker = DataQualityChecker(df)
checker \
    .check_not_null("customer_id", Severity.CRITICAL) \
    .check_not_null("email", Severity.HIGH) \
    .check_unique(["order_id"], Severity.CRITICAL) \
    .check_range("amount", min_val=0, severity=Severity.HIGH)

summary = checker.get_summary()
print(f"Quality Check: {summary['passed']}/{summary['total_checks']} passed")
```

## Integration with Medallion Architecture

### Bronze Layer Checks

- Schema validation (required columns present)
- Basic type validation
- Corrupt record detection
- Source freshness

### Silver Layer Checks

- Completeness of key fields
- Referential integrity
- Deduplication validation
- SCD Type 2 constraints

### Gold Layer Checks

- Fact/dimension relationships
- Aggregate accuracy
- Business rule compliance
- KPI validation

## Related Skills

- [medallion-architecture](../medallion-architecture/SKILL.md) - Layer-specific quality checks
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Routing failed records
- [scd-pattern](../scd-pattern/SKILL.md) - SCD Type 2 validation

## References

- [dbt-expectations](references/dbt-expectations.md) - Complete dbt test catalog
- [PySpark Validation](references/pyspark-validation.md) - Validation function library
- [Quality Scoring](references/quality-scoring.md) - Score calculation and dashboards
- [Alerting Patterns](references/alerting-patterns.md) - Notification and escalation
