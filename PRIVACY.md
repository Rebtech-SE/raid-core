# Privacy & Data Handling

This repository contains the RAID plugin marketplace for Claude Code (and
GitHub Copilot CLI, which installs the same plugins natively): the
`raid-core` plugin plus per-platform tiers (`raid-fabric`, `raid-gcp`,
`raid-aws`, `raid-databricks`), made of markdown skills, subagent definitions,
and the telemetry hook.

## Summary

- The plugins contain **one opt-in telemetry purpose**, registered as two hook
  entries in one file — a Claude `PostToolUse` hook and a `SessionStart`
  hook — and it is **opt-in**: per engagement repo (`.raid/config.yaml`), or, for
  a global install, per machine (`~/.raid/config.yaml`). By default it sends
  nothing; a per-repo config always takes precedence over the global one.
- Without a recorded opt-in, no data ever leaves your machine because of these
  plugins. There is no background service, no install tracking, and no
  analytics code beyond the hook described below.
- Data otherwise leaves your machine only when your AI host (Claude Code and
  its model provider) or an explicitly invoked integration (e.g. `az`, `fab`,
  `dbt` against your own services) performs a network request. That behavior
  is controlled by those tools, not by this repository.

## The opt-in usage telemetry, precisely

**What it is.** `raid-core` ships a telemetry hook in two harness-specific
forms, registered together in `plugins/raid-core/hooks/hooks.json`:
- **Claude Code** — a `PostToolUse` hook (`plugins/raid-core/hooks/telemetry.sh`)
  that observes each RAID skill invocation (one event per skill).
- **GitHub Copilot** — a `SessionStart` hook
  (`plugins/raid-core/hooks/telemetry-copilot.sh`) that fires once per
  RAID-configured session (Copilot can't reliably observe individual skill
  invocations), with `skill_name` set to the sentinel `"copilot:session-start"`.

  Both hosts *execute* this second hook, because `SessionStart` is the only event
  name Claude Code accepts (an unrecognised one makes it reject the whole plugin).
  Under Claude Code the script exits immediately without reading config, sending, or
  writing anything: it reports only when the host marks itself as Copilot
  (`COPILOT_CLI` / `COPILOT_PLUGIN_ROOT`). Claude sessions are covered by the
  per-skill hook above and never produce a session event.

Both are governed by the identical opt-in gate and kill switch below and send the
identical payload shape.

**When it sends.** Only when an opt-in config contains a `telemetry:` block with
`enabled: true`. The hook checks the current repo's `.raid/config.yaml` first;
when there is none, it falls back to a global `~/.raid/config.yaml` (so a global
install — the default on Copilot — can report). The per-repo block is written by
the `setup-raid` skill and the global one during install (`INSTALL.md`), in both
cases **only after an explicit yes**. Precedence is deliberate: if a per-repo
`.raid/config.yaml` exists it alone governs — even without a `telemetry:` block —
so a globally opted-in user never leaks telemetry into a client repo that didn't
opt in. No config at either location, `enabled: false`, or any error reading the
config: the hook exits silently. rebtech consultants are instructed to leave
telemetry off on client-owned devices unless the engagement agreement covers it.

**What it sends — the complete payload:**

```json
{
  "ts": "<UTC timestamp>",
  "skill_name": "<name of the RAID skill invoked>",
  "plugin_version": "<release identifier of raid-core (commit SHA) or 'unknown'>",
  "engagement_id": "<the id you configured in .raid/config.yaml>",
  "session_id": "<Claude Code's random session id>",
  "installation_id": "<random pseudonym, see below>"
}
```

No prompts, no code, no file paths, no repository contents, no usernames, no
hostnames, no IP-derived identity is collected by the hook. Only invocations
of RAID skills (those namespaced `raid-core:`/`raid-fabric:`/other `raid-*`
tiers) are reported; invocations of any other skill — your own, another
plugin's — are ignored entirely.

**About `installation_id` (pseudonymous data).** This is a random value
generated once per engagement checkout and stored, gitignored, in
`.raid/installation_id`. Its only purpose is to let rebtech count *how many
different people* worked on an engagement (`COUNT(DISTINCT installation_id)` per
`engagement_id`) — not who they are. It is **not** a global machine identifier:
it is scoped to a single engagement repo and regenerated for each checkout, so
one person's activity is never linkable across engagements, and there is no
rebtech-wide profile of any individual. It contains no name and is not derived
from your username, hostname, or IP. Because it is nonetheless a persistent
pseudonymous identifier, we treat it as personal data under the GDPR: it is sent
only under the same opt-in, and on client-owned devices consultants leave
telemetry off unless the engagement agreement covers anonymised toolkit-usage
metrics. To reset it, delete `.raid/installation_id` (a new random id is created
on the next run).

**The global opt-in is a deliberate exception.** When telemetry is enabled
globally (`~/.raid/config.yaml`, for a global install), the id lives at
`~/.raid/installation_id` and events carry `engagement_id: "global"`. Off any
engagement repo there is no per-checkout boundary, so this global id is a
**persistent per-machine pseudonym** — unlike the per-repo id, it *can* link one
machine's global sessions to each other over time. It still contains no name and
is not derived from your username, hostname, or IP; it is still sent only under
the explicit global opt-in; and it is still GDPR personal data. This is why
consultants leave telemetry off on client-owned devices unless the engagement
agreement covers it. To reset it, delete `~/.raid/installation_id`.

**Where it goes.** An HTTPS endpoint operated by rebtech
(`https://raid-plugin-telemetry.azurewebsites.net/api/ingest`), which stores
events for aggregate analysis of skill usage. The request is fire-and-forget
with a 3-second timeout; if the endpoint is unreachable, nothing happens.

**How to turn it off.**

- Per repo: remove the `telemetry:` block from `.raid/config.yaml` (or set
  `enabled: false`).
- Globally: remove the `telemetry:` block from `~/.raid/config.yaml` (or set
  `enabled: false`, or delete the file).
- Per machine, regardless of config: set the environment variable
  `RAID_TELEMETRY_DISABLED=1`.
- Entirely: uninstall the plugins.

## Data Ownership and Retention

Telemetry events are retained by rebtech for product-improvement analysis of
the RAID toolkit itself. They contain no customer project data. Data handling
for model prompts or external services you invoke is governed by those
services.

## Security Reporting

If you identify a security issue in this repository, contact rebtech via
`dev.azure.com/rebtech` or your engagement contact.
