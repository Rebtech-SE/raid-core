---
name: maintain-verification-skill
description: >-
  Use to audit and repair an engagement's `verify-<platform>` skill and data map after the
  gold layer changed, a mart was added or dropped, or a grain moved -- and at handover, so
  the customer inherits a check that still works. Triggers: 'is the data map still right',
  'the verify skill is stale', 'audit our verification'. Covers every mapped mart from the
  models and re-runs its proof query against real data, then ships proven corrections.
  `create-verification-skill` builds the map; this keeps it honest.
disable-model-invocation: true
---

# Maintain Verification Skill

A data map rots faster than an application's feature map. A mart changes grain, a column is
dropped, a new gold model ships and nobody adds it, a proof query still passes because it
counts rows that no longer mean what they meant. A stale map is worse than no map: it is a
check that reports green while proving nothing.

This is the upkeep loop for the `verify-<platform>` skill and data map that
`create-verification-skill` generated. Any project-local verification skill with a data map
works as a target.

The unit of rigor is **the mart**, not the sentence. Every mapped mart gets read from the
models and exercised against real data. Do not terminalise every bullet in the skill body.

## Outcome

Pick one and say which:

- **clean** -- every mart got model coverage and a live proof run; nothing worth shipping.
  No branch, no PR.
- **changed** -- one PR ships proven corrections to the map, the skill body, or the query
  tool.
- **blocked** -- coverage could not finish, or a proven fix could not ship safely. Say
  exactly what blocked it and which marts were left uncovered.

## Edit scope

Only the verification skill's own directory: its `SKILL.md`, its data map files, and any
query helper it owns.

**Never edit models, notebooks or pipelines during a run.** Behaviour the map describes
that the platform no longer does is one of two things, and they are not the same:

- **map drift** -- the map is wrong, the platform is right. Fix the map.
- **a data or model defect** -- the platform is wrong. Record it, hand it to
  `debug-data-issue` or the tracker, and keep it out of this PR. Papering over a real
  regression by rewriting the map to match the broken behaviour is the one failure this
  skill must never commit.

Honour inherited scope. An audit-only run reports proposed corrections and edits nothing.
An explicit no-commit boundary leaves approved repairs uncommitted.

## Pass

### 0. Locate the target

Find the project-local skill whose body has run/query sections and a data map -- usually
`verify-*/` under whichever of `.agents/skills/`, `.claude/skills/` or `.cursor/skills/`
the repo uses. Several candidates -> ask which. None -> stop and point at
`create-verification-skill`; do not invent a target.

### 1. Index hygiene

Read the data map's index and glob its sibling files. Fix missing, extra, duplicate and
dead entries. Lightweight -- no generated inventory.

### 2. Model wave

One read-only pass per mapped mart, answering from the models and the platform metadata,
never from the map itself:

- Does the mart still exist, under that name, in that layer?
- **Is the stated grain still the grain?** Re-derive it from the model's final `select`
  and its joins, not from the map's claim. A silently changed grain is the highest-value
  find in this whole pass, and the one a passing proof query hides.
- Are the stated columns, keys and audit columns still there?
- Are the stated consumers still consuming it (reports, semantic model, downstream models,
  an API)?
- Does the proof query still reference columns that exist, and does it still prove the
  property it claims to prove?

Dispatch one subagent per mart when the host supports it, launched concurrently within its
limits. Otherwise walk them sequentially inline and say so -- do not claim independent
review you did not get. Children read; they never run the pipeline and never edit files.

Return shape per mart: what it is now / grain re-derived from source / suspected drift with
the model path, or none / the live check to run.

### 3. Reconcile

Every mapped mart has a returned summary. Merge overlapping checks so one platform state
serves several marts. Spot-check cited drift against the model; do not re-prove clean
claims.

Then sweep the other direction: read recent changes to the gold layer and the semantic
model for **consumer-facing marts missing from the map**. Require a concrete model path
before calling one missing.

### 4. Live pass

Required even when the models look clean -- this is the step that separates this skill from
a documentation review, and skipping it is how a map stays green while lying.

Follow the verification skill's own run model; it decides, not this skill. The coordinator
owns all execution.

- **Doctor first.** Connection alive, right workspace/warehouse/project, credentials valid,
  and pointed at the environment the map names. Doctor again after any failed check.
- **Run every mart's proof query** against real data and read the actual numbers. A query
  that errors, returns zero rows where the map says otherwise, or returns a grain
  duplicate is a finding, not a retry.
- **Read-only, and never production without an explicit go-ahead.** Everything here is a
  `select`. If the map's proof query writes anything, that is a defect in the map -- fix
  it under edit scope.
- A mart that cannot be reached is `unverified` only with the concrete blocker (permission,
  environment, an upstream load that has not run) and the route attempted. If the map omits
  that prerequisite, that omission is itself drift.
- Evidence survives cleanup. Append one line per proof execution to
  `docs/testing/test-results.jsonl` in the format `write-test-report` defines -- the ledger
  is the only record that a check failed once it goes green again.

A doctor failure caused by skill drift **is** drift: fix it under edit scope, retry once,
then continue. Only after that does the pass go `blocked`.

### 5. Triage

- Wrong or missing mart description, grain, consumers -> **map drift**, fix it.
- Correct data the query tool cannot reach or express -> **tooling gap**, fix the tool or
  the skill body. Re-run the fixed query live before it ships.
- The numbers are actually wrong -> **platform defect**. Record it for the user with the
  query and the output, route it to `debug-data-issue` or the tracker, keep it out of this
  PR.
- A consumer-facing mart with no map entry -> write the entry, including a proof query, and
  run it.

### 6. Ship or stop

**changed** -> one PR of proven corrections; re-read every changed file before opening it.
**clean** or **blocked** -> no PR; report the outcome and the coverage honestly, naming
every mart left uncovered.

Keep short run notes (marts covered, blockers, confirmed drift, outcome) in a scratch
location. Do not commit them.

## Reply

The outcome, the marts covered and how, the drift fixed, the platform defects handed off,
and anything left unverified with its reason. Never present partial coverage as a clean
pass.

Related: `create-verification-skill`, `principle-reconcile-against-source`,
`principle-prove-it-works`, `principle-declare-the-grain`, `write-test-report`,
`debug-data-issue`.
