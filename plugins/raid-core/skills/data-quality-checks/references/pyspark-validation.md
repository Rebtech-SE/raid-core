# PySpark Validation Library

Comprehensive validation functions for data quality in PySpark.

## Core Validation Framework

```python
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import *
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional
from enum import Enum
from datetime import datetime, timedelta

class Severity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"

@dataclass
class ValidationResult:
    name: str
    check_type: str
    severity: Severity
    passed: bool
    total_rows: int
    failed_rows: int
    pass_rate: float
    details: Dict[str, Any] = field(default_factory=dict)
    sample_failures: List[Dict] = field(default_factory=list)

class DataValidator:
    """Comprehensive data validation for PySpark DataFrames."""

    def __init__(self, df: DataFrame, name: str = "dataset"):
        self.df = df
        self.name = name
        self.results: List[ValidationResult] = []
        self._total_rows = None

    @property
    def total_rows(self) -> int:
        if self._total_rows is None:
            self._total_rows = self.df.count()
        return self._total_rows

    def _add_result(self, result: ValidationResult):
        self.results.append(result)
        return self

    # ========== Completeness Checks ==========

    def check_not_null(
        self,
        columns: List[str],
        severity: Severity = Severity.HIGH
    ) -> 'DataValidator':
        """Check columns for null values."""
        for col in columns:
            null_count = self.df.filter(F.col(col).isNull()).count()
            pass_rate = (self.total_rows - null_count) / self.total_rows if self.total_rows > 0 else 0

            self._add_result(ValidationResult(
                name=f"not_null_{col}",
                check_type="completeness",
                severity=severity,
                passed=null_count == 0,
                total_rows=self.total_rows,
                failed_rows=null_count,
                pass_rate=pass_rate,
                details={"column": col}
            ))
        return self

    def check_completeness_threshold(
        self,
        column: str,
        threshold: float = 0.95,
        severity: Severity = Severity.MEDIUM
    ) -> 'DataValidator':
        """Check column meets minimum completeness threshold."""
        non_null = self.df.filter(F.col(column).isNotNull()).count()
        completeness = non_null / self.total_rows if self.total_rows > 0 else 0

        self._add_result(ValidationResult(
            name=f"completeness_{column}",
            check_type="completeness",
            severity=severity,
            passed=completeness >= threshold,
            total_rows=self.total_rows,
            failed_rows=self.total_rows - non_null,
            pass_rate=completeness,
            details={"column": column, "threshold": threshold, "actual": completeness}
        ))
        return self

    # ========== Uniqueness Checks ==========

    def check_unique(
        self,
        columns: List[str],
        severity: Severity = Severity.HIGH
    ) -> 'DataValidator':
        """Check columns are unique (no duplicates)."""
        distinct_count = self.df.select(*columns).distinct().count()
        duplicates = self.total_rows - distinct_count

        sample = []
        if duplicates > 0:
            sample = self.df.groupBy(*columns).count() \
                .filter(F.col("count") > 1) \
                .limit(5).collect()
            sample = [row.asDict() for row in sample]

        self._add_result(ValidationResult(
            name=f"unique_{'_'.join(columns)}",
            check_type="consistency",
            severity=severity,
            passed=duplicates == 0,
            total_rows=self.total_rows,
            failed_rows=duplicates,
            pass_rate=distinct_count / self.total_rows if self.total_rows > 0 else 0,
            details={"columns": columns, "distinct_count": distinct_count},
            sample_failures=sample
        ))
        return self

    # ========== Range Checks ==========

    def check_range(
        self,
        column: str,
        min_value: Optional[float] = None,
        max_value: Optional[float] = None,
        severity: Severity = Severity.MEDIUM
    ) -> 'DataValidator':
        """Check values are within specified range."""
        conditions = []
        if min_value is not None:
            conditions.append(F.col(column) >= min_value)
        if max_value is not None:
            conditions.append(F.col(column) <= max_value)

        if conditions:
            combined = conditions[0]
            for c in conditions[1:]:
                combined = combined & c
            valid_count = self.df.filter(combined | F.col(column).isNull()).count()
        else:
            valid_count = self.total_rows

        invalid_count = self.total_rows - valid_count

        self._add_result(ValidationResult(
            name=f"range_{column}",
            check_type="accuracy",
            severity=severity,
            passed=invalid_count == 0,
            total_rows=self.total_rows,
            failed_rows=invalid_count,
            pass_rate=valid_count / self.total_rows if self.total_rows > 0 else 0,
            details={"column": column, "min": min_value, "max": max_value}
        ))
        return self

    # ========== Value Set Checks ==========

    def check_values_in_set(
        self,
        column: str,
        allowed_values: List[Any],
        severity: Severity = Severity.MEDIUM
    ) -> 'DataValidator':
        """Check values are in allowed set."""
        invalid = self.df.filter(
            ~F.col(column).isin(allowed_values) & F.col(column).isNotNull()
        )
        invalid_count = invalid.count()

        sample = []
        if invalid_count > 0:
            sample = invalid.select(column).distinct().limit(10).collect()
            sample = [row.asDict() for row in sample]

        self._add_result(ValidationResult(
            name=f"values_in_set_{column}",
            check_type="validity",
            severity=severity,
            passed=invalid_count == 0,
            total_rows=self.total_rows,
            failed_rows=invalid_count,
            pass_rate=(self.total_rows - invalid_count) / self.total_rows if self.total_rows > 0 else 0,
            details={"column": column, "allowed_values": allowed_values},
            sample_failures=sample
        ))
        return self

    # ========== Pattern Checks ==========

    def check_pattern(
        self,
        column: str,
        pattern: str,
        description: str = None,
        severity: Severity = Severity.MEDIUM
    ) -> 'DataValidator':
        """Check values match regex pattern."""
        non_matching = self.df.filter(
            ~F.col(column).rlike(pattern) & F.col(column).isNotNull()
        )
        invalid_count = non_matching.count()

        sample = []
        if invalid_count > 0:
            sample = non_matching.select(column).distinct().limit(5).collect()
            sample = [row.asDict() for row in sample]

        self._add_result(ValidationResult(
            name=f"pattern_{column}",
            check_type="validity",
            severity=severity,
            passed=invalid_count == 0,
            total_rows=self.total_rows,
            failed_rows=invalid_count,
            pass_rate=(self.total_rows - invalid_count) / self.total_rows if self.total_rows > 0 else 0,
            details={"column": column, "pattern": pattern, "description": description},
            sample_failures=sample
        ))
        return self

    # ========== Referential Integrity ==========

    def check_foreign_key(
        self,
        fk_column: str,
        reference_df: DataFrame,
        ref_column: str,
        severity: Severity = Severity.HIGH
    ) -> 'DataValidator':
        """Check foreign key references exist."""
        ref_keys = reference_df.select(F.col(ref_column).alias("_ref")).distinct()

        orphans = self.df.join(
            ref_keys,
            F.col(fk_column) == F.col("_ref"),
            "left_anti"
        ).filter(F.col(fk_column).isNotNull())

        orphan_count = orphans.count()

        sample = []
        if orphan_count > 0:
            sample = orphans.select(fk_column).distinct().limit(10).collect()
            sample = [row.asDict() for row in sample]

        self._add_result(ValidationResult(
            name=f"fk_{fk_column}",
            check_type="consistency",
            severity=severity,
            passed=orphan_count == 0,
            total_rows=self.total_rows,
            failed_rows=orphan_count,
            pass_rate=(self.total_rows - orphan_count) / self.total_rows if self.total_rows > 0 else 0,
            details={"fk_column": fk_column, "ref_column": ref_column},
            sample_failures=sample
        ))
        return self

    # ========== Freshness Checks ==========

    def check_freshness(
        self,
        timestamp_column: str,
        max_age_hours: int = 24,
        severity: Severity = Severity.HIGH
    ) -> 'DataValidator':
        """Check data is fresh (within max age)."""
        max_ts = self.df.agg(F.max(timestamp_column)).collect()[0][0]
        cutoff = datetime.now() - timedelta(hours=max_age_hours)

        is_fresh = max_ts >= cutoff if max_ts else False
        hours_old = (datetime.now() - max_ts).total_seconds() / 3600 if max_ts else None

        self._add_result(ValidationResult(
            name=f"freshness_{timestamp_column}",
            check_type="timeliness",
            severity=severity,
            passed=is_fresh,
            total_rows=self.total_rows,
            failed_rows=0 if is_fresh else self.total_rows,
            pass_rate=1.0 if is_fresh else 0.0,
            details={
                "column": timestamp_column,
                "max_timestamp": str(max_ts),
                "max_age_hours": max_age_hours,
                "actual_hours_old": hours_old
            }
        ))
        return self

    # ========== Custom Rule Checks ==========

    def check_expression(
        self,
        name: str,
        expression: str,
        severity: Severity = Severity.MEDIUM
    ) -> 'DataValidator':
        """Check custom SQL expression."""
        violations = self.df.filter(~F.expr(expression))
        violation_count = violations.count()

        sample = []
        if violation_count > 0:
            sample = violations.limit(5).collect()
            sample = [row.asDict() for row in sample]

        self._add_result(ValidationResult(
            name=name,
            check_type="business_rule",
            severity=severity,
            passed=violation_count == 0,
            total_rows=self.total_rows,
            failed_rows=violation_count,
            pass_rate=(self.total_rows - violation_count) / self.total_rows if self.total_rows > 0 else 0,
            details={"expression": expression},
            sample_failures=sample
        ))
        return self

    # ========== Results ==========

    def get_results(self) -> List[ValidationResult]:
        return self.results

    def get_summary(self) -> Dict[str, Any]:
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed

        by_severity = {}
        for sev in Severity:
            sev_results = [r for r in self.results if r.severity == sev]
            by_severity[sev.value] = {
                "total": len(sev_results),
                "passed": sum(1 for r in sev_results if r.passed),
                "failed": sum(1 for r in sev_results if not r.passed)
            }

        critical_failures = by_severity.get("critical", {}).get("failed", 0)

        return {
            "dataset": self.name,
            "total_rows": self.total_rows,
            "total_checks": total,
            "passed": passed,
            "failed": failed,
            "pass_rate": passed / total if total > 0 else 0,
            "critical_failures": critical_failures,
            "by_severity": by_severity,
            "overall_status": "PASS" if critical_failures == 0 else "FAIL"
        }

    def print_report(self):
        """Print formatted validation report."""
        summary = self.get_summary()

        print("\n" + "=" * 70)
        print(f"DATA QUALITY REPORT: {summary['dataset']}")
        print("=" * 70)
        print(f"Total Rows: {summary['total_rows']:,}")
        print(f"Checks: {summary['passed']}/{summary['total_checks']} passed ({summary['pass_rate']:.1%})")
        print(f"Status: {summary['overall_status']}")
        print("-" * 70)

        for result in self.results:
            status = "PASS" if result.passed else "FAIL"
            print(f"[{status}] {result.name} ({result.severity.value})")
            if not result.passed:
                print(f"       Failed: {result.failed_rows:,} rows ({1 - result.pass_rate:.1%})")
                if result.sample_failures:
                    print(f"       Sample: {result.sample_failures[:3]}")

        print("=" * 70)
```

## Usage Example

```python
# Create validator
validator = DataValidator(df, "customers")

# Chain validation checks
validator \
    .check_not_null(["customer_id", "email"], Severity.CRITICAL) \
    .check_unique(["customer_id"], Severity.CRITICAL) \
    .check_pattern("email", r"^[^@]+@[^@]+\.[^@]+$", "Email format") \
    .check_values_in_set("status", ["active", "inactive", "pending"]) \
    .check_range("age", min_value=0, max_value=150) \
    .check_freshness("updated_at", max_age_hours=24) \
    .check_expression("positive_balance", "balance >= 0")

# Get results
validator.print_report()
summary = validator.get_summary()

# Fail pipeline if critical checks fail
if summary["critical_failures"] > 0:
    raise Exception(f"Data quality validation failed: {summary['critical_failures']} critical failures")
```

## Common Patterns

```python
# Email pattern
EMAIL_PATTERN = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

# Phone patterns
PHONE_US = r"^(\+1)?[0-9]{10}$"
PHONE_INTERNATIONAL = r"^\+?[0-9]{10,15}$"

# ID patterns
UUID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
NUMERIC_ID = r"^[0-9]+$"

# Date patterns
ISO_DATE = r"^\d{4}-\d{2}-\d{2}$"
US_DATE = r"^\d{2}/\d{2}/\d{4}$"

# Postal codes
US_ZIP = r"^\d{5}(-\d{4})?$"
UK_POSTCODE = r"^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$"
```
