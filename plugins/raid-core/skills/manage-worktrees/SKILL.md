---
name: manage-worktrees
description: >-
  Use when the user says 'make a worktree', 'work on this in parallel', 'set up an
  isolated branch checkout', 'clean up worktrees'. Creates, lists and removes git
  worktrees so multiple builds run in parallel on separate branches without colliding in
  one working directory. Useful when raid-mode or ship-engagement runs several units
  concurrently, or to keep a long build isolated from a quick fix.
argument-hint: "[add <branch> | list | remove <path-or-branch>; for add, optionally a base branch]"
---

# RAID Worktree

Git worktrees let one repository have several working directories checked out at once,
each on its own branch -- so a long Silver build and a quick Bronze fix don't fight over
the same files, and `raid-mode`/`ship-engagement` can run isolated units in parallel. This
skill manages them safely and consistently.

## Inputs

<input> #$ARGUMENTS </input>

Sub-command: `add <branch>` (default if a branch name is given), `list`, or
`remove <path-or-branch>`.

## Operations

### add

Create a worktree on a fresh `feature/*` branch off `origin/main` (per
`raid-core/AGENTS.md` -- new work branches off freshly fetched `origin/main`, never a
drifted local checkout):

```bash
git fetch origin
git worktree add ../<repo>-<branch-slug> -b feature/<branch> origin/main
```

- Place worktrees as **siblings** of the repo (e.g. `../<repo>-<slug>`), not nested
  inside it -- a nested worktree pollutes the parent's status and can be scanned twice.
- If the branch already exists, check it out into the worktree instead of `-b`.
- Per-engagement setup is **not** copied automatically: a Python `.venv`, `.raid/`
  config, or local secrets live in the original tree. Tell the user what the new
  worktree needs (typically: create/point a `.venv`; `.raid/config.yaml` is read from
  the repo, confirm it resolves). Don't silently assume the environment is ready.
- Report the new worktree path and branch, and how to enter it (the user `cd`s there;
  this session stays in the current directory unless they move it).

### list

`git worktree list` -- show each worktree's path, branch, and HEAD. Flag any that are
prunable (their directory is gone) or locked.

### remove

```bash
git worktree remove <path>
```

- Resolve a branch name to its worktree path via `git worktree list` first.
- **Refuse to remove a worktree with uncommitted changes** unless the user explicitly
  confirms `--force` -- removing it discards that work. Surface the dirty state and stop.
- Never remove the main working tree (the original repo directory).
- After removal, offer `git worktree prune` to clear stale administrative refs, and note
  that the branch itself still exists (delete it with `clean-gone-branches` once
  its PR merges).

## Rules

- Worktrees are siblings of the repo, on `feature/*` branches off fresh `origin/main`.
- Never remove a dirty worktree or the main working tree without explicit confirmation.
- Worktree creation does not carry over `.venv`/secrets -- state what the new tree needs.
- Repo-relative paths in any generated docs.
