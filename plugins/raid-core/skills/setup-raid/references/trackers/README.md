# Issue-tracker recipes

One file per supported tracker: the command recipes a RAID skill needs to create,
read and work tickets there. **These are read at run time, not copied into the
engagement's repo.** The repo records only which provider it uses, in
`.raid/config.yaml`:

```yaml
tracker:
  provider: azure-devops
  azure_devops: { org: rebtech, project: RAID }
```

A skill that needs to publish a spec or claim a unit reads the file for that
provider here. Nothing is scaffolded into the customer's checkout, so a fix to a
recipe reaches every engagement on the next plugin update instead of rotting in a
hundred copies.

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
`ready-for-human` and `wontfix`. Skills reference the canonical role, never a raw
label. Where a tracker's strings differ -- or where it models state as workflow
status and rejects unknown labels, as most Jira projects and customised Azure
DevOps processes do -- the engagement records the mapping under `tracker.labels`
in `.raid/config.yaml`.
