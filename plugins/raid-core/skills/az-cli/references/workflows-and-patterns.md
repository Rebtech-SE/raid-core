# Workflows, Best Practices & Scripting Patterns

## Common Workflows

### Create PR from current branch

```bash
CURRENT_BRANCH=$(git branch --show-current)
az repos pr create \
  --source-branch "$CURRENT_BRANCH" \
  --target-branch main \
  --title "$(git log -1 --pretty=%B)" \
  --open
```

### Download latest pipeline artifact

```bash
RUN_ID=$(az pipelines runs list --pipeline-ids {pipeline-id} --top 1 --query "[0].id" -o tsv)
az pipelines runs artifact download \
  --artifact-name 'webapp' \
  --path ./output \
  --run-id "$RUN_ID"
```

### Run pipeline and wait for completion

```bash
RUN_ID=$(az pipelines run --name "$PIPELINE_NAME" --query "id" -o tsv)

while true; do
  STATUS=$(az pipelines runs show --run-id "$RUN_ID" --query "status" -o tsv)
  if [[ "$STATUS" != "inProgress" && "$STATUS" != "notStarted" ]]; then
    break
  fi
  sleep 10
done

RESULT=$(az pipelines runs show --run-id "$RUN_ID" --query "result" -o tsv)
if [[ "$RESULT" != "succeeded" ]]; then
  echo "Pipeline failed with result: $RESULT"
  exit 1
fi
```

### Bulk update work items

```bash
for id in $(az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.State]='New'" -o tsv); do
  az boards work-item update --id "$id" --state "Active"
done
```

### Create work item on pipeline failure

```bash
az boards work-item create \
  --title "Build $BUILD_BUILDNUMBER failed" \
  --type Bug \
  --description "Pipeline run $RUN_ID failed with result: $RESULT"
```

## Authentication Best Practices

```bash
# Use PAT from environment variable (avoids shell history)
export AZURE_DEVOPS_EXT_PAT="$MY_PAT"
az devops login --organization "$ORG_URL"

# Set defaults to avoid repeating --org/--project
az devops configure --defaults organization="$ORG_URL" project="$PROJECT"

# Clear credentials when done
az devops logout --organization "$ORG_URL"
```

## Script-Safe Output

```bash
# TSV for shell variable assignment (no formatting overhead)
PIPELINE_ID=$(az pipelines list --query "[?name=='MyPipeline'].id" -o tsv)

# Suppress warnings in scripts
az pipelines list --only-show-errors

# No output for fire-and-forget commands
az pipelines run --name "$PIPELINE_NAME" -o none

# JSON for programmatic access
BUILD_STATUS=$(az pipelines build show --id "$BUILD_ID" --query "status" -o json)
```

## Retry with Exponential Backoff

```bash
retry_command() {
  local max_attempts=3
  local attempt=1
  local delay=5

  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    echo "Attempt $attempt failed. Retrying in ${delay}s..."
    sleep "$delay"
    ((attempt++))
    delay=$((delay * 2))
  done

  echo "All $max_attempts attempts failed"
  return 1
}

# Usage
retry_command az pipelines run --name "$PIPELINE_NAME"
```

## Idempotent Operations

### Check before create

```bash
# Pipeline
PIPELINE_ID=$(az pipelines list --query "[?name=='$PIPELINE_NAME'].id" -o tsv)
if [[ -z "$PIPELINE_ID" ]]; then
  az pipelines create --name "$PIPELINE_NAME" --yaml-path azure-pipelines.yml
fi

# Variable group
VG_ID=$(az pipelines variable-group list --query "[?name=='$VG_NAME'].id" -o tsv)
if [[ -z "$VG_ID" ]]; then
  VG_ID=$(az pipelines variable-group create \
    --name "$VG_NAME" \
    --variables API_URL="$API_URL" API_KEY="$API_KEY" \
    --authorize true \
    --query "id" -o tsv)
fi

# Work item (query by title to prevent duplicates)
WI_ID=$(az boards query \
  --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType]='$TYPE' AND [System.Title]='$TITLE'" \
  --query "[0].id" -o tsv)
if [[ -z "$WI_ID" ]]; then
  WI_ID=$(az boards work-item create --title "$TITLE" --type "$TYPE" --query "id" -o tsv)
fi
```

### Reusable ensure functions

```bash
ensure_pipeline() {
  local name=$1
  local yaml_path=$2
  local id
  id=$(az pipelines list --query "[?name=='$name'].id" -o tsv)
  if [[ -z "$id" ]]; then
    echo "Creating pipeline: $name"
    az pipelines create --name "$name" --yaml-path "$yaml_path"
  else
    echo "Pipeline exists: $name (ID: $id)"
  fi
}

ensure_variable_group() {
  local vg_name=$1
  shift
  local id
  id=$(az pipelines variable-group list --query "[?name=='$vg_name'].id" -o tsv)
  if [[ -z "$id" ]]; then
    echo "Creating variable group: $vg_name"
    id=$(az pipelines variable-group create \
      --name "$vg_name" --variables "$@" --authorize true --query "id" -o tsv)
  fi
  echo "$id"
}
```

## Input Validation

```bash
# Required parameters
if [[ -z "$PROJECT" || -z "$REPO" ]]; then
  echo "Error: PROJECT and REPO must be set"
  exit 1
fi

# Check branch exists
if ! az repos ref list --repository "$REPO" --query "[?name=='refs/heads/$BRANCH']" -o tsv | grep -q .; then
  echo "Error: Branch $BRANCH does not exist"
  exit 1
fi
```

## Service Connection from Config

```bash
cat > /tmp/service-connection.json <<EOF
{
  "data": {
    "subscriptionId": "$SUBSCRIPTION_ID",
    "subscriptionName": "$SUBSCRIPTION_NAME",
    "creationMode": "Manual"
  },
  "url": "https://management.azure.com/",
  "authorization": {
    "parameters": {
      "tenantid": "$TENANT_ID",
      "serviceprincipalid": "$SP_ID",
      "authenticationType": "spnKey",
      "serviceprincipalkey": "$SP_KEY"
    },
    "scheme": "ServicePrincipal"
  },
  "type": "azurerm",
  "isShared": false,
  "isReady": true
}
EOF

az devops service-endpoint create \
  --service-endpoint-configuration /tmp/service-connection.json \
  --project "$PROJECT"
```

## Branch Policy Automation

Apply standardized policies across all repos:

```bash
apply_branch_policies() {
  local branch=$1
  local project=$2

  REPOS=$(az repos list --project "$project" --query "[].id" -o tsv)

  for repo_id in $REPOS; do
    echo "Applying policies to repo: $repo_id"

    # Minimum approvers
    az repos policy approver-count create \
      --blocking true --enabled true \
      --branch "$branch" --repository-id "$repo_id" \
      --minimum-approver-count 2 --creator-vote-counts true

    # Require linked work items
    az repos policy work-item-linking create \
      --blocking true --enabled true \
      --branch "$branch" --repository-id "$repo_id"

    # Build validation
    BUILD_ID=$(az pipelines list --query "[?name=='CI'].id" -o tsv | head -1)
    if [[ -n "$BUILD_ID" ]]; then
      az repos policy build create \
        --blocking true --enabled true \
        --branch "$branch" --repository-id "$repo_id" \
        --build-definition-id "$BUILD_ID" \
        --queue-on-source-update-only true
    fi
  done
}
```

## Multi-Environment Deployment

```bash
deploy_to_environments() {
  local run_id=$1
  shift
  local environments=("$@")

  # Download artifacts
  ARTIFACT_NAME=$(az pipelines runs artifact list --run-id "$run_id" --query "[0].name" -o tsv)
  az pipelines runs artifact download \
    --artifact-name "$ARTIFACT_NAME" --path ./artifacts --run-id "$run_id"

  # Deploy sequentially per environment
  for env in "${environments[@]}"; do
    echo "Deploying to: $env"

    DEPLOY_RUN_ID=$(az pipelines run \
      --name "Deploy-$env" \
      --variables ARTIFACT_PATH=./artifacts ENV="$env" \
      --query "id" -o tsv)

    # Wait for deployment
    while true; do
      STATUS=$(az pipelines runs show --run-id "$DEPLOY_RUN_ID" --query "status" -o tsv)
      if [[ "$STATUS" != "inProgress" && "$STATUS" != "notStarted" ]]; then
        break
      fi
      sleep 10
    done

    RESULT=$(az pipelines runs show --run-id "$DEPLOY_RUN_ID" --query "result" -o tsv)
    if [[ "$RESULT" != "succeeded" ]]; then
      echo "Deployment to $env failed"
      exit 1
    fi
  done
}

# Usage
deploy_to_environments "$RUN_ID" dev staging prod
```

## Pipeline Secret Variables

```bash
# Create secret variable (value not visible after creation)
az pipelines variable create --name "API_KEY" --value "$SECRET" --secret true --pipeline-name "CI"

# Use environment variable to avoid shell history
export AZURE_DEVOPS_EXT_PIPELINE_VAR_API_KEY="$SECRET"
az pipelines variable create --name "API_KEY" --secret true --pipeline-name "CI"

# Variable group with secrets
az pipelines variable-group variable create \
  --group-id "$VG_ID" --name "DB_PASSWORD" --value "$PASSWORD" --secret true
```
