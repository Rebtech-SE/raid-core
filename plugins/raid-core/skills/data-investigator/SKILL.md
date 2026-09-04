---
name: data-investigator
description: >-
  Triggers include 'profile a source', 'investigate data', 'data audit', 'understand the
  source', 'source discovery'. Tech-agnostic methodology for investigating and profiling
  a data source before modeling it: defines the investigation phases, the report
  template, and the sufficiency rubric that decide when a source is understood well
  enough to build on. Platform execution layers (e.g. investigate-fabric-source) map
  these phases to concrete tooling.
---

# Data Investigator (methodology)

The platform-agnostic methodology for understanding a data source before you model it. This
skill defines *what* to find out and *when you know enough*. Platform skills (e.g.
`investigate-fabric-source` in raid-fabric) define *how* to run each probe with real tooling.

Investigate to answer one question: **can I trust this source enough to build on it, and
what will break if I do?**

## Investigation phases

Run these in order; each narrows uncertainty before the next.

1. **Shape** -- what objects exist, their columns and types, and approximate row counts.
   Output: an inventory of tables/files in scope.
2. **Grain** -- what does one row mean? Find the true unique key (test it -- a claimed key
   with duplicates is the most common and most damaging surprise).
3. **Completeness** -- null rates per column, mandatory vs optional, default/sentinel values
   masquerading as data (`-1`, `1900-01-01`, `'N/A'`).
4. **Distribution** -- cardinality, value ranges, date ranges, skew. Spot enums, outliers,
   and columns that are secretly free text.
5. **Integrity** -- do foreign keys resolve? Orphan rate? Referential assumptions the source
   does not actually enforce.
6. **Change** -- how does the source change over time? Append-only or mutated in place? Is
   there a reliable change/timestamp column for incremental loads? Late-arriving data?
7. **Sensitivity** -- which columns are PII or otherwise governed; retention implications.

## Probe discipline

- Prefer cheap probes (metadata, `TOP N`, approximate distinct, sampling) before expensive
  full scans. Record sample sizes in the report.
- Test assumptions, do not assume them -- especially the primary key (phase 2) and FK
  integrity (phase 5). State each as a query and its actual result.
- Capture evidence (numbers), not impressions. "0.4% null" beats "mostly populated".

## Sufficiency rubric -- stop when all are true

You have investigated enough when you can state, with evidence:

- [ ] The grain (one row = ?) and a key that is provably unique.
- [ ] Expected volume and growth rate.
- [ ] Null/default behavior for every column you will use.
- [ ] Whether and how the source changes (incremental strategy is decidable).
- [ ] FK integrity for every relationship you will rely on.
- [ ] Which columns are PII.

If any box is unchecked, you cannot write a trustworthy data contract yet. Keep probing.

## Report template

```
# Data Report -- <source>
## Inventory (phase 1)
## Grain & key (phase 2)   -- key tested: <query> -> <result>
## Completeness (phase 3)  -- per-column null/default rates
## Distribution (phase 4)
## Integrity (phase 5)     -- FK checks: <query> -> orphan count
## Change behavior (phase 6) -- incremental column, late data, mutation pattern
## Sensitivity (phase 7)   -- PII columns, retention
## Verdict                 -- trustable? caveats? what will break downstream?
```

This report is the raw material the RAID assess stage folds into its requirements summary.
See also [data-quality-checks](../data-quality-checks/SKILL.md) for the assertions that
later enforce what this investigation discovers.
