---
name: blast-radius
description: >-
  Use before shipping a change that can break things outside its diff. Finds what it
  could break downstream and proves the facts that matter. Fills the PR's Risk block.
disable-model-invocation: true
---

# Blast Radius

Audit a change for breakage that symbol search and local review miss. Work from the
diff, its base, and the real consumers of the changed behaviour. This is read-only
unless the user's scope includes fixes. It is not a code review (`review-changes`) and
not a lineage explainer (`how`); it uses `how` to find the consumers.

## Trace the change outward

1. **Name the behaviour that changed**, not the lines: grain, primary and foreign keys,
   column names, types and nullability, filters and row scope, measure semantics,
   partitioning, materialization (table, view, incremental), incremental logic, macro
   output, source definitions, schedules, and pipeline, infrastructure or skill
   behaviour.
2. **Use `how`** to trace ownership and lineage, and `why` when a past decision (an ADR,
   a glossary rule, a comment) decides whether the change is safe.
3. **Pick the one or two facts safety depends on.** "No downstream model joins on the old
   key", "row count per key is unchanged", "every consumer reads the column by name".
   One decisive fact beats a long list of speculative risks.
4. **Follow each fact past the grep**: dependent models (the transformation tool's own
   lineage, such as `dbt ls --select <model>+`), macro callers, columns that flow
   unnamed through `select *`, views and semantic models that read the changed object,
   reports and dashboards, exports, scheduled jobs, and other repos or teams that read
   it. For a skill or agent change, the consumers are the agents and people who run it.

## Prove the safety facts

Take each fact as far as the evidence allows:

1. Source location (file and line).
2. A demonstrated path showing the bad case cannot reach the change.
3. A query or build that runs the shipped code against real rows: key uniqueness, row
   counts, null rates, FK integrity, old-vs-new parity of the measure a consumer reads.
4. The consumer itself: the report, semantic model or downstream query showing the
   number people see is unchanged, or changed as intended.

Aim for level 3 or 4. Mark a fact `unproven` when it cannot be checked cheaply, and say
what would check it. Do not add broad tests to make the audit look rigorous; one focused
query against the real contract is better.

Classify each remaining risk by mechanism, likelihood, impact, and the cheapest check
that would catch it. Keep confirmed risks apart from concerns checked and cleared.

## Reply

What changed in behaviour; the safety facts with the evidence level reached; confirmed
risks; cleared concerns; and the cheapest check left before delivery. Cite the paths,
commands and queries used so anyone can rerun them.

When the audit feeds a PR, also give the four Risk lines `commit-push-pr` puts in the
body: **Impact** (the consumers whose output changes), **Rollback** (only when a revert
is not enough), **Verified** and **Detection**.
