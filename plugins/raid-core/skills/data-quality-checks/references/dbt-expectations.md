# dbt-expectations Reference

Complete guide to data quality testing with dbt-expectations package.

## Installation

```yaml
# packages.yml
packages:
  - package: calogica/dbt_expectations
    version: 0.10.0
```

```bash
dbt deps
```

## Test Categories

### Column Value Tests

#### Null Checks

```yaml
columns:
  - name: customer_id
    tests:
      # Basic not null
      - not_null

      # Conditional not null
      - dbt_expectations.expect_column_values_to_not_be_null:
          row_condition: "status = 'active'"
```

#### Value Ranges

```yaml
columns:
  - name: amount
    tests:
      - dbt_expectations.expect_column_values_to_be_between:
          min_value: 0
          max_value: 1000000
          strictly: false  # inclusive bounds

  - name: discount_percent
    tests:
      - dbt_expectations.expect_column_values_to_be_between:
          min_value: 0
          max_value: 100
          row_condition: "discount_percent IS NOT NULL"
```

#### Value Lists

```yaml
columns:
  - name: status
    tests:
      - accepted_values:
          values: ['active', 'inactive', 'pending']

      - dbt_expectations.expect_column_values_to_be_in_set:
          value_set: ['active', 'inactive', 'pending', 'closed']
          row_condition: "created_date > '2024-01-01'"
```

#### Pattern Matching

```yaml
columns:
  - name: email
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

  - name: phone
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^\\+?[0-9]{10,15}$"
          row_condition: "phone IS NOT NULL"

  - name: uuid_field
    tests:
      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
```

#### String Length

```yaml
columns:
  - name: product_code
    tests:
      - dbt_expectations.expect_column_value_lengths_to_equal:
          value: 10

  - name: description
    tests:
      - dbt_expectations.expect_column_value_lengths_to_be_between:
          min_value: 1
          max_value: 500
```

### Column Aggregate Tests

#### Statistical Tests

```yaml
columns:
  - name: amount
    tests:
      - dbt_expectations.expect_column_mean_to_be_between:
          min_value: 100
          max_value: 10000

      - dbt_expectations.expect_column_stdev_to_be_between:
          min_value: 0
          max_value: 1000

      - dbt_expectations.expect_column_sum_to_be_between:
          min_value: 1000000
          max_value: 100000000
          group_by: ['region']
```

#### Distribution Tests

```yaml
columns:
  - name: category
    tests:
      - dbt_expectations.expect_column_distinct_count_to_equal:
          value: 5

      - dbt_expectations.expect_column_distinct_count_to_be_between:
          min_value: 3
          max_value: 10

      - dbt_expectations.expect_column_proportion_of_unique_values_to_be_between:
          min_value: 0.9
          max_value: 1.0
```

#### Freshness Tests

```yaml
columns:
  - name: updated_at
    tests:
      - dbt_expectations.expect_column_max_to_be_between:
          min_value: "{{ (modules.datetime.datetime.now() - modules.datetime.timedelta(hours=24)).strftime('%Y-%m-%d %H:%M:%S') }}"

      - dbt_expectations.expect_row_values_to_have_recent_data:
          datepart: day
          interval: 1
```

### Table-Level Tests

#### Row Count

```yaml
models:
  - name: orders
    tests:
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1000
          max_value: 10000000

      - dbt_expectations.expect_table_row_count_to_equal_other_table:
          compare_model: ref('stg_orders')
```

#### Column Presence

```yaml
models:
  - name: customers
    tests:
      - dbt_expectations.expect_table_columns_to_contain_set:
          column_list:
            - customer_id
            - email
            - created_at

      - dbt_expectations.expect_table_columns_to_match_set:
          column_list:
            - customer_id
            - customer_name
            - email
            - phone
            - created_at
            - updated_at
```

### Multi-Column Tests

#### Column Pair Comparisons

```yaml
models:
  - name: orders
    tests:
      - dbt_expectations.expect_column_pair_values_A_to_be_greater_than_B:
          column_A: end_date
          column_B: start_date
          or_equal: true

      - dbt_expectations.expect_column_pair_values_to_be_equal:
          column_A: quantity * unit_price
          column_B: total_amount
          tolerance: 0.01
```

#### Compound Uniqueness

```yaml
models:
  - name: fact_sales
    tests:
      - dbt_expectations.expect_compound_columns_to_be_unique:
          column_list:
            - customer_id
            - product_id
            - order_date
```

### Comparison Tests

#### Compare to Other Tables

```yaml
models:
  - name: dim_customer
    tests:
      - dbt_expectations.expect_table_row_count_to_equal_other_table:
          compare_model: ref('stg_customers')
          group_by: ['region']
          compare_group_by: ['region']
          factor: 1  # exact match
          tolerance: 0.05  # 5% tolerance
```

## Custom Test Configuration

### Severity Levels

```yaml
columns:
  - name: customer_id
    tests:
      - not_null:
          config:
            severity: error  # Blocks pipeline

      - dbt_expectations.expect_column_values_to_match_regex:
          regex: "^C[0-9]{6}$"
          config:
            severity: warn  # Warning only
```

### Conditional Testing

```yaml
columns:
  - name: email
    tests:
      - dbt_expectations.expect_column_values_to_not_be_null:
          row_condition: "account_type = 'business'"
          config:
            where: "created_date > '2024-01-01'"
```

### Store Failures

```yaml
# dbt_project.yml
tests:
  +store_failures: true
  +schema: dbt_test_failures
```

```yaml
# Per-test configuration
columns:
  - name: amount
    tests:
      - dbt_expectations.expect_column_values_to_be_between:
          min_value: 0
          config:
            store_failures: true
            limit: 100  # Store up to 100 failures
```

## Common Test Patterns

### Primary Key Validation

```yaml
models:
  - name: dim_customer
    columns:
      - name: sk_customer
        tests:
          - unique
          - not_null
```

### Foreign Key Validation

```yaml
models:
  - name: fact_orders
    columns:
      - name: customer_id
        tests:
          - relationships:
              to: ref('dim_customer')
              field: customer_id
              config:
                where: "is_current = true"
```

### SCD Type 2 Validation

```yaml
models:
  - name: dim_customer
    tests:
      # Only one current per business key
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - customer_id
          config:
            where: "is_current = true"

    columns:
      - name: valid_from
        tests:
          - not_null

      - name: valid_to
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_in_set:
              value_set: ['9999-12-31']
              row_condition: "is_current = true"
```

### Data Quality Dashboard

```yaml
# Create a test summary model
# models/quality/test_summary.sql
{{ config(materialized='table') }}

SELECT
    'dim_customer' AS model_name,
    'null_check_email' AS test_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) AS failures,
    1 - (SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END) / COUNT(*)) AS pass_rate,
    CURRENT_TIMESTAMP() AS tested_at
FROM {{ ref('dim_customer') }}
```

## Running Tests

```bash
# Run all tests
dbt test

# Run tests for specific model
dbt test --select dim_customer

# Run only dbt-expectations tests
dbt test --select tag:dbt_expectations

# Run and store failures
dbt test --store-failures

# Run with specific severity
dbt test --warn-error  # Treat warnings as errors
```

## CI/CD Integration

```yaml
# .github/workflows/dbt-test.yml
name: dbt Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          pip install dbt-core dbt-snowflake
          dbt deps

      - name: Run tests
        run: |
          dbt test --target ci --store-failures

      - name: Check critical failures
        run: |
          # Fail if any error-severity tests failed
          dbt test --target ci --severity error
```
