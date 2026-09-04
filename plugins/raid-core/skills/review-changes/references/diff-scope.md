# Diff Scope Rules

These rules apply to every reviewer. They define what is "your code to review"
versus pre-existing context.

## Scope Discovery

Determine the diff to review using this priority order:

1. **User-specified scope.** If the caller passed `BASE:`, `FILES:`, or `DIFF:`
   markers, use that scope exactly.
2. **Working copy changes.** If there are unstaged or staged changes
   (`git diff HEAD` is non-empty), review those.
3. **Unpushed commits vs base branch.** If the working copy is clean, review
   `git diff $(git merge-base HEAD <base>)..HEAD` where `<base>` is the default
   branch (`main` or `master`).

The scope step in the SKILL.md handles discovery and passes you the resolved diff.
You do not need to run git commands yourself unless PR scope mode requires it (below).

## Remote PR/MR scope

The repo may live on any host. When the caller passes a PR/MR id or URL, the SKILL.md
detects the provider from the remote (see `raid-core/AGENTS.md`) and resolves the head
and base with that provider's CLI — `gh pr view` (GitHub), `az repos pr show` (Azure
DevOps), or `glab mr view` (GitLab); use the one matching the remote, never a mismatched
CLI. The reviewer still receives a resolved `<diff>` and, when the head is not the local
working tree, a `pr-remote` marker plus a `<pr-head-ref>` (see below). Do not call the
provider CLI yourself unless remote scope requires `git show`.

## Remote scope (`pr-remote` and `branch-remote`)

When the review context includes `<pr-scope-mode>pr-remote</pr-scope-mode>` or
`<pr-scope-mode>branch-remote</pr-scope-mode>`, the working tree is **not** the
reviewed head. Do **not** use Read/Grep on workspace paths for files in the
changed-file list -- they may not match the branch or PR under review.

Instead:

- Prefer `git show <remote-head-ref>:<path>` when `<pr-head-ref>` or
  `<branch-head-ref>` is provided in context.
- Otherwise rely on diff hunks in the provided `<diff>` only.
- Do not treat local workspace contents as evidence for findings on changed files.

## Finding Classification Tiers

Every finding you report falls into one of three tiers based on its relationship to
the diff:

### Primary (directly changed code)

Lines added or modified in the diff. This is your main focus. Report findings against
these lines at full confidence.

### Secondary (immediately surrounding code)

Unchanged code within the same model, notebook cell, or block as a changed line. If a
change introduces a bug that's only visible by reading the surrounding context, report
it -- but note that the issue exists in the interaction between new and existing code.
For data work this includes: a new column added to a SELECT that breaks an existing
`GROUP BY`, or a new upstream join that changes the grain consumed by unchanged
downstream logic in the same model.

### Pre-existing (unrelated to this diff)

Issues in unchanged code that the diff didn't touch and doesn't interact with. Mark
these as `"pre_existing": true` in your output. They're reported separately and don't
count toward the review verdict.

**The rule:** If you'd flag the same issue on an identical diff that didn't include the
surrounding file, it's pre-existing. If the diff makes the issue *newly relevant*
(e.g., a new model now reads from an existing table whose latent bug now affects the
new output), it's secondary.
