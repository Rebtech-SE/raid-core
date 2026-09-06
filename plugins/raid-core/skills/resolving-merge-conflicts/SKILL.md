---
name: resolving-merge-conflicts
description: >-
  Use when a git merge or rebase is in progress and conflicted -- 'fix the conflicts',
  'this rebase is a mess', 'merge main into my branch'. Resolves by understanding both
  intents rather than picking a side, with specific handling for the files that conflict
  worst in a data repo: dbt schema YAML, notebook and pipeline JSON, lock files and
  generated manifests. Finishes by rebuilding and re-running the tests, never just by
  making git quiet.
---

# Resolving Merge Conflicts

An in-progress merge, rebase or cherry-pick with conflicts. The goal is code that expresses
**both** intents, not a working tree that git stopped complaining about.

## 1. Establish what is actually happening

Never resolve blind. Get the state first:

```
git status
git log --oneline --left-right --merge
git diff --name-only --diff-filter=U
```

Know which operation is in flight, because the sides mean opposite things:

- **Merge:** `--ours` is your branch, `--theirs` is the branch being merged in.
- **Rebase:** they are **swapped** -- `--ours` is the upstream you are replaying onto,
  `--theirs` is your own commit. Getting this backwards is the most common way a rebase
  silently discards someone's work.

For each conflicted file, read both sides' history before deciding:
`git log -p --merge -- <file>`.

## 2. Resolve by intent

For each conflict, name what each side was trying to do. Then write the resolution that
serves both. Picking a side wholesale is a valid answer only when one side genuinely
supersedes the other, and then you say so.

If you cannot tell what a side intended, stop and ask -- or use `why` on that
commit. A guessed resolution in a warehouse surfaces weeks later as a wrong number.

**Never resolve by deleting the conflicting logic from both sides.** That is not a
resolution; it is a silent revert of two people's work.

## 3. The files that conflict worst here

- **dbt `schema.yml` / `sources.yml`.** Almost always additive on both sides: two people
  added tests or columns to the same model. **Keep both**, then check for a duplicate key --
  YAML will happily accept two entries for the same column and dbt will use one of them.
  Re-check that every `unique`/`not_null` still matches the model's declared grain.
- **`dbt_project.yml`, `packages.yml`.** Merge both sets of config; watch for the same path
  configured twice with different materializations, which parses fine and silently wins one
  way.
- **Notebook and pipeline JSON** (`.ipynb`, Fabric item definitions, ADF/Synapse JSON).
  Conflict markers inside JSON produce an invalid file that no tool will open. Resolve to
  valid JSON first, then diff semantically. Prefer taking one side whole and re-applying the
  other side's change by hand over hand-merging nested JSON. **Validate the file parses**
  before staging it, and re-open the notebook to confirm cell order and outputs survived.
- **Lock files and generated manifests** (`package-lock.json`, `poetry.lock`,
  `manifest.json`, compiled `target/`). Do not hand-merge. Take one side, then regenerate
  from the merged source of truth and stage the regenerated file.
- **Migration and DDL scripts.** Two migrations added at the same version or ordinal is a
  conflict git cannot see: both sides parse, and the sequence is wrong. Check ordering
  explicitly and renumber rather than merging text.

## 4. Verify before you finish the merge

Resolving is not done when the markers are gone.

- `grep -rn '^<<<<<<<\|^=======\|^>>>>>>>'` across the tree. A marker left in a YAML or SQL
  file will not always fail a build.
- Every touched file parses: the YAML loads, the JSON loads, the SQL compiles.
- **Rebuild and re-run the tests** for the models the merge touched, and their downstream.
  A conflict resolved in a shared staging model changes every mart below it.
- Where you have read access and the merge touched transformation logic, **check the output
  against real data** -- row count and grain at minimum. `raid-core`'s hard rule applies to
  a merge resolution exactly as it does to a build; a merge is a change to what the
  platform produces.

Then `git add` the resolved files and complete the operation (`git merge --continue`,
`git rebase --continue`). Never `--no-verify` past a failing hook to finish a merge.

## 5. When to stop

Abort and ask (`git merge --abort` / `git rebase --abort`, which are safe and lose only the
in-progress resolution) when:

- the conflict encodes a real disagreement about the model, the grain or a definition --
  that is a `domain-modeling` conversation, not a merge decision;
- the rebase has grown so many conflicting commits that a merge would be honest and the
  rebase is fiction;
- you would have to guess what a side intended.

## Reply

What conflicted, how each was resolved and on whose intent, what you regenerated rather
than merged, and the build and data checks that passed afterwards. Name anything you took
one side on and why.

Related: `commit-push-pr`, `resolve-pr-feedback`, `why`, `manage-worktrees`.
