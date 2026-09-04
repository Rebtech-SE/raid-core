# Branch creation from main

RAID branches off freshly fetched `origin/main` (the protected default). Local `main`
may have stale commits (another session/worktree advanced it) or commits the user
authored intending to branch from later. Local git can't distinguish these -- ask when
unpushed commits are present.

## Decision flow

### 1. Fetch fresh remote base

```bash
git fetch --no-tags origin main
```

If fetch fails (network, auth, no remote), use the fallback at the bottom.

### 2. Check for unpushed local commits on `main`

```bash
git log origin/main..HEAD --oneline
```

- **Empty output:** set `BASE_REF=origin/main` and proceed to step 3.
- **Non-empty output:** show the commit list and ask (per the "Asking the user"
  convention in `SKILL.md`):

  > "Local `main` has N unpushed commits not on `origin/main`. Carry them onto the new
  > feature branch, or leave them on local `main`?"

  - **Carry forward** -> `BASE_REF=HEAD`. The new branch starts from local HEAD,
    preserving the commits.
  - **Leave on `main`** -> `BASE_REF=origin/main`. The new branch starts clean; commits
    remain on local `main`.

  Never default silently -- carrying foreign commits into a PR is worse than asking again.

### 3. Create the feature branch

Name it `feature/<slug>` (or `bugfix/<slug>`) derived from the change content; a
persisted personal branch like `ossian-dev` is also valid.

```bash
git checkout -b <branch-name> "$BASE_REF"
```

If checkout fails because uncommitted changes would be overwritten, stash and retry:

```bash
git stash push -u -m "commit-push-pr: pre-branch <branch-name>"
git checkout -b <branch-name> "$BASE_REF"
git stash pop
```

If `git stash pop` reports conflicts, surface the conflict output and the stash ref to
the user -- do not auto-resolve.

## Fetch failure fallback

If `git fetch` fails, branch from current local HEAD:

```bash
git checkout -b <branch-name>
```

Note in the user-facing summary that base freshness was not verified. Skip the
unpushed-commits check -- without a fresh `origin/main`, the answer is unreliable.
