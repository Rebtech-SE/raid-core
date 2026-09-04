"""
Fabric Data Pipeline Creation Example

This example demonstrates how to create a Data Pipeline in Microsoft Fabric
that orchestrates:
1. CSV ingestion from OneLake to Warehouse (COPY activity)
2. Trigger for dbt transformation (Webhook or Notebook)

It builds the pipeline definition (pipeline-content.json) in Python and shells
out to the Fabric CLI (`fab`) to deploy and schedule it.

Prerequisites:
- Fabric CLI installed: pip install ms-fabric-cli
- Authenticated: fab auth login (verify with: fab auth status)
- Workspace access for the signed-in identity

Definition spec:
https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/datapipeline-definition

Usage:
    python fabric_pipeline_example.py
"""

import json
import subprocess
import tempfile
from pathlib import Path

WORKSPACE = "MyWorkspace"  # workspace display name (no .Workspace suffix here)


def run_fab(*args: str) -> subprocess.CompletedProcess:
    """Run a fab CLI command and fail loudly on error."""
    cmd = ["fab", *args]
    print("[INFO] running:", " ".join(cmd))
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def copy_activity(name, source_path, sink_schema, sink_table, depends_on=()):
    """Copy activity: lakehouse file -> warehouse table.

    typeProperties are abridged; see the definition spec for the full
    source/sink schemas per connector.
    """
    return {
        "name": name,
        "type": "Copy",
        "dependsOn": [
            {"activity": dep, "dependencyConditions": ["Succeeded"]} for dep in depends_on
        ],
        "typeProperties": {
            "source": {"type": "LakehouseReadSettings", "path": source_path},
            "sink": {
                "type": "DataWarehouseSink",
                "schema": sink_schema,
                "table": sink_table,
            },
        },
    }


def notebook_activity(name, notebook_id, workspace_id, depends_on=(), parameters=None):
    """Notebook activity (type TridentNotebook)."""
    return {
        "name": name,
        "type": "TridentNotebook",
        "dependsOn": [
            {"activity": dep, "dependencyConditions": ["Succeeded"]} for dep in depends_on
        ],
        "typeProperties": {
            "notebookId": notebook_id,
            "workspaceId": workspace_id,
            "parameters": parameters or {},
        },
    }


def webhook_activity(name, url, body, depends_on=()):
    """Web activity, e.g. to trigger an Azure DevOps pipeline."""
    return {
        "name": name,
        "type": "WebActivity",
        "dependsOn": [
            {"activity": dep, "dependencyConditions": ["Succeeded"]} for dep in depends_on
        ],
        "typeProperties": {"url": url, "method": "POST", "body": json.dumps(body)},
    }


def foreach_activity(name, items, activities, is_sequential=False, batch_count=10):
    """ForEach activity iterating over an expression-valued item list."""
    return {
        "name": name,
        "type": "ForEach",
        "dependsOn": [],
        "typeProperties": {
            "items": {"value": items, "type": "Expression"},
            "isSequential": is_sequential,
            "batchCount": batch_count,
            "activities": activities,
        },
    }


def if_condition_activity(name, expression, if_true, if_false, depends_on=()):
    """IfCondition activity for conditional branching."""
    return {
        "name": name,
        "type": "IfCondition",
        "dependsOn": [
            {"activity": dep, "dependencyConditions": ["Succeeded"]} for dep in depends_on
        ],
        "typeProperties": {
            "expression": {"value": expression, "type": "Expression"},
            "ifTrueActivities": if_true,
            "ifFalseActivities": if_false,
        },
    }


def deploy_pipeline(pipeline_name, description, activities, workspace=WORKSPACE):
    """Write pipeline-content.json and import it as a DataPipeline via fab."""
    definition = {"properties": {"description": description, "activities": activities}}

    with tempfile.TemporaryDirectory() as tmp:
        defn_dir = Path(tmp) / f"{pipeline_name}.DataPipeline"
        defn_dir.mkdir()
        (defn_dir / "pipeline-content.json").write_text(json.dumps(definition, indent=2))

        pipeline_path = f"{workspace}.Workspace/{pipeline_name}.DataPipeline"
        run_fab("import", pipeline_path, "-i", str(defn_dir), "-f")

    print(f"[OK] deployed {pipeline_path}")
    return pipeline_path


def create_retail_ingestion_pipeline():
    """
    Example: Create a complete retail data ingestion pipeline.

    This pipeline:
    1. Copies CSV from OneLake to Warehouse staging table
    2. Triggers a dbt transformation notebook
    """
    copy = copy_activity(
        name="CopyRetailCSVToWarehouse",
        source_path="Files/dbt_source/retail_sales.csv",
        sink_schema="staging",
        sink_table="raw_retail_sales",
    )

    # Option A: Run dbt via Notebook
    dbt_notebook = notebook_activity(
        name="RunDbtTransformations",
        notebook_id="<your-dbt-notebook-id>",  # fab get "<ws>.Workspace/<nb>.Notebook" -q id
        workspace_id="<your-workspace-id>",  # fab get "<ws>.Workspace" -q id
        depends_on=["CopyRetailCSVToWarehouse"],
        parameters={"target": {"value": "dev", "type": "string"}},
    )

    # Option B: Trigger Azure DevOps pipeline via webhook
    devops_webhook = webhook_activity(  # noqa: F841 - alternative to Option A
        name="TriggerDbtPipeline",
        url="https://dev.azure.com/<org>/<project>/_apis/pipelines/<pipeline-id>/runs?api-version=7.0",
        depends_on=["CopyRetailCSVToWarehouse"],
        body={"templateParameters": {"environment": "dev"}},
    )

    # Deploy with the notebook option
    pipeline_path = deploy_pipeline(
        pipeline_name="RetailDataIngestion",
        description="Ingest retail CSV and run dbt transformations",
        activities=[copy, dbt_notebook],
    )

    # Add daily schedule at 6 AM (synchronous fab call, non-zero exit on failure)
    run_fab(
        "job",
        "run-sch",
        pipeline_path,
        "--type",
        "daily",
        "--interval",
        "06:00",
        "--start",
        "2024-01-01T06:00:00",
        "--enable",
    )

    return pipeline_path


def create_multi_file_ingestion_pipeline():
    """
    Example: Create a pipeline that processes multiple files using ForEach.
    """
    copy = copy_activity(
        name="CopyFile",
        source_path="@item().path",  # Expression for current item
        sink_schema="staging",
        sink_table="@item().table",
    )

    foreach = foreach_activity(
        name="ProcessAllFiles",
        items="@variables('fileList')",
        activities=[copy],
        is_sequential=False,
        batch_count=10,
    )

    notify = webhook_activity(
        name="NotifyCompletion",
        url="https://hooks.slack.com/services/...",
        depends_on=["ProcessAllFiles"],
        body={"text": "Pipeline completed successfully"},
    )

    return deploy_pipeline(
        pipeline_name="MultiFileIngestion",
        description="Process multiple CSV files in parallel",
        activities=[foreach, notify],
    )


def create_conditional_pipeline():
    """
    Example: Create a pipeline with conditional logic.
    """
    quality_check = notebook_activity(
        name="DataQualityCheck",
        notebook_id="<quality-check-notebook-id>",
        workspace_id="<your-workspace-id>",
    )

    # Success path: continue processing
    process = notebook_activity(
        name="ProcessData",
        notebook_id="<process-notebook-id>",
        workspace_id="<your-workspace-id>",
    )

    # Failure path: send alert
    alert = webhook_activity(
        name="SendAlert",
        url="https://api.pagerduty.com/v2/enqueue",
        body={"routing_key": "...", "event_action": "trigger"},
    )

    condition = if_condition_activity(
        name="CheckQualityResult",
        expression="@equals(activity('DataQualityCheck').output.status, 'passed')",
        if_true=[process],
        if_false=[alert],
        depends_on=["DataQualityCheck"],
    )

    return deploy_pipeline(
        pipeline_name="ConditionalPipeline",
        description="Pipeline with quality check and conditional branching",
        activities=[quality_check, condition],
    )


if __name__ == "__main__":
    print("Fabric Pipeline Deployment Examples (fab CLI)")
    print("=" * 45)
    print()
    print("Available examples:")
    print("1. create_retail_ingestion_pipeline() - Basic COPY + Notebook pipeline")
    print("2. create_multi_file_ingestion_pipeline() - ForEach parallel processing")
    print("3. create_conditional_pipeline() - Conditional branching")
    print()
    print("To run an example:")
    print("  1. Install and authenticate the Fabric CLI:")
    print("     pip install ms-fabric-cli && fab auth login")
    print("  2. Set WORKSPACE and update notebook/workspace IDs and URLs")
    print("     (look up IDs with: fab get '<ws>.Workspace/<item>' -q id)")
    print("  3. Call the function, e.g.:")
    print("     path = create_retail_ingestion_pipeline()")
    print("  4. Test-run it: fab job run '<ws>.Workspace/<name>.DataPipeline'")
