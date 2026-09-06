# Writing Agent Briefs

Adapted from ossian-stack `skills/triage/AGENT-BRIEF.md`, translated for data
work. An agent brief is what an issue or PR body becomes when it moves to
`ready-for-agent`. It is the authoritative specification that an agent working
through `raid-mode` will build from. The original report and discussion are
context -- the brief is the contract.

**It uses RAID's standard ticket-brief shape: Goal, Scope, Context, Acceptance,
Verify, Forbidden, Blocked by.** That is the same shape `to-tickets`
publishes, `wayfinder` gives a decision ticket, and `raid-mode` uses to brief a
subagent -- one shape, so a ticket from any of them is picked up by any of the
others with no translation. The section definitions live in `to-tickets`'
`references/ticket-brief.md`; this file is the data-shaped guidance for filling
them in during triage.

**Rewrite the ticket body, do not only comment.** The pickup loop reads the
body. A Verify or Blocked by that exists only in a comment is one an agent will
not see. On a tracker whose issues are page-bodied, the body rewrite *is* the
brief; post a short readiness summary as the comment and let it point at the
body.

The brief states **what the agent should do**: for an issue, building the
change from nothing (a Bronze ingestion, a Silver conform, a Gold measure); for
a PR, what is left to do *to the existing diff* -- finish it, close gaps,
address review points. Same principles either way.

## Principles

### Durability over precision

The issue may sit in `ready-for-agent` for days or weeks. The codebase will
change in the meantime. Write the brief so it stays useful even as models are
renamed, moved, or refactored.

- **Do** describe contracts: the model's grain, its keys, its output columns
  and types, the load pattern (full/incremental/SCD), the layer it belongs in
- **Do** name the business concepts by their `GLOSSARY.md` terms, and any
  config shapes or interfaces (dbt model contract, notebook parameters,
  pipeline trigger) the agent should look for or modify
- **Don't** reference file paths -- they go stale
- **Don't** reference line numbers
- **Don't** assume the current model graph will remain the same

### Behavioral, not procedural

Describe **what** the data should look like, not **how** to build it. The
agent will explore the codebase fresh and make its own implementation
decisions, following the repo's conventions.

- **Good:** "`gold.orders` carries one row per order line per day (grain:
  order_line x business_date); late-arriving events are restated in the
  affected partitions on the next run"
- **Bad:** "Open models/gold/orders.sql and change the join on line 42"
- **Good:** "`net_sales` excludes cancelled and returned lines, per the
  glossary definition; the measure is exposed in the `fct_sales` presentation
  model, not computed in the BI layer"
- **Bad:** "Add a COALESCE somewhere so the nulls go away"

### Complete, data-checkable acceptance criteria

The agent needs to know when it is done, and on this work "done" is checked
against real data. Every criterion should be independently verifiable with a
query or a test.

- **Good:** "Row count in `silver.orders` reconciles with the source extract
  for the same period within the documented tolerance; the reconciliation
  query is pasted in the PR"
- **Good:** "`dbt build` passes and the grain-uniqueness test on
  `order_line_id + business_date` is green"
- **Bad:** "Data looks correct"

### Explicit scope boundaries

State what is out of scope. This prevents the agent from gold-plating or
making assumptions about adjacent models.

### Verification expectations

State what must be validated against real data before the work is reviewable,
and what access the agent has. If triage could not validate (no read access),
the brief says so and labels the upstream claim **"not validated against
data"** -- the building agent re-raises rather than inheriting the doubt
silently.

## Template

```markdown
**Category:** bug / enhancement

## Goal

One or two sentences: the outcome, from the consumer's point of view. For a
bug, what should hold instead of the broken behaviour -- with the numbers
triage observed and whether they were validated against real data. For an
enhancement, what the platform should do that it does not do now. State the
grain, the keys and the load pattern, plus the edge cases (late-arriving data,
nulls, source restatements).

For a PR, the Goal is what is left to do *to the existing diff* -- finish it,
close the gaps, address the review points -- not a rebuild from scratch.

## Scope

The models, layers and domains this may change, and what it must not touch.
Named in `GLOSSARY.md` vocabulary, not file paths. Include the contracts that
must hold:

- `silver.orders` grain and uniqueness -- what changes and why
- downstream consumers -- which marts, reports or extracts read this model
- config shape -- new parameters, variables or triggers needed
- the branch or worktree convention, and the environment the work happens in

## Context

Pointers a cold agent needs: the original issue and its evidence, the ADR that
settled the grain, the `design.html` section that fixes the entity model, the
profiling report, the prior ticket this builds on. Plus the domain terms this
work depends on:

- `net_sales` -- per `GLOSSARY.md`; this work implements it, it does not
  redefine it

## Acceptance

- [ ] specific, data-checkable criterion 1
- [ ] specific, data-checkable criterion 2

At least one criterion is a statement about the data, not the code.

## Verify

The exact commands that prove Acceptance -- the project's `verify-<platform>`
skill and its proof queries where they exist -- plus the reconciliation to run
(row-count parity, grain uniqueness, null rates, before/after parity) and any
gotcha about when the source lands. State whether read access is available; if
it is not, say so here so the agent labels its result "not validated against
data" rather than discovering the gap at the end.

## Forbidden

What must not happen beyond the standing rules: no production writes, no
backfill or overwrite without a go-ahead, no grain change, nothing outside the
scope above. Plus the adjacent work that looks related and is not.

## Blocked by

The tickets that gate this one, or `None -- can start immediately`. Use the
tracker's native blocking relation as well where it has one.
```

## Example: bug brief

```markdown
**Category:** bug

## Goal

`gold.orders` carries exactly one row per `order_line_id` per `business_date`,
and late-arriving restatements update the affected rows in place on the next
run instead of appending. Today it returns 2 rows for some `order_line_id`s
over the last 3 business days -- validated against the source: 14,203 source
lines vs 14,218 model rows for the period. The duplication coincides with
source restatements arriving after the daily load.

## Scope

May change: the `gold.orders` model and its incremental strategy. Must not
change its grain (`order_line_id` x `business_date`) or anything upstream in
silver. Downstream `fct_sales` and the revenue dashboard read this model and
must not see a grain change. Branch `feature/*` off `origin/main`; build in dev.

## Context

- Reported in #418, with the reconciliation query and its output.
- `order` per `GLOSSARY.md` -- cancelled orders are excluded from this model.
- The restatement behaviour of the source is profiled in the investigation
  report linked from #418.

## Acceptance

- [ ] grain-uniqueness test on `order_line_id` + `business_date` passes
- [ ] row counts reconcile with the source for the affected period
- [ ] the backfill of the affected days is included and reconciled
- [ ] load runs after a restatement are idempotent (a re-run changes nothing)

## Verify

`dbt build --select +gold.orders`, then the reconciliation in
`.agents/skills/verify-<platform>/data-map/gold-orders.md`. Read access:
available. Gotcha: the source extract lands at 03:00 UTC; running before that
makes the reconciliation short by a day.

## Forbidden

No production writes. The backfill of the affected days is part of this work
but stays a gated step -- queue it with the proposed range, do not run it.
Do not change the model's grain. Do not backfill periods before the current
quarter.

## Blocked by

None -- can start immediately.
```

## Example: PR brief

For a PR, the Goal describes what is left to do to the diff, and Context points
at the diff itself.

```markdown
**Category:** enhancement

## Goal

Finish the contributor's incremental-load change to `silver_customers`. The PR
converts the full-refresh load to incremental using an ingestion-timestamp
watermark and the happy path works. Two gaps remain: the watermark is not
persisted between runs, and there is no before/after parity check.

## Scope

May change: `silver_customers` and its incremental config, plus the parity
check. Must not touch the bronze load or any downstream mart.

## Context

PR #221 and its review comments. The watermark pattern this should follow is
in `silver_products`.

## Acceptance

- [ ] re-running the incremental load changes nothing (idempotent)
- [ ] parity between the old full-refresh output and the incremental output for
      the same period
- [ ] late-arriving updates are picked up on the next run

## Verify

Full-refresh into a scratch schema, then the incremental path, then diff row
count, key set and column checksum. Read access: available.

## Forbidden

No production writes. Do not force-push over the contributor's commits.

## Blocked by

None -- can start immediately.
```

## Bad brief

```markdown
**Summary:** Fix the orders thing

**What to do:**
Orders are broken. Look at the orders model and fix it.
The join around line 150 has the issue.

**Files to change:**
- models/gold/orders.sql (line 150)
- models/staging/stg_orders.sql (line 42)
```

Bad because: it is not in the brief shape at all -- no Goal a stranger could
execute, no Scope, no Acceptance, no Verify, no Forbidden. Plus no grain, no
numbers, no validated evidence, and file paths and line numbers that will go
stale. **A section you cannot fill means the ticket is not ready: do not apply
`ready-for-agent` to it.**
