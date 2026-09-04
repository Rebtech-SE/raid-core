# `/tune-workload` Usage Guide

## What This Skill Is For

`/tune-workload` is for data-workload tuning problems where:

1. You can try multiple model, query, or config variants.
2. You can run the same measurement against each variant.
3. You want the skill to keep the good variants and reject the bad ones - and prove the
   output data did not change.

It is best for "search the space and score the results" work, not one-shot implementation
work. For a known one-line fix, just make it. For a correctness review, use
`review-changes`.

## When To Use It

Use `/tune-workload` when the problem looks like:

- "This gold model takes 40 minutes to build - get it down without changing the numbers."
- "Cut the warehouse cost (slot-time / DBU / CU-seconds) of this dashboard query."
- "Find an incremental / partition / clustering strategy that scans the least data."
- "Tune the nightly pipeline so it finishes inside the SLA window."
- "Improve the data-quality rule generator without flooding valid rows with false positives."
- "Compare several join orders, materializations, or warehouse sizes against the same harness."

Choose `type: hard` when success is objective and cheap to measure (the common case):

- Model / query runtime
- Warehouse cost: bytes scanned, slot-seconds, DBU, CU-seconds
- Pipeline wall-clock / incremental-load duration
- Rows-per-second throughput
- dbt test pass rate

Choose `type: judge` when a number can be gamed or human usefulness matters:

- Usefulness / precision of generated data-quality rules or anomaly flags
- Realism of synthetic or seed test data
- Quality of generated metric / column descriptions
- Semantic equivalence of a large rewrite where exact row parity is genuinely uncomputable

## The non-negotiable: output parity

A tuning loop can always "win" by quietly returning different data - a dropped filter, a
changed grain, a deduped join. **Make output parity a hard degenerate gate on every run**
(`rowcount_delta == 0`, `checksum_match == 1`, `tests_failed == 0`). The loop is only
allowed to make a model faster or cheaper, never to change what it produces. Validate
against real data (see the engagement's hard rules) - the parity diff runs against the
actual warehouse, not a guess.

## When Not To Use It

`/tune-workload` is usually the wrong tool when:

- The fix is obvious and does not need experimentation.
- There is no repeatable measurement harness and no read access to time/cost a run.
- The "search space" is fake and only has one plausible answer.
- The cost of evaluating variants (warehouse spend) is too high to justify multiple runs.

## How To Think About It

The pattern is:

1. Define the target (the metric and its direction).
2. Build or validate the measurement harness first - including the parity diff.
3. Generate multiple plausible variants (materialization, partition/cluster key,
   incremental predicate, join order, warehouse size).
4. Run the same measurement loop against each variant.
5. Keep the variants that improve the target without breaking the parity/test gates.

The core rule is simple:

- If a hard metric captures "better," optimize the hard metric.
- If a hard metric can be gamed, add LLM-as-judge.

Example: switching a model to incremental cuts build time dramatically. That sounds good
until the incremental predicate silently drops late-arriving rows. Hard runtime says
"improved"; the parity gate (`rowcount_delta == 0`) catches that the data changed and
rejects the variant.

## First-Run Advice

For the first run:

- Prefer `execution.mode: serial`
- Set `execution.max_concurrent: 1`
- Keep `stopping.max_iterations` small
- Keep `stopping.max_hours` small
- Avoid new dependencies until the baseline and parity diff are trustworthy
- In judge mode, use a small sample and a low cost cap

The goal of the first run is to validate the harness, not to win the optimization immediately.

## Example Prompts

### 1. Model Runtime / Cost

```text
Use /tune-workload to cut the build time of the gold_orders mart.

It currently takes ~40 min on the warehouse. Try variants - incremental load on the
order_date high-watermark, clustering by customer_id, a different materialization, a
flattened join - and measure build_seconds and bytes_scanned for each.

Hard requirement: the output must be identical. Gate every variant on rowcount_delta == 0
and a checksum over (order_id, order_total) matching the baseline, and keep all dbt tests
green. Prefer the fastest variant that passes those gates.
```

### 2. Query Cost

```text
Use /tune-workload to reduce the warehouse cost of the executive dashboard query.

Compare partition-pruning predicates, pre-aggregated intermediate models, and a
materialized rollup. Measure bytes_scanned and slot_seconds per run. Do not change the
numbers the dashboard shows - gate on result parity against the current query output.
```

### 3. Data-Quality Rule Generation (judge mode)

```text
Use /tune-workload to improve our generated data-quality rules.

Run the generator against a labelled baseline dataset. Reject any run that flags more than
10% of known-good rows (false_positive_rate gate). Then use LLM-as-judge to sample the
surviving rules and score whether each catches a real, business-meaningful defect rather
than firing on legitimate variation. Optimize for mean judge score, not rule count.
```

## Choosing Between Hard Metrics And Judge Mode

Use hard metrics alone when:

- "Better" is obvious from the numbers, and parity proves the data is unchanged.

Add judge mode when:

- The numbers can improve while the real output gets worse, and exact parity is not the
  target (generated rules, synthetic data, descriptions).

Common pattern:

- Hard gates reject broken outputs and prove parity.
- Judge mode scores the surviving candidates for actual usefulness.

That hybrid setup is the best default for generator-style data work; pure hard metrics are
the default for runtime/cost tuning of existing models.
