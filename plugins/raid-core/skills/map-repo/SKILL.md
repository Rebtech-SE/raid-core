---
name: map-repo
description: >-
  Use at the start of work in an unfamiliar repo, or when the user says 'map this repo',
  'onboard to this codebase', 'what are the conventions here', 'prime the repo', 'audit
  the tech debt'. Explores a repo read-only and persists its architecture map plus
  conventions/standards into a managed block in AGENTS.md (created if missing, merged not
  clobbered), and writes a separate dated tech-debt report to docs/audit/. Standalone --
  needs no requirements doc or engagement.
argument-hint: "[path to a repo, or empty for the current working directory] "
---

# Map Repo

The agent's front door to a repo. `map-repo` explores an existing codebase and writes
what it learns into two places: the **operative conventions and architecture** go into a
managed block in `AGENTS.md` so every future session (and every RAID skill) inherits
them; the **technical debt and risks** go into a separate dated report so the agent isn't
left guessing where the bodies are buried.

It is **not** `assess-platform` (which ships in `raid-greenfield`). `assess-platform` produces a
client-facing `assessment.html` deliverable, read once by a human at an approval gate, and
is coupled to a customer engagement and its requirements. `map-repo` produces durable *agent* context: terse
markdown, re-read every session, updated in place, and needs no requirements doc or
engagement to run. The two share the same discovery subagents, so nothing is rediscovered
twice.

**IMPORTANT: all file references in both outputs use repo-relative paths**, never
absolute paths.

## Interaction method

Use the platform's blocking question tool: `AskUserQuestion` in Claude Code (call
`ToolSearch` with `select:AskUserQuestion` first if its schema isn't loaded). Fall back
to numbered options in chat only when no blocking tool exists. `map-repo` is mostly
non-interactive - it explores and writes - but it **asks once before editing an
instruction file** that already holds hand-authored content (see Phase 2a), and never
silently overwrites.

## Input and routing

<input> #$ARGUMENTS </input>

The input is a path to the repo to prime; empty means the current working directory.
There is no greenfield/brownfield split and no requirements intake - `map-repo` always
operates on an existing repo and is purely additive to whatever is there.

## Workflow

### Phase 0: Detect context

Establish what already exists before exploring or writing:

- Read `.raid/config.yaml` for the active platform if present (it sharpens what the
  discovery subagent looks for).
- **Find the repo's existing agent-instruction convention and adopt it.** `map-repo`
  always runs against a repo, so the repo -- not the harness you happen to be running in
  -- decides where the block goes. Look for all of these:

  | Convention | Used by |
  |---|---|
  | `AGENTS.md` | the open standard (Codex, Cursor, Copilot coding agent, others) |
  | `CLAUDE.md` | Claude Code |
  | `.github/copilot-instructions.md` | GitHub Copilot (CLI and the VS Code chat extension) |
  | `.cursor/rules/*.mdc`, `.cursorrules` | Cursor |

  The **substantive file is the edit target**. One may be a shim that `@`-includes another,
  or `CLAUDE.md` may be a symlink to `AGENTS.md` (as in RAID repos) -- ignore shims and
  edit what they point at. If the repo genuinely maintains two independent files, the
  block goes in one (prefer `AGENTS.md`) and the others get a pointer line; see
  `references/agents-block.md`. Never write the block into two files.
- **If the repo has none of them,** the target is a new `AGENTS.md` (Phase 2a). Do not
  detect the harness and do not create a `CLAUDE.md`, a symlink, or any other
  harness-specific file -- `AGENTS.md` is the portable default.
- Check whether a prior `map-repo` managed block already exists in the target file
  (the sentinel pair from Phase 2a). If it does, this is a **re-run**: Phase 2a refreshes
  the block in place rather than inserting a new one.
- Check for an existing `docs/audit/` report from a prior run; a re-run updates the
  current dated report (see Phase 2b).

### Phase 1: Explore (read-only)

Map the repo. This phase is strictly read-only - never run the repo's code, execute its
scripts, or mutate anything.

- Dispatch `raid-repo-research-analyst` against the repo. It returns a structured map:
  platform & stack (with versions), architecture & layering, key models & grain,
  ingestion & sources, **conventions** (naming, SQL style, testing, config/secrets, and
  any rules the repo already states), and **observations & gaps** (fragile spots, thin
  tests, duplicated logic, missing docs). Its output is the raw material for both outputs:
  conventions/architecture feed Phase 2a, observations/gaps feed Phase 2b.
  relevant to the repo's stack and domain, so recorded conventions and known-debt reflect
  what the team has already learned.
- Dispatch `raid-git-history-analyzer` **only on a specific oddity** the analyst surfaced
  ("why is this model built this way?") - it is scoped to a single question, not a blanket
  history scan. Skip it when nothing needs explaining.

### Phase 2a: Write the AGENTS.md managed block

Persist the **operative** findings - architecture map and conventions/standards - into a
delimited managed block in the target instruction file. Follow
`references/agents-block.md` for the marker format, the section schema, and a worked
example. Render the block from that reference; do not hand-roll its shape.

Rules that govern the write:

- **The sentinel is a data format, not the skill name.** The managed block stays
  `<!-- prime-repo:start -->` / `<!-- prime-repo:end -->` even though this skill is now
  `map-repo`. Repos in the field carry that marker in their `AGENTS.md`; renaming it would
  orphan every block RAID has ever written. Never rename a sentinel to track a skill rename.
- **Managed block only.** Write only the content between the `<!-- prime-repo:start -->`
  and `<!-- prime-repo:end -->` sentinels. Everything outside them - including
  hand-authored conventions - is left byte-for-byte unchanged. Do not re-serialize or
  reformat the surrounding file.
- **Legacy sentinel.** Repos primed before 2026-08-29 carry `<!-- raid-prime:start -->` /
  `<!-- raid-prime:end -->`, the skill's former name. **Match either pair when locating an
  existing block**, and when you rewrite it, replace the old sentinels with the
  `map-repo` pair in place. Never leave both pairs in a file and never append a second
  block because the new sentinel was absent.
- **Merge, not clobber.** On a re-run, replace the content *between* the existing
  sentinels in place. Never append a second block; never delete content outside them.
- **Create only when absent, and create only `AGENTS.md`.** When the repo has none of the
  conventions from Phase 0, create `AGENTS.md` containing the block - and stop there. Do
  not add a `CLAUDE.md`, a symlink, or a harness-specific file: a symlink does not survive
  a Windows checkout, and a second file is one more thing to drift. Add one only if the
  user explicitly asks. When a convention already exists, target the substantive file from
  Phase 0 and keep any symlink/shim relationship intact - never create a competing file.
- **No domain vocabulary here.** Business terms, measure definitions and grain belong in
  `GLOSSARY.md`, owned by `domain-modeling`. If the repo has one, the block points at it;
  it never copies terms out of it. Two homes for the same term is how they drift apart.
- **No debt list here.** The block carries architecture and conventions only. Debt goes
  to Phase 2b. At most, record the *operative consequence* of a known issue when it
  changes how the agent should act (e.g. "X is the source of truth, not Y"), never a
  findings backlog.
- **Ask before editing existing hand-authored content.** When the target file already
  exists with substantive content and has no prior `map-repo` block, show the proposed
  block and where it goes, then ask once (blocking question) before writing. A re-run that
  only refreshes an existing block does not need to re-ask. In a pipeline/headless
  context, apply the smallest edit directly and surface it in the close-out.

### Phase 2b: Write the tech-debt report

Persist the **technical debt and risks** to `docs/audit/<date>-techdebt.md`. Follow
`references/techdebt-report.md` for the section structure and an example. This is
dev-facing markdown, deliberately *not* a templated HTML deliverable.

- Each finding carries a **severity** and a repo-relative `file:line` anchor. A finding
  with no locatable anchor is still recorded, marked repo-wide rather than dropped.
- The date lives in the filename. On a same-day re-run, overwrite the current dated
  report rather than creating a second file for the same day.
- Create `docs/audit/` if it does not exist.

### Phase 3: Report

Tell the user what landed: **name the managed-block target file explicitly** (and whether
it was created, inserted into, or refreshed) -- if their harness doesn't auto-load that
file, naming it is what makes that visible -- plus the tech-debt report path with a
one-line headline of what it found. Point the next step at `raid-mode` for incremental work, or -- when the
user is heading into a customer engagement and `raid-greenfield` is installed --
`assess-platform`, which builds on the primed `AGENTS.md` instead of re-deriving the
conventions.

## Scope discipline

- **Agent context, not a client deliverable.** `map-repo` writes operative markdown for
  the agent. Client-facing discovery (`assessment.html`), requirements intake, and the
  "what's present vs what's missing against requirements" gap analysis all belong to
  `assess-platform` in `raid-greenfield`.
- **Read-only on the repo.** Exploration uses read tools and read-only `git`; the only
  writes are the managed block and the tech-debt report. Never run the repo's pipelines or
  mutate its data.
- **Additive and idempotent.** Re-running refreshes the managed block and the dated report
  in place; it never duplicates a block or clobbers hand-authored content.

## References

- `references/agents-block.md` - the managed-block marker format, section schema (architecture + conventions), and a worked example showing the byte-level merge behavior.
- `references/techdebt-report.md` - the light fixed-section structure for `docs/audit/<date>-techdebt.md` and an example finding (severity + `file:line`).
