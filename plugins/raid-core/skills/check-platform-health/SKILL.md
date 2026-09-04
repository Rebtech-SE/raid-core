---
name: check-platform-health
description: >-
  Use when the user asks 'is the platform healthy', 'check the pipelines', 'are the
  tables fresh', 'platform status', 'what's broken in production'. Takes an operational
  health pulse of the data platform you built or operate: recent pipeline/job run
  outcomes, data freshness vs expected cadence, and data-quality failures. Read-only and
  platform-aware - dispatches the platform expert to gather signals, then reports
  OK/WARN/ALERT per dimension.
argument-hint: "[optional: scope - which tables/jobs/datasets, or a platform area; --since <window>]"
---

# RAID Platform Pulse

A fast, observational health check of a **delivered** data platform -- not a build step, but
the "is it healthy right now, and what needs attention?" sweep you run on an engagement that
is live. It answers three questions and nothing more, so it stays cheap to run often:

1. **Run health** -- did the recent pipeline/job runs succeed, and when did each last run?
2. **Freshness** -- is the data as current as its cadence promises, or is something stale?
3. **Data quality** -- are DQ assertions / tests passing, or are failures piling up?

This skill is **read-only**: it observes and reports. It never re-runs a pipeline, backfills,
or mutates data -- when it finds a problem it hands off to `debug-data-issue`.

## Inputs

<input> #$ARGUMENTS </input>

- **Scope** (optional): which tables/jobs/datasets to check, or a platform area (e.g. "the
  gold marts", "the nightly ingestion job"). Blank = the key targets from `.raid/config.yaml`
  (gold/silver tables, the scheduled pipelines) or, if none recorded, ask once what to watch.
- `--since <window>` (optional): how far back for run history (default: last 24h / last few runs).

## Workflow

### 1. Resolve platform and scope

Read `.raid/config.yaml` for the platform and the naming/audit conventions (the
`_ingestion_timestamp` / `_valid_from` columns the freshness check keys on). Determine the
scope (argument -> config -> ask). If no engagement config exists, this platform isn't set up
for RAID yet -- say so and point at `setup-raid`.

### 2. Gather signals via the platform expert

Dispatch the tier's platform expert to collect the raw signals -- it owns the CLI/SDK detail,
so this skill stays platform-agnostic:

- **Fabric** -> `fabric-cli-expert`: pipeline/notebook run history and status via
  `fab job run-list` / `fab job run-status`; freshness via `MAX(_ingestion_timestamp)` /
  event-date per table over the SQL endpoint (sqlcmd); DQ via recent assertion/test results.
- **Databricks** -> `databricks-expert`: `databricks jobs list-runs` / pipeline events for run
  outcomes; freshness and DQ via `experimental aitools tools query`.
- **BigQuery** -> `bigquery-expert`: run/cost history from `INFORMATION_SCHEMA.JOBS_BY_PROJECT`;
  freshness via `MAX()` timestamp queries (dry-run-sized per that expert's cost discipline).

Pass the expert the scope and the audit-column names so it queries the right things. Ask it for
facts (counts, timestamps, statuses), not prose.

### 3. Score each dimension

Turn the signals into a status per dimension:

- **Run health:** OK = latest runs succeeded; WARN = a transient/retried failure or a run
  overdue vs schedule; ALERT = a current failed run or a job that hasn't run when it should have.
- **Freshness:** compare `now - latest data timestamp` against the table's expected cadence
  (from config, or stated by the user). OK within cadence; WARN approaching the bound; ALERT
  past it (stale data reaching consumers).
- **Data quality:** OK = assertions/tests green; WARN = non-blocking check failures or rising
  dead-letter volume; ALERT = a failed gate or integrity violation on a consumed table.

Be honest about unknowns -- if a signal couldn't be gathered (no permission, missing run
history), report it as "unknown", not "OK". A silent gap reads as health it didn't verify.

### 4. Report the pulse

Print a compact status board, then the detail only for what needs attention:

```
Platform pulse - <platform> - <scope> - <window>
  Run health   : [OK|WARN|ALERT]
  Freshness    : [OK|WARN|ALERT]
  Data quality : [OK|WARN|ALERT]

Needs attention:
  - <ALERT/WARN item> : <one-line fact> -> <recommended action>
```

Use `[OK]`/`[WARN]`/`[ALERT]` text markers. Repo-relative
paths. For each flagged item, give the concrete fact (the failed run id, the stale table and its
lag, the failing assertion) and a recommended next step.

### 5. Hand off

- A failing pipeline or wrong-data finding -> `debug-data-issue` (root-cause it).
- A recurring failure worth remembering -> file it on the engagement's issue tracker.
- All green -> say so plainly and stop; don't manufacture concerns.

## Rules

- Read-only: observe and report; never re-run, backfill, or mutate. Remediation is `debug-data-issue`.
- Dispatch the platform expert for gathering; keep this skill platform-agnostic.
- Unknown != OK -- report signals you couldn't gather as unknown.
- Repo-relative paths.
- Right-size the run: three dimensions, cheap probes (the BigQuery expert dry-runs first); don't full-scan to check freshness.
