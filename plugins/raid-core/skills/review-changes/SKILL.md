---
name: review-changes
description: >-
  Use before opening a PR or after a unit of data work. Review the scoped diff for
  data correctness, requirements coverage and risk. Verify findings against source
  evidence. Interactive mode applies safe fixes. mode:agent reports JSON. Not for a
  second-model opinion (autoreview), tidying settled code (simplify-code), or answering
  existing PR comments (resolve-pr-feedback).
argument-hint: "[mode:agent] [base:<ref>] [plan:<path>] [blank to review current branch, or a PR/MR id or URL on GitHub, Azure DevOps, or GitLab]"
---

# RAID Compliance Review

Review the scoped change in the current session. Read the evidence once, apply the
checks that match the change, and report what you verified.

## When to use

- Before opening a PR on a data change
- After completing a unit of work in `raid-mode`
- When requirements compliance must be verified against the plan/the prestudy
- Standalone, or inside a larger workflow (use `mode:agent` for JSON)

## Argument parsing

Parse `$ARGUMENTS` for optional tokens; strip each recognized token before treating
the remainder as a PR/MR id or URL (GitHub, Azure DevOps, or GitLab) or branch name.

| Token | Effect |
|-------|--------|
| `mode:agent` | Report-only: return JSON (see JSON output) and skip the Stage 5c apply. Does not change reviewer selection or merge logic. |
| `base:<sha-or-ref>` | Diff base on the current checkout (skips auto base detection). |
| `plan:<path>` | Plan/requirements file for traceability (explicit). |
| `depth:<full\|lean>` | Force the review depth, skipping auto-inference. Otherwise the depth is inferred (Stage 3) and announced. |

Stop the review when incompatible scope selectors conflict (e.g. `base:` and
a PR id together). Emit a one-line reason; in `mode:agent` return
`{"status":"failed","reason":"..."}`.

## Operating principles

- **Apply and commit locally; never push.** In default (interactive) mode the review
  applies safe, verified fixes (Stage 5c) and, when the tree was clean before the
  review, commits them as one `fix(review):` commit; on a dirty tree it applies but
  leaves them for the user. In `mode:agent` it never mutates the tree. Never push,
  open PRs, or file tracker items.
- **No blocking prompts.** Infer scope and intent from tokens, git state, PR
  metadata, and the plan. Note uncertainty in Coverage; do not stop to ask.
- **Depth is inferred and announced, never asked.** The review **depth** (Full | Lean)
  is resolved from the `depth:` token, the plan's announced tier, and the diff scope
  (Stage 3), then announced with the checks. Default to **Full** when uncertain -- Lean
  is an opt-down taken only when the change is clearly small and low-risk.
- **Explicit mutations only.** Never run `git checkout`/`switch` or a provider PR/MR
  checkout (`gh pr checkout`, `az repos pr checkout`, `glab mr checkout`). A PR id/branch
  selects review **scope**, not permission to switch trees.
- **Validate against real data when read access exists.** Run read-only SQL
  (`SELECT COUNT(*)`, schema introspection) using the installed tier guidance to
  confirm data-dependent findings (and all-clears) against actual data; never DDL/DML.
  Per `raid-core/AGENTS.md`, when warehouse read access is available the review is not
  trustworthy on code-reading alone: a clean result that *could* have been checked
  against data but was not is reported as such (in Coverage / residual_risks), not as a
  confident pass. Record whether warehouse access is available.
- **Follow `raid-core/AGENTS.md`** -- repo-relative paths in everything this skill emits.

## Severity, confidence, routing

Defined in `references/findings-schema.json` and `references/action-class-rubric.md`:
P0-P3 severity; discrete confidence anchors `0/25/50/75/100`; `autofix_class`
(`gated_auto`/`manual`/`advisory`); `owner` (`downstream-resolver`/`human`/`release`).

## How to run

### Stage 1: Determine scope

Resolve the diff to review (see `references/diff-scope.md` for the full rules):

1. **Explicit:** if `base:` was passed, diff the current checkout against it.
2. **Remote PR/MR** (a PR/MR id or URL): resolve head and base from the host detected on
   the remote (see the provider table in `raid-core/AGENTS.md`) — GitHub
   `gh pr view <id> --json headRefName,baseRefName`, Azure DevOps
   `az repos pr show --id <id>` (the `az-cli` skill's `repos` reference), GitLab
   `glab mr view <iid>`. If the
   PR head is not the local working tree, set scope mode `pr-remote` and capture
   `PR_HEAD_REF`; reviewers then inspect via `git show <PR_HEAD_REF>:<path>`.
3. **Working copy:** if `git diff HEAD` is non-empty, review those changes
   (`local-aligned`).
4. **Unpushed commits:** otherwise review `git diff $(git merge-base HEAD <base>)..HEAD`
   against the default branch (`main`).

Record the file list, the diff, the scope mode, and (untracked files excluded) note
exclusions for Coverage. Review tracked changes only.

### Stage 2: Intent discovery

Write a 2-3 line summary of what the change is trying to accomplish, from the PR
title/body, the branch name, the latest commits, and the conversation. Check the change against this stated purpose.

### Stage 2b: Plan / requirements discovery

Establish the requirements baseline for the `compliance-traceability` check and the
Requirements Completeness section:

- Use `plan:` when passed (`plan_source: explicit`).
- Else discover conservatively: the plan held in this session, when there is one (its
  inline units carry the requirements each advances), plus `architecture.html`, `design.html`,
  `testplan.html`, `assessment.html` under `docs/artifacts/`, and any prestudy referenced by the
  branch/PR (`plan_source: inferred`).
- If none found, note it once in Coverage and review against intent only.

### Stage 3: Select checks

Read [the review checklist](references/review-checklist.md). Resolve Lean or Full
in this order: explicit `depth:`, large or high-risk diff, announced plan depth,
small incremental diff, otherwise Full. State the depth and reasons for additional
checks. Run applicable risk checks at either depth.

Read the root and applicable nested `AGENTS.md` / `CLAUDE.md` files and the
requirements baseline. For a remote PR, inspect its exact head and base.

### Stage 4: Review and verify

Walk the changed behavior once using the selected checks. Trace the effects on
consumers and validate data-dependent conclusions with read-only probes. Record
checks that could not run. For risky deployments, include baseline, post-run
assertions and rollback in Deployment Notes.

Follow [the findings procedure](references/check-findings.md). It covers
verification, optional independent review and routing.

### Stage 5: Finalize findings

Report every applicable check ID in the top-level `reviewers` JSON field. On each
finding, use `reviewer` for a single supporting check ID or `reviewers` for all
supporting IDs when deduplicating across checks. Keep the attribution on entries
in `actionable_findings` too. Record the independent check in Coverage when it
occurred. Produce the findings list before applying any fixes.

### Stage 5c: Act on findings (default mode only)

**Skip entirely in `mode:agent`.** Bias to act: apply every finding that is a clear,
reversible improvement (a missing merge predicate, a corrected join key, an added
`unique`/`not_null` test, a removed dead model), regardless of severity. Push back when
the reviewer is wrong (keep the finding, state the disagreement); skip taste calls but
surface what was skipped.

- **Scope invariant:** apply only when the working tree *is* what was reviewed
  (`local-aligned`/standalone). In `pr-remote` do not apply -- report instead.
- **Verify, then keep:** after applying, run the affected tests / `dbt build --select`
  / DQ assertions (targeted; broaden when fixes span models). If they fail, revert that
  fix and report it as a finding instead. Never leave the tree red.
- **Commit when the pre-review tree was clean:** commit applied fixes as one
  `fix(review): <summary>` commit; on a dirty tree, apply but do not commit. Never push.
- **Surface green-but-unverifiable edits** (a merge predicate, a contract/schema
  change, a backfill) prominently in the Applied section.

### Stage 6: Synthesize and present

**Load `references/review-output-template.md` and mirror it** -- it is the canonical
skeleton. **Default:** pipe-delimited markdown tables grouped by severity (5 columns:
`# | File | Issue | Reviewer | Confidence`), terse `Issue` cell with depth in a keyed
`- **#N** -- ...` detail line. Sections: Header (scope/intent/mode/checks), Applied
(default only), per-severity Findings, Requirements Completeness (only when a plan was
found in Stage 2b -- explicit unaddressed requirements are P1/manual/actionable;
inferred are P3/advisory/report-only), Actionable Findings, Pre-existing,
Deployment Notes (for a risky deploy), Coverage, and a blockquote Verdict. No
time estimates. Run the template's format-verification gate before delivering.
Apply `unslop` as a write-through constraint on the finding text and the verdict.

### JSON output format (`mode:agent` only)

Generate a unique run ID. Emit **one raw JSON object** (no markdown fence) and also write `review.json` under
`/tmp/raid/review-changes/<run-id>/`. Minimum fields: `status`, `verdict`, `scope`,
`intent`, `depth`, `reviewers`, `findings`, `actionable_findings`, `artifact_path`,
`run_id`. `depth` records the resolved review depth (`full`/`lean`) for traceability.
This is the combined report contract. Use `findings.items` in
`references/findings-schema.json` for each finding's fields and keep the
per-finding attribution from Stage 5. The schema's root `reviewer` field applies
to per-check envelopes.
`mode:agent` does not apply fixes; the handoff is `actionable_findings`. Failure:
`{"status":"failed","reason":"..."}`; partial: `"status":"degraded"` with a reason.

## Quality gates

- Never push, switch branches, or run DDL/DML.
- Suppress findings below anchor 75 (except P0 at 50+).
- Verify every P0/P1 against the reviewed version and record missing evidence.
- Default to **Full** when depth inference is ambiguous; never silently
  under-review. The depth trims the always-on floor only, never an applicable risk check.

## Included references

- [Review checklist](references/review-checklist.md)
- [Findings procedure](references/check-findings.md)
- `references/diff-scope.md` -- scope discovery + remote PR/MR scope + finding tiers
- `references/action-class-rubric.md` -- autofix_class + owner routing
- `references/findings-schema.json` -- the structured findings contract
- `references/review-output-template.md` -- the canonical report skeleton
