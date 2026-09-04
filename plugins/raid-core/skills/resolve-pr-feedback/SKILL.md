---
name: resolve-pr-feedback
description: >-
  Use after reviewers comment on a RAID PR, or when the user says 'address the PR
  feedback', 'resolve the review comments', 'respond to the reviewers'. Works through
  the review threads on a pull/merge request - GitHub, Azure DevOps, or GitLab: fetches
  the open/unresolved comments, assesses each for validity, implements the warranted
  fixes, and drafts a reply for every thread.
argument-hint: "[optional: PR id; defaults to the PR for the current branch]"
---

# RAID Resolve PR Feedback

Turn reviewer comments on a PR into resolved threads -- fixes implemented where
warranted, a reasoned reply on every thread, nothing silently ignored. Reviewer feedback
is signal, not a command queue: some comments are right, some rest on a misread, some are
out of scope. Each gets assessed on its merits before code changes.

**Provider (detect first).** Detect the host from `git remote get-url origin` and use its
CLI (see the provider table in `raid-core/AGENTS.md`). The command blocks below give the
GitHub, Azure DevOps, and GitLab forms for each step:

- **GitHub** — `gh pr view --json comments,reviews` and `gh api` for review threads;
  `gh pr comment` / `gh api` to reply; GraphQL `resolveReviewThread` to resolve.
- **Azure DevOps** — `az-cli` skill (`references/repos.md`) for PR access; comment threads
  are read/replied to via `az devops invoke` (the `az repos pr` group does not manage
  threads directly).
- **GitLab** — `glab` merge-request discussions via `glab api .../discussions`; `glab mr
  note` to reply; set `resolved=true` on the discussion to resolve.

If the host is none of these (or its CLI is missing), fetch what you can and tell the user
which steps must be done manually — never silently skip a thread.

## Workflow

### 1. Identify the PR and fetch threads

- Resolve the PR: `$ARGUMENTS` id if given, else the active PR for the current branch.
  - GitHub: `gh pr list --head <branch> --state open`
  - Azure DevOps: `az repos pr list --source-branch <branch> --status active`
  - GitLab: `glab mr list --source-branch <branch>`
- Fetch the comment threads:

  ```bash
  # GitHub:
  gh pr view <prId> --json comments,reviews,reviewThreads 2>/dev/null \
    || gh api repos/{owner}/{repo}/pulls/<prId>/comments

  # Azure DevOps (repository id + PR id required):
  az devops invoke --area git --resource pullRequestThreads \
    --route-parameters project=<project> repositoryId=<repoId> pullRequestId=<prId> \
    --api-version 7.1 -o json

  # GitLab:
  glab api projects/:id/merge_requests/<mrIid>/discussions
  ```

  Keep only threads that are **active/unresolved** and are reviewer comments (skip
  system threads -- pushes, votes, status changes -- and already-resolved threads).

### 2. Assess each thread (parallel)

Dispatch one `raid-pr-comment-resolver` subagent per unresolved thread (fan them out;
they don't depend on each other). Each agent gets the comment text, the file + line it
anchors to, and the surrounding diff, and returns a structured verdict:

- **valid** -- a real issue; should be fixed. Includes the concrete fix.
- **valid-out-of-scope** -- real but doesn't belong in this PR; propose a follow-up
  tracker item (issue / work item) instead of changing code here.
- **misunderstanding** -- the comment rests on a misread; the reply explains why, with
  evidence from the code (no change).
- **discussion** -- a question or preference, not a defect; draft a reply, change only
  if the user agrees.

Every verdict carries proposed reply text. The agent does **not** push or post -- it
returns findings; this skill orchestrates application.

### 3. Confirm the plan

Summarize the threads by verdict (how many will get code changes, how many are replies
only, any proposed follow-up tracker items) and confirm before changing code or posting
(blocking question). The user may overrule any verdict.

### 4. Implement the warranted fixes

For each `valid` thread, make the change in the working tree. Group related fixes; keep
each change minimal and on-point to the comment. After implementing, verify as the
change demands (run the affected dbt build/tests, re-run the notebook, re-check the DQ
assertion) -- a fix that answers a reviewer must itself be correct. Commit via the
`commit-push-pr` rules (conventional, explicit staging). Do not `git push --force` a shared
branch; push the new commits normally if the user approves.

### 5. Reply on every thread

Post the drafted reply to each thread so the reviewer sees the resolution:

```bash
# GitHub (reply on a review thread; --body-file avoids quoting issues):
gh api repos/{owner}/{repo}/pulls/<prId>/comments/<commentId>/replies --field body=@<reply.txt>
# (or a general PR comment:  gh pr comment <prId> --body-file <reply.txt>)

# Azure DevOps:
az devops invoke --area git --resource pullRequestThreadComments \
  --route-parameters project=<project> repositoryId=<repoId> pullRequestId=<prId> threadId=<id> \
  --http-method POST --in-file <comment.json> --api-version 7.1

# GitLab (reply within a discussion):
glab api projects/:id/merge_requests/<mrIid>/discussions/<discussionId>/notes \
  --method POST --field body="<reply text>"
```

For a fixed thread, the reply states what changed (and the commit); for a
misunderstanding, it explains with evidence; for out-of-scope, it links the follow-up
tracker item. Resolve threads that are settled only with the user's go-ahead -- leave
genuine discussions open. Resolve via: GitHub GraphQL `resolveReviewThread`; Azure
`pullRequestThreads` PATCH `status` to `fixed`/`closed`; GitLab set `resolved=true` on the
discussion.

### 6. Report

List each thread: verdict, action taken (commit hash for fixes, reply posted,
tracker-item id for deferrals), and any thread left open for discussion. Note remaining
work and whether the branch was pushed.

### 7. Close the loop

This is the last interactive step of the build, so it is where the knowledge loop
closes. If resolving the feedback surfaced something durable -- a non-obvious fix, a
reviewer who caught a recurring data trap (an SCD edge case, a source quirk, a
medallion-boundary mistake), or a decision worth not re-litigating -- recommend
filing it on the tracker once the PR merges, so the next occurrence is minutes, not
a re-review. Pure preference threads and one-off typo fixes do not need compounding; a
fix you would not want to rediscover does.

## Rules

- Assess validity before changing code -- not every comment warrants a fix; never blindly comply.
- A reply on every addressed thread; resolve threads only with the user's go-ahead.
- Fixes are verified (tests/build/assertion) before they answer a reviewer.
- Out-of-scope but valid -> a follow-up tracker item (issue / work item), not scope creep in this PR.
- Confirm before posting or pushing; never force-push a shared branch. Repo-relative paths.
- Close the loop: recommend a tracker item for any durable fix or decision the feedback surfaced once the PR merges.
