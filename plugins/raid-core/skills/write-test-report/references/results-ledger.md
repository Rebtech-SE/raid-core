# The results ledger

`docs/testing/test-results.jsonl` -- the append-only record of every test execution across
every development cycle. It is the only thing in RAID that remembers a test failed after
the test goes green, which is what makes a test report more than a screenshot of the last
run.

## Why a committed file

RAID has no server and no runtime state store. The repo is the only durable place, so the
ledger is a file in the repo, committed with the work that produced it. That also makes
failure history reviewable in a PR and survivable across machines and people.

JSONL, not JSON: appending a line never rewrites the file, so two runs cannot clobber each
other and the diff of a cycle is the lines it added.

## Format

One JSON object per line, one line per test **execution**. Never edit or delete a line --
a correction is a new line, the same as any other append-only store.

```json
{"cycle":"2026-08-18-001","ts":"2026-08-18T09:41:22Z","test_id":"silver.assignment.relationships_broker_id","name":"assignment.Broker_Id -> broker","planned_id":"TP-14","unit":"U3","layer":"silver","outcome":"fail","reason":"12 orphan rows: Broker_Id not present in broker","duration_s":4.2}
{"cycle":"2026-08-18-002","ts":"2026-08-18T14:02:10Z","test_id":"silver.assignment.relationships_broker_id","name":"assignment.Broker_Id -> broker","planned_id":"TP-14","unit":"U3","layer":"silver","outcome":"pass","reason":null,"duration_s":3.9}
```

| Field | Required | Notes |
|---|---|---|
| `cycle` | yes | `YYYY-MM-DD-NNN`, one per work cycle. Every line from that run shares it. |
| `ts` | yes | UTC ISO-8601, when the test ran |
| `test_id` | yes | Stable identifier -- the dbt test name, notebook assertion id, or `<layer>.<model>.<check>`. **Stability matters more than beauty**: it is the key that joins a failure in cycle 3 to the pass in cycle 9. Renaming it silently breaks the history. |
| `name` | yes | Human-readable, for the report |
| `planned_id` | no | The id of the planned test in `testplan.html` / the plan unit. Absent means unplanned -- surfaced in the report as coverage drift, not hidden. |
| `unit` | no | The plan's U-ID this ran under |
| `layer` | no | bronze/silver/gold, staging/edw/mart, staging/dimension/fact |
| `outcome` | yes | `pass` \| `fail` \| `error` \| `skip`. `fail` = assertion failed; `error` = the test could not run. |
| `reason` | on failure | **Required whenever outcome is not `pass`.** A failure line with a null reason is a defect in the writer, not a terse entry -- the story this serves asks for the reason explicitly. |
| `duration_s` | no | Seconds |

## Writing to it

The `raid-mode` work loop appends after each unit's tests. Create `docs/testing/` and the file if absent.

```bash
mkdir -p docs/testing
cat >> docs/testing/test-results.jsonl <<'LEDGER'
{"cycle":"...","ts":"...","test_id":"...","name":"...","outcome":"pass","reason":null}
LEDGER
```

Harvest outcomes from what the platform already produces rather than re-running anything:

| Source | Where the outcomes are |
|---|---|
| dbt | `target/run_results.json` -- one result per node, with `status`, `message`, `execution_time` |
| dbt `store_failures` | the DLQ tables hold the failing rows; the table name identifies the test |
| Fabric notebooks | job status via `fab job run`, plus the DQ assertions the unit ran |
| Great Expectations | the validation result JSON |

`run_results.json` is overwritten every run -- that is exactly why its contents are copied
into the ledger rather than pointed at.

## Reading it

`write-test-report` reads the whole file, groups by `test_id`, and derives:

- **current state** -- the outcome of the newest line per `test_id`
- **failure history** -- every `test_id` with any `fail`/`error` line, including ones whose
  newest line is a pass (reported as *failed earlier, green now*)
- **coverage** -- planned tests with no ledger line at all
- **cycle trend** -- pass rate per `cycle`

## Keeping it honest

- **Append only.** No edits, no deletions, no rewriting history to make a cycle look clean.
- **Never reset it between cycles.** Truncating the ledger destroys the one thing it is for.
- **Keep `test_id` stable across renames.** If a test genuinely must be renamed, append a
  line recording the rename rather than rewriting the old ones.
- It grows slowly (one line per test per cycle) and compresses well. Do not rotate it
  without deciding where the history goes.
