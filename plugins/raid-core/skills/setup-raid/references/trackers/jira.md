# Recipes: Jira (via REST API)

Used when the provider in `docs/agents/issue-tracker.md` is `jira`. `<SITE>` and
`<PROJECT>` come from the identifiers in that file. If the customer ships its own Jira
CLI in the repo, prefer it over raw REST.
## Where work lives

Issues live in **Jira**, project `<PROJECT>` at `https://<SITE>.atlassian.net`.

## Credentials

`JIRA_BASE_URL`, `JIRA_EMAIL` and `JIRA_API_TOKEN` in the environment, or in the
repo's gitignored `.env`. Never commit or echo them.

```bash
jira() { curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" "$JIRA_BASE_URL/rest/api/3$1" "${@:2}"; }
```

## Issue types and workflow

**Read these from the live project before the first write** -- Jira projects are
heavily customised and a guessed type or status fails:

```bash
jira "/issue/createmeta/<PROJECT>/issuetypes"            # valid types
jira "/issue/<KEY>/transitions"                          # valid transitions for an issue
```

Record the answers in the engagement's `docs/agents/issue-tracker.md` once
discovered, with the date. A project with `Defect`
and no `Bug` is common; so is a status set that models state as workflow rather
than labels.

## Conventions

- **Create**: `POST /issue` with
  `{"fields":{"project":{"key":"<PROJECT>"},"summary":"...","description":<ADF>,"issuetype":{"name":"Story"}}}`.
  Descriptions use **Atlassian Document Format**, not markdown -- send
  `{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"..."}]}]}`
  or set `Content-Type` for the v2 API where plain text is accepted.
- **Read**: `GET /issue/<KEY>?expand=renderedFields,changelog` plus
  `GET /issue/<KEY>/comment`. Fetch attachments before concluding a ticket lacks detail.
- **Search**: `GET /search?jql=project=<PROJECT> AND statusCategory != Done ORDER BY updated DESC`.
- **Comment**: `POST /issue/<KEY>/comment`.
- **Labels**: `PUT /issue/<KEY>` with `{"update":{"labels":[{"add":"ready-for-agent"}]}}`.
  Prefer `add`/`remove` over `set` so concurrent edits by humans survive. **Many
  projects enforce a controlled label vocabulary and reject unknown strings** --
  check before inventing a label.
- **Transition**: `POST /issue/<KEY>/transitions` with the transition id from the
  transitions call above. Look the id up by the target status *name* each time; ids
  differ per workflow and are never worth recording.
- **Roles on an existing board**: when the `mapping` block's `roles` map a role to a
  `status`, "set the role" means transition to that status (plus add the mapped
  `label` if one is given, and set `resolution` in the transition payload's `fields`
  when mapped, e.g. Done / "Won't Do" for `wontfix`). Querying a role then becomes
  JQL on `status = "<name>"` (`AND labels = <label>` when both are mapped). A
  `categories` mapping means create with that `issuetype` instead of adding a
  `bug`/`enhancement` label.

## Pull requests as a request surface

**No.** Jira is not a code-review surface. Code review happens on the git host; when
the engagement's `docs/agents/issue-tracker.md` records `external_prs: yes`, take the
PR commands from that host's recipe (`github.md`, `azure-devops.md`).

## When a skill says "publish to the issue tracker"

Create an issue in `<PROJECT>` -- `Story` for a spec, `Task` for a unit of build
work, the project's defect type for a bug. Fall back to `Task` when `Story` is
unavailable.

## When a skill says "fetch the relevant ticket"

`GET /issue/<KEY>` plus its comments and attachments; summarise before building.

## Wayfinding operations

The **map** is one issue (`Epic`); each implementation unit is a child issue.

- **Map**: an `Epic` (or the `mapping` block's `wayfinder.map_issuetype`) labelled
  `wayfinder:map`, its description carrying the plan's scope, decisions and open
  questions. With `markers: body`, the label is replaced by `Type: wayfinder-map` at
  the top of the description.
- **Unit ticket**: a child issue via the epic link -- set `parent` to the epic key
  on create (`{"fields":{"parent":{"key":"<EPIC>"}}}`) on team-managed projects, or
  the project's epic-link custom field on company-managed ones. Where neither is
  available, put `Part of: <EPIC>` at the top of the description. Label
  `wayfinder:<type>` (or `Type: <type>` in the body with `markers: body`).
- **Blocking**: the native issue link --
  `POST /issueLink` with
  `{"type":{"name":"Blocks"},"inwardIssue":{"key":"<blocker>"},"outwardIssue":{"key":"<child>"}}`.
  Verify the link type name exists (`GET /issueLinkType`); fall back to a
  `Blocked by: <KEY>, <KEY>` line at the top of the description.
- **Frontier query**:
  `jql=parent = <EPIC> AND statusCategory != Done AND assignee IS EMPTY` -- then
  drop any whose `issuelinks` contain an unresolved `is blocked by`.
- **Claim**: `PUT /issue/<KEY>` setting `assignee` -- the session's first write.
- **Resolve**: comment with what was built and how it was verified, then transition
  to the project's done status.
