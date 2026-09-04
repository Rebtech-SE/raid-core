# SCD Testing Patterns

Comprehensive testing strategies for validating SCD implementations.

## Core SCD Type 2 Constraints

Every SCD Type 2 table must satisfy these constraints:

1. **Single current record per business key**: Only one `_is_current = true` per key
1. **No overlapping validity periods**: Date ranges don't overlap for same key
1. **No gaps in history**: Validity periods are contiguous (optional)
1. **Valid date ranges**: `_valid_from <= _valid_to`
1. **Current records have open end date**: `_is_current = true` implies `_valid_to = '9999-12-31'`
1. **Hash consistency**: `_hash` matches computed value from tracked columns

## dbt Tests

### Schema Tests

```yaml
# models/marts/schema.yml
version: 2

models:
  - name: dim_customer
    description: Customer dimension with SCD Type 2 history
    tests:
      # Only one current record per business key
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - customer_id
          where: "_is_current = true"

      # No overlapping validity periods
      - no_overlapping_periods:
          partition_by: customer_id
          valid_from: _valid_from
          valid_to: _valid_to

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

      - name: _valid_from
        tests:
          - not_null

      - name: _valid_to
        tests:
          - not_null
          # Current records must have end date 9999-12-31
          - accepted_values:
              values: ['9999-12-31']
              where: "_is_current = true"

      - name: _is_current
        tests:
          - not_null
          - accepted_values:
              values: [true, false]

      - name: _hash
        tests:
          - not_null
```

### Custom Test: No Overlapping Periods

```sql
-- tests/generic/no_overlapping_periods.sql
{% test no_overlapping_periods(model, partition_by, valid_from, valid_to) %}

WITH ordered AS (
    SELECT
        {{ partition_by }},
        {{ valid_from }},
        {{ valid_to }},
        LEAD({{ valid_from }}) OVER (
            PARTITION BY {{ partition_by }}
            ORDER BY {{ valid_from }}
        ) AS next_valid_from
    FROM {{ model }}
),

overlaps AS (
    SELECT *
    FROM ordered
    WHERE {{ valid_to }} >= next_valid_from
)

SELECT * FROM overlaps

{% endtest %}
```

### Custom Test: Hash Consistency

```sql
-- tests/generic/hash_consistency.sql
{% test hash_consistency(model, hash_column, source_columns) %}

{%- set hash_expr = dbt_utils.generate_surrogate_key(source_columns) -%}

SELECT
    *,
    {{ hash_expr }} AS computed_hash
FROM {{ model }}
WHERE {{ hash_column }} != {{ hash_expr }}

{% endtest %}
```

Usage:

```yaml
models:
  - name: dim_customer
    tests:
      - hash_consistency:
          hash_column: _hash
          source_columns: ['customer_name', 'email', 'address', 'status']
```

### Custom Test: Valid Date Ranges

```sql
-- tests/generic/valid_date_ranges.sql
{% test valid_date_ranges(model, valid_from, valid_to) %}

SELECT *
FROM {{ model }}
WHERE {{ valid_from }} > {{ valid_to }}

{% endtest %}
```

### Snapshot-Specific Tests

```sql
-- tests/snapshot_integrity.sql
-- Verify snapshot has expected columns and values

SELECT *
FROM {{ ref('customers_snapshot') }}
WHERE dbt_valid_from IS NULL
   OR (dbt_valid_to IS NULL AND dbt_scd_id NOT IN (
       SELECT dbt_scd_id
       FROM {{ ref('customers_snapshot') }}
       WHERE dbt_valid_to IS NULL
       GROUP BY customer_id
       HAVING COUNT(*) = 1
   ))
```

## PySpark Tests

### Complete Test Suite

```python
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from typing import List, Dict
from dataclasses import dataclass

@dataclass
class SCDTestResult:
    test_name: str
    passed: bool
    error_count: int
    error_message: str = ""
    sample_errors: List[dict] = None

def test_scd2_table(
    spark: SparkSession,
    table_name: str,
    business_key: str,
    tracked_columns: List[str],
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to",
    is_current_col: str = "_is_current",
    hash_col: str = "_hash",
    end_date: str = "9999-12-31"
) -> List[SCDTestResult]:
    """
    Run comprehensive SCD Type 2 validation tests.

    Returns list of test results.
    """
    df = spark.table(table_name)
    results = []

    # Test 1: Single current record per business key
    current_counts = df.filter(F.col(is_current_col) == True) \
        .groupBy(business_key) \
        .count() \
        .filter(F.col("count") > 1)

    error_count = current_counts.count()
    results.append(SCDTestResult(
        test_name="single_current_per_key",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} business keys with multiple current records",
        sample_errors=current_counts.limit(5).collect() if error_count > 0 else None
    ))

    # Test 2: Valid date ranges (_valid_from <= _valid_to)
    invalid_ranges = df.filter(F.col(valid_from_col) > F.col(valid_to_col))
    error_count = invalid_ranges.count()
    results.append(SCDTestResult(
        test_name="valid_date_ranges",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} records with invalid date ranges"
    ))

    # Test 3: Current records have correct end date
    bad_current = df.filter(
        (F.col(is_current_col) == True) &
        (F.col(valid_to_col) != F.to_date(F.lit(end_date)))
    )
    error_count = bad_current.count()
    results.append(SCDTestResult(
        test_name="current_has_open_end_date",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} current records without {end_date} end date"
    ))

    # Test 4: No overlapping periods
    window = Window.partitionBy(business_key).orderBy(valid_from_col)
    with_next = df.withColumn(
        "_next_valid_from",
        F.lead(valid_from_col).over(window)
    )
    overlaps = with_next.filter(
        F.col(valid_to_col) >= F.col("_next_valid_from")
    )
    error_count = overlaps.count()
    results.append(SCDTestResult(
        test_name="no_overlapping_periods",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} overlapping validity periods"
    ))

    # Test 5: Hash consistency
    hash_expr = F.md5(
        F.concat_ws("||", *[F.coalesce(F.col(c).cast("string"), F.lit("")) for c in tracked_columns])
    )
    hash_mismatches = df.filter(F.col(hash_col) != hash_expr)
    error_count = hash_mismatches.count()
    results.append(SCDTestResult(
        test_name="hash_consistency",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} records with inconsistent hash"
    ))

    # Test 6: No null business keys
    null_keys = df.filter(F.col(business_key).isNull())
    error_count = null_keys.count()
    results.append(SCDTestResult(
        test_name="no_null_business_keys",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} records with null business key"
    ))

    # Test 7: No null dates
    null_dates = df.filter(
        F.col(valid_from_col).isNull() | F.col(valid_to_col).isNull()
    )
    error_count = null_dates.count()
    results.append(SCDTestResult(
        test_name="no_null_dates",
        passed=error_count == 0,
        error_count=error_count,
        error_message=f"Found {error_count} records with null validity dates"
    ))

    return results

def print_test_results(results: List[SCDTestResult]):
    """Print formatted test results."""
    print("\n" + "=" * 60)
    print("SCD Type 2 Validation Results")
    print("=" * 60)

    passed = sum(1 for r in results if r.passed)
    total = len(results)

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"\n[{status}] {result.test_name}")
        if not result.passed:
            print(f"       {result.error_message}")
            if result.sample_errors:
                print(f"       Sample errors: {result.sample_errors[:3]}")

    print("\n" + "-" * 60)
    print(f"Total: {passed}/{total} tests passed")
    print("=" * 60)

# Usage
results = test_scd2_table(
    spark=spark,
    table_name="gold.dim_customer",
    business_key="customer_id",
    tracked_columns=["customer_name", "email", "address", "status"]
)
print_test_results(results)
```

### Test Helper Functions

```python
def assert_single_current_per_key(
    df: DataFrame,
    business_key: str,
    is_current_col: str = "_is_current"
) -> bool:
    """Assert only one current record per business key."""
    duplicates = df.filter(F.col(is_current_col) == True) \
        .groupBy(business_key) \
        .count() \
        .filter(F.col("count") > 1)
    return duplicates.count() == 0

def assert_no_overlapping_periods(
    df: DataFrame,
    business_key: str,
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to"
) -> bool:
    """Assert no overlapping validity periods."""
    window = Window.partitionBy(business_key).orderBy(valid_from_col)
    with_next = df.withColumn(
        "_next_from",
        F.lead(valid_from_col).over(window)
    )
    overlaps = with_next.filter(F.col(valid_to_col) >= F.col("_next_from"))
    return overlaps.count() == 0

def assert_contiguous_history(
    df: DataFrame,
    business_key: str,
    valid_from_col: str = "_valid_from",
    valid_to_col: str = "_valid_to"
) -> bool:
    """Assert validity periods are contiguous (no gaps)."""
    window = Window.partitionBy(business_key).orderBy(valid_from_col)
    with_next = df.withColumn(
        "_next_from",
        F.lead(valid_from_col).over(window)
    )
    gaps = with_next.filter(
        F.col("_next_from").isNotNull() &
        (F.date_add(F.col(valid_to_col), 1) != F.col("_next_from"))
    )
    return gaps.count() == 0
```

## Data Quality Checks for SCD

### Pre-Load Validation

```python
def validate_source_for_scd(
    source_df: DataFrame,
    business_key: str,
    tracked_columns: List[str]
) -> Dict[str, bool]:
    """Validate source data before SCD processing."""
    checks = {}

    # Check 1: Business key not null
    null_keys = source_df.filter(F.col(business_key).isNull()).count()
    checks["business_key_not_null"] = null_keys == 0

    # Check 2: Business key unique (for point-in-time source)
    total = source_df.count()
    distinct = source_df.select(business_key).distinct().count()
    checks["business_key_unique"] = total == distinct

    # Check 3: No all-null tracked columns
    all_null_condition = F.lit(True)
    for col in tracked_columns:
        all_null_condition = all_null_condition & F.col(col).isNull()
    all_null_rows = source_df.filter(all_null_condition).count()
    checks["tracked_columns_not_all_null"] = all_null_rows == 0

    return checks
```

### Post-Load Validation

```python
def validate_scd_load(
    spark: SparkSession,
    table_name: str,
    business_key: str,
    expected_inserts: int = None,
    expected_updates: int = None
) -> Dict[str, bool]:
    """Validate SCD load completed correctly."""
    df = spark.table(table_name)
    checks = {}

    # Check table exists and has data
    checks["table_has_data"] = df.count() > 0

    # Check current records exist
    current_count = df.filter(F.col("_is_current") == True).count()
    checks["has_current_records"] = current_count > 0

    # If expected counts provided, validate them
    if expected_inserts is not None:
        # This would require tracking inserts during load
        pass

    return checks
```

## Regression Tests

### Test SCD Behavior with Known Data

```python
def test_scd2_insert_behavior(spark: SparkSession):
    """Test that new records are inserted correctly."""
    # Create test source data
    test_data = [("C001", "Alice", "alice@test.com")]
    source_df = spark.createDataFrame(test_data, ["customer_id", "name", "email"])

    # Apply SCD (to temp table)
    apply_scd_type2(
        spark=spark,
        source_df=source_df,
        target_table="test_dim_customer",
        business_key="customer_id",
        tracked_columns=["name", "email"]
    )

    # Verify
    result = spark.table("test_dim_customer")
    assert result.count() == 1, "Should have 1 record"
    assert result.filter(F.col("_is_current") == True).count() == 1, "Should be current"

    # Cleanup
    spark.sql("DROP TABLE IF EXISTS test_dim_customer")

def test_scd2_update_behavior(spark: SparkSession):
    """Test that updates create new versions and close old ones."""
    # Initial load
    initial_data = [("C001", "Alice", "alice@test.com")]
    source_df = spark.createDataFrame(initial_data, ["customer_id", "name", "email"])

    apply_scd_type2(
        spark=spark,
        source_df=source_df,
        target_table="test_dim_customer",
        business_key="customer_id",
        tracked_columns=["name", "email"]
    )

    # Update load
    updated_data = [("C001", "Alice Smith", "alice.smith@test.com")]
    source_df = spark.createDataFrame(updated_data, ["customer_id", "name", "email"])

    apply_scd_type2(
        spark=spark,
        source_df=source_df,
        target_table="test_dim_customer",
        business_key="customer_id",
        tracked_columns=["name", "email"]
    )

    # Verify
    result = spark.table("test_dim_customer")
    assert result.count() == 2, "Should have 2 versions"
    assert result.filter(F.col("_is_current") == True).count() == 1, "Only 1 current"
    assert result.filter(F.col("_is_current") == False).count() == 1, "1 historical"

    current = result.filter(F.col("_is_current") == True).first()
    assert current["name"] == "Alice Smith", "Current should have new name"

    # Cleanup
    spark.sql("DROP TABLE IF EXISTS test_dim_customer")
```

## Integration with CI/CD

### dbt Test in CI

```yaml
# .github/workflows/dbt-test.yml
name: dbt Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: pip install dbt-core dbt-snowflake dbt-utils

      - name: Run dbt tests
        run: |
          dbt deps
          dbt test --select dim_customer --target ci
```

### PySpark Test in CI

```python
# tests/test_scd.py
import pytest
from pyspark.sql import SparkSession

@pytest.fixture(scope="session")
def spark():
    return SparkSession.builder \
        .master("local[*]") \
        .appName("SCD Tests") \
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
        .getOrCreate()

def test_scd2_validation(spark):
    """Validate SCD Type 2 table constraints."""
    results = test_scd2_table(
        spark=spark,
        table_name="gold.dim_customer",
        business_key="customer_id",
        tracked_columns=["name", "email", "status"]
    )

    failed = [r for r in results if not r.passed]
    assert len(failed) == 0, f"Failed tests: {[r.test_name for r in failed]}"
```
