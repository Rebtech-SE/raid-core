---
name: debug-data-issue
description: >-
  Use when the user says 'debug this', 'why is this number wrong', 'this pipeline/test
  is failing', 'find the root cause'. Finds the root cause of a data bug before fixing
  it - a failed notebook run, a dbt test failure, wrong numbers in a mart, a broken
  pipeline, a row-count or reconciliation mismatch. Traces the full causal chain
  (symptom -> failing transform -> upstream data) and proves the cause with a failing
  test before a minimal fix.
argument-hint: "[the symptom: error text, failing model/test, the wrong number and where, or a run/pipeline link]"
---

# RAID Debug

Find the **root cause** of a data bug and prove it, before changing anything. The
failure mode this skill exists to prevent is treating a symptom -- patching the model
that shows the wrong number when the real cause is an upstream duplicate key or a
source schema drift. In data work the symptom and the cause are often tiers apart, so
the discipline is to trace the full causal chain through the medallion layers before
touching code.

A correct data fix is **test-first**: reproduce the bug as a failing check (a dbt test,
a DQ assertion, a row-count reconciliation), then make the smallest change that turns
it green, then confirm nothing downstream regressed.

## Inputs

<input> #$ARGUMENTS </input>

The symptom in whatever form the user has it: an error/traceback from a notebook or
pipeline run, a failing dbt/test name, "the numbers are wrong" with where they're wrong,
a reconciliation mismatch, or a run/pipeline link. If the symptom is vague, get one
concrete observable (which model/table, which column/metric, expected vs actual) before
investigating -- you cannot trace a chain from "it's broken."

## Method

### 1. Capture the symptom precisely

State the observable failure exactly: the error and where it fires, or the wrong value
vs the expected value and the grain it's wrong at (per row? in aggregate? for a subset
of keys?). Note when it started if known -- a bug that appeared after a specific run or
deploy narrows the search.

### 2. Reproduce it

Get a deterministic repro before theorizing. Run the failing model/notebook/test, or
query the offending rows directly. For a "wrong numbers" bug, write the query that
exhibits the discrepancy (the count that's too high, the keys that fan out, the rows
that should exist and don't). If it isn't reproducible yet, that is the first problem
to solve -- intermittent pipeline failures often point at run-time-dependent inputs
(late-arriving data, `CURRENT_DATE` boundaries, ordering).

### 3. Trace the causal chain upstream

Walk the lineage from the symptom toward the source, one transform at a time, asking at
each hop "is the data already wrong when it arrives here, or does this step break it?"

- **Isolate the tier.** Is Gold wrong because Silver is wrong, or because the Gold
  transform is wrong over correct Silver? Query the upstream relation and check. Repeat
  until you find the first tier where the data is wrong -- that is where the cause lives,
  not necessarily where the symptom shows.
- **Hunt the usual data root causes** at that hop: a join on a non-unique key (grain
  fan-out inflating counts/SUMs), a filter dropping more rows than intended, NULL
  propagation, an SCD merge that left multiple `_is_current = true` rows or stale
  `_valid_to`, an incremental load with a gap or overlap at the run boundary, a source
  schema/type drift, a timezone/date-boundary error, a deduplication with an unstable
  `ORDER BY`.
- **Use history and prior learnings.** When the code looks deliberate but wrong,
  dispatch `raid-git-history-analyzer` to recover why it's that way (it may be fixing an
  older bug).

### 4. Confirm the root cause

Before fixing, articulate the cause as a falsifiable statement and verify it against the
data ("for keys with two source contacts, this join emits two rows, doubling the SUM --
confirmed: key X shows 2 rows, expected 1"). Do not proceed on a plausible-but-unverified
theory. If verification fails, the cause is elsewhere -- return to step 3.

### 5. Fix test-first

1. **Write the failing check** that encodes the bug at its grain -- a `unique`/
   `not_null`/relationship dbt test, a DQ assertion, or a reconciliation query. Confirm
   it fails for the right reason.
2. **Make the minimal fix at the cause**, not at the symptom tier. Fix the upstream
   transform / SCD merge / join key, not a downstream patch that masks it.
3. **Confirm green and check downstream.** The new check passes, the original symptom is
   gone, and dependent models/tests still pass (no regression, no new fan-out). Re-run
   the affected build.

### 6. Hand off

Summarize: the symptom, the verified root cause (with the tier it lived at), the fix,
and the check that now guards it. If the cause was non-obvious or likely to recur (an
SCD edge case, a source quirk, a run-boundary trap), recommend filing it on the tracker to
capture it so the next occurrence is minutes, not hours. The fix is local only -- a PR
is `commit-push-pr`.

## Rules

- Root cause before fix; symptom-patching is the failure mode to avoid.
- Test-first: a bug isn't fixed until a check that failed now passes and downstream is clear.
- Fix at the tier where the data first goes wrong, not where the symptom surfaces.
- Verify the cause against real data before changing code; never fix on an unproven theory.
- Read-only investigation until the cause is confirmed; repo-relative paths.
