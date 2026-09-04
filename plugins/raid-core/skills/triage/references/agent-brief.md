# Writing Agent Briefs

Adapted from ossian-stack `skills/triage/AGENT-BRIEF.md`, translated for data
work. An agent brief is a structured comment posted on an issue or PR when it
moves to `ready-for-agent`. It is the authoritative specification that an agent
working through `raid-mode` will build from. The original body and discussion
are context -- the brief is the contract.

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
## Agent Brief

**Category:** bug / enhancement
**Summary:** one-line description of what needs to happen

**Current behavior:**
What happens now. For bugs, the broken behavior -- with the numbers triage
observed (and whether it was validated against real data). For enhancements,
the status quo the feature builds on.

**Desired behavior:**
What should hold after the work is complete. State the grain, the keys, the
load pattern, and edge cases (late-arriving data, nulls, source restatements).

**Domain terms:** (glossary definitions this work depends on or sharpens)
- `net_sales` -- per GLOSSARY.md; this work implements, not redefines, it

**Key contracts:**
- `silver.orders` grain and uniqueness -- what changes and why
- Downstream consumers -- which marts/dashboards read this model
- Config shape -- any new parameters, variables, or triggers needed

**Verification expectations:**
- What must be checked against real data before review (row-count
  reconciliation, grain uniqueness, null rates, before/after parity)
- Read access available: yes/no

**Acceptance criteria:**
- [ ] Specific, data-checkable criterion 1
- [ ] Specific, data-checkable criterion 2

**Out of scope:**
- What should NOT be changed or addressed here
- Adjacent model that might seem related but is separate
```

## Example: bug brief

```markdown
## Agent Brief

**Category:** bug
**Summary:** Duplicate rows in gold.orders after late-arriving source events

**Current behavior:**
For the last 3 business days, `gold.orders` returns 2 rows for some
order_line_ids (validated against the source: 14,203 source lines vs 14,218
rows in the model for the period). The duplication coincides with source
restatements arriving after the daily load.

**Desired behavior:**
`gold.orders` carries exactly one row per order_line_id per business_date;
late-arriving restatements update the affected rows in place on the next run
instead of appending.

**Domain terms:**
- `order` -- per GLOSSARY.md; cancelled orders are excluded from this model

**Key contracts:**
- `gold.orders` grain: order_line_id x business_date -- unchanged
- Downstream: `fct_sales` and the revenue dashboard read this model and must
  not see the grain change

**Verification expectations:**
- Read access available: yes
- Before/after row-count parity against the source for the affected period,
  plus the grain-uniqueness test green

**Acceptance criteria:**
- [ ] Grain-uniqueness test on order_line_id + business_date passes
- [ ] Row counts reconcile with the source for the affected period
- [ ] The backfill of the affected days is included and reconciled
- [ ] Load runs after a restatement are idempotent (re-run changes nothing)

**Out of scope:**
- Changing the model's grain
- Backfilling periods before the current quarter
```

## Example: PR brief

For a PR, "Current behavior" describes the state of the diff, and the brief
asks the agent to finish or fix it rather than build from scratch.

```markdown
**Category:** enhancement
**Summary:** Finish the contributor's incremental-load change to silver_customers

**Current behavior:**
The PR converts the full-refresh load to incremental using an ingestion
timestamp watermark. The happy path works; two gaps remain: the watermark is
not persisted between runs, and there is no before/after parity check.

**Verification expectations:**
- Read access available: yes
- Before/after row-count and checksum parity on a full re-run vs the
  incremental path

**Acceptance criteria:**
- [ ] Re-running the incremental load changes nothing (idempotent)
- [ ] Parity between the old full-refresh output and the incremental output
      for the same period
- [ ] Late-arriving updates are picked up on the next run
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

Bad because: no category, no grain or numbers, no validated evidence, file
paths and line numbers that will go stale, no acceptance criteria, no scope
boundaries.
