# Planned tests

The one definition of where a unit's planned tests come from. `raid-mode` builds them,
`to-tickets` assigns them to slices, and `write-test-report` reconciles the ledger against
them. All three read this file rather than describing it themselves.

## Where they come from

Take the first source that exists, in this order:

1. **`docs/artifacts/testplan.html`, by TP id.** When the file exists, its `#per-source` and
   `#baseline` tables are the planned tests: one row per assertion, each with a stable id
   such as `TP-customer-03`. Trigger on the file, not on whether `raid-greenfield` is
   installed -- a core-only session can inherit a test plan from an earlier greenfield run.
2. **The claimed ticket's Acceptance.** No test plan, but the unit came from a ticket: its
   Acceptance criteria are the planned tests. When a test plan exists too, the Acceptance
   lists the TP ids it covers, so the two never disagree.
3. **The unit's inline DQ checks.** Neither of the above: the data-quality checks worked
   out for the unit in the conversation.

## The rules

- **Each planned test lands in exactly one unit or ticket.** A TP id in two tickets is
  built twice or claimed as done by whichever finishes first; a TP id in none is a hole
  nobody owns. `to-tickets` reports both before it publishes.
- **A planned test that cannot be built is stated, never dropped.** No source column to
  test, a threshold nobody has set, a check the platform cannot express: say which TP id,
  and why, in the unit's summary and the ticket's Resolve comment. Silence reads as a pass.
- **The id is the join key.** Every ledger line for a planned test carries it as
  `planned_id` (`write-test-report`'s `references/results-ledger.md`). With no test plan,
  `planned_id` is the ticket's Acceptance line or the unit's check name, written the same
  way every run.
- **The test plan is not a status board.** `testplan.html` is the signed-off strategy and
  stays untouched after sign-off. Whether a TP id is green lives in the ledger and the test
  report, never in a column added to the plan.
