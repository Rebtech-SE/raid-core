# Orchestration Decision Matrix

## Choose Fabric-Native When

- All workloads are inside Microsoft Fabric
- You need minimal infrastructure and managed scheduling
- Pipelines include Fabric notebooks, Dataflows, or dbt jobs

## Choose External Orchestrator When

- Workflows span multiple platforms or clouds
- You need complex branching, sensors, or custom operators
- You already run an enterprise orchestrator (Airflow/Dagster/Prefect)

## Choose dbt-Only Scheduling When

- Only dbt transformations are required
- Ingestion is handled upstream
- You want a simple, managed scheduler

## Key Decision Questions

- Where does ingestion run (Fabric or external)?
- Is the pipeline only dbt, or mixed with notebooks and dataflows?
- Do you need event-driven triggers?
- Is there a central enterprise orchestrator you must use?
- What SLA and backfill complexity is required?
