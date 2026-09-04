---
name: commit-push-pr
description: >-
  Use when the user says 'commit and PR', 'ship this', 'open a PR', 'commit my changes',
  'push and create a PR', or 'ship this for review'. Stages, commits, pushes, and opens
  or updates a pull or merge request on GitHub, Azure DevOps, or GitLab with an
  unslopped, value-first PR description, then automatically runs babysit to monitor to merge-ready.
argument-hint: "[optional: --update (refresh existing PR); --description-only; --work-items <id>; --no-babysit; --no-unslop]"
---

# RAID Commit, Push, and PR

Take completed local work to a review-ready pull or merge request against `main`, run an automatic `unslop` pass on the PR copy, and automatically hand off to `babysit` to monitor the PR to merge-ready.

**Provider Detection.** The commands below depend on where the repo is hosted.
Detect the provider from `git remote get-url origin` and use its CLI consistently (see `raid-core/AGENTS.md`):
- **GitHub** (`github.com`/GH Enterprise) -> `gh` CLI (`gh pr create`, `gh pr edit`).
- **Azure DevOps** (`dev.azure.com`/`*.visualstudio.com`) -> `az repos` CLI (`az repos pr create`, `az repos pr update`). Refer to the `az-cli` skill (`plugins/raid-core/skills/az-cli/SKILL.md` / `az-cli`) for environment setup, defaults, and authentication.
- **GitLab** -> `glab` CLI (`glab mr create`, `glab mr update`).
- **Generic / Missing CLI** -> push branch, then print the remote's compare/create web URL for the user to finish.

**Asking the user:** When this skill says "ask the user", use the platform's blocking question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex, `ask_user` in Gemini/Copilot). Fall back to presenting the question in chat only when no blocking tool exists in the harness or the call errors. Never silently skip the question.

---

## Mode Dispatch

- **Description-only** (`--description-only`, or "write/draft a PR description", "describe this PR", or a PR URL/id pasted alone) — run Step 4 (including the `unslop` pass) only; print the result.
- **Description update** (`--update`, or "refresh/rewrite the PR description" with no commit/push intent) — if no open PR for the branch, report and stop. Otherwise run Step 4 with the `unslop` pass, then Step 5 to preview and apply via the provider CLI.
- **Full workflow** (default) — run Steps 1 through 6 in order.

---

## Context Gathering

Gather current git & PR status using standard shell commands:

```bash
printf '=== STATUS ===\n'; git status
printf '\n=== DIFF ===\n'; git diff HEAD
printf '\n=== BRANCH ===\n'; B=$(git branch --show-current); echo "$B"
printf '\n=== LOG ===\n'; git log --oneline -10
printf '\n=== REMOTE ===\n'; R=$(git remote get-url origin 2>/dev/null); echo "${R:-NO_REMOTE}"
printf '\n=== PR_CHECK ===\n'
case "$R" in
  *dev.azure.com*|*visualstudio.com*)
    az repos pr list --source-branch "$B" --status active --query "[0].{id:pullRequestId,title:title}" -o json 2>/dev/null || echo NO_OPEN_PR ;;
  *github.com*)
    gh pr list --head "$B" --state open --json number,title 2>/dev/null || echo NO_OPEN_PR ;;
  *gitlab*)
    glab mr list --source-branch "$B" 2>/dev/null || echo NO_OPEN_PR ;;
  *)
    echo GENERIC_REMOTE ;;
esac
```

---

## Step 1: Resolve branch and branching strategy

Read the project's branching conventions (`AGENTS.md` or git config):

- **Protected target branch (`main`/`master`):** If on `main`/`master` with work to commit or ship, cut a feature branch (`feature/<slug>` or `bugfix/<slug>`) off freshly fetched `origin/main`. Read `references/branch-creation.md` for decision flow.
- **Trunk-direct repository:** If the repo explicitly permits direct commits on `main` and no PR is requested, committing directly is supported.
- **Detached HEAD:** Prompt to create a `feature/*` branch first.
- **Feature branch:** Continue on current branch.

Note existing active PR ID if found during context check.

---

## Step 2: Stage and commit

Scan changed files for naturally distinct concerns. If they clearly group into separate logical changes, create separate commits (2-3 max). Group at file level only — no `git add -p`.

Stage explicit paths. **Avoid `git add -A` and `git add .`**:

```bash
git add file1 file2 file3 && git commit -m "$(cat <<'EOF'
commit message here
EOF
)"
```

Write conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).

---

## Step 3: Plan-status gate and push

**Plan-status gate (hard, before push).** If the branch implements a plan held in this session, verify the plan's `Status:` reflects what is shipping (`complete` if this PR finishes the plan's scope, `active` if units remain) and that completed units' Status boxes / met Definition of Done items are checked. Carry the current status into the PR description **before** pushing.

Then push:

```bash
git push -u origin HEAD
```

Never `git push --force` to a shared branch. If the working tree is clean and all commits are already pushed, this step is a no-op.

---

## Step 4: Compose and unslop the PR title and body

**1. Draft the title and body.** Read `references/pr-description-writing.md` for guidance.

- **Value-first description:** Focus on what is now fixed or possible, not an enumeration of diffs.
- **Tracker link (opt-in only):** Link one *only* when the user explicitly passes `--work-items <id>` (GitHub/GitLab `Closes #<id>`; Azure Boards `AB#<id>`). Otherwise open the PR unlinked.
- **Verification evidence (RAID):** For data changes, state what was verified against real data (row-count reconciliation, grain/key uniqueness, null/sentinel rates, FK integrity, before/after parity for migrations/backfills, tests/DQ green). If not validated against real data, label it explicitly "not validated against data".
- **Attribution Badges:** Append the RAID attribution badge and harness/model badge after a `---` divider (see Step D of `references/pr-description-writing.md`).

**2. Automatic `unslop` pass.** Run `unslop` on the draft title and body before applying:
- Audit against `unslop` guidelines: eliminate AI tells (em dashes, mid-sentence colon overuse, formulaic lead-ins like "This PR introduces...", fluff, empty adverbs, excessive hedging, sycophant tone, corporate padding).
- Ensure the title and body are written in crisp, plain, direct, human prose.

---

## Step 5: Apply and report

Write the body to a temp file and pass it by file reference — never inline strings.

```bash
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/raid-pr-body.XXXXXX") && cat > "$BODY_FILE" <<'__RAID_PR_BODY_END__'
<the composed, unslopped body markdown goes here>
__RAID_PR_BODY_END__
```

**GitHub (`gh`):**
```bash
# New PR:
gh pr create --base main --head "$(git branch --show-current)" --title "<TITLE>" --body-file "$BODY_FILE"
# Existing PR update:
gh pr edit <pr-number> --title "<TITLE>" --body-file "$BODY_FILE"
```

**Azure DevOps (`az repos`):**
Refer to `az-cli` (`plugins/raid-core/skills/az-cli/SKILL.md`) for setup / defaults.
```bash
# New PR:
az repos pr create --source-branch "$(git branch --show-current)" --target-branch main --title "<TITLE>" --description "@$BODY_FILE"
# Existing PR update:
az repos pr update --id <pr-id> --title "<TITLE>" --description "@$BODY_FILE"
# Explicit work item link (only if --work-items <id> was passed):
az repos pr work-item add --id <pr-id> --work-items <id>
```

**GitLab (`glab`):**
```bash
# New MR:
glab mr create --target-branch main --source-branch "$(git branch --source-current)" --title "<TITLE>" --description "$(cat "$BODY_FILE")" --yes
# Existing MR update:
glab mr update <mr-iid> --title "<TITLE>" --description "$(cat "$BODY_FILE")"
```

**Generic remote / CLI missing:** Print the unslopped body and the remote's compare URL for the user.

Report the PR URL, target branch (`main`), and commits included.

---

## Step 6: Automatic babysit integration

Unless `--no-babysit` is explicitly passed:
1. Automatically run `babysit` on the opened or updated PR URL / ID.
2. `babysit` monitors the PR: checks branch policy / status, CI runs, reviewer votes, and conflict status until the PR is merge-ready.
3. Does **not** auto-merge — leaves final merge approval to the user.

---

## Rules

- Combined single workflow: stage, commit, push, draft + unslop PR, apply, and babysit.
- Respect project branching rules; default target is `main`. Never auto-merge (e.g. `az --auto-complete`, `gh pr merge`, `glab mr merge`) and never force-push a shared branch.
- Conventional, ASCII PR titles; unslopped body; real-data verification evidence for data changes.
- Do not ask about or infer a tracker item. Link one only when `--work-items <id>` is explicitly passed.
