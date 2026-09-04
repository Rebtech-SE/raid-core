# Platform notes

Worked examples of the guarantees in the main skill's step 2, on platforms RAID has tiers
for. **Illustration, not a template.** Read the entry for your platform if one exists, then
derive your own answers from the platform in front of you. Every entry here contains at
least one fact that is false on the other platforms.

If your platform is not listed, that is normal -- there are far more warehouses than
entries here. Work the guarantee list in the main skill with the tier's expert agent, and
add an entry here afterwards if the engagement produced one worth keeping.

## The trap this file exists to prevent

The obvious move is to copy a working wrapper from the last engagement. It fails in ways
that are quiet rather than loud:

- **A read-only statement list does not transfer.** `SELECT` and `WITH` are read-only
  nearly everywhere. Almost nothing else generalises. A copied list rejects legitimate
  reads on the new platform, and -- worse -- can admit something that is not a read on this
  engine.
- **A cost guard measures the wrong thing.** A byte ceiling is meaningless where billing is
  by compute time; a cluster auto-stop is meaningless where billing is by data scanned.
- **The command may not exist.** CLI surfaces move, and a command that is correct today can
  be renamed or was never real. Confirm against the tier skill, not memory.

## Statement forms: what is read-only where

| | Read-only forms | Notes |
| --- | --- | --- |
| **BigQuery** | `SELECT`, `WITH` | No `EXPLAIN`, no `DESCRIBE`. The query plan comes from a dry run; object metadata from `INFORMATION_SCHEMA`. |
| **T-SQL** (Fabric Warehouse and SQL endpoints, Synapse) | `SELECT`, `WITH` | No `EXPLAIN`, no `SHOW`, no `DESCRIBE`. The equivalents are `SET SHOWPLAN_ALL ON`, `sp_help`, and the `INFORMATION_SCHEMA` views. |
| **Databricks SQL** | `SELECT`, `WITH`, `SHOW`, `DESCRIBE`, `EXPLAIN` | All five exist and are read-only. |

Whatever list you end up with, **record which dialect it is for** in the tool itself. A
list with no dialect named cannot be safely maintained by the next person.

Forms to watch for on any engine, because they read and write:

- `CALL` / `EXEC` -- a procedure can do anything.
- `SELECT ... INTO` -- writes a table.
- A CTE feeding a DML statement, where the engine allows it.
- Session settings that change behaviour for later statements.

## Cost model and the ceiling that is actually enforced

| | Billed by | A ceiling the engine honours |
| --- | --- | --- |
| **BigQuery** | bytes scanned | `--maximum_bytes_billed`, enforced server-side: the query is refused, not merely reported. A dry run returns the byte estimate beforehand. |
| **Fabric / Synapse (T-SQL)** | capacity units, not scanned bytes | No byte ceiling exists. Use a query timeout, `SET QUERY_GOVERNOR_COST_LIMIT`, or the capacity's own throttling. |
| **Databricks** | warehouse or cluster running time | Warehouse size, auto-stop, and a statement timeout. A byte estimate is not the relevant number. |

`LIMIT` / `TOP` caps rows **returned**, never work **done**. A `LIMIT 1` over a wide
partitioned table can still scan terabytes. Say this in the tool's help; it is the most
common misunderstanding about warehouse cost.

## Getting a result set out

| | Client | Watch out for |
| --- | --- | --- |
| **BigQuery** | the `bq` CLI | `--dry_run` for the estimate, `--format=json` for parseable output. |
| **Fabric** | `sqlcmd` (Go build) against the Warehouse or SQL endpoint | See the `sqldw-cli` skill (raid-fabric). Lakehouse and Mirrored DB SQL endpoints are read-only for table data **by design** -- pointing at one is a stronger read-only guarantee than any parser. |
| **Databricks** | `databricks experimental aitools tools query` | `databricks sql execute` and `databricks execute-statement` **do not exist**; the `databricks-core` skill lists them as common wrong guesses. The working command is marked experimental and may move -- re-confirm rather than trusting this line. |

Where no CLI serves, the platform's SQL execution REST API driven by a shell HTTP client
plus the standard library is usually the stable path, and it typically exposes timeout and
row-limit parameters that double as guards.

## A worked wrapper

`raid-gcp`'s `bigquery` skill ships `bqw.py`, a single-file Python wrapper with no
third-party imports. Read it for the **shape** of a guarded tool -- argument surface,
doctor mode, the order of validate-then-estimate-then-execute, how refusals are reported.

Its statement allowlist, its dry-run costing and its `--maximum_bytes_billed` ceiling are
BigQuery facts. Each one is wrong somewhere else.
