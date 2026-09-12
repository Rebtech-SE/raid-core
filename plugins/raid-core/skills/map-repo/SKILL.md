---
name: map-repo
description: >-
  Use at the start of work in an unfamiliar repo, or when the user says 'map this repo',
  'onboard to this codebase', 'document the architecture', 'what are the conventions here',
  'audit the tech debt'. Explores a repo read-only, generates or updates its architecture
  doc, and keeps AGENTS.md a short router to the stack, the commands and the docs that go
  deeper. Reports the conventions it finds and offers codify-conventions to enforce them;
  writes a dated tech-debt report to docs/audit/.
argument-hint: "[path to a repo, or empty for the current working directory] "
---

# Map Repo

The agent's front door to a repo. `map-repo` explores an existing codebase and leaves three
things behind:

- **An architecture doc** -- how the platform is built: the architecture style and its
  layers, the key models and their grain, the sources, the data flow, the schedules and
  neighbouring systems it depends on. It uses the doc the repo already has and keeps it
  current; when there is none, it generates `docs/architecture.md`.
- **A short router in `AGENTS.md`**, which every session reads first. It says what the repo
  is, how to build, test and deploy it, and where to read more -- the architecture doc
  first. An agent reliably follows only so many instructions, so anything not needed in
  every session lives in a doc the router points to, not in the router.
- **A dated tech-debt report**, so the agent isn't left guessing where the bodies are
  buried.

**Conventions go in none of them.** Naming, layer vocabulary, audit and SCD column names,
SQL style and test rules are picked up from the code an agent is imitating, and what it
misses a check catches every time where a prose rule catches it sometimes. `map-repo`
reports the conventions it observed and offers to run `codify-conventions`, which wires
each enforceable one into sqlfluff, dbt, a linter or a hook, keeps the judgment calls in
`CONVENTIONS.md`, and routes `AGENTS.md` to it.

It is **not** `assess-platform` (which ships in `raid-greenfield`). `assess-platform` produces a
client-facing `assessment.html` deliverable, read once by a human at an approval gate, and
is coupled to a customer engagement and its requirements. `map-repo` produces durable
engineering context: terse markdown, re-read and updated in place, needing no requirements
doc or engagement to run. The two share the same discovery subagents, so nothing is
rediscovered twice.

**IMPORTANT: all file references in every output use repo-relative paths**, never
absolute paths.

## Interaction method

Use the platform's blocking question tool: `AskUserQuestion` in Claude Code (call
`ToolSearch` with `select:AskUserQuestion` first if its schema isn't loaded). Fall back
to numbered options in chat only when no blocking tool exists. `map-repo` is mostly
non-interactive - it explores and writes - but it **asks once before editing a file that
already holds hand-authored content** (see Phase 2), asks once at the end whether to run
`codify-conventions` (Phase 3), and never silently overwrites.

## Input and routing

<input> #$ARGUMENTS </input>

The input is a path to the repo to map; empty means the current working directory.
There is no greenfield/brownfield split and no requirements intake - `map-repo` always
operates on an existing repo and is purely additive to whatever is there.

## Workflow

### Phase 0: Detect context

Establish what already exists before exploring or writing:

- **Find the repo's existing agent-instruction convention and adopt it.** `map-repo`
  always runs against a repo, so the repo -- not the harness you happen to be running in
  -- decides where the router goes. Look for all of these:

  | Convention | Used by |
  |---|---|
  | `AGENTS.md` | the open standard (Codex, Cursor, Copilot coding agent, others) |
  | `CLAUDE.md` | Claude Code |
  | `.github/copilot-instructions.md` | GitHub Copilot (CLI and the VS Code chat extension) |
  | `.cursor/rules/*.mdc`, `.cursorrules` | Cursor |

  The **substantive file is the edit target**. One may be a shim that `@`-includes another,
  or `CLAUDE.md` may be a symlink to `AGENTS.md` (as in RAID repos) -- ignore shims and
  edit what they point at. If the repo genuinely maintains two independent files, the
  router goes in one (prefer `AGENTS.md`) and the others get a pointer line; see
  `references/agents-sections.md`. Never write the same content into two files.
- **If the repo has none of them,** the target is a new `AGENTS.md`. Do not detect the
  harness and do not create a `CLAUDE.md`, a symlink, or any other harness-specific file --
  `AGENTS.md` is the portable default.
- **Find the architecture doc.** Look for `ARCHITECTURE.md`, `docs/architecture.md`, a
  `docs/architecture/` directory, an architecture page the README or the instruction file
  links to, and `docs/artifacts/architecture.html` on a greenfield engagement. The first
  hand-maintained one found is the doc Phase 2 keeps current; with none, Phase 2 creates
  `docs/architecture.md`.
- **Read what is already documented.** Read the instruction files, the architecture doc
  and the repo's other docs -- `README*`, `CONTRIBUTING*`, `docs/` (including `docs/adr/`
  and `docs/agents/`), `CONVENTIONS.md`, `GLOSSARY.md`. Note what each already covers and
  which docs exist to point at. That decides what Phase 2 writes: the gaps, and anything
  the code now contradicts.
- Check for an existing `docs/audit/` report from a prior run; a re-run updates the
  current dated report.

### Phase 1: Explore (read-only)

Map the repo. This phase is strictly read-only - never run the repo's code, execute its
scripts, or mutate anything.

- Dispatch `raid-repo-research-analyst` against the repo, with the Phase 0 notes on what is
  already documented, so it confirms those facts against the code instead of re-deriving
  them and spends its effort on what is not written down. It returns a structured map:
  platform & stack (with versions), architecture & layering, key models & grain,
  ingestion & sources, **conventions** (naming, SQL style, testing, config/secrets, and
  any rules the repo already states), and **observations & gaps** (fragile spots, thin
  tests, duplicated logic, missing docs).
- Dispatch `raid-git-history-analyzer` **only on a specific oddity** the analyst surfaced
  ("why is this model built this way?") - it is scoped to a single question, not a blanket
  history scan. Skip it when nothing needs explaining.

The analyst's map splits four ways: architecture, layering, models, sources and flow go to
the architecture doc; the stack in a line, the top-level layout and the commands go to the
router; conventions go to the Phase 3 hand-off; observations and gaps go to the tech-debt
report.

### Phase 2: Write

These rules govern every edit to a file that already exists:

- **Fill gaps; don't restate.** For each fact: already said and still true -> leave it.
  Covered by another doc -> a pointer to that doc, never a copy. Said, but contradicted by
  the code -> propose the correction, showing what the file says and what the code does.
  Not said anywhere -> add it.
- **Write into the file's own structure.** Put each addition under the heading where it
  belongs, in the file's voice and format; add a heading only for what has no home. No
  comment markers and no generated-section banner: the result reads like the rest of the
  file.
- **Leave everything else alone.** Touch only the lines you add or correct. Do not
  re-serialize, reorder or reformat the surrounding file.
- **Re-runs repeat the comparison.** A re-run reads the files again and adds or corrects
  only what has changed since. It never appends a second copy of a section.
- **Ask before editing hand-authored content.** When a target file already has substantive
  content, show the proposed additions and corrections and where each goes, then ask once
  (blocking question) before writing. In a pipeline/headless context, apply the smallest
  edit directly and surface it in the close-out.

#### 2a. The architecture doc

Keep the doc Phase 0 found current, or create `docs/architecture.md`. Follow
`references/architecture-doc.md` for what it covers and an example. It describes what the
code does today, and it **names the architecture style** -- medallion, Inmon EDW or Kimball
dimensional -- because `review-changes` picks its layering reviewer from that line.

`docs/artifacts/architecture.html` is a signed-off design deliverable: never edit it. Point
at it, and put any place the built repo diverges from it in the tech-debt report.

#### 2b. The router in the instruction file

Keep the router short. Follow `references/agents-sections.md` for what goes in and a
worked example.

- **Point at the docs; don't absorb them.** The router always points at the architecture
  doc, and at `CONVENTIONS.md`, `GLOSSARY.md`, `docs/adr/` and
  `docs/agents/issue-tracker.md` when they exist. A pointer says what the doc answers, in
  a few words.
- **Strike what an agent would do anyway.** "Run the tests before committing", "write clean
  SQL" and "follow the existing patterns" earn no line. Keep the local facts an agent cannot
  guess: this repo's odd build step, the sibling repo it depends on, the schedule a model has
  to land before.
- **No conventions.** Convention rules the file already carries stay where they are; the
  report says which of them a check could enforce.
- **No domain vocabulary.** Business terms, measure definitions and grain belong in
  `GLOSSARY.md`, owned by `domain-modeling`; the router points at it.
- **Create only when absent, and create only `AGENTS.md`.** When the repo has no
  instruction file, create `AGENTS.md` with the router - and stop there. Do not add a
  `CLAUDE.md`, a symlink, or a harness-specific file: a symlink does not survive a Windows
  checkout, and a second file is one more thing to drift. Add one only if the user
  explicitly asks. When a convention already exists, target the substantive file from
  Phase 0 and keep any symlink/shim relationship intact - never create a competing file.

#### 2c. The tech-debt report

Persist the **technical debt and risks** to `docs/audit/<date>-techdebt.md`. Follow
`references/techdebt-report.md` for the section structure and an example. This is
dev-facing markdown, deliberately *not* a templated HTML deliverable.

- Each finding carries a **severity** and a repo-relative `file:line` anchor. A finding
  with no locatable anchor is still recorded, marked repo-wide rather than dropped.
- The date lives in the filename. On a same-day re-run, overwrite the current dated
  report rather than creating a second file for the same day.
- Create `docs/audit/` if it does not exist.
- An operative consequence of a known issue that changes how an agent should act ("X is the
  source of truth, not Y") may also go in the architecture doc; the findings list never does.

### Phase 3: Report and hand off

Tell the user what landed:

- **The architecture doc and the instruction file, named explicitly**, and what changed in
  each -- created, facts added or corrected, pointers added, or already complete. If their
  harness doesn't auto-load the instruction file, naming it is what makes that visible.
- **The tech-debt report path**, with a one-line headline of what it found.
- **The conventions observed**, each marked *enforceable* (naming the check that would catch
  it -- a sqlfluff rule, a dbt test, a pre-commit hook) or a *judgment call*.

Then ask once whether to run `codify-conventions` now with those conventions as its
starting audit. On a yes, invoke it. On a no, or in a pipeline/headless context, leave the
list in the report and name `codify-conventions` as the step that enforces it.

Point the next step at `raid-mode` for incremental work, or -- when the user is heading into
a customer engagement and `raid-greenfield` is installed -- `assess-platform`, which builds
on the architecture doc instead of re-deriving it.

## Scope discipline

- **Engineering context, not a client deliverable.** Client-facing discovery
  (`assessment.html`), requirements intake, and the "what's present vs what's missing
  against requirements" gap analysis all belong to `assess-platform` in `raid-greenfield`.
- **Read-only on the repo.** Exploration uses read tools and read-only `git`; the only
  writes are the architecture doc, the instruction file and the tech-debt report. Never run
  the repo's pipelines or mutate its data.
- **Additive and idempotent.** Re-running updates all three in place; it never duplicates a
  section or clobbers hand-authored content.

## References

- `references/architecture-doc.md` - what the architecture doc covers, how it stays current, and an example.
- `references/agents-sections.md` - what the router in `AGENTS.md` carries and points at, how it merges with the file, and a worked example.
- `references/techdebt-report.md` - the light fixed-section structure for `docs/audit/<date>-techdebt.md` and an example finding (severity + `file:line`).
