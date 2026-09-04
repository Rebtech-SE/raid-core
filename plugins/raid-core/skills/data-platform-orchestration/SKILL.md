---
name: data-platform-orchestration
description: >-
  Use when designing or documenting orchestration for dbt runs, PySpark notebook
  pipelines, or end-to-end ingestion->transform workflows. Triggers: 'orchestration
  patterns', 'schedule dbt', 'pipeline dependencies', 'backfill strategy', 'Fabric
  orchestration', 'notebook orchestration', 'schedule pipeline', 'automate dbt'. Covers
  batch/streaming scheduling, dependency graphs, retries, SLAs, backfills, and
  observability.
---

# Data Platform Orchestration

## Purpose

Design and implement how data pipelines are scheduled, triggered, retried, and monitored. This skill provides working code examples for orchestrating ingestion and dbt transformations on Microsoft Fabric.

## When to Use This Skill

Use when the user needs to:
- Schedule dbt runs on Fabric (daily, hourly, event-driven)
- Create Fabric Data Pipelines for ingestion
- Orchestrate end-to-end data flows (ingestion -> transformation)
- Set up CI/CD for dbt (GitHub Actions or Azure DevOps)
- Configure retries, backfills, and error handling

## Quick Start: Which Approach?

| Scenario | Recommended Approach | Template/Example |
|----------|---------------------|------------------|
| Simple: dbt only, manual trigger | CI workflow (GitHub Actions / Azure DevOps) | `templates/github-actions-dbt-pipeline.yml` / `templates/azure-devops-dbt-pipeline.yml` |
| Standard: Ingestion + dbt, scheduled | Fabric Pipeline + CI | `examples/fabric_pipeline_example.py` |
| All-in-Fabric: No external systems | Fabric Pipeline + Notebook | `references/end-to-end-orchestration.md` |
| Complex: Multi-platform | External orchestrator | `references/platform-agnostic-patterns.md` |

Pick the CI host that matches where the repo lives (detect from the remote — see the
provider table in `raid-core/AGENTS.md`); default to GitHub Actions when the host is
ambiguous. The two templates are stage-for-stage equivalent.

## Templates Available

### CI workflow for dbt
`templates/github-actions-dbt-pipeline.yml` (GitHub Actions) and
`templates/azure-devops-dbt-pipeline.yml` (Azure DevOps Pipelines) — same stages, pick
the one matching the repo's host.

Complete CI/CD pipeline that:
- Installs ODBC Driver 18
- Installs dbt-core and dbt-fabric
- Runs dbt build with service principal auth
- Publishes artifacts and docs
- Supports scheduled runs (daily 6 AM)

**Usage (GitHub Actions)**:
1. Copy to `.github/workflows/dbt-pipeline.yml`
2. Add the `FABRIC_*` and `AZURE_*` repository secrets (Settings -> Secrets and variables -> Actions)
3. Push — the workflow runs on PR, push, and the daily schedule

**Usage (Azure DevOps)**:
1. Copy to `.azure-pipelines/dbt-pipeline.yml`
2. Create variable group `fabric-dbt-credentials`
3. Create pipeline in Azure DevOps

### Fabric Pipeline Deployer
`examples/fabric_pipeline_example.py`

Python module for creating Fabric Data Pipelines: builds the
`pipeline-content.json` definition and deploys it via the Fabric CLI (`fab import`):
- COPY activities (CSV to Warehouse)
- Notebook activities (run dbt in Fabric)
- Webhook activities (trigger CI: GitHub Actions / Azure DevOps)
- Schedules via `fab job run-sch`

**Usage**:
```python
from examples.fabric_pipeline_example import copy_activity, deploy_pipeline

activities = [copy_activity("CopySales", "Files/raw/sales.csv", "stg", "sales")]
result = deploy_pipeline(
    pipeline_name="MyPipeline",
    description="Ingest sales data",
    activities=activities,
)
```

Requires `pip install ms-fabric-cli` and `fab auth login`.

## Architecture Patterns

### Pattern 1: Hybrid (Recommended for Production)

```
OneLake -> Fabric Pipeline (COPY) -> Warehouse Staging
                    |
                    v
         Webhook -> CI (GitHub Actions / Azure DevOps) -> dbt build -> Warehouse Marts
```

**Benefits**: GitOps, version control, proper CI/CD
**Implementation**: See `references/end-to-end-orchestration.md`

### Pattern 2: Fabric-Native

```
OneLake -> Fabric Pipeline (COPY) -> Warehouse Staging
                    |
                    v
         Notebook Activity -> dbt build -> Warehouse Marts
```

**Benefits**: Single platform, simpler setup
**Trade-offs**: Less CI/CD integration

### Pattern 3: External Orchestrator

```
Airflow/Prefect DAG
    |
    +--> Fabric API: Run Pipeline
    |
    +--> dbt build on orchestrator
```

**Benefits**: Full control, cross-platform
**Trade-offs**: Infrastructure to manage

## How to Use This Skill

### Step 1: Identify Workload Type

- **Batch**: Daily/hourly scheduled runs
- **Micro-batch**: Frequent incremental updates (every 15 min)
- **Event-driven**: Triggered by data arrival

### Step 2: Define Dependency Graph

```
[Source Files]
      |
      v
[Ingestion: COPY to staging]
      |
      v
[dbt: staging models]
      |
      v
[dbt: intermediate models]
      |
      v
[dbt: marts models]
      |
      v
[dbt: tests]
      |
      v
[Optional: BI refresh]
```

### Step 3: Choose Orchestration Approach

Based on Quick Start table above.

### Step 4: Implement

Use the templates and examples provided:
- Copy the CI YAML template for the repo's host (GitHub Actions or Azure DevOps)
- Run Fabric pipeline deployer script
- Configure triggers and schedules

### Step 5: Configure Monitoring

- Fabric: Monitoring hub
- CI (GitHub Actions / Azure DevOps): workflow/pipeline runs
- dbt: Parse `target/run_results.json`

## References

| Document | Purpose |
|----------|---------|
| `references/end-to-end-orchestration.md` | Complete working examples for all patterns |
| `references/fabric-orchestration.md` | Fabric-specific options and triggers |
| `references/platform-agnostic-patterns.md` | General orchestration concepts |
| `references/orchestration-decision-matrix.md` | Decision framework |

## Output Expectations

When applying this skill, produce:
1. Architecture diagram (ASCII or description)
2. Chosen approach with rationale
3. Working code/config from templates
4. Schedule configuration
5. Retry and error handling policy
6. Monitoring setup

## Related Skills

- `set-up-dbt-on-fabric` (raid-fabric) - dbt setup and configuration
- `fabric-architecture` (raid-fabric) - Medallion layer decisions
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - Error handling patterns
- [build-ingestion-pipeline](../build-ingestion-pipeline/SKILL.md) - Ingestion tool selection
