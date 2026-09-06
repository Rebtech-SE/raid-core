# The ticket brief

The one shape every RAID ticket body uses, wherever it came from. `triage` rewrites an
incoming issue into it, `to-tickets` publishes a breakdown in it, `wayfinder` uses it for
a decision ticket, and `raid-mode` uses the same fields when briefing a subagent. One shape
means a ticket written by any of them is picked up by any of the others with no translation.

**Seven sections, in this order:**

```
Goal
Scope
Context
Acceptance
Verify
Forbidden
Blocked by
```

A field you cannot fill is a ticket that is not ready. Do not apply `ready-for-agent` to it.

---

## Goal

One or two sentences. The outcome, from the consumer's point of view, executable by someone
with no access to the conversation that produced it. Not a layer-by-layer implementation
list.

> Ship a `dim_customer` SCD2 dimension so the sales report can show the segment a customer
> was in at the time of each order, not just their segment today.

## Scope

What this ticket may change and what it must not. Name **models, layers and domains in the
project's own vocabulary**, not file paths -- paths go stale, `GLOSSARY.md` terms do not.
State the branch or worktree convention if the project has one, and the environment the
work happens in.

> May change: the silver conform and gold dimension for customer. Must not touch the
> bronze load or any other dimension. Branch `feature/*` off `origin/main`; build in dev.

## Context

Pointers, not prose. The parent spec or issue, the ADR that settled the grain, the
`design.html` section that fixes the entity model, the prior ticket this builds on, the
source-profiling report from `data-investigator`. Paste in anything a cold agent needs that
currently lives only in a conversation -- a subagent cannot see its siblings and a pickup
agent cannot see last week.

## Acceptance

Checkable criteria, one per line, as a task list. Every box ticked against the real
artifact, never a self-report.

For data work at least one criterion is a **statement about the data**, not about the code:

- [ ] `dim_customer` is unique on `customer_key` (grain check passes)
- [ ] every `fct_order.customer_key` resolves in `dim_customer` (no orphans)
- [ ] row count reconciles to source within the documented late-arrival window
- [ ] a customer with a segment change has exactly two rows, non-overlapping validity

## Verify

The exact commands that prove Acceptance, plus known gotchas. Prefer the project's own
`verify-<platform>` skill and its data map (see `create-verification-skill`) over commands
composed here. A pickup agent runs these before calling the work done.

> `dbt build --select +dim_customer`, then the proof query in
> `.agents/skills/verify-fabric/data-map/dim_customer.md`. Gotcha: the source extract lands
> at 03:00 UTC; run after that or the reconciliation will be short by a day.

## Forbidden

Actions this ticket may not take, beyond the standing rules in `raid-core/AGENTS.md`. On a
customer estate this section is not boilerplate -- it is the written form of the autonomy
boundary:

> No writes to production. No backfill, truncate or overwrite of existing tables in any
> environment. No schema change to bronze. No dependency bumps. No changes outside the
> customer domain.

## Blocked by

The tickets that gate this one, or `None -- can start immediately`. Use the tracker's
**native** blocking relation as well when it has one, so the frontier renders in the
tracker's own UI. Never leave a known dependency in prose only.
