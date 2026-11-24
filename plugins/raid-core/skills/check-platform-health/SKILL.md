---
name: check-platform-health
description: >-
  Use for 'is the platform healthy', 'are the tables fresh', 'check the pipelines', 'what's
  broken in production'. Read-only pulse: runs, freshness, DQ failures.
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
  gold marts", "the nightly ingestion job"). Blank = the key targets the repo shows
  (gold/silver tables, the scheduled pipelines) or, if none are evident, ask once what to watch.
- `--since <window>` (optional): how far back for run history (default: last 24h / last few runs).

## Workflow

### 1. Resolve platform and scope

Read the platform off the repo (the dbt project and its adapter, Fabric item folders,
`databricks.yml`, BigQuery/Dataform) or the stack its `AGENTS.md` states, and the audit and
SCD column names the freshness check keys on from the models themselves (the `scd-pattern` /
`medallion-architecture` defaults are `_ingestion_timestamp` / `_valid_from`).
Determine the scope (argument -> repo -> ask). If the repo does not settle the platform, ask
once.

### 2. Gather signals using the tier skill

Use the installed tier skill for commands and connection details. Query only
the resolved scope and time window.

- **Fabric** -> `operate-fabric`: recent jobs via `fab`, freshness via the SQL
  endpoint, and recent assertion results.
- **Databricks** -> `operate-databricks`: job and pipeline history, freshness and
  quality via read-only SQL.
- **BigQuery** -> `operate-bigquery`: recent jobs via `INFORMATION_SCHEMA.JOBS_BY_PROJECT`,
  and partition-scoped freshness and quality checks. Dry-run before querying.

When no tier is installed for this platform (core-only, AWS, or another warehouse),
gather the same signals yourself with the platform's own CLI or SQL endpoint, read-only,
confirm each command with `--help` or the provider docs before relying on it, and report any
signal you could not gather as unknown.

### 3. Score each dimension

Turn the signals into a status per dimension:

- **Run health:** OK = latest runs succeeded; WARN = a transient/retried failure or a run
  overdue vs schedule; ALERT = a current failed run or a job that hasn't run when it should have.
- **Freshness:** compare `now - latest data timestamp` against the table's expected cadence
  (from the job's schedule, or stated by the user). OK within cadence; WARN approaching the bound; ALERT
  past it (stale data reaching consumers).
- **Data quality:** OK = assertions/tests green; WARN = non-blocking check failures or rising
  dead-letter volume; ALERT = a failed gate or integrity violation on a consumed table.

Be honest about unknowns -- if a signal couldn't be gathered (no permission, missing run
history), report it as "unknown", not "OK". A silent gap reads as health it didn't verify.

### 4. Report the pulse

Print a compact status board, then the detail only for what needs attention:
Apply `unslop` as a write-through constraint on the detail lines.

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
- Use the installed tier skill for read-only probes (otherwise gather read-only yourself, see step 2); keep this skill platform-agnostic.
- Unknown != OK -- report signals you couldn't gather as unknown.
- Repo-relative paths.
- Right-size the run: three dimensions, cheap probes (dry-run BigQuery probes first); don't full-scan to check freshness.
