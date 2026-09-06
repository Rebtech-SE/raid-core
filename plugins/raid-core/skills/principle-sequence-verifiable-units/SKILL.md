---
name: principle-sequence-verifiable-units
description: "Use for multi-step data work -- a backfill, a migration sweep, a layer of models, a run of similar edits -- and for how you stack commits and PRs. Break the work into units that each end in a checkable state, check each before starting the next, and order delivery so the sequence proves itself to a reviewer."
disable-model-invocation: true
---

# Sequence Verifiable Units

**Order the work as a sequence of small units, each ending in a state you can check, and do
not advance until the current one is green.**

The same discipline runs at two altitudes: how you execute, and how you deliver.

**Why it matters more here.** A break caught at the unit that caused it is cheap to
localise. A break caught after a batch is buried under everything built on top of it -- and
in a warehouse the batch has already written rows. A wrong join that runs across forty
models is not a bad commit, it is a restatement.

## Execution

Choose a coherent unit that can be verified on its own. For data work that is usually one
complete slice through the layers -- a bronze load, a silver conform, a gold mart -- with
its tests, not a layer done everywhere.

- **Run the unit's check before building on it.** The targeted `dbt build`/`dbt test`, the
  job run, the DQ assertions, and the reconciliation query. Never leave the tree red and
  keep going.
- **A sweep is a sequence, not a batch.** Migrating twelve models, backfilling forty
  partitions, or applying the same edit across a layer: do the first one, verify it against
  real data, and only then let the rest follow. The first unit is where you find out your
  assumption was wrong, and it is cheap there.
- **Independent mechanical edits may form one unit.** The unit need not be one file. It
  needs one check.
- Preserve unrelated work and compare against the baseline the project's branching
  conventions require.

## Delivery

- **Capture failing-before-passing evidence** when fixing a defect -- the test that fails on
  the old code and passes on the new -- without requiring a broken commit to exist in
  history.
- When commits are authorized, **order green slices so a reviewer can follow the proof**:
  baseline before treatment, subtraction before reshape, scaffold before feature, the
  dimension before the fact that references it.
- Each slice stands alone, so a single revert undoes one thing.

## The data-specific edge

**A unit that writes is a unit that has to be reversible or gated.** Sequencing does not
make an irreversible step safe. A backfill, a truncate, an overwrite, or a promotion
between environments stays a hard pause under `raid-core/AGENTS.md` no matter how small the
unit is. Sequence the reversible work, queue the gated steps, and let the operator clear
them in one pass.

Reuse the project's `verify-<platform>` skill and its proof queries
(`create-verification-skill`) so the per-unit check is cheap enough that nobody is tempted
to defer it. A check that costs five minutes gets skipped; a check that costs one command
does not.

The sequencing complement to `principle-prove-it-works`, which keeps each check real.

Related: `principle-prove-it-works`, `principle-reconcile-against-source`, `to-tickets`,
`refactoring`, `create-verification-skill`.
