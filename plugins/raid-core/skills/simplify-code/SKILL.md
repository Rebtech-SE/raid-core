---
name: simplify-code
description: >-
  Use after building and before review-changes, or when the user says 'simplify this',
  'clean up this model', 'tidy these changes before the PR'. Rewrites settled data code -
  dbt models, SQL, notebooks, pipelines - so it is skimmable and hard to misuse: fewer
  models and flags, fewer macro parameters, exhaustive CASE handling, a failing test
  instead of a COALESCE fallback, reuse before new SQL. Quality only, no bug hunt - same
  rows, same grain, same values, proved.
argument-hint: "[blank to simplify current branch changes, or name a model/notebook/dir to simplify]"
---

# RAID Simplify

Take data code that already works and make it consumable: the same rows out, in a shape a
reader can hold in their head. This is a quality pass, not a review - it does not hunt for
correctness bugs (that is `review-changes`). It collapses duplicated SQL, points new logic
at existing macros and staging models, cuts states and columns nothing needs, replaces
defensive fallbacks with assertions - then proves the marts are unchanged.

Run it when a unit has settled, before review, commit or handoff. Do not run it while the
model is still being shaped; it fights you.

`raid-mode` builds it; `simplify-code` tightens it; `review-changes` reviews it.

## The standard

This is what good looks like - the target, not just a list of things to hunt. The rule
numbers are stable (they match the engineering standard this skill is adapted from); cite
them by number in findings and in the summary.

**Cut**

- **[7] Remove anything not strictly required.** A CTE nothing selects from, an `int_*`
  model with no `ref()`, a column no mart reads, a config knob or `var()` nothing sets, a
  debug cell, a comment restating the SQL. Design for observed usage, not imagined future
  columns.
- **[8] Bias for fewer lines** - fewer models, fewer CTEs, fewer columns carried. Fewer
  lines is a proxy, not the goal: faster comprehension is the goal.
- **[17] Sweat the small leaks.** A staging model that renames one column and is
  `ref()`ed once. `SELECT *` dragging an upstream rename into gold. The same business
  predicate spelled out in two marts. Each is cheap to ignore once and expensive once it
  spreads through the DAG.

**Reduce the state space**

- **[2] Minimize possible states.** Fewer intermediate models, fewer boolean flags on a
  row, fewer optional macro parameters, fewer nullable columns. Two independent flags is
  four states; if only three are legal, the row can be in an impossible state and someone
  will eventually write SQL for it.
- **[3] One typed status beats a bag of flags.** Replace loose combinations with a single
  status/type column backed by a seed and an `accepted_values` test, rather than
  `is_active` + `is_cancelled` + `is_pending` that can disagree.
- **[6] Be opinionated about parameters.** Macros take the arguments the project actually
  passes, with no permissive defaults. Assert the shape at the boundary (a contract, a
  `not_null`, an `accepted_values`) instead of accepting anything and coping downstream.
- **[13] Never pass overrides you do not need.** A macro argument or `var()` that every
  call site sets to the same value is not a parameter - inline it.
- **[14] Do not make a required thing optional.** An argument defaulted to `none` that the
  macro immediately errors on. A column declared nullable that is never null in any load.
- **[15] Consolidate decisions.** Define a business rule once - "active customer", the
  currency conversion, the reporting-date truncation - in one model or macro, and let
  everything downstream `ref()` the result instead of re-deriving the same predicate.
  The same rule in five marts is five places to drift.
- **[16] Question the threading.** A column carried bronze -> silver -> gold untouched so
  it is "available later"; a pipeline parameter threaded through four activities to reach
  one notebook. Count the layers it crosses without being used and look for the direct
  path: join it where it is needed, read the config where it is consumed.

**Trust the contract**

- **[4] Handle every variant exhaustively; fail on the unknown.** A `CASE` over source
  codes ends in an explicit `ELSE` that raises (`ERROR('unmapped status: ' || status)`) or
  maps through a seed whose misses a test catches - never a silent fallthrough to `NULL`
  and never `ELSE 'Other'` on a column that drives a measure. An unmapped source value is
  news; a bucket labelled Other is a wrong number nobody notices for a quarter.
- **[5] Do not write defensive SQL.** Do not re-check what the upstream contract already
  guarantees: a `WHERE id IS NOT NULL` on a `not_null`-tested key, a `QUALIFY
  row_number() = 1` on a key already tested unique, a `TRY_CAST` on a column staging
  already typed. If the guarantee does not exist yet, add the test - do not add the guard.
  At the raw source boundary the opposite holds: input you do not control is untrusted and
  its guards stay.
- **[12] Assert instead of papering over.** A failing dbt test beats a `COALESCE(x, 0)` on
  a column that should never be null; `dbt_utils.expression_is_true` beats a `WHERE` that
  quietly drops the rows that break an assumption. A fallback converts a loud failure at
  the true cause into a quiet wrong answer in a report far away. `COALESCE` is right where
  null genuinely means zero - say so in a comment, and only there.

**Keep it readable**

- **[1] Write extremely simple SQL.** A reader should follow the model top to bottom, CTE
  by CTE, without holding the whole DAG in their head.
- **[9] No clever code.** No window function doing three jobs at once, no recursive CTE
  where a date spine and a join read plainly, no Jinja metaprogramming that hides which
  columns the model produces.
- **[10] Do not over-decompose the DAG.** An `int_*` model that only filters and has one
  consumer belongs in that consumer as a CTE. If answering "where does this column come
  from" takes more than three model hops, flatten. A medallion layer boundary is not
  over-decomposition - see Balance.
- **[11] Filter early.** Push the predicate into the first CTE instead of nesting
  conditions in the final `SELECT`.

Rules 5 and 12 are the ones that feel wrong and are not. A default value or a swallowed
exception hides the case where the assumption broke; a test states the assumption and
fails at the point it stops holding. A `COALESCE` added to make a dashboard stop showing
nulls is a symptom fix - it leaves the real cause in place and teaches the next reader
that the null was expected.

**Fix the pattern, not the instance.** When a finding is a shape rather than a one-off -
the same re-derived predicate, the same falsely optional macro argument, the same
`ELSE 'Other'` - search the whole scope for the other occurrences and fix them in one
pass. Fixing one and leaving five teaches the next reader that the shape is fine.

**Balance - do not over-simplify.** Faster comprehension is the goal, not fewer lines. Do
not inline a CTE that gives a transformation step a name, merge unrelated models, collapse
a layer that exists for the medallion boundary (staging/intermediate/mart separation is
intentional, as is a conformed dimension that only one mart uses today), or delete a macro
whose purpose you have not confirmed is obsolete (`git blame` for intent). If a change
would be longer or harder to follow than the original, do not make it.

**The test all of it serves:** writing SQL is cheap for you, which makes over-engineering
easy. Borrow a human maintainer's fatigue instead. If the engineer who owns this model in
a year would find it exhausting, it is a bad solution however correct it is.

## Order of operations

Subtract, then collapse, then polish. The order matters: deleting shrinks the surface,
which usually makes the next simplification obvious, and polishing a model you are about
to delete is wasted work.

1. **Subtract** [7][8][17] - dead CTEs, unread columns, unreferenced models, speculative
   config, comments that restate the SQL.
2. **Collapse** [2][3][13][14][15][16] - fewer states, fewer parameters, one source of
   truth per decision.
3. **Polish** [1][9][10][11] - naming, CTE order, early filters, line count.

This ordering is the `principle-subtract-before-you-add` skill, restated here because this
skill needs it every run.

## Step 1: Identify scope

Resolve the simplification scope in this order:

1. **If the user named a scope** (a model, a notebook, a directory, "the staging models
   I just wrote"), use exactly that. Do not widen user-named scope. If the right fix lives
   outside it, say so and leave it.
2. **Otherwise, in a git repository**, default to the diff between the current branch and
   its base (`git diff origin/main...`, or the configured upstream). This is the common
   case: tidy everything added on this branch before opening a PR. If there is no
   upstream/base ref, fall back to staged + unstaged changes (`git diff HEAD`).
3. **Outside git or with no diff**, review the most recently modified files the user
   mentioned or that were edited earlier in this conversation.

Drop what is not hand-written data code: compiled output (`target/`), installed packages
(`dbt_packages/`), vendored notebooks, generated `.platform`/manifest files, lockfiles,
formatting-only churn. On a mixed diff keep the hand-written models and drop the rest; if
what remains is empty, stop with "nothing to simplify".

If none of these yields a non-empty scope, stop and ask what to simplify rather than
guessing.

## Step 2: Launch 4 review agents in parallel

You cannot be a cold reader of code you just wrote - you know why every line is there, and
those reasons are what keep the shape alive. So delegate the reading.

Spawn the four reviewers below in a single message (one `Agent`/`Task` dispatch each,
mid-tier model - `model: "sonnet"`). Omit the `mode` parameter so the user's permission
settings apply. Give each reviewer:

- the resolved file paths and the changed hunks;
- **the rules it owns from The standard, pasted in full**, plus the Balance clause;
- the platform context from `.raid/config.yaml` (Fabric / Databricks / BigQuery / etc.)
  and the dbt project's conventions, so its suggestions match the engine's idioms.

Give it nothing else - no commit message, no ticket text, no account of why the code looks
the way it does. Anything that explains the shape re-anchors the reviewer to the shape you
are trying to escape. Tell each one: *"it was already like that" is not a defense - judge
what is on the page; you have no baseline, so never claim behavior is broken; report, do
not edit; finding nothing is a real answer.* Findings come back as
`[rule] path:line - what is wrong -> what it should be instead`.

### Agent 1: Reuse Reviewer - rules [15] [17]

For each change:

1. **Search for existing models, macros, and helpers** that could replace newly written
   code - the dbt project's `macros/`, `models/staging/`, shared notebook utilities, and
   files adjacent to the changed ones.
2. **Flag a new staging model or CTE that duplicates an existing one.** Point at the
   model already in the project (a `stg_*`/`int_*` model, a `ref()`-able mart) to use
   instead.
3. **Flag hand-rolled logic that an existing macro already covers** - a SCD2 / surrogate-
   key / date-spine / currency-rounding pattern reimplemented inline when the project (or
   `dbt_utils`) has a macro; a `CASE` cleanup that repeats a documented business rule;
   ad-hoc connection/secret handling a shared notebook helper already wraps.
4. **Flag the same decision made in more than one place** [15] - a predicate, default or
   date window re-derived in several models. Name where it should live and what the other
   sites should `ref()` instead.

### Agent 2: Clarity Reviewer - rules [1] [7] [8] [9] [10] [11]

Read the changed files top to bottom, cold, at reading speed, and note every place you
slowed down. Those places are the findings.

1. **Copy-pasted CTEs / near-duplicate models**: blocks that differ only by a literal or
   a column - unify with a single CTE, a `ref()`, or a parameterized macro.
2. **Stringly-typed columns**: raw status/type strings where the project already has an
   enum, a seed, or a constants macro.
3. **Nested conditionals**: `CASE` chains or nested `WHEN`/subqueries 3+ levels deep, or
   notebook `if/elif` ladders - flatten with a lookup/seed join, a mapping table, or
   early returns.
4. **SELECT \* through transformation layers**: `SELECT *` that drags every upstream
   column into silver/gold where an explicit column list belongs (final-CTE passthrough
   in a staging model is fine; flag it only where columns must be intentional).
5. **Unnecessary comments**: comments narrating WHAT the SQL does or referencing the task
   - delete. Keep only non-obvious WHY (a source quirk, a business rule, a deliberate
   late-arriving-dimension workaround).
6. **Dead code**: unreferenced CTEs, columns selected but never consumed downstream,
   `int_*` models with no `ref()`, notebook cells left from debugging, unused imports.
   Verify "unused" with the project's linter where configured (`ruff F401`,
   `sqlfluff`) and by searching for `ref()`/column usage across `models/` before
   deleting - re-exports and dynamically-built SQL produce false positives, and a missed
   catch is cheaper than deleting a live model.
7. **Over-decomposition** [10]: a single-consumer `int_*` model that only filters or
   renames; a column whose origin takes more than three hops to answer. Inlining is a
   valid finding.

### Agent 3: Contract & State Reviewer - rules [2] [3] [4] [5] [6] [12] [13] [14] [16]

Read signatures and contracts before bodies: macro arguments, model `config()` and
`unique_key`, `schema.yml` columns/tests/contracts, notebook function parameters, pipeline
parameters. Your question is not "is this clear" but **how many distinct states can this
code be in, and how many of them are reachable?**

1. **Count the states** [2][3]: arguments per macro, boolean flags per row, optional
   config knobs, nullable columns. For each, ask what happens when it is absent, empty or
   unexpected. If the answer is "that cannot happen", the contract should say so - a
   `not_null`, an `accepted_values`, a dbt contract, or one status column replacing three
   flags.
2. **Non-exhaustive mappings** [4]: a `CASE` over source codes with no explicit `ELSE`, an
   `ELSE 'Other'`/`ELSE NULL` that swallows unmapped values, a mapping seed joined without
   a test on the misses. Say what the loud failure should be.
3. **Defensive SQL** [5]: re-checks of what an upstream test or contract already
   guarantees. Note the boundary: guards on raw/landed source data are not defensive code
   and must stay; flag only re-validation inside the warehouse, and name the test that
   makes the guard redundant.
4. **Fallbacks hiding failure** [12]: `COALESCE` inventing a value where null means
   something broke, a `WHERE` that silently drops rows failing an assumption, a
   `try/except` around a load that logs and continues. Name the test that should replace
   it.
5. **Overrides and falsely optional arguments** [13][14]: a macro argument or `var()` that
   every call site passes identically; an argument defaulted to `none` that the body
   immediately errors on. Name the call sites you checked.
6. **Unopinionated parameters** [6]: a macro accepting more shapes than any caller passes;
   a model loading data with no contract or test on the columns it depends on.
7. **Threaded signals** [16]: a column or parameter crossing layers untouched. Count the
   layers and say what the direct path is.

Close with the current state count for the scope and what it would be after your findings.

### Agent 4: Efficiency Reviewer - tag findings [E]

Review the same changes for wasted work (correctness-preserving only):

1. **Redundant scans**: the same source table read in multiple CTEs that could be read
   once; a CTE materialized and then fully re-aggregated.
2. **Full refresh where incremental fits**: a model rebuilt in full each run when it has a
   natural high-watermark / partition key and the project supports `is_incremental()`.
   Flag only where the load mode in the design says incremental; do not invent one.
3. **Missing partition/cluster pruning**: a `WHERE` that cannot prune because it wraps the
   partition column in a function, or a join that reads all partitions when a date filter
   belongs upstream.
4. **N+1 / per-row work**: a scalar subquery or UDF call per row where a join or window
   would do; a notebook loop issuing one query per id where a single set-based query
   works.
5. **Wide intermediate results**: selecting and carrying columns through several layers
   that the final mart never uses - drop them at the earliest layer.
6. **Notebook hot paths**: collecting a full DataFrame to the driver to compute something
   the warehouse/Spark could do; re-reading a Lakehouse table already in scope.

Flag an efficiency item only when the rewrite is plainly behavior-preserving. Anything
that changes grain, null handling, or ordering belongs to `review-changes`, not here.

## Step 3: Apply the fixes

Wait for all four agents. Aggregate findings, order them by the Order of operations
(subtract before collapse before polish), and fix each directly. Skip false positives and
anything not worth the churn - note it and move on; do not argue with a finding or raise
it to the user. The reviewers read, you edit.

Before applying each fix, confirm it preserves behavior against **What must not change**
below. If a change cannot clear that bar, skip it - Step 4's checks do not cover every
behavior.

If the applied fixes changed the shape of the scope substantially - a model split or
merged, a macro extracted, a layer collapsed - run one more reviewer pass over the new
state, then stop. Two passes is the ceiling; say how many ran and what the last one found.

## What must not change

Behavior is fixed, and for data work behavior means the output table. For every model in
scope, before and after:

- **The same rows.** Identical row count *and* the same key set - none added by a join
  that widened, none dropped by a predicate that moved ahead of a `LEFT JOIN`, none
  deduplicated away.
- **The same grain.** One row per declared key, unchanged (`principle-declare-the-grain`).
  A collapsed CTE, a removed `DISTINCT`/`QUALIFY`, or a merged model that changes the
  grain is not a simplification, it is a bug.
- **The same values.** Every column value identical, nulls included - `NULL`, `''` and `0`
  are three different answers. Type changes (`DECIMAL(18,2)` -> `FLOAT`), timezone
  handling, rounding order and string collation all count as value changes.
- **The same schema contract.** Column names and types, and column order wherever
  something downstream depends on it (`SELECT *` consumers, BI semantic models, exports).
  A rename is a breaking change even when the values match.
- **The same load semantics.** Incremental vs full refresh, `unique_key`, merge/insert
  strategy, partition and cluster keys, snapshot strategy. These decide what lands, when,
  and what history survives.
- **The same side effects.** Tests that run, contracts and constraints declared,
  exposures, downstream triggers, DQ thresholds.

Never delete or weaken a test, loosen a DQ threshold, drop a `not_null`, widen an
`accepted_values` list, or relax a contract to make a check pass. Rule [5] says do not
re-check what the contract guarantees; it never says remove the contract. Where a rule and
a data-safety check conflict - a PII mask, a row-level filter, a retention or deletion
guard, a deduplication that prevents double-counting, a reconciliation against source -
the check wins, and you report the conflict rather than resolving it silently.

A compatibility path - a legacy column kept for an old report, a shim view, a renamed
column still exposed under its old name - goes only when nothing outside the scope reads
it. Check `ref()`/`source()` usage, `exposures`, BI models and downstream repos first;
when the consumer is outside the repo and you cannot verify it, leave it and say so.

## Step 4: Prove behavior is preserved

The whole premise is that simplification does not change output. After applying fixes:

**Lint and compile.** Run the project's fast checks over the changed files: `dbt compile`
(or `dbt parse`), `sqlfluff lint`, `ruff` on notebooks/scripts. These catch the common
regressions - a dropped `ref()`, a renamed CTE still referenced, a broken import.

**Build and test the changed models:**
- `dbt build --select <changed models>+` (downstream included) and run their tests, or
  re-run the changed notebook and its DQ assertions. Match scope to blast radius - a
  two-line tidy of one staging model does not need a full-project build.
- Broaden when reach is obvious: a macro used everywhere was rewritten, or a heavily
  `ref()`-ed staging model changed. Judgment about ripple, not a mechanical rule.
- **Where the data should be identical, prove it.** For a non-trivial rewrite of a model
  that already has a built table, diff the result against the prior version - row count,
  a checksum/hash over the key+measure columns, or `dbt-audit-helper`'s
  `compare_relations` if the project has it. A green test suite confirms invariants, not
  that every value is identical.
- **A new assertion is part of the fix.** When rule [12] replaced a fallback with a test,
  or rule [4] replaced a silent `ELSE` with a failure, run that test - a red one means the
  hidden case was real and live. Report it; do not revert to the fallback (see
  `data-quality-checks`).

Surface any failure with the check name and output. Do not relax a test, loosen a DQ
threshold, or skip a check to make it pass - that defeats the guarantee. Either fix the
break the simplification introduced or revert the specific change that caused it.

If no lint, build, or test is configured for the changed code, say so explicitly in the
summary; do not silently skip verification.

## Step 5: Summarize

Keep it short:

- What changed, by rule number, and what was already good.
- Passes run, and what the last one found.
- Anything skipped and why - a rule that would have changed behavior, a fix outside the
  scope, a data-safety check that outranked a rule.
- Which checks ran and their results, plus (for any non-trivial rewrite) the
  row-count/checksum confirmation that the mart is unchanged.

If there were no findings worth acting on, say the code did not need changes. State line
or model counts before and after only when the reduction is large enough to be the point.

The result is local only. Hand off to `review-changes` for the correctness review, then
`commit-push-pr` to open the PR.

## Rules

- Quality only - never change rows, grain, values, load semantics, or side effects. Bugs are `review-changes`'s job.
- Subtract before you collapse before you polish; cite findings by rule number.
- Reuse what the project already has (models, macros, seeds) before writing new SQL.
- Prefer a failing test to a defensive fallback - and never remove the contract itself.
- Prove unchanged output for non-trivial rewrites (tests + a row-count/checksum diff), not just a green suite.
- Respect the medallion boundary - do not collapse staging/intermediate/mart layers to save lines.
- Skip false positives silently; do not over-simplify. Repo-relative paths.
