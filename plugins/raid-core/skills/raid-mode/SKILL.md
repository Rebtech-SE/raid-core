---
name: raid-mode
description: >-
  Use for RAID, /raid-mode, or any data-platform work in a repo - dbt models, notebooks,
  pipelines, warehouse or lakehouse tables, medallion layers, SCD dimensions,
  data-quality checks. Routes the request (direct / incremental / greenfield
  pipeline), runs the RAID skills as the steps need them, and holds the approval gates
  and the validate-against-real-data bar. Start here rather than picking skills by hand.
# Cursor-only presentation keys. Claude Code, Codex and Copilot all ignore unknown
# frontmatter, so these are inert everywhere else. Deliberately NOT set:
# `disable-model-invocation` -- it is a real Claude Code key that would stop Claude
# routing data work here on its own, which is the whole point of the skill.
mode: true
icon: layers
color: teal
reminder: >-
  Data-platform work in a repo? Route it through raid-mode. Casual question, or the
  user opts out -> don't.
---

# RAID mode

RAID's working model for data-platform engagements. You pick the route, run the skills in
order, and hold the two things that make the output trustworthy: **the approval gates**
and **validation against real data**.

Skills below are named by what they do. `raid-core` is always installed; the greenfield
stages need `raid-greenfield`, and the platform CLI expert comes from the tier plugin
(`raid-fabric`, `raid-databricks`, `raid-gcp`, `raid-aws`).

## First, orient

- Unfamiliar repo? Run `map-repo` **before anything else**. It captures the repo's
  architecture and conventions into `AGENTS.md`, so every later step builds on real
  context instead of rediscovering it.
- No `.raid/config.yaml`? Run `setup-raid` once.
- **Terms doing real work?** The moment a definition is contested or a measure has to be
  pinned down -- "net sales", "active customer", the grain of a table -- run
  `domain-modeling`. It settles the term in `GLOSSARY.md` and records genuinely hard
  decisions as ADRs. Do not carry a fuzzy definition into a build.
- **Plan or decision still fuzzy?** Stress-test it with `grill-with-docs` before
  building: rounds of frontier questions down a design tree, each settled decision
  written into `GLOSSARY.md`/`docs/adr/` as the round ends. Do not start a unit on an
  un-grilled decision the user is not clearly behind.

## Pick the route

Announce the route you picked and why, so the user can override before work starts.

| Route | When | Flow |
|---|---|---|
| **Direct** | 1-2 files, no behavioural or modelling decision -- rename, config, typo | Do it here. No ticket, no ceremony |
| **Incremental** *(default)* | Work on an existing codebase: ~<=5 models/files, no new source system, no new platform decision, conventions observable in the repo | Do the work (below) -> `simplify-code` -> `review-changes` |
| **Too big to see the end of** | A platform migration, a new source system, a domain re-model -- more than one session can hold, and the route itself is still unclear | `wayfinder` charts it as decision tickets, one at a time, then come back here |
| **Greenfield** | New platform, new engagement, novel grain/SCD decisions, or the customer is owed sign-off artifacts. **Needs `raid-greenfield`** | (`plan-project`) -> (`ingest-requirements`) -> `assess-platform` -> `design-architecture` -> `design-data-model` -> (`write-test-plan`) -> then work the incremental route |

Any incremental criterion missed escalates a route up. If the work needs the greenfield pipeline and
`raid-greenfield` is not installed, say so and offer the install -- never improvise the
artifacts. To run the whole chain hands-off, use `ship-engagement` instead of driving it
yourself; pass `interactive` to keep the gates.

**Where the breakdown lives.** RAID does not write plan files into a customer's repo. Work
out the units in the conversation and build them. If the work will outlive this session --
someone else picks it up, it spans days, it needs to be visible to the customer -- publish
the units as tickets on the engagement's issue tracker (`tracker.provider` in
`.raid/config.yaml`; recipes in `setup-raid`'s `references/trackers/`), marked
`ready-for-agent`, and work them from there. A ticket you claim before building is also how
two agents avoid colliding. Work that arrived from outside this session -- a reported data
bug, a customer request -- reaches you the same way: it has been through `triage` and
arrives as a `ready-for-agent` ticket with an agent brief; read the brief as the contract
and claim the ticket before building.

## Do the work

One unit at a time, each finished before the next starts. A unit is one coherent slice --
a Bronze ingestion, a Silver conform, a Gold mart, or whatever the repo's own layering
calls a complete piece. Never half-built models.

- **Set up first.** Detect the platform from `.raid/config.yaml`. If on the default
  branch, cut a `feature/*` branch off freshly fetched `origin/main` before changing
  anything. Use the existing `.venv`/`venv`.
- **Follow the repo, not the textbook.** Mirror existing models and notebooks. On a
  brownfield repo the existing layering *is* the settled architecture -- follow it, don't
  re-derive a medallion one over the top. Where greenfield artifacts exist, honour them:
  `architecture.html` fixes tier/grain/naming/audit columns, `design.html` fixes the
  entity model, load modes and wave order.
- **Read the domain skill before writing the pattern** -- `medallion-architecture`,
  `scd-pattern`, `build-ingestion-pipeline`, `data-quality-checks`, `build-dbt-models`,
  and the tier plugin's own skills.
- **Dispatch the platform expert** (`fabric-cli-expert`, `databricks-expert`,
  `bigquery-expert`) for platform-specific execution rather than guessing CLI syntax.
- **Build the tests with the code**, in the same unit -- unique/not_null on keys,
  relationships on FKs, reconciliation. Not "later".
- **Verify before moving on.** Targeted `dbt build`/`dbt test`, the notebook run, the DQ
  assertions. A unit is not done until its verification is green. Never leave the tree red.
- **Validate against real data** -- see The bar. A green compile is not a verified unit.
- **Record the test outcomes.** Append one line per test execution to
  `docs/testing/test-results.jsonl`, harvested from what the run already produced
  (`target/run_results.json`, the DQ assertions, the job status) -- never re-run to
  collect them. Append, never rewrite: the ledger is the only record that a test failed
  once it goes green again. Format in `write-test-report`'s `references/results-ledger.md`.
- **Self-review each unit**, not just at the end: `review-changes mode:agent` scoped to
  the unit's diff, and address the actionable findings. Per-unit passes are cheap and stay
  localized; deferring to the end accumulates findings across files.
- **Update the docs the change touched** -- a project README, files under `docs/`,
  AGENTS.md conventions, any skill whose behaviour changed. Part of done, not a follow-up.
- **Stay in scope.** Adjacent work you discover becomes a note or a tracker item, not
  silent expansion.

Then `simplify-code` while the diff is small, the full `review-changes` before shipping,
and `commit-push-pr`. Never push or open a PR without a go-ahead.

## Route to the specialists

- **Something is wrong** -> `debug-data-issue` (root cause before fix, proven by a
  failing test). Fabric specifics: `debug-fabric`.
- **Too slow / too expensive** -> `tune-workload`. For a known one-line fix, just fix it.
- **Is production healthy?** -> `check-platform-health`.
- **Profiling a source before modelling it** -> `data-investigator`, or
  `investigate-fabric-source` on Fabric.
- **Modelling decisions** -> the knowledge skills: `medallion-architecture`,
  `kimball-dimensional-modeling`, `inmon-data-warehouse`, `scd-pattern`,
  `data-quality-checks`.
- **Shipping** -> `commit-push-pr` (stages, commits, pushes, unslopped PR copy, applies, and babysits); `resolve-pr-feedback` when
  reviewers respond.
- **An open PR that needs to go green** ("babysit this", "get it green", "watch CI",
  "check on PR X") -> `babysit`. It drives the PR to merge-ready on GitHub, Azure DevOps
  or GitLab and stops there -- the merge stays the user's call.
- **No scripted way to prove the data is right** -> `close-the-loop`. Builds a guarded
  read-only query tool plus a `verify-<platform>` skill and a data map that records, per
  mart, the query that proves it correct. Run it once per engagement; it is what makes
  "validate against real data" something an agent can actually execute.
- **Writing or fixing a skill** -> `create-skill`. Also the reference for any skill RAID
  generates into a customer repo.
- **Platform work** -> dispatch the tier's expert agent (`fabric-cli-expert`,
  `databricks-expert`, `bigquery-expert`) rather than guessing CLI syntax.

## Playbooks

A playbook is the order you do things in for one shape of task; a skill is a capability you
invoke. Match the task to a playbook below, open its file, and **copy its steps into your
todolist verbatim** before any task-specific todos. A step you choose not to do stays in the
list with `skip: <reason>` -- skipping silently is not allowed. See
[playbooks/README.md](./playbooks/README.md).

- **Autonomous run.** A long task driven to a checkable predicate without stopping -- a
  backfill, a migration sweep, a metric hillclimb. "Run until done", "I'm going to bed".
  [`playbooks/autonomous-run.md`](./playbooks/autonomous-run.md).

When no playbook fits, say so and work the route directly. Do not force a task into the
nearest one.

## Autonomy

**Proceed on reversible work.** Reading data, running a query, building a model in a dev
environment, creating a branch, writing a ticket, running tests -- do them and report what
happened. Do not ask permission for work you can undo.

**Always pause** for anything you cannot take back on someone else's estate:

- any write to a **customer production** environment;
- a **deploy** or a promotion between environments;
- a **backfill, truncate, drop or overwrite** of existing data, in any environment;
- **pushing** or opening a PR;
- anything the engagement agreement gates.

The asymmetry is deliberate. RAID runs on a customer's platform, spending their money, and
a wrong reversible step costs minutes while a wrong irreversible one can cost a reporting
cycle. Advice to never block on the human is written for your own repo; it does not
transfer to someone else's estate.

**Session overrides.** "Run until done", "don't stop", "I'm going to bed" -> keep going
through the reversible work and queue the gated items with what you would do and why, so
the operator clears the batch in one pass instead of one prompt at a time. An override
never converts a hard pause into a proceed.

## Subagent briefs

Every dispatch carries the whole brief. A field you cannot fill is a unit you have not
scoped yet -- scope it before spawning.

```
GOAL        one sentence, the outcome, executable by someone with no access to this chat
SCOPE       the files/models this unit may write; what it must not touch; its branch or worktree
CONTEXT     pointers to the files, artifacts and tickets it needs; paste upstream findings
            in full, because a subagent cannot see its siblings
ACCEPTANCE  checkable criteria, one per line, including the data checks that prove it
```

Three rules that stop the common failures:

- **One writer per branch or worktree.** Two agents in one working directory collide; use
  `manage-worktrees` when running units in parallel.
- **Standing constraints go in every spawn and every resume, verbatim.** Directives decay
  across resumes, and each dropped one costs a human turn.
- **You own the subagent's work.** Review the actual diff and write your own summary.
  An agent reports what it intended, not always what happened.

## Principles

Read the leaf skill in full for any principle you apply, and name it in your reply
alongside the specific choice it changed. A citation with no decision behind it means you
did not read the leaf.

**Data**

- **Declare the Grain** (`principle-declare-the-grain`). Before any model, fact or
  dimension, and at every join or aggregate that changes what a row means.
- **Reconcile Against Source** (`principle-reconcile-against-source`). Before calling any
  transform, migration or backfill done. This is how the real-data bar gets discharged.
- **Model the Domain** (`principle-model-the-domain`). Writing stateful logic, or when the
  same shape assumption repeats across models. An SCD, a conformed dimension or a mapping
  table instead of a `CASE` chain.

**Verification**

- **Prove It Works** (`principle-prove-it-works`). After a task, before declaring done.
  Run it and read the actual rows, never "it compiles".
- **Fix Root Causes** (`principle-fix-root-causes`). Debugging. In data work, suspect the
  data and the load before the SQL.

**Design**

- **Subtract Before You Add** (`principle-subtract-before-you-add`). Sequencing an
  addition or refactor. Drop the unread columns and unused models first.
- **Exhaust the Design Space** (`principle-exhaust-the-design-space`). A modelling or
  architectural decision with no precedent in the repo. Two or three sketches, then commit.
- **Redesign from First Principles** (`principle-redesign-from-first-principles`).
  Integrating a new requirement into an existing design.

**Meta**

- **Encode Lessons in Structure** (`principle-encode-lessons-in-structure`). You catch
  yourself writing the same instruction twice. Make it a test or a contract, not more prose.

Principles are guidance you cite. The **hard rules** in `raid-core/AGENTS.md` are not
negotiable and are always in force; a principle points at a hard rule, it never restates
or softens one.

## The bar

These are the parts that do not bend:

1. **Validate against real data whenever you have read access.** Row-count parity,
   grain/key uniqueness, null/sentinel rates, FK integrity, before/after parity. A
   correctness or migration claim is not trustworthy until checked against real data. No
   read access -> say so, lower confidence, and label the conclusion "not validated
   against data".
2. **The approval gates are real stops.** `assess-platform`, `design-architecture` and
   `design-data-model` each wait for the operator's Approve or Revise. The pause is the
   point. Only `ship-engagement` switches them off, and its artifacts stay stamped *not
   operator approved*.
3. **Anything that must outlive the session has a home.** Conventions in `AGENTS.md`,
   domain terms in `GLOSSARY.md`, hard decisions in `docs/adr/`, greenfield deliverables in
   `docs/artifacts/`, and work-in-progress on the issue tracker. Nothing important stays
   only in the conversation.
4. **Report what happened.** If a check failed, say so with the output. If a step was
   skipped, say that. Never present unverified work as verified.

## When not to use it

A casual question, a one-line explanation, or work outside a data platform. Answer
directly instead. The user opting out ends the mode for that turn.
