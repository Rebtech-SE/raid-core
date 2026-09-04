# End-to-End Orchestration: Ingestion + dbt on Fabric

## Overview

This document provides working patterns for orchestrating data pipelines that combine:
1. **Ingestion**: Loading data into Fabric Warehouse
2. **Transformation**: Running dbt models
3. **Scheduling**: Automated daily/hourly runs

## Architecture Options

### Option A: Fabric-Native (Recommended for simplicity)

```
[OneLake Files] -> [Fabric Pipeline: COPY] -> [Warehouse Staging]
                                                      |
                                                      v
                              [Fabric Pipeline: Notebook Activity]
                                                      |
                                                      v
                                            [dbt build in Notebook]
                                                      |
                                                      v
                                          [Warehouse: marts tables]
```

**Pros**: All in Fabric, single scheduling interface
**Cons**: dbt in notebook is less elegant, limited CI/CD integration

### Option B: Hybrid (Recommended for production)

```
[OneLake Files] -> [Fabric Pipeline: COPY] -> [Warehouse Staging]
                                                      |
                                                      v
                              [Fabric Pipeline: Webhook Activity]
                                                      |
                                                      v
                            [CI: dbt build (GitHub Actions / Azure DevOps)]
                                                      |
                                                      v
                                          [Warehouse: marts tables]
```

**Pros**: GitOps, proper CI/CD, dbt version control
**Cons**: Two systems to manage

### Option C: External Orchestrator

```
[Airflow/Prefect DAG]
        |
        +--> [Fabric REST API: Run Pipeline] -> [Warehouse Staging]
        |
        +--> [dbt build on Airflow worker] -> [Warehouse: marts tables]
```

**Pros**: Full control, cross-platform
**Cons**: Infrastructure to manage

## Working Example: Option B (Hybrid)

### Step 1: Create Ingestion Pipeline in Fabric

Use the Python example in `examples/fabric_pipeline_example.py`:

```python
from examples.fabric_pipeline_example import (
    copy_activity,
    deploy_pipeline,
    run_fab,
    webhook_activity,
)

# COPY activity for CSV ingestion
copy = copy_activity(
    name="IngestRetailCSV",
    source_path="Files/dbt_source/retail_sales.csv",
    sink_schema="staging",
    sink_table="raw_retail_sales",
)

# Webhook to trigger the CI run. GitHub Actions (default):
webhook = webhook_activity(
    name="TriggerDbtPipeline",
    url="https://api.github.com/repos/myorg/myrepo/dispatches",
    depends_on=["IngestRetailCSV"],
    body={"event_type": "fabric-ingest-complete", "client_payload": {"environment": "prod"}},
)
# Azure DevOps equivalent:
#   url="https://dev.azure.com/myorg/myproject/_apis/pipelines/123/runs?api-version=7.0",
#   body={"templateParameters": {"environment": "prod"}}

# Build pipeline-content.json and deploy via fab import
pipeline_path = deploy_pipeline(
    pipeline_name="RetailDataPipeline",
    description="Ingest CSV and trigger dbt",
    activities=[copy, webhook],
)

# Add daily schedule at 6 AM (fab exits non-zero on failure)
run_fab(
    "job", "run-sch", pipeline_path,
    "--type", "daily", "--interval", "06:00",
    "--start", "2024-01-01T06:00:00", "--enable",
)
```

### Step 2: Configure the CI workflow

Pick the template matching the repo's host (detect from the remote — see the provider
table in `raid-core/AGENTS.md`); default to GitHub Actions when ambiguous. Both are
stage-for-stage equivalent.

**GitHub Actions (default)** — `templates/github-actions-dbt-pipeline.yml`:

1. Copy to your repo as `.github/workflows/dbt-pipeline.yml`
2. Add repository secrets (Settings -> Secrets and variables -> Actions):
   `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `FABRIC_SERVER`,
   `FABRIC_DATABASE`, `FABRIC_SCHEMA`
3. Push — it runs on PR, push, the daily schedule, and on `repository_dispatch`

**Azure DevOps** — `templates/azure-devops-dbt-pipeline.yml`:

1. Copy to your repo as `.azure-pipelines/dbt-pipeline.yml`
2. Create variable group `fabric-dbt-credentials` with the same `AZURE_*` / `FABRIC_*` values
3. Create the pipeline in Azure DevOps pointing to the YAML file

### Step 3: Enable Webhook Authentication

For the webhook to trigger the CI run, authenticate the request.

**GitHub Actions** — a `repository_dispatch` POST needs a fine-grained PAT (or app token)
with `contents: write`:

```python
webhook["typeProperties"]["headers"] = {
    "Authorization": "Bearer $(github-token)",
    "Accept": "application/vnd.github+json",
}
```

**Azure DevOps** — a PAT, base64-encoded:

```python
webhook["typeProperties"]["headers"] = {
    "Authorization": "Basic $(base64-encoded-pat)"
}
```

Or use the host's native incoming-webhook/service-hook mechanism.

## Working Example: Option A (Fabric-Native)

### dbt Runner Notebook

Create a notebook that runs dbt and deploy it to Fabric:

```python
# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {"name": "synapse_pyspark"},
# META   "dependencies": {}
# META }

# CELL ********************

# Install dbt (first run only - consider baking into environment)
%pip install dbt-core dbt-fabric --quiet

# CELL ********************

import os
import subprocess

# Configuration
DBT_PROJECT_PATH = "/lakehouse/default/Files/dbt/retail_analytics"
DBT_PROFILES_DIR = "/lakehouse/default/Files/dbt"

# Set environment variables for auth
os.environ["FABRIC_SERVER"] = "your-server.datawarehouse.fabric.microsoft.com"
os.environ["FABRIC_DATABASE"] = "RetailWarehouse"
os.environ["FABRIC_SCHEMA"] = "dbt_prod"
os.environ["AZURE_TENANT_ID"] = dbutils.secrets.get("fabric", "tenant-id")
os.environ["AZURE_CLIENT_ID"] = dbutils.secrets.get("fabric", "client-id")
os.environ["AZURE_CLIENT_SECRET"] = dbutils.secrets.get("fabric", "client-secret")

# CELL ********************

# Run dbt build
result = subprocess.run(
    ["dbt", "build", "--profiles-dir", DBT_PROFILES_DIR],
    cwd=DBT_PROJECT_PATH,
    capture_output=True,
    text=True,
)

print("=== STDOUT ===")
print(result.stdout)

if result.returncode != 0:
    print("=== STDERR ===")
    print(result.stderr)
    raise Exception(f"dbt build failed with exit code {result.returncode}")

print("[OK] dbt build completed successfully")
```

### Pipeline with Notebook Activity

```python
from examples.fabric_pipeline_example import (
    copy_activity,
    deploy_pipeline,
    notebook_activity,
)

copy = copy_activity(...)

notebook = notebook_activity(
    name="RunDbt",
    notebook_id="<dbt-runner-notebook-id>",  # fab get "<ws>.Workspace/<nb>.Notebook" -q id
    workspace_id="<workspace-id>",  # fab get "<ws>.Workspace" -q id
    depends_on=["IngestRetailCSV"],
)

deploy_pipeline(
    pipeline_name="RetailPipeline",
    description="Ingest retail CSV, then run dbt",
    activities=[copy, notebook],
)
```

## Scheduling Patterns

### Daily Full Refresh

```yaml
schedule:
  frequency: Day
  interval: 1
  startTime: "06:00:00"
  timeZone: "UTC"
```

Pipeline runs `dbt build` which rebuilds all tables.

### Hourly Incremental

```yaml
schedule:
  frequency: Hour
  interval: 1
```

dbt command: `dbt run --select tag:incremental`

### Event-Driven (Near Real-Time)

Use Fabric Eventstreams to trigger pipeline on new data arrival:

1. Configure Eventstream source (e.g., Event Hub, Kafka)
2. Add Eventstream as pipeline trigger
3. Pipeline runs on each event batch

## Error Handling and Retries

### Pipeline-Level Retries

```python
copy_activity = {
    "name": "IngestData",
    "type": "Copy",
    "policy": {
        "retry": 3,
        "retryIntervalInSeconds": 60,
        "timeout": "0.01:00:00",
    },
    ...
}
```

### dbt-Level Retries (in CI)

GitHub Actions:

```yaml
- name: dbt build with retry
  working-directory: ${{ env.DBT_PROJECT_DIR }}
  run: dbt build --fail-fast || dbt build --select result:error+
```

Azure DevOps:

```yaml
- script: |
    cd $(DBT_PROJECT_DIR)
    dbt build --fail-fast || dbt build --select result:error+
  displayName: "dbt build with retry"
```

### Dead Letter Handling

See `../dead-letter-queue/SKILL.md` for patterns on handling failed records.

## Monitoring and Alerting

### Fabric Pipeline Monitoring

- Monitor in Fabric workspace > Monitoring hub
- Set up alerts via Azure Monitor integration

### dbt Monitoring

- Publish `target/run_results.json` as artifact
- Parse for failures in downstream job
- Integrate with Slack/Teams via webhook

### Key Metrics to Track

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| Pipeline duration | Fabric | > 2x baseline |
| dbt test failures | run_results.json | > 0 |
| Row count delta | Custom query | > 20% change |
| Freshness | dbt source freshness | > SLA |

## Backfill Strategy

### Historical Backfill

1. Disable scheduled triggers
2. Run pipeline with date range parameter
3. dbt incremental models process historical data
4. Re-enable triggers

```python
# Parameterized pipeline for backfill: declare parameters in the definition
# (deploy_pipeline builds properties from description + activities; add
# parameters to the definition before import, or author the JSON directly)
deploy_pipeline(
    pipeline_name="RetailBackfill",
    description="Backfill with date-range parameters",
    activities=[...],  # activities reference @pipeline().parameters.start_date etc.
)
```

```bash
# Pass the date range at run time as typed parameters
fab job run "ws.Workspace/RetailBackfill.DataPipeline" \
    -P start_date:string=2024-01-01 -P end_date:string=2024-01-31
```

### dbt Backfill Commands

```bash
# Full refresh specific models
dbt run --select my_model --full-refresh

# Run for specific date range (requires model support)
dbt run --vars '{"start_date": "2024-01-01", "end_date": "2024-01-31"}'
```

## Security Considerations

1. **Secrets Management**: Use Azure Key Vault or Fabric secrets
2. **Service Principal**: Minimum required permissions
3. **Network**: Consider Private Link for production
4. **Audit**: Enable Fabric audit logs

## Quick Start Checklist

- [ ] Fabric Warehouse created
- [ ] Service principal with workspace access
- [ ] dbt project with profiles.yml template
- [ ] CI secrets/variables configured (GitHub Actions secrets or Azure DevOps variable group)
- [ ] Pipeline YAML committed to repo
- [ ] Fabric ingestion pipeline created
- [ ] Schedule trigger configured
- [ ] Monitoring alerts set up
