# Data Quality Scoring

Patterns for calculating, tracking, and reporting data quality scores.

## Quality Score Calculation

### Basic Scoring Model

```python
from dataclasses import dataclass
from typing import Dict, List
from enum import Enum

class QualityDimension(Enum):
    COMPLETENESS = "completeness"
    ACCURACY = "accuracy"
    CONSISTENCY = "consistency"
    TIMELINESS = "timeliness"
    VALIDITY = "validity"

@dataclass
class DimensionScore:
    dimension: QualityDimension
    score: float  # 0.0 to 1.0
    weight: float  # Weight in overall score
    checks_passed: int
    checks_total: int

class QualityScoreCalculator:
    """Calculate weighted quality scores."""

    DEFAULT_WEIGHTS = {
        QualityDimension.COMPLETENESS: 0.25,
        QualityDimension.ACCURACY: 0.25,
        QualityDimension.CONSISTENCY: 0.20,
        QualityDimension.TIMELINESS: 0.15,
        QualityDimension.VALIDITY: 0.15
    }

    def __init__(self, weights: Dict[QualityDimension, float] = None):
        self.weights = weights or self.DEFAULT_WEIGHTS
        self.dimension_scores: Dict[QualityDimension, DimensionScore] = {}

    def add_check_result(
        self,
        dimension: QualityDimension,
        passed: bool,
        score: float = None
    ):
        """Add a check result to dimension."""
        if dimension not in self.dimension_scores:
            self.dimension_scores[dimension] = DimensionScore(
                dimension=dimension,
                score=0.0,
                weight=self.weights.get(dimension, 0.1),
                checks_passed=0,
                checks_total=0
            )

        ds = self.dimension_scores[dimension]
        ds.checks_total += 1
        if passed:
            ds.checks_passed += 1

        # Update dimension score
        ds.score = ds.checks_passed / ds.checks_total if ds.checks_total > 0 else 0

    def calculate_overall_score(self) -> float:
        """Calculate weighted overall quality score."""
        if not self.dimension_scores:
            return 0.0

        weighted_sum = 0.0
        total_weight = 0.0

        for dim, ds in self.dimension_scores.items():
            weighted_sum += ds.score * ds.weight
            total_weight += ds.weight

        return weighted_sum / total_weight if total_weight > 0 else 0.0

    def get_grade(self, score: float = None) -> str:
        """Convert score to letter grade."""
        score = score or self.calculate_overall_score()

        if score >= 0.95:
            return "A"
        elif score >= 0.85:
            return "B"
        elif score >= 0.75:
            return "C"
        elif score >= 0.65:
            return "D"
        else:
            return "F"

    def get_report(self) -> Dict:
        """Generate quality score report."""
        overall = self.calculate_overall_score()

        return {
            "overall_score": overall,
            "overall_grade": self.get_grade(overall),
            "dimensions": {
                dim.value: {
                    "score": ds.score,
                    "grade": self.get_grade(ds.score),
                    "weight": ds.weight,
                    "checks_passed": ds.checks_passed,
                    "checks_total": ds.checks_total
                }
                for dim, ds in self.dimension_scores.items()
            }
        }
```

### Usage with DataValidator

```python
# Integrate scoring with validation
def calculate_quality_score(validator_results: List[ValidationResult]) -> Dict:
    """Calculate quality score from validation results."""

    # Map check types to dimensions
    type_to_dimension = {
        "completeness": QualityDimension.COMPLETENESS,
        "accuracy": QualityDimension.ACCURACY,
        "consistency": QualityDimension.CONSISTENCY,
        "timeliness": QualityDimension.TIMELINESS,
        "validity": QualityDimension.VALIDITY,
        "business_rule": QualityDimension.VALIDITY
    }

    calculator = QualityScoreCalculator()

    for result in validator_results:
        dimension = type_to_dimension.get(
            result.check_type,
            QualityDimension.VALIDITY
        )
        calculator.add_check_result(dimension, result.passed, result.pass_rate)

    return calculator.get_report()

# Usage
validator = DataValidator(df, "orders")
validator.check_not_null(["order_id"]).check_unique(["order_id"])

report = calculate_quality_score(validator.get_results())
print(f"Quality Score: {report['overall_score']:.1%} ({report['overall_grade']})")
```

## Quality Metrics Storage

### PySpark Quality Metrics Table

```python
from pyspark.sql import functions as F
from pyspark.sql.types import *
from datetime import datetime

def store_quality_metrics(
    spark,
    dataset_name: str,
    validation_results: List[ValidationResult],
    quality_score: float,
    metrics_table: str = "audit.data_quality_metrics"
):
    """Store quality metrics for trend analysis."""

    # Create metrics records
    records = []
    run_timestamp = datetime.now()

    for result in validation_results:
        records.append({
            "dataset_name": dataset_name,
            "check_name": result.name,
            "check_type": result.check_type,
            "severity": result.severity.value,
            "passed": result.passed,
            "total_rows": result.total_rows,
            "failed_rows": result.failed_rows,
            "pass_rate": result.pass_rate,
            "run_timestamp": run_timestamp
        })

    # Add overall score record
    records.append({
        "dataset_name": dataset_name,
        "check_name": "_overall_score",
        "check_type": "overall",
        "severity": "info",
        "passed": quality_score >= 0.95,
        "total_rows": validation_results[0].total_rows if validation_results else 0,
        "failed_rows": 0,
        "pass_rate": quality_score,
        "run_timestamp": run_timestamp
    })

    # Write to table
    metrics_df = spark.createDataFrame(records)
    metrics_df.write.mode("append").saveAsTable(metrics_table)

    return len(records)
```

### dbt Quality Metrics Model

```sql
-- models/quality/quality_metrics.sql
{{
  config(
    materialized='incremental',
    unique_key=['dataset_name', 'check_name', 'run_date']
  )
}}

WITH current_checks AS (
    SELECT
        'dim_customer' AS dataset_name,
        'completeness_email' AS check_name,
        'completeness' AS check_type,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) AS failed_rows,
        1 - (SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) / COUNT(*)) AS pass_rate,
        CURRENT_DATE() AS run_date,
        CURRENT_TIMESTAMP() AS run_timestamp
    FROM {{ ref('dim_customer') }}

    UNION ALL

    SELECT
        'dim_customer' AS dataset_name,
        'uniqueness_customer_id' AS check_name,
        'consistency' AS check_type,
        COUNT(*) AS total_rows,
        COUNT(*) - COUNT(DISTINCT customer_id) AS failed_rows,
        COUNT(DISTINCT customer_id) / COUNT(*) AS pass_rate,
        CURRENT_DATE() AS run_date,
        CURRENT_TIMESTAMP() AS run_timestamp
    FROM {{ ref('dim_customer') }}
    WHERE is_current = TRUE
)

SELECT * FROM current_checks
```

## Quality Dashboard Queries

### Trend Analysis

```sql
-- Quality score trend over time
SELECT
    dataset_name,
    run_date,
    AVG(pass_rate) AS avg_quality_score,
    SUM(CASE WHEN passed THEN 1 ELSE 0 END) AS checks_passed,
    COUNT(*) AS total_checks
FROM audit.data_quality_metrics
WHERE check_name != '_overall_score'
GROUP BY dataset_name, run_date
ORDER BY dataset_name, run_date DESC;
```

```python
# PySpark trend visualization
from pyspark.sql.window import Window

def get_quality_trend(spark, dataset_name: str, days: int = 30):
    """Get quality score trend for dataset."""

    return spark.sql(f"""
        SELECT
            run_date,
            pass_rate AS quality_score,
            LAG(pass_rate) OVER (ORDER BY run_date) AS prev_score,
            pass_rate - LAG(pass_rate) OVER (ORDER BY run_date) AS score_change
        FROM audit.data_quality_metrics
        WHERE dataset_name = '{dataset_name}'
          AND check_name = '_overall_score'
          AND run_date >= DATE_SUB(CURRENT_DATE(), {days})
        ORDER BY run_date
    """)
```

### Dimension Breakdown

```sql
-- Quality by dimension
SELECT
    dataset_name,
    check_type AS dimension,
    AVG(pass_rate) AS dimension_score,
    COUNT(*) AS check_count,
    SUM(CASE WHEN NOT passed THEN 1 ELSE 0 END) AS failing_checks
FROM audit.data_quality_metrics
WHERE run_date = CURRENT_DATE()
  AND check_name != '_overall_score'
GROUP BY dataset_name, check_type
ORDER BY dataset_name, dimension_score;
```

### Failing Checks Alert

```sql
-- Get currently failing checks
SELECT
    dataset_name,
    check_name,
    check_type,
    severity,
    pass_rate,
    failed_rows,
    run_timestamp
FROM audit.data_quality_metrics
WHERE run_date = CURRENT_DATE()
  AND NOT passed
  AND severity IN ('critical', 'high')
ORDER BY
    CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 ELSE 3 END,
    pass_rate;
```

## Quality SLA Monitoring

```python
@dataclass
class QualitySLA:
    dataset: str
    min_overall_score: float = 0.95
    max_critical_failures: int = 0
    max_high_failures: int = 2
    min_completeness: float = 0.99
    max_freshness_hours: int = 24

def check_quality_sla(
    validator: DataValidator,
    sla: QualitySLA
) -> Dict[str, Any]:
    """Check if quality meets SLA requirements."""

    summary = validator.get_summary()
    score_report = calculate_quality_score(validator.get_results())

    violations = []

    # Check overall score
    if score_report["overall_score"] < sla.min_overall_score:
        violations.append({
            "sla": "min_overall_score",
            "required": sla.min_overall_score,
            "actual": score_report["overall_score"]
        })

    # Check critical failures
    critical_failures = summary["by_severity"].get("critical", {}).get("failed", 0)
    if critical_failures > sla.max_critical_failures:
        violations.append({
            "sla": "max_critical_failures",
            "required": sla.max_critical_failures,
            "actual": critical_failures
        })

    # Check high failures
    high_failures = summary["by_severity"].get("high", {}).get("failed", 0)
    if high_failures > sla.max_high_failures:
        violations.append({
            "sla": "max_high_failures",
            "required": sla.max_high_failures,
            "actual": high_failures
        })

    # Check completeness dimension
    completeness = score_report["dimensions"].get("completeness", {}).get("score", 0)
    if completeness < sla.min_completeness:
        violations.append({
            "sla": "min_completeness",
            "required": sla.min_completeness,
            "actual": completeness
        })

    return {
        "sla_met": len(violations) == 0,
        "violations": violations,
        "quality_score": score_report["overall_score"],
        "quality_grade": score_report["overall_grade"]
    }

# Usage
sla = QualitySLA(dataset="customers", min_overall_score=0.95)
sla_result = check_quality_sla(validator, sla)

if not sla_result["sla_met"]:
    print(f"SLA VIOLATED: {sla_result['violations']}")
```
