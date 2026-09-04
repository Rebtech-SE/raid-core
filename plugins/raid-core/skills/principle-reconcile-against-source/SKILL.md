---
name: principle-reconcile-against-source
description: "Use before calling any transform, migration or backfill done. A pipeline that ran is not a pipeline that is correct -- tie the numbers back to the source and show the comparison."
disable-model-invocation: true
---

# Reconcile Against Source

**A transform is not correct because it ran. It is correct because the numbers tie back.**
Run the comparison and show it.

Green is the weakest possible signal in data work. A model compiles, a job succeeds, a test
passes -- and the output can still be missing a third of the rows, double-counting a join,
or silently dropping everything with a null key. The only thing that settles it is putting
the source and the target side by side.

## What to reconcile

- **Row counts** against the source, or against the expectation when the transform is
  meant to change the count. If it changed, say by how much and why.
- **Key uniqueness and grain**, per `principle-declare-the-grain`.
- **Measure totals.** Sum the money, the quantity, the duration -- whatever the business
  actually reads -- on both sides for the same window.
- **Null and sentinel rates** on the columns that carry meaning. A column that is 40% null
  where the source is 2% null is a broken join, not a data quality finding.
- **Referential integrity** -- every FK resolves, or the orphans are counted and explained.
- **Before/after parity** for any migration, refactor or backfill. The old and the new must
  agree on the same window, or the difference must be stated and justified.

## Apply it

Run the probe yourself where you have read access; dispatch the platform expert
(`fabric-cli-expert`, `databricks-expert`, `bigquery-expert`) to execute it. Show the query
and the actual numbers in your report, not a summary of them.

**Where you have no read access, say so explicitly** and label the conclusion "not
validated against data". Lower your confidence to match. Never present an
unreconciled result as verified -- that is the failure this principle exists to prevent,
and it is the one that reaches the customer.

This is the applied form of `raid-core`'s hard rule on validating against real data; that
rule is the requirement, this is how you discharge it.

Related: `principle-prove-it-works`, `data-quality-checks`, `debug-data-issue`.
