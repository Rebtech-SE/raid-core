# RAID Review Output Template

Use this **exact format** when presenting synthesized review findings -- this example
is the **canonical skeleton: copy its structure and fill it in**, do not re-derive a
layout. Findings are grouped by severity, not by reviewer.

**IMPORTANT:** Use pipe-delimited markdown tables (`| col | col |`). Do NOT use ASCII
box-drawing characters.

**IMPORTANT:** Escape literal pipe characters in table cells. Any `|` that appears
inside a finding title, issue description, code snippet, regex, or delimited-string
example must be written as `\|` so column boundaries are determined only by unescaped
pipes. Unescaped pipes corrupt the row's `Reviewer` and `Confidence` values.

## Example

```markdown
## RAID Review Results

**Scope:** merge-base with the review base branch -> working tree (9 files, 218 lines)
**Intent:** Build dim_customer as an SCD2 dimension from the staging layer
**Mode:** interactive

**Reviewers:** correctness, testing, maintainability, data-integrity, scd-correctness, cost-perf
- data-integrity -- new dimension build with a merge into a persistent table
- scd-correctness -- SCD2 effective-dating logic added
- cost-perf -- full-table merge with no incremental filter

### Applied (safe, verified)

| # | File | Fix | Reviewer |
|---|------|-----|----------|
| 4 | `models/silver/schema.yml` | Added missing `unique` + `not_null` tests on `customer_sk` | testing |
| 5 | `models/silver/dim_customer.sql:72` | Removed redundant `CAST(amount AS DECIMAL)` -- already decimal upstream | maintainability |

Validation: `dbt build --select dim_customer` green; 14 tests pass (was 12), 0 fail.
Committed: `fix(review): add key tests, drop redundant cast on dim_customer` (working tree was clean before review).

### P0 -- Critical

| # | File | Issue | Reviewer | Confidence |
|---|------|-------|----------|------------|
| 1 | `models/silver/dim_customer.sql:58` | SCD2 merge overwrites history -- no current-row predicate | scd-correctness | 100 |

- **#1** -- Every run rewrites all historical versions instead of only the current row, so point-in-time joins return today's attributes for past facts. The merge matches on `customer_id` alone; add `AND target._is_current = true` to match the pattern in `dim_account.sql:44`.

### P1 -- High

| # | File | Issue | Reviewer | Confidence |
|---|------|-------|----------|------------|
| 2 | `models/silver/dim_customer.sql:31` | Join on `email` fans out the grain | correctness, data-integrity | 100 |
| 3 | `models/silver/dim_customer.sql:12` | No incremental filter -- full rebuild every run | cost-perf | 75 |

- **#2** -- `email` is not unique in `stg_contacts` (no uniqueness guarantee upstream), so the join duplicates customer rows and inflates downstream counts. Join on `contact_id` (the staging PK) instead, or dedup with `qualify row_number()` before the join.
- **#3** -- the model reprocesses all source rows each run; on the full contacts table this is a growing cost and runtime. Add an incremental watermark on `_loaded_at` matching the pattern in `fct_orders.sql`. Design decision -- see Actionable Findings.

### P2 -- Moderate

| # | File | Issue | Reviewer | Confidence |
|---|------|-------|----------|------------|
| 6 | `models/silver/dim_customer.sql:45` | No handling for late-arriving source rows | scd-correctness | 75 |

### P3 -- Low

(none)

### Actionable Findings

| # | File | Issue | Route | Notes |
|---|------|-------|-------|-------|
| 1 | `dim_customer.sql:58` | Missing current-row predicate in SCD2 merge | `gated_auto -> downstream-resolver` | `suggested_fix` present -- caller decides whether to apply |
| 3 | `dim_customer.sql:12` | Incremental strategy needs a modeling decision | `manual -> downstream-resolver` | Needs design input before implementation |

### Pre-existing Issues

| # | File | Issue | Reviewer |
|---|------|-------|----------|
| 1 | `stg_contacts.sql:8` | Source dedup relies on `distinct *`, masks true duplicates | data-integrity |

### Deployment Notes

- Pre-deploy: capture baseline row count `SELECT COUNT(*) FROM silver.dim_customer;`
- Verify after first run: current rows per customer should be exactly 1 --
  `SELECT customer_id, COUNT(*) FROM silver.dim_customer WHERE _is_current GROUP BY 1 HAVING COUNT(*) > 1;` returns 0 rows
- Rollback: the merge is idempotent once finding #1 is fixed; otherwise restore from the prior snapshot table

### Coverage

- Suppressed: 2 findings below anchor 75 (1 at anchor 50, 1 at anchor 25)
- Residual risks: no source-freshness check on `stg_contacts`
- Testing gaps: no reconciliation test of dimension row count vs source distinct customers

---

> **Verdict:** Ready with fixes
>
> **Reasoning:** 1 critical SCD2 history-loss bug must be fixed. The grain fan-out (P1 #2) silently inflates every downstream count and should be fixed before merge.
>
> **Fix order:** P0 history-loss -> P1 grain fan-out -> P1 incremental strategy (design) -> P2 late-arriving rows if straightforward
```

## Anti-patterns

Do NOT produce output like this. The following is wrong:

```markdown
Findings

Sev: P1
File: dim_customer.sql:31
Issue: Some problem description
Reviewer(s): data-integrity
Confidence: 75
Route: advisory -> human
────────────────────────────────────────
```

This fails because: no pipe-delimited tables, no severity-grouped `###` headers, uses
box-drawing horizontal rules, no numbered findings, no `## RAID Review Results` title,
and the verdict is not in a blockquote. Always use the table format from the example
above. When a finding needs more explanation than fits a terse `Issue` cell, put it in
the keyed detail list under the table (`- **#N** -- ...`) -- never expand it into
`Field:`-prefixed blocks.

## Formatting Rules

- **Pipe-delimited markdown tables** for findings -- never ASCII box-drawing characters
  or per-finding horizontal-rule separators (the report-level `---` before the verdict
  is still required).
- **Escape literal `|` in table cells** -- any `|` inside a finding title, issue
  description, code snippet, or regex must be written as `\|`. Applies especially to
  string-delimiter examples and logical-OR operators quoted inside findings.
- **Severity-grouped sections** -- `### P0 -- Critical`, `### P1 -- High`,
  `### P2 -- Moderate`, `### P3 -- Low`. Omit empty severity levels.
- **Stable sequential finding numbers** -- assign once after sorting, continue them
  across severity sections, and reuse those same numbers in Actionable Findings. Do not
  restart at `1` per section.
- **Always include file:line location** for code findings.
- **Reviewer column** shows which persona(s) flagged the issue. Multiple reviewers =
  cross-reviewer agreement.
- **Confidence column** shows the finding's anchor as an integer (`50`, `75`, or
  `100`). Never render as a float.
- **No `Route` column in the per-severity tables** -- the synthesized route
  (``<autofix_class> -> <owner>``) appears only in the Actionable Findings table and
  the `mode:agent` JSON. The scannable severity tables are 5 columns:
  `# | File | Issue | Reviewer | Confidence`.
- **Detail line (per finding, as needed)** -- keep the `Issue` cell to one short clause
  (~12 words, no second sentence); put the full explanation in a bullet under the
  severity table, keyed by stable `#`: `- **#N** -- <why it matters + concrete fix
  direction>`. Add a detail line for findings whose one-liner is not self-sufficient --
  usually P0/P1; P2/P3 are typically terse-only.
- **Header includes** scope, intent, and reviewer team with per-conditional
  justifications.
- **Mode line** -- include `interactive` or `agent`.
- **Applied section (default mode only)** -- when the review applied fixes, list them
  first, before the severity tables, as `# | File | Fix | Reviewer` followed by a
  one-line validation outcome (e.g. "`dbt build` green; 14 tests pass") and the
  **commit status** -- committed as an isolated `fix(review): ...` commit when the
  working tree was clean before the review, or left uncommitted when it was already
  dirty. A fix spanning multiple files is one row with one `#`. Flag
  green-but-unverifiable edits (a merge predicate, a contract change) inline in the
  `Fix` cell, e.g. `(integrity-posture -- verify in diff)`. Applied findings keep their
  stable `#` and appear only here, not in the severity tables. Omit in `mode:agent` and
  when nothing was applied.
- **Actionable Findings section** -- include when the actionable queue is non-empty.
- **Pre-existing section** -- separate table, no confidence column.
- **Deployment Notes section** -- key checklist items from
  `raid-deploy-verification-agent` (baseline counts, post-run verification SQL,
  backfill/rollback). Omit if the agent did not run. Schema drift surfaces as
  `data-migration` findings -- no separate section.
- **Coverage section** -- suppressed count, residual risks, testing gaps, failed
  reviewers.
- **Summary uses blockquotes** for verdict, reasoning, and fix order.
- **Horizontal rule** (`---`) separates findings from verdict.
- **`###` headers** for each section -- never plain text headers.

## Agent mode (JSON)

When `mode:agent` is active, **do not** emit the markdown table report above. Emit
**one parseable JSON object** as the primary response and write the same payload to
`review.json` under `/tmp/raid/review-changes/<run-id>/`.

The contract is defined in SKILL.md under **`### JSON output format (mode:agent only)`**.
Minimum fields: `status`, `verdict`, `scope`, `intent`, `reviewers`, `findings`,
`actionable_findings`, `artifact_path`, `run_id`.

Key differences from the interactive markdown format:

- **No pipe-delimited tables** -- findings are JSON arrays with merged fields (`#`,
  `title`, `severity`, `file`, `line`, `confidence`, `autofix_class`, `owner`,
  `suggested_fix`, `why_it_matters`, `evidence`, `reviewers`, etc.).
- **`actionable_findings`** -- subset for caller apply workflows (`gated_auto` /
  `manual` with `downstream-resolver`).
- **No `applied_fixes` and no Applied section** -- `mode:agent` does not apply fixes;
  the caller does. The handoff is `actionable_findings`.
- **Failure/degraded paths** -- `{"status":"failed","reason":"..."}` or
  `"status":"degraded"` with reason; never mix markdown tables into the JSON response.
- **Stable `#`** -- same numbering as Stage 5 synthesis, carried in JSON finding
  objects for downstream apply/residual tracking.
