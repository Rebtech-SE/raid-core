# Project status

The one definition of the status view: what `raid-mode` answers to "where are we",
"project status", "what is next". It is a **Question** route: it reads and reports, and it
never writes a file, changes a status or starts a step.

## What it reads

Read what exists; skip what does not, and say nothing about what is missing unless the user
asks.

1. **Project type** -- per `references/project-type.md` (`trace.json`, else the
   `RAID project type:` line in `AGENTS.md`).
2. **`docs/artifacts/trace.json`** (format: `references/trace-file.md`) -- `project.steps`
   with status, `project.waivers`, `iterations`, and the counts of requirements, designs
   and tests.
3. **The test ledger** -- `docs/testing/test-results.jsonl` (`write-test-report`'s
   `references/results-ledger.md`): newest outcome per TP id, rolled up per level when the
   trace file gives levels.
4. **Open questions** -- `docs/artifacts/open-questions.html`: open count and blocking
   count, when it exists.
5. **The gap check** -- when `plan-project`'s `scripts/check_trace.py` (raid-greenfield) is
   installed, run it read-only and take its gap lines. Without it, count requirements
   without tests from the trace file directly.

Without a trace file, the status is the project type and the conversation's units, and
nothing else changes.

## What it shows

One short block, in this order:

- **Type** -- the project type and, for `direct`, the line "no project plan".
- **Steps** -- one row per step: done, open, or skipped with its reason.
- **Iteration** -- the open iteration, its requirements, and how many of them have a
  passing test per level.
- **Gaps** -- requirements without tests, designs without approval, items made for an older
  requirement version, open blocking questions.
- **Next step** -- the first open step in process order that is not skipped, with the skill
  that does it when that skill is installed. For the `direct` type: the next unit of work.

Apply `unslop`. Keep it to what fits on one screen; offer detail rather than printing it.
