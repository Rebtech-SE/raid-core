---
name: refactoring
description: >-
  Use to restructure working data code without changing what it produces -- split a fat
  model into staging and intermediate, re-layer bronze/silver/gold, rename a conformed
  dimension, move a metric into the semantic layer, deduplicate copy-pasted SQL. Pins the
  output first, then moves in behaviour-preserving steps and proves the rows are identical.
  `simplify-code` makes settled code readable in place; this one moves things.
---

# Refactoring

**You own the contract. The structure changes; the output does not.**

Distinct from building a model, which changes what exists, and from `debug-data-issue`,
which corrects wrong output. Distinct from `simplify-code`, which makes settled code
readable without moving it. This skill moves things: models, layers, keys, call graphs.

A refactor that smuggles in a data change loses its safety net -- and in a warehouse the
change is invisible until a report moves. If the cleanup reveals a genuine defect, split it
out and ship the structural change first against the pinned output. A redesign is allowed,
but name it as one and get agreement if it exceeds the authorized scope.

Split a large authorized refactor into verifiable units
(`principle-sequence-verifiable-units`). Size alone is not a reason to abandon it.

## 1. Pin the output first

**This is the step that makes a data refactor safe, and the one people skip.** Before
moving anything, capture what the current code produces, so you can prove the new code
produces it too:

- **Row count and key set** at the model's declared grain.
- **A full-column checksum or hash aggregate** over the result, ordered deterministically.
  On most warehouses a `sum` of a row-level hash is enough and is cheap.
- **The measures that matter**, totalled and split by the one or two dimensions the
  business actually reads them by.
- **Null and sentinel rates** per column, which catch a silently dropped `coalesce`.

Materialise the baseline into a scratch table or a saved result **before the first edit**,
in dev, and name where it lives. Reuse the project's `verify-<platform>` skill and its
proof queries where they exist (`create-verification-skill`); they are already written for
exactly this.

A green `dbt compile`, a passing type check, or "the tests still pass" is **not** a pin. A
compile proves the SQL parses. The existing tests prove the properties someone thought to
assert, which is never the whole contract. `principle-prove-it-works`.

Use `how` first when you do not already know the contract -- the grain, the
consumers, the filters -- of what you are about to reshape.

## 2. Name the structure the code is missing

Say what shape the code is reaching for: a staging layer over repeated source cleanup, a
conformed dimension over the same joins pasted into six marts, a mapping table over a
`case` chain of source ids, a single incremental predicate over four copies of the same
date logic, a metric in the semantic layer over the same aggregate in three reports.

The reshape must **delete branches or make invalid states unrepresentable**. If it only
adds a layer, it is not the right shape. Boring SQL stays when the shape is already clear
and local. `principle-model-the-domain`.

## 3. Name the target shape before moving

State what the model layout, the layering and the dependency graph should be if this were
built today -- `principle-redesign-from-first-principles`. Write it down before the first
move, so the moves have something to aim at and you can tell when you have arrived.

If the right shape is not obvious, sketch two or three and compare
(`principle-exhaust-the-design-space`). Do not take the first one.

## 4. Subtract before you add

Delete dead weight before introducing the new shape: unused models, columns nothing reads,
one-consumer wrappers, redundant `not_null` tests on a column that is already the key,
orphaned sources. Deletion shrinks the surface the reshape has to cover.
`principle-subtract-before-you-add`.

Prove a model is unused before deleting it: the dependency graph **and** a grep across
reports, notebooks and ad-hoc SQL, because the graph does not see those.

## 5. Move in small behaviour-preserving steps

Each step keeps the pin green. Migrate every consumer this change controls.

**Compatibility that must stay, stays.** A published table a customer's report reads, a
view another team queries, a column in an extract, a semantic-model measure: these are
deployed clients. Keep the old surface as a view over the new shape and record the
remaining migration boundary. When the change is wide enough that batches cannot land
green alone, sequence it as expand - migrate - contract and publish it as tickets
(`to-tickets`).

Spot-check every rename against the actual files. Renames silently miss usages in strings,
YAML, Jinja, report definitions, comments and column aliases -- and no compiler catches any
of them.

Mechanical edits can go to a subagent with a specific scope: the paths, the exact names
being moved, the output to hold. Review the diff yourself. A delegate's "looks good" is not
review.

## 6. Prove the output is unchanged

Re-run the pin and **diff it against the baseline**. Identical row counts, identical key
set, identical checksum, identical measures. Where they differ, the refactor is not done --
localise the delta to one hop before touching anything else.

Run it as a script a reviewer can re-run, not a one-time eyeball. Attach the numbers to the
PR, and append the run to `docs/testing/test-results.jsonl` per `write-test-report`.

Own the verification yourself. A delegate's summary is not proof.

Where you have no read access, say so plainly, label the refactor "not validated against
data", and do not present it as verified. `raid-core`'s hard rule does not bend for a
refactor.

## 7. Confirm the change earned its place

The measure is **reduced reader load**: fewer hops between a question and its answer, less
duplicated logic, fewer models with only one consumer, a grain you can state without
reading the joins.

If the diff does not lower reader load somewhere, revert it. A refactor that leaves the
platform equally hard to read has spent risk for nothing.

## 8. Commit in ordered slices

Small commits that tell the story: the subtraction, then the reshape, then the follow-on
cleanup -- so a single revert undoes one slice. Each slice is output-preserving and green
before the next begins.

## Reply

What moved, the pin you held it against, the diff that proves the output is unchanged (with
the actual numbers), the reader-load delta, and what shipped versus what you reverted. No
new behaviour.

Related: `simplify-code`, `how`, `to-tickets`, `create-verification-skill`,
`principle-sequence-verifiable-units`, `principle-subtract-before-you-add`,
`principle-redesign-from-first-principles`, `principle-prove-it-works`.
