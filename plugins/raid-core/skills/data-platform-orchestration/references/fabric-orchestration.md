# Fabric Orchestration Patterns

## Scope

Use this when the platform is Microsoft Fabric and you need to orchestrate ingestion, notebook execution, or dbt runs.

## Primary Orchestration Options

1. Fabric Data Factory pipelines

   - Use for scheduling ingestion, notebook execution, and multi-step workflows.
   - Supports activity-level retries and parameter passing.

1. Fabric dbt jobs (managed runtime)

   - Use for dbt-only orchestration inside Fabric.
   - Schedule dbt run/test and chain to other pipeline activities.

1. Event-driven triggers

   - Eventstreams -> landing in Lakehouse/Eventhouse, then trigger downstream jobs.
   - Use when near-real-time ingestion is required.

1. External orchestrators (only if needed)

   - Azure Data Factory, Airflow, or CI schedulers.
   - Use when cross-platform coordination is required.

## Recommended Flow (Fabric Native)

- Ingestion: Fabric Data Factory pipeline or Eventstream
- Bronze load: Notebook activity (append-only)
- Silver/Gold: Notebook activity or dbt job
- Tests: dbt tests or data quality notebook
- Publish: Power BI refresh or semantic model update

## Trigger Types

- Scheduled: daily/hourly pipelines
- Event-based: Eventstream triggers for streaming or micro-batch
- Manual: for backfills or reprocessing

## Retries and Idempotency

- Configure retry per activity in pipeline.
- Make notebooks idempotent using watermark columns and merge logic.
- Record batch_id per run for traceability.

## Backfill Strategy

- Run ingestion and transformation for a historical range.
- Disable downstream publish until backfill completes.
- Record backfill runs as separate batch_id values.

## Observability Signals

- Pipeline success/failure
- Row counts per layer
- Freshness lag per table
- Error quarantine counts

## When to Use Fabric dbt Jobs vs Pipelines

- Use Fabric dbt jobs for dbt-only workloads.
- Use pipelines for multi-step orchestration that includes notebooks or ingestion.
- Chain dbt job as a pipeline activity if needed.
