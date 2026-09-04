# Platform-Agnostic Orchestration Patterns

## Core Concepts

- DAG: explicit dependencies across stages and datasets.
- Idempotency: each task can be rerun without corrupting data.
- Watermarks: incremental processing based on time or sequence.
- SLAs: freshness and completion time targets.

## Common Pipeline Shapes

1. Batch daily

   - Source -> Bronze -> Silver -> Gold -> BI

1. Micro-batch streaming

   - Source -> Bronze (stream) -> Silver (micro-batch) -> Gold (materialized)

1. Hybrid

   - Streaming path for near-real-time
   - Batch path for reconciled daily aggregates

## Trigger Types

- Schedule-based (cron, interval)
- Event-based (file arrival, message queue)
- Dependency-based (dataset-ready events)
- Manual (backfill, reruns)

## Retry Strategy

- Retries for transient failures (network, throttling)
- Fail-fast for schema changes or contract violations
- Use exponential backoff and max retry count

## Backfill Strategy

- Separate backfill mode with explicit date range
- Disable downstream publishes until backfill complete
- Track backfill runs with batch_id or run_id

## Data Quality Gates

- Validate Bronze load counts and schema
- Silver checks: uniqueness, referential integrity
- Gold checks: reconciliations and metric validation

## Observability

- Run status, duration, and SLA breaches
- Row count deltas between layers
- Data freshness lag
- Error quarantine volume

## Orchestration Platform Examples

- Airflow, Dagster, Prefect, Azure Data Factory, dbt Cloud
- Choose based on dependency complexity, cross-platform needs, and ops maturity
