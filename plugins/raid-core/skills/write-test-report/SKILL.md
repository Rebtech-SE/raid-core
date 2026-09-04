---
name: write-test-report
description: >-
  Use after a development cycle finishes, or when the user says 'generate the
  test report', 'what did the tests do', 'test results for this cycle'. Produces the test
  report: reconciles every planned test against what actually ran, records each outcome
  with its failure reason, and carries earlier failures forward even after a test goes
  green. Reads the append-only ledger docs/testing/test-results.jsonl plus the planned
  tests (testplan.html on a greenfield build, the plan's inline DQ checks on
  incremental work) and writes docs/testing/testreport.html from the bundled template.
argument-hint: "[optional: a cycle id, or a plan path; blank uses the newest cycle in the ledger]"
---

# RAID Test Report

The record of what the tests actually did. `write-test-plan` (raid-greenfield) says what
*will* be tested; the `raid-mode` work loop runs the tests; this skill documents the outcome after each
development cycle.

The deliverable is **`docs/testing/testreport.html`**, rendered from
`references/testreport-template.html`. It is a record, not a decision document -- there is
no approval gate on it, and it carries no approval badge.

**Works with or without `raid-greenfield`.** A greenfield build reads planned
tests from `docs/artifacts/testplan.html` when it exists; incremental work reads them from the
per-unit DQ checks inline in the session's plan. The report is written to
`docs/testing/`, beside its ledger, rather than the greenfield-owned `docs/artifacts/` --
a core-only engagement must never be made to scaffold that directory. On a greenfield
engagement, link the report from the artifacts index rather than moving it.

## What makes this more than a run summary

Three things the report must do, in order of how easily they are lost:

1. **Earlier failures survive.** A test that failed in cycle 3 still appears in cycle 9's
   report, badged as having healed, with its reason and when it last failed. A report that
   only shows the newest run is a screenshot, and it hides exactly the fragility worth
   knowing about. This is why the ledger is append-only and why the report has a Failure
   History section.
2. **Every *planned* test is represented** -- including ones that never ran. A planned test
   with no ledger entry is a coverage hole, and silence about it reads as a pass.
3. **Every failure carries its reason.** A failed row with an empty reason fails the
   requirement this report exists to satisfy.

## Inputs

<input> #$ARGUMENTS </input>

- **The ledger** -- `docs/testing/test-results.jsonl`, append-only, written by the `raid-mode` work loop as each unit's tests run.
  Format and the rules for keeping it honest: [results-ledger.md](references/results-ledger.md).
- **The planned tests** -- `docs/artifacts/testplan.html` (sections `#per-source`,
  `#baseline`) when it exists; otherwise the DQ checks the units carried when they were built.
- `$ARGUMENTS` may name a cycle id or a plan; blank means the newest cycle in the ledger.

**If the ledger is missing or empty**, say so plainly and stop -- do not render an empty
report or reconstruct outcomes by re-running tests. A report is a record of what happened,
and inventing one is worse than not having one. Point the user at the `raid-mode` work loop, which
writes the ledger as it builds.

## Workflow

### Phase 1: Read and reconcile

Read the whole ledger, not just the current cycle -- the history sections need all of it.
Group by `test_id` and derive:

- **current state** -- the outcome on the newest line per `test_id`
- **healed** -- any `test_id` with a `fail`/`error` line whose newest line is a `pass`
- **still failing** -- newest line is `fail`/`error`
- **never run** -- planned tests with no ledger line
- **unplanned** -- ledger lines with no `planned_id` (coverage drift; report, do not hide)
- **per-cycle totals** -- planned, run, passed, failed, pass rate

Reconcile against the planned tests by `planned_id`, falling back to `test_id` where the
plan predates ids. Where a planned test cannot be matched at all, list it as never run and
note the ambiguity rather than guessing.

### Phase 2: Render

Read `references/testreport-template.html`, fill every `data-fill` slot, replace every
`<!-- FILL: ... -->` comment, and write `docs/testing/testreport.html`. Keep the section
`id`s intact. Self-contained, ASCII only, repo-relative paths.

Badge outcomes: `.b-pass`, `.b-fail`, `.b-notrun`, `.b-healed`. The stat strip's numbers
must match the tables beneath it.

Right-size it: a cycle with nine tests and no failures is a short document. Do not pad the
history section with reassurance -- if nothing has ever failed, one line says so.

### Phase 3: Hand off

Report the headline to the user: planned / passing / failing / never run, and anything that
healed without explanation. If tests are still failing, another pass through the `raid-mode` work loop is the next step, not
`review-changes` -- a red cycle is not ready for review.

## Operating principles

1. **Report, never re-run.** This skill reads the ledger. It does not execute tests, and it
   never writes to the ledger -- the work loop does that as each unit's tests run. A report that runs its own tests
   is reporting on itself.
2. **Never edit the ledger to make a cycle look clean.** If a line is wrong, append a
   correction.
3. **Absence is a finding.** Planned-but-never-run and failing-with-no-reason are both
   reported prominently, not omitted for tidiness.
4. **The newest run is not the whole story.** Any test that has ever failed appears in the
   report, whatever its current colour.

## References

- [results-ledger.md](references/results-ledger.md) - ledger format, how the work loopan` writes it, how to harvest outcomes from dbt/Fabric, and the rules that keep the history trustworthy
