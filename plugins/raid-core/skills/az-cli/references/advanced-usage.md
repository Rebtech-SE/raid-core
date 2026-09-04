# Advanced Usage: Output, Queries & Parameters

## Output Formats

All commands support multiple output formats via `--output` / `-o`:

```bash
az pipelines list --output table    # human-readable
az pipelines list --output json     # default, machine-readable
az pipelines list --output jsonc    # colored JSON
az pipelines list --output tsv      # tab-separated, best for shell scripts
az pipelines list --output yaml     # YAML format
az pipelines list --output none     # suppress output (execute only)
```

## JMESPath Queries

Filter and transform output with `--query`:

```bash
# Filter by name
az pipelines list --query "[?name=='myPipeline']"

# Select specific fields
az pipelines list --query "[].{Name:name, ID:id}"

# Chain filter + select
az pipelines list --query "[?name.contains('CI')].{Name:name, ID:id}" -o table

# First result / top N
az pipelines list --query "[0]"
az pipelines list --query "[0:5]"
```

### Multi-Condition Filtering

```bash
# AND conditions
az pipelines list --query "[?name.contains('CI') && enabled==\`true\`]"

# Filter runs by status and result
az pipelines runs list --query "[?status=='completed' && result=='succeeded']"

# Sort descending
az pipelines runs list --query "sort_by([?status=='completed'], &finishTime) | reverse(@)"

# Filter then take top N
az pipelines runs list --query "[?result=='succeeded'] | [0:5]"
```

### Nested Property Extraction

```bash
# Extract nested objects
az pipelines show --id $ID --query "{Name:name, Repo:repository.{Name:name, Type:type}, Folder:folder}"

# Build details
az pipelines build show --id $ID --query "{ID:id, Number:buildNumber, Status:status, Result:result, Requested:requestedFor.displayName}"

# Work item fields
az boards work-item show --id $ID --query "{Title:fields.\"System.Title\", State:fields.\"System.State\", Iteration:fields.\"System.IterationPath\"}"
```

### Aggregation and Deduplication

```bash
# Unique reviewers across PRs
az repos pr list --query "[].reviewers[] | unique_by(@, &displayName)"

# Count by grouping
az pipelines runs list --query "length([?result=='succeeded'])"

# Find longest running builds
az pipelines build list --query "sort_by([?result=='succeeded'], &queueTime) | reverse(@) | [0:3].{ID:id, Number:buildNumber}"
```

### Defaults and Conditionals

```bash
# Default values with ||
az pipelines show --id $ID --query "{Name:name, Folder:folder || 'Root', Description:description || 'No description'}"

# Ternary expression
az pipelines list --query "[].{Name:name, Status:(enabled && 'Enabled' || 'Disabled')}"
```

## Global Arguments

| Flag | Description |
|---|---|
| `--help` / `-h` | Show command help |
| `--output` / `-o` | Output format (json, jsonc, none, table, tsv, yaml, yamlc) |
| `--query` | JMESPath query string |
| `--verbose` | Increase logging verbosity |
| `--debug` | Show all debug logs |
| `--only-show-errors` | Suppress warnings |
| `--yes` / `-y` | Skip confirmation prompts |

## Common Parameters

| Flag | Description |
|---|---|
| `--org` / `--organization` | Azure DevOps organization URL |
| `--project` / `-p` | Project name or ID |
| `--detect` | Auto-detect org/project from git remote |
| `--open` | Open resource in web browser |

## Git Aliases

```bash
# Enable git aliases for DevOps commands
az devops configure --use-git-aliases true

# Then use git directly
git pr create --target-branch main
git pr list
git pr checkout 123
```

## Getting Help

```bash
az devops --help              # command group help
az repos pr create --help     # specific command help
az find "az repos pr create"  # search for examples
```
