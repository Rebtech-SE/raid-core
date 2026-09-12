# Issue-tracker recipes

One file per supported tracker: the command recipes a RAID skill needs to create,
read and work tickets there. **These are read at run time, not copied into the
engagement's repo**, so a fix to a recipe reaches every engagement on the next plugin
update instead of rotting in a hundred copies.

| Provider | Interface | File |
| --- | --- | --- |
| `azure-devops` | `az` + `azure-devops` extension (see the `az-cli` skill) | `azure-devops.md` |
| `jira` | REST API via `curl`, or a client-shipped CLI | `jira.md` |
| `linear` | GraphQL API via `curl` | `linear.md` |
| `github` | `gh` | `github.md` |
| `gitlab` | `glab` | not written yet -- mirror `github.md` |
| `local` | markdown files under `docs/tickets/` | fallback when a customer tracker is unreachable |

**The tracker is not the git host.** Azure DevOps Repos with Jira boards, and
GitHub with Linear, are both common in enterprise estates. Detect the git host
from the remote; **ask** which tracker the engagement uses.

## The engagement's `docs/agents/issue-tracker.md`

What the repo does keep is one short file saying where its tickets live. `setup-raid`
writes it when the team wants a tracker, and its absence means the engagement has none.
It documents the setup -- the tickets themselves are in the tracker. A skill reads it to
know which recipe file to open and what to fill into the recipe's placeholders:

~~~markdown
# Issue tracker

Tickets for this repo live in Jira: site `acme.atlassian.net`, project `DATA`.
The command recipes ship with RAID, in `setup-raid`'s `references/trackers/jira.md`.

- provider: jira
- site: acme.atlassian.net
- project_key: DATA

## Mapping

```yaml
roles:
  needs-triage:    { status: "To Do" }
  ready-for-agent: { status: Ready, label: agent }
  wontfix:         { status: Done, resolution: "Won't Do" }
categories:
  bug:         { issuetype: Bug }
  enhancement: { issuetype: Story }
wayfinder:
  map_issuetype: Epic
  markers: body
```
~~~

The identifiers each provider needs:

| Provider | Identifiers |
| --- | --- |
| `azure-devops` | `org`, `project` -- the Boards project, which may differ from the repo's |
| `jira` | `site`, `project_key` |
| `linear` | `team_key`, `team_id` |
| `github` | `owner`, `repo` -- usually the git remote |
| `gitlab` | `group`, `project` |
| `local` | none -- tickets are files under `docs/tickets/` |

Two optional additions, for any provider:

- `external_prs: yes` when the engagement treats external pull requests as incoming
  requests, so `triage` works them like issues. Absent means no; each recipe's "Pull
  requests as a request surface" section says which commands apply.
- A short `## Types and states` section with the item types, states and transitions
  read off the live tracker, dated -- customers customise, and a recipe says when to
  look them up.

Omit `## Mapping` when the defaults (plain labels) work, and map only the entries that
differ; see Triage roles below.

## The contract

Every file answers the same five questions in the same order, because that is what
the calling skills rely on:

1. Credentials and setup.
2. Item types and states -- and how to discover them, since customers customise.
3. The CRUD recipes: create, read, list/query, comment, label, change state, close.
4. Whether external pull requests are a request surface.
5. The **plan-map operations** -- how a plan map, its unit tickets, blocking edges
   and frontier query are physically represented here.

Where a tracker lacks a native capability, every file falls back to the same
portable body convention, so a skill written against the contract works anywhere:

- `Part of: <map-id>` at the top of a unit ticket, when there is no native parent link.
- `Blocked by: <id>, <id>` at the top of a unit ticket, when there are no native
  dependency links.

## Triage roles

The canonical roles are `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human` and `wontfix`; the categories are `bug` and `enhancement`; the
wayfinder markers are `wayfinder:map` and `wayfinder:<type>`. Skills reference the
canonical name, never a raw string, and by default each one is a plain label.

Where that does not fit an existing tracker -- board columns model state, the label
vocabulary is controlled, bug-vs-story is an issue type, as on most Jira projects and
customised Azure DevOps processes -- the engagement records what each canonical name
*means* there in the `mapping` block of `docs/agents/issue-tracker.md` (shape above).
A role maps to a label, a workflow status, or both; a category maps to an issue type;
the wayfinder markers can move from labels into body fields. Every recipe's "label"
and "change state" operations are read through that mapping: setting a role that maps
to a status means transitioning the issue, and a role with both a status and a label
means both must hold. Unmapped entries keep the label default.
