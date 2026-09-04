---
name: review-changes
description: >-
  Use before opening a PR or after finishing a unit of data work. Structured review of a
  data change using tiered reviewer personas, confidence-gated findings, an independent
  validator pass, and a merge/dedup pipeline. Combines requirements traceability with
  data-correctness review (integrity, SCD, layering, reliability, cost, security).
  Interactive mode applies safe, verified fixes; mode:agent reports JSON and the caller
  applies.
argument-hint: "[mode:agent] [base:<ref>] [plan:<path>] [blank to review current branch, or a PR/MR id or URL on GitHub, Azure DevOps, or GitLab]"
---

# RAID Compliance Review

Reviews a data change (SQL, dbt models, notebooks, pipelines) using dynamically
selected reviewer personas. Spawns parallel sub-agents that return structured JSON,
independently validates surviving findings, then merges and deduplicates into a
single report. Built on the collaboration backbone in `references/`.

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

Stop without dispatching when incompatible scope selectors conflict (e.g. `base:` and
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
  (Stage 3), then announced with the team. Default to **Full** when uncertain -- Lean
  is an opt-down taken only when the change is clearly small and low-risk.
- **Explicit mutations only.** Never run `git checkout`/`switch` or a provider PR/MR
  checkout (`gh pr checkout`, `az repos pr checkout`, `glab mr checkout`). A PR id/branch
  selects review **scope**, not permission to switch trees.
- **Validate against real data when read access exists.** Reviewers run read-only SQL
  (`SELECT COUNT(*)`, schema introspection) -- or dispatch the platform expert -- to
  confirm data-dependent findings (and all-clears) against actual data; never DDL/DML.
  Per `raid-core/AGENTS.md`, when warehouse read access is available the review is not
  trustworthy on code-reading alone: a clean result that *could* have been checked
  against data but was not is reported as such (in Coverage / residual_risks), not as a
  confident pass. Tell reviewers in their context whether warehouse access is available.
- **Follow `raid-core/AGENTS.md`** -- repo-relative paths in everything this skill emits.

## Severity, confidence, routing

Defined in `references/findings-schema.json` and `references/action-class-rubric.md`:
P0-P3 severity; discrete confidence anchors `0/25/50/75/100`; `autofix_class`
(`gated_auto`/`manual`/`advisory`); `owner` (`downstream-resolver`/`human`/`release`).

## Reviewers

The reviewer team is selected from `references/persona-catalog.md` -- 6 always-on
personas, plus conditional
personas (including the layering persona -- `medallion-architecture`,
`inmon-architecture` or `kimball-architecture`) chosen by reading the diff. The
**review depth** scales the always-on floor: **Full** runs all 6 always-on
personas; **Lean** trims to `correctness`, `data-integrity`,
`project-standards`, and `compliance-traceability` (see `references/persona-catalog.md`
-> Review depth). All always-on and conditional review personas now have agent files;
the platform experts beyond `fabric-cli-expert` and the doc-review personas are still
pending. **Skip any persona whose agent file does not exist yet and note it in
Coverage.**

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
title/body, the branch name, the latest commits, and the conversation. This intent is
passed to every reviewer so they can check code against stated purpose.

### Stage 2b: Plan / requirements discovery

Establish the requirements baseline for the `compliance-traceability` persona and the
Requirements Completeness section:

- Use `plan:` when passed (`plan_source: explicit`).
- Else discover conservatively: the plan held in this session, when there is one (its
  inline units carry the requirements each advances), plus `architecture.html`, `design.html`,
  `testplan.html`, `assessment.html` under `docs/artifacts/` (legacy: flat `docs/`, and
  an older `plan.md`/`tasks.md`/`testplan.md` trio), and any prestudy referenced by the
  branch/PR (`plan_source: inferred`).
- If none found, note it once in Coverage and review against intent only.

### Stage 3: Select reviewers

**1. Resolve the review depth** (Full | Lean) by precedence per
`references/persona-catalog.md` -> Review depth: the `depth:` token wins; else a
large-or-high-risk diff (PII, financial, backfill, migration, new source) forces
**Full**; else the plan's announced tier (Stage 2b); else the diff-scope heuristic
(Lean for a small brownfield-incremental diff); else **default Full**.

**2. Select the always-on floor for that depth** (skip missing agent files, note in
Coverage): **Full** runs all 6 always-on personas; **Lean** trims to
`correctness`, `data-integrity`, `project-standards`, and `compliance-traceability`.
**3. Select conditional personas by judgment** from the full diff per
`references/persona-catalog.md` (scd-correctness, pipeline-reliability, cost-perf,
data-security, data-contract, data-migration, adversarial) -- these fire on their own
diff signal at **either** depth, so a small-but-risky Lean diff still pulls its
specialist. Select **the layering persona** only when the diff crosses or defines a
layer boundary **and** the repo has a layered architecture -- then pick the one matching
it: `medallion-architecture` for medallion repos, `inmon-architecture` for Inmon EDW
repos, `kimball-architecture` for Kimball dimensional repos (`architecture:` in
`.raid/config.yaml`; absent = medallion), never more than one. Its skip
is a normal non-selection, not a Coverage note. Select the
`raid-deploy-verification-agent` when the change is a risky deploy, and the platform
expert (e.g. `fabric-cli-expert`) when `.raid/config.yaml` names that platform and the
diff involves its execution surface.

**4. Announce the depth and the team** before spawning -- the one-line reason the depth
was inferred, plus a one-line justification per conditional reviewer selected. This is
an announcement, not a prompt; do not wait for a reply.

### Stage 3b: Discover project-standards paths

Collect the relevant `CLAUDE.md`/`AGENTS.md` paths (root plus any in ancestor
directories of changed files) to pass to `raid-project-standards-reviewer` in a
`<standards-paths>` block.

### Stage 4: Spawn sub-agents

**Run ID** -- generate before dispatch; scopes all artifacts:

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' ')
mkdir -p "/tmp/raid/review-changes/$RUN_ID"
```

**Model tiering.** `raid-correctness-reviewer` and `raid-adversarial-reviewer` inherit
the session model (highest-stakes analysis). All other personas, synthesis agents, and
validators use the platform's mid-tier model (`model: "sonnet"` in Claude Code) to cut
cost/latency. Omit the override where the dispatch primitive has none.

**Bounded parallel dispatch.** Respect the harness active-subagent limit; queue and
fill freed slots. Treat concurrency-limit spawn errors as backpressure (re-queue),
not reviewer failure.

Spawn each persona with the `references/subagent-template.md` wrapper, substituting:
the persona's agent-file content, `references/diff-scope.md`, `references/findings-schema.json`,
PR metadata (`<pr-context>`), and review context (intent, file list, diff, scope mode,
`PR_HEAD_REF` when set, run id, reviewer name). For `project-standards` append the
`<standards-paths>` block; for `compliance-traceability` append a
`<requirements-context>` block with the Stage 2b paths; for `data-migration` append the
resolved `<review-base>`.

Each persona writes full JSON to
`/tmp/raid/review-changes/$RUN_ID/<reviewer>.json` and returns compact JSON
(merge-tier fields). The synthesis agent (`raid-deploy-verification-agent`) is
dispatched through the same scheduler with the same context bundle; its output is
unstructured and synthesized in Stage 6.

### Stage 5: Merge findings

Convert the compact returns into one deduplicated, confidence-gated set:

1. **Validate** each return against the merge-tier field/value constraints; drop
   malformed findings and record the count.
2. **Deduplicate** by fingerprint `normalize(file) + line_bucket(line, +/-3) +
   normalize(title)`; keep highest severity and anchor; record which reviewers flagged it.
3. **Cross-reviewer agreement** -- when 2+ reviewers match a fingerprint, promote one
   anchor step (`50->75`, `75->100`). Note the agreement in the Reviewer column.
4. **Separate pre-existing** (`pre_existing: true`) into their own list.
5. **Normalize routing** -- set final `autofix_class`/`owner`/`requires_verification`;
   keep the more conservative route on disagreement.
6. **Mode-aware demotion** -- a P2/P3 + `advisory` finding flagged **only** by
   `testing` or `maintainability` moves to `testing_gaps` / `residual_risks`
   respectively. Any cross-reviewer corroboration keeps it in primary.
7. **Confidence gate** -- suppress remaining findings below anchor 75; exception: P0 at
   anchor 50+ survives. Record suppressed counts by anchor.
8. **Partition** -- actionable queue (`gated_auto`/`manual` owned by
   `downstream-resolver`) vs report-only (`advisory`, or `human`/`release` owned).
9. **Sort and number** by severity -> anchor desc -> file -> line; assign stable `#`
   reused across all sections.
10. **Collect coverage** -- union residual_risks and testing_gaps; preserve the
    synthesis-agent outputs.

### Stage 5b: Validation pass

Independent re-verification with `references/validator-template.md`. Runs whenever at
least one finding survives Stage 5. One validator sub-agent per surviving finding
(mid-tier model, read-only). Budget cap 15 by severity (P0 first); **never drop a
P0/P1 from validation** -- raise the cap if P0/P1 alone exceed 15. Pass each validator
the finding fields, `why_it_matters` from the artifact file, the diff, and the scope
mode / `PR_HEAD_REF`. `validated:false` drops the finding (record the reason);
validator infra failure drops P2/P3 but keeps P0/P1 as `degraded`. Record metrics for
Coverage.

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
`- **#N** -- ...` detail line. Sections: Header (scope/intent/mode/team), Applied
(default only), per-severity Findings, Requirements Completeness (only when a plan was
found in Stage 2b -- explicit unaddressed requirements are P1/manual/actionable;
inferred are P3/advisory/report-only), Actionable Findings, Pre-existing,
Deployment Notes (from
`raid-deploy-verification-agent` when it ran), Coverage, and a blockquote Verdict. No
time estimates. Run the template's format-verification gate before delivering.

### JSON output format (`mode:agent` only)

Emit **one raw JSON object** (no markdown fence) and also write `review.json` under
`/tmp/raid/review-changes/<run-id>/`. Minimum fields: `status`, `verdict`, `scope`,
`intent`, `depth`, `reviewers`, `findings`, `actionable_findings`, `artifact_path`,
`run_id`. `depth` records the resolved review depth (`full`/`lean`) for traceability.
`mode:agent` does not apply fixes; the handoff is `actionable_findings`. Failure:
`{"status":"failed","reason":"..."}`; partial: `"status":"degraded"` with a reason.

## Quality gates

- Never push, switch branches, or run DDL/DML.
- Suppress findings below anchor 75 (except P0 at 50+).
- Always validate P0/P1 findings (Stage 5b).
- Skip-and-note any persona whose agent file is not yet built.
- Default to **Full** when depth inference is ambiguous; never silently
  under-review. The depth trims the always-on floor only, never a warranted conditional.

## Included references

- `references/persona-catalog.md` -- reviewer roster and selection rules
- `references/subagent-template.md` -- the persona spawn wrapper + output contract
- `references/validator-template.md` -- the independent validation pass
- `references/diff-scope.md` -- scope discovery + remote PR/MR scope + finding tiers
- `references/action-class-rubric.md` -- autofix_class + owner routing
- `references/findings-schema.json` -- the structured findings contract
- `references/review-output-template.md` -- the canonical report skeleton
