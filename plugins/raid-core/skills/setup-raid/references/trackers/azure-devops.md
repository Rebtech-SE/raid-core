# Recipes: Azure DevOps Boards (via `az`)

Used when the provider in `docs/agents/issue-tracker.md` is `azure-devops`. `<ORG>` and
`<PROJECT>` come from the identifiers in that file. Command shapes follow the
`az-cli` skill's `references/boards.md` -- read it for the full surface, and verify
against the installed `azure-devops` extension version before scripting anything
unfamiliar.
## Where work lives

Work items live in project `<PROJECT>` at `https://dev.azure.com/<ORG>`. Use the `az` CLI with the `azure-devops` extension.
The `az-cli` skill carries the full command reference.

## Setup (one-time per machine)

```bash
az extension add --name azure-devops
az login
az devops configure --defaults organization=https://dev.azure.com/<ORG> project=<PROJECT>
```

## Work item types and states

Types: `Epic`, `Feature`, `User Story`, `Task`, `Bug`. **Confirm against the live
project before relying on a type for a write** -- customers customise process
templates, and a type that does not exist fails at create time.

States are process-template specific (`New`/`Active`/`Resolved`/`Closed` on Agile;
`New`/`Approved`/`Committed`/`Done` on Scrum). Discover valid states from an
existing item rather than assuming.

## Conventions

- **Create**: `az boards work-item create --title "..." --type "Task" --description "..."`.
  For a long body, write the markdown to a file and pass it through a field:
  `--fields "System.Description=$(cat body.md)"`.
- **Read**: `az boards work-item show --id <id> --expand all` (fields + relations).
  Comments are a separate REST call:
  `az rest --method get --url "https://dev.azure.com/<ORG>/<PROJECT>/_apis/wit/workItems/<id>/comments?api-version=7.1"`.
- **List / query**: `az boards query --wiql "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.State] <> 'Closed' ORDER BY [System.ChangedDate] DESC"`.
  Useful fields: `System.Id`, `System.Title`, `System.State`, `System.AssignedTo`,
  `System.WorkItemType`, `System.Tags`, `System.IterationPath`, `System.AreaPath`.
  Macros: `@Me`, `@Today`, `@CurrentIteration`.
- **Comment**: `az boards work-item update --id <id> --discussion "..."`.
- **Labels** are `System.Tags`, a semicolon-joined string **replaced wholesale on
  write**. Read, modify, write back -- never blind-set, or you drop other people's
  tags: `az boards work-item update --id <id> --fields "System.Tags=ready-for-agent;wayfinder:task"`.
  On a customised process whose columns already model state, the `roles` in the
  `mapping` block may map a role to a `status` instead: then set `System.State` (and the mapped tag,
  if any) rather than adding a tag, and query on `[System.State]` accordingly.
- **Change state**: `az boards work-item update --id <id> --state "Active"`.
- **Close**: `az boards work-item update --id <id> --state "Closed"` (or the
  process's done state).

## Pull requests as a request surface

**No**, unless the engagement's `docs/agents/issue-tracker.md` records
`external_prs: yes`. PR commands: `az repos pr list`, `az repos pr show --id <id>`,
`az repos pr create`.

## When a skill says "publish to the issue tracker"

Create a work item (`az boards work-item create`), type `User Story` for a spec,
`Task` for a unit of build work, `Bug` for a defect.

## When a skill says "fetch the relevant ticket"

`az boards work-item show --id <id> --expand all`, plus the comments REST call
above. Summarise the context before building anything.

## Wayfinding operations

The **map** is one work item (`Epic` or `Feature`); each implementation unit is a
child work item.

- **Map**: `az boards work-item create --title "<engagement/plan name>" --type "Epic" --fields "System.Tags=wayfinder:map"`.
  Its description carries the plan's scope, decisions and open questions.
- **Unit ticket**: a child work item, linked by hierarchy --
  `az boards work-item relation add --id <child> --relation-type "System.LinkTypes.Hierarchy-Reverse" --target-id <map>`
  (Hierarchy-Reverse points a child at its parent; `az boards work-item relation list-type`
  lists the exact strings available in this org). Tag `wayfinder:<type>`.
- **Blocking**: the native predecessor/successor dependency --
  `az boards work-item relation add --id <child> --relation-type "System.LinkTypes.Dependency-Reverse" --target-id <blocker>`.
  Confirm the direction with `relation list-type`; where dependencies are
  unavailable, fall back to a `Blocked by: <id>, <id>` line at the top of the
  description.
- **Frontier query**: children of the map with no open blocker and no assignee.
  List children with a link query --
  `az boards query --wiql "SELECT [System.Id], [System.Title] FROM WorkItemLinks WHERE [Source].[System.Id] = <map-id> AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' MODE (MustContain)"`
  -- then drop any whose relations include an open predecessor (`work-item show --expand all`).
- **Claim**: `az boards work-item update --id <id> --assigned-to <me>` -- the
  session's first write, so two agents cannot pick the same unit.
- **Resolve**: `--discussion "<what was built and how it was verified>"`, then
  `--state "Closed"`.
