# Data change review checklist

Use these IDs to label checks and findings.

## Every review

- **correctness**. Trace changed joins, filters, and computations through the
  output. Check fan-out, dropped rows, null semantics, denominators, partitioning,
  window bounds and date/time boundaries against intent.
- **data-integrity**. Check grain, uniqueness, null rates, referential integrity and
  source-to-target parity. Compare counts and key sets. Recompute from the intended
  source population. Test that reconciliation fails when expected input is missing.
  Zero against zero is evidence only when the intended population is proven empty.
- **project-standards**. Check governing instructions and local conventions. Cite the
  rule and the changed behavior for any violation.
- **compliance-traceability**. Map requirements due in the reviewed scope to
  implementation and verification. Explicit unmet requirements due in scope are
  P1/manual/actionable. Exclude requirements explicitly deferred to future phases.
  Gaps against inferred requirements are P3/advisory. If no baseline exists,
  review against intent.

## Full only

- **testing**. Check changed invariants, realistic failure scenarios and actual
  coverage of the affected consumers. Confirm assertions can fail.
- **maintainability**. Flag duplicated business logic, hidden state and complexity
  with a concrete maintenance cost.

## Add when the diff warrants it, at either depth

| Check ID | Apply when | What to verify |
| --- | --- | --- |
| `scd-correctness` | Dimension, merge, incremental predicate or anti-join changes | Current-row guards, one current row per active key, stable surrogate keys, contiguous effective dates, late arrivals, tracked attributes and replay. Compare the watermark with every source mutation, including deletes and status-only deactivations that leave creation timestamps unchanged. |
| `pipeline-reliability` | Ingestion, schedules, retries, or orchestration change | External-call timeouts, bounded retries with backoff, idempotent reruns, partial failure, checkpoints after durable success, dependency order, alerts, freshness and rows in = loaded + rejected per batch. Verify how overlapping runs are prevented or made safe. Exercise null inputs that can fall through both branches. |
| `cost-perf` | Compute, scan or movement may increase materially | Pruning, repeated scans, skew, spill, unnecessary full refresh and estimated cost. |
| `data-security` | Sensitive data, credentials, grants or regulated scope change | Least privilege, tenant separation, masking, retention and exposure across layers. |
| `data-contract` | A consumed schema, model, event or load contract changes | Types, nullability, removals, renames, consumer compatibility and rollout. |
| `data-migration` | Persisted data or schema is changed or backfilled | Destructive DDL, preservation, ordering, idempotence, concurrent writes, parity and rollback. Inspect the review base. |
| `adversarial` | High-risk diff or roughly 50+ changed non-test, non-generated lines | Challenge assumptions and trace a plausible path to lost data, wrong numbers or a false all-clear. |
| `medallion-architecture` | Cross-layer diff in a medallion repo | Tier boundaries, skipped layers and ownership of business logic. |
| `inmon-architecture` | Cross-layer diff in an Inmon repo | Normalized EDW, subject areas, non-volatility and marts sourced from the EDW. |
| `kimball-architecture` | Cross-layer diff in a Kimball repo | Fact grain, conformed dimensions, bridges, semi-additive measures and correct serving paths. |

Choose at most one layering check from the repo's settled architecture. Use the
installed tier guidance and the engagement's existing read-only verification tools.

## Deployment Notes

For destructive DDL, a large rebuild, backfill, grain change or nullability change,
include pre-run baseline, exact post-run assertions, replay or backfill order,
rollback or restore steps, and monitoring signals. Record planned checks as such.
