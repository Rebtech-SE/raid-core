---
name: clean-gone-branches
description: >-
  Use when the user says 'clean up merged branches', 'remove gone branches', 'tidy up my
  local branches'. Deletes local git branches whose upstream tracking branch has been
  removed on the remote (typically merged PR branches deleted on the remote). Prunes
  stale remote refs first, lists what would be deleted, and confirms before removing.
argument-hint: "[optional: --dry-run (list only); --force (include unmerged gone branches)]"
---

# RAID Clean Gone Branches

After a PR merges, the `feature/*` branch is usually deleted on the remote, but the
local copy lingers and accumulates. This skill removes the local branches whose upstream
is **gone** -- safely, with a confirmation, never touching `main`/`master` or the
current branch.

Pure git; harness- and platform-agnostic.

## Workflow

1. **Prune stale remote refs.** `git fetch --prune` so local tracking refs reflect what
   actually still exists on `origin`. Without this, "gone" detection is stale.

2. **Find gone branches.** List local branches whose upstream is gone:

   ```bash
   git branch -vv | grep ': gone]'
   ```

   Exclude the current branch and `main`/`master` from the candidate list regardless.

3. **Classify by merge state.** For each candidate, check whether it's already merged
   into `main` (`git branch --merged main`). Split into:
   - **merged & gone** -- safe to delete (`git branch -d`).
   - **unmerged & gone** -- has commits not on `main`; deleting loses them. List these
     separately and only delete with `-D` if the user passed `--force` or confirms each.

4. **Show and confirm.** Print the two lists (branch name, last commit subject, merged
   yes/no). `--dry-run` stops here. Otherwise confirm (blocking question) before
   deleting -- default to deleting only the merged-&-gone set; require explicit opt-in
   for the unmerged ones.

5. **Delete and report.** Delete the confirmed branches; report what was removed and what
   was kept (and why -- unmerged, current, protected).

## Rules

- Never delete the current branch, `main`, or `master`.
- `git branch -d` (safe) for merged branches; `-D` (force) only with explicit per-branch
  or `--force` opt-in, never as the default.
- `--dry-run` deletes nothing.
- Operates only on local branches -- never delete remote branches here.
