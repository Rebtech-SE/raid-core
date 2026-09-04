# `autofix_class` rubric (personas)

`autofix_class` describes the **intrinsic shape** of follow-up work -- it is signal,
**not an apply gate or permission**. In `mode:agent` the caller interprets findings
and owns apply; in default (interactive) mode `review-changes` applies safe fixes
itself by judgment (SKILL.md apply stage). Either way the class informs *what to do
first* and *what to flag* -- it does not mechanically decide what gets applied.

| `autofix_class` | Meaning |
|-----------------|---------|
| `gated_auto` | A concrete change is proposed in `suggested_fix`. Callers may apply after their own judgment. |
| `manual` | Actionable work that needs design input or a decision before code changes. Include `suggested_fix` when you can propose a defensible default. |
| `advisory` | Report-only -- learnings, residual risk, rollout/backfill notes. |

## Persona guidance

- Prefer `gated_auto` when you can write a defensible `suggested_fix` for a localized
  change (a missing merge predicate, a wrong join key, an absent audit column, a
  missing dbt test).
- Use `manual` when the right fix depends on product intent, the data model, or
  cross-cutting refactors (re-graining a fact table, changing an incremental
  strategy, a contract change with downstream consumers).
- Use `advisory` when nothing breaks if left unfixed but the observation has value
  (a backfill note, a residual cost risk, a modeling asymmetry).
- Do **not** invent other classes -- callers decide what to apply; reviewers classify
  and propose.

## Owner field

| `owner` | Meaning |
|---------|---------|
| `downstream-resolver` | Caller or human should act after review. |
| `human` | Judgment required before implementation (data-model or product decision). |
| `release` | Operational / rollout / backfill follow-up. |

Default actionable findings to `downstream-resolver` unless the item is genuinely
human-only (needs a data-owner or product decision) or release-owned (a
backfill, a deploy-window action, a monitoring change).
