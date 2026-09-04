# Recipes: Linear (via GraphQL API)

Used when `.raid/config.yaml` has `tracker.provider: linear`. `<TEAM>` and the team
UUID come from the `tracker.linear` block. Linear has no official CLI -- use the
GraphQL API with `curl`. Verify unfamiliar field names against Linear's public
schema before scripting them.
## Where work lives

Issues live in **Linear**, team `<TEAM>`. Use the GraphQL API
at `https://api.linear.app/graphql`.

## Credentials

`LINEAR_API_KEY` in the environment or the repo's gitignored `.env`
(`Settings -> API -> Personal API keys`). Send it as `Authorization: <key>` --
no `Bearer` prefix. Never commit or echo it.

```bash
lq() { curl -s https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d "{\"query\":$(jq -Rs . <<<"$1")}"; }
```

## Reading

```bash
# Who am I (claiming needs this id)
lq 'query { viewer { id name } }'

# One issue with everything the skills need
lq 'query { issue(id: "ENG-123") { id identifier title description
  state { name type } assignee { name } labels { nodes { name } }
  children { nodes { identifier title state { type } } }
  relations { nodes { type relatedIssue { identifier state { type } } } } } }'

# Open issues for the team
lq 'query { team(id: "<team-uuid>") { issues(filter: { state: { type: { nin: ["completed","canceled"] } } }) { nodes { identifier title } } } }'
```

Issue identifiers (`ENG-123`) work directly as the `id` argument on `issue` queries.
Resolve `<team-uuid>` once with `query { teams { nodes { id key name } } }` and
record it here.

## Conventions

- **Create**: `issueCreate(input: { teamId: "<team-uuid>", title: "...", description: "markdown" })`.
  Descriptions are plain markdown. Optional: `parentId`, `assigneeId`, `labelIds`,
  `projectId`.
- **Comment**: `commentCreate(input: { issueId: "<uuid>", body: "markdown" })`.
- **Labels**: create once per workspace with `issueLabelCreate(input: { name: "ready-for-agent" })`,
  then attach via `labelIds`. `issueUpdate` **replaces** the label set -- read,
  modify, write back.
- **Change state**: `issueUpdate(id: "ENG-123", input: { stateId: "<uuid>" })`.
  Resolve state UUIDs from
  `workflowStates(filter: { team: { id: { eq: "<team-uuid>" } } }) { nodes { id name type } }`.
  Filter on `type` (`backlog`/`unstarted`/`started`/`completed`/`canceled`), not
  on the display name -- teams rename states freely.
- **Close**: transition to a state whose `type` is `completed`.

## Pull requests as a request surface

**No.** Linear is not a code-review surface. If the engagement connects a git
platform, record that host's CLI commands here when set to `yes`.

## When a skill says "publish to the issue tracker"

Create a Linear issue on team `<TEAM>`.

## When a skill says "fetch the relevant ticket"

Run the single-issue query above (description, state, labels, children, relations)
and summarise before building.

## Wayfinding operations

The **map** is one Linear issue; each implementation unit is a sub-issue. A Linear
**project** is the better home when the plan spans more than one cycle -- use it
instead of a map issue and treat `project.issues` as the children.

- **Map**: one issue labelled `wayfinder:map`, its description carrying the plan's
  scope, decisions and open questions.
- **Unit ticket**: a sub-issue via `parentId` on `issueCreate`. Where sub-issues
  are unavailable, put `Part of: <map identifier>` at the top of the child
  description. Label `wayfinder:<type>`.
- **Blocking**: the native relation --
  `issueRelationCreate(input: { issueId: "<child-uuid>", relatedIssueId: "<blocker-uuid>", type: blocks })`
  with the blocker as `issueId` and the child as `relatedIssueId`, so the UI shows
  the dependency. Verify direction on the first edge you create. Fall back to a
  `Blocked by: ENG-n, ENG-n` line at the top of the child description.
- **Frontier query**: the map's `children` in a non-completed state, dropping any
  whose `relations` contain a `blocked_by` related issue whose `state.type` is not
  `completed`, or that already have an assignee.
- **Claim**: `issueUpdate(id: "...", input: { assigneeId: "<viewer id>" })` -- the
  session's first write.
- **Resolve**: `commentCreate` with what was built and how it was verified,
  transition to a `completed` state.
