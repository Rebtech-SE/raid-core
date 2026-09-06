# RAID - engagement conventions

These rules govern work done with the RAID plugins during a data-platform
engagement. They ship inside `raid-core` (always installed) and apply to every
RAID skill and subagent, including the platform tiers (raid-fabric, raid-gcp,
raid-aws, raid-databricks).

## Start here: `raid-mode`

**`raid-mode` is the entry point.** It reads the request, picks the route, and runs the
skills below as the steps need them -- holding the approval gates and the
validate-against-real-data bar. Call the individual skills directly only when you already
know exactly which one you want.

## The build loop

`raid-core` is the **build loop** -- everything you need to work, review and ship data
work in a codebase whose architecture already exists (your own, or a customer's):

```
raid-mode -> work -> (write-test-report) -> simplify-code -> review-changes
```

- **raid-mode** - the entry point and the working model: picks the route, holds the
  breakdown, and carries the build discipline (one complete unit at a time, tests with the
  code, verified against real data, per-unit self-review). RAID writes **no plan file into
  the customer's repo** - units live in the conversation, or as tickets on the engagement's
  issue tracker when the work must outlive the session
- **wayfinder** *(when the work is too big to see the end of)* - charts the open decisions
  as a map of tickets on the tracker and resolves them one at a time, until nothing is left
  to decide
- **write-test-report** *(after a cycle)* - the test report for the cycle: planned vs
  executed, each outcome with its failure reason, and failures carried forward even after
  a test goes green -> `docs/testing/testreport.html` (beside its ledger, so a core-only
  engagement never needs the greenfield-owned `docs/artifacts/`)
- **simplify-code** - quality-only tidy of the changed models/notebooks
- **review-changes** - multi-agent review: correctness, integrity, medallion, SCD, reliability

**Understanding, not changing** -- a question is not authorization to edit anything:
**how** (mechanism, and the lineage trace back from a number to its source, naming
the transform and the grain at each hop), **why** (the recorded rationale behind a
grain, an SCD choice or a discrepancy, cited to an ADR, artifact, commit or ticket, with
inference labelled as inference), and **teach** (walks a person through it plainly, on top
of both -- also the handover explainer).

**Breaking work down** -- **to-tickets** cuts a plan, artifact or conversation into
vertical slices that each land bronze-to-gold with their tests, declares the blocking
edges, and publishes them on the tracker. Wide schema changes go expand-migrate-contract
instead of a tracer bullet. It publishes in the **standard ticket-brief shape** (below).

**Proving it works** -- **create-verification-skill** builds the guarded query tool, the
project-local `verify-<platform>` skill and the data map once per engagement;
**maintain-verification-skill** audits and repairs that map against the models and against
real data afterwards, so it does not go green while proving nothing.

**Reshaping and enforcing** -- **refactoring** (structural moves with the output pinned
and diffed before and after; `simplify-code` is the in-place counterpart),
**codify-conventions** (turn how the repo behaves into sqlfluff/dbt/hook checks that
actually fire -- the mechanism behind `principle-encode-lessons-in-structure`, where
`map-repo` only records them), **resolving-merge-conflicts** (dbt YAML, notebook and
pipeline JSON, lock files and generated manifests).

Other side-channel skills: **map-repo** (explore a repo read-only and prime durable agent
context -- architecture + conventions into a managed block in `AGENTS.md`, plus a
`docs/audit/` tech-debt report), **setup-raid** (platform detection + `.raid/config.yaml`),
**domain-modeling** (settle the business vocabulary in `GLOSSARY.md` and record hard
decisions as ADRs), **grilling** + its routers **grill-me** / **grill-with-docs**
(stress-test a plan or decision in rounds down a design tree; the with-docs router
writes each settled decision into the glossary and `docs/adr/` as the round ends, via
`domain-modeling`; **grill-me** is the same interview without the artifacts), **triage**
(move tracker issues and external PRs through the triage roles into agent-ready briefs --
the intake front door whose `ready-for-agent` tickets this build loop claims; verifies
claims against real data before anything is brief-worthy),
**debug-data-issue**,
**tune-workload** (metric-driven tuning loop for query cost/runtime/DQ),
**review-sessions** (read-only sweep over recent session history for decisions, fixes and
unfinished threads the in-the-moment loop missed), **check-platform-health**,
**handoff** (compact the session into a pickup document in the OS temp directory --
never into the customer's repo), **autoreview** (an extra single-engine review of a change
bundle, asked for by name -- distinct from `review-changes`, which is the data-reviewer
panel in the build loop), **report-raid-bug** (RAID itself misbehaved),
**unslop** (audit and rewrite copy to eliminate AI slop), and the git skills
(**commit-push-pr** -- single unified skill to stage, commit, push, draft unslopped PR
copy, apply across GitHub/Azure DevOps/GitLab, and babysit to merge-ready;
**manage-worktrees**, **resolve-pr-feedback**, **babysit** --
drive an open PR to merge-ready on any host, never merging it).

## One brief shape

Every ticket body and every subagent brief uses the same seven sections, in this order:

```
Goal   Scope   Context   Acceptance   Verify   Forbidden   Blocked by
```

`to-tickets` publishes in it, `triage` rewrites an incoming issue into it, `wayfinder`
gives a `task` ticket that shape, and `raid-mode` briefs a subagent with it. One shape
means a ticket written by any of them is picked up by any of the others with no
translation. **A section you cannot fill is a ticket that is not ready** -- do not mark it
`ready-for-agent`. The section definitions live in `to-tickets`'
`references/ticket-brief.md`; `triage`'s `references/agent-brief.md` is the data-shaped
guidance for filling them in.

On a customer estate, `Verify` and `Forbidden` are the sections that matter most: `Verify`
is where the real-data check gets written down instead of improvised, and `Forbidden` is
the written form of the autonomy boundary in the hard rules below.

## The full pipeline (raid-greenfield)

When the platform and design decisions **don't exist yet**, or the engagement owes the
customer sign-off artifacts, install **`raid-greenfield`** alongside this plugin. It adds
the discovery-and-design front end and the pipeline runner:

```
(plan-project) -> (ingest-requirements) -> assess-platform -> design-architecture -> design-data-model -> (write-test-plan) -> [raid-mode work -> (write-test-report) -> review-changes]
```

`raid-greenfield` also ships **ship-engagement** (runs the whole chain autonomously) and
**review-document** (planning-doc persona panel). Core's skills stay useful on their own:
The work loop consumes `architecture.html`/`design.html` when they exist and works from the
repo's own conventions when they don't, and calls `review-document` only when installed.

**docs/ layout:** customer material and generated deliverables never mix flat in `docs/`:

```
docs/
  audit/        # map-repo tech-debt reports (dated)
  testing/      # test-results.jsonl (append-only ledger) + testreport.html per cycle
  inputs/       # customer-provided source docs (raid-greenfield: ingest-requirements)
  artifacts/    # RAID-generated HTML deliverables (raid-greenfield)
```

`docs/inputs/` and `docs/artifacts/` are only created when `raid-greenfield` is installed
-- a core-only engagement never scaffolds them.

**Legacy fallback:** older engagements have the artifacts flat in `docs/`. When reading
an artifact, look in `docs/artifacts/` first, then fall back to `docs/<name>`; write new
artifacts to `docs/artifacts/` (matching where the existing one lives on a re-run, so a
legacy engagement isn't left with two copies).

## Choosing the route

**Incremental is the default.** On an existing codebase, the repo's conventions (layering,
naming, grain, patterns) *are* the settled architecture and design -- don't re-derive
them. On an unfamiliar repo, run **map-repo** first to capture those conventions into
`AGENTS.md`; later skills build on the primed context instead of rediscovering it.

| Route | When | Flow | Where the breakdown lives |
|---|---|---|---|
| **Direct** | Trivial: 1-2 files, no behavioral/modeling decision (rename, config, typo) | do it in `raid-mode` | nowhere -- just do it |
| **Incremental** *(default)* | Work on an existing codebase: ~<=5 models/files of new build, no new source system, no new platform decision, conventions observable in the repo | `raid-mode` work loop -> `simplify-code` -> `review-changes` | the conversation, or tracker tickets when it must outlive the session |
| **Too big to see the end of** | More than one session can hold, and the route itself is unclear -- a platform migration, a new source system, a domain re-model | `wayfinder` -> back to the incremental route once the way is clear | a map of decision tickets on the tracker |
| **Greenfield** *(needs `raid-greenfield`)* | New platform, new engagement, new source systems, novel grain/SCD decisions, or customer sign-off artifacts are owed | `assess-platform -> design-architecture -> design-data-model -> (write-test-plan)` -> then the incremental route | HTML artifacts under `docs/artifacts/` |

Any incremental criterion missed escalates the work a route up. `raid-mode` announces the
route so the user can override. If the work needs the greenfield pipeline and `raid-greenfield` isn't
installed, say so and offer the install rather than improvising the artifacts.

## Glossary

- **Skill** - a slash-invoked capability that orchestrates: pulls its own reference
  files progressively and dispatches subagents. User-facing.
- **Agent (subagent)** - a specialized worker a skill dispatches in an isolated
  context to return a result. Not invoked directly by users.
- **Domain skill** - tech knowledge (medallion, ingestion, scd, fabric-*, etc.) the
  orchestration skills and subagents read for the right technical decisions.

## Hard rules

- **Validate against real data whenever you have read access.** If you can run queries
  against the source/target warehouse or database (read access), you MUST verify what
  you build, change, or migrate against real data before it is "done" and before any
  review passes -- run the query and check the actual numbers: row-count parity,
  grain/key uniqueness, null/sentinel rates, FK integrity, before/after parity for
  migrations and backfills. A correctness, integrity, migration, or SCD claim -- and its
  all-clear -- is not trustworthy until checked against real data. The platform expert
  (`fabric-cli-expert` / `databricks-expert` / `bigquery-expert`) runs these probes.
  If you do **not** have read access, say so explicitly, lower confidence accordingly,
  and label the conclusion "not validated against data" -- never present an
  unverified-against-data result as verified. Validation is read-only; the only writes
  are the build's own gated DDL/DML, and never against prod without an explicit go-ahead.
- **Python uses an existing `.venv` or `venv`;** create one if none exists.
- **Conventional commits:** `feat(scope): summary`, `fix:`, `docs:`, `chore:`.
- **Repo-relative paths everywhere** in generated documents (e.g.
  `src/models/user.sql`), never absolute paths - they break portability across
  machines and teammates.

## Version control: host-agnostic, GitHub by default

RAID's git workflow is the same on any host. The **principles below are fixed**; only the
*commands* differ by provider, which you detect from the remote and then use consistently.
**Default to GitHub** when the host is ambiguous, but **never assume a single host** —
detect it and match.

**Detect the provider** from `git remote get-url origin`, then use that provider's CLI
for the whole task — never mix providers or assume one the remote doesn't match:

| Remote host | Provider | CLI | Term |
|---|---|---|---|
| `github.com` / GitHub Enterprise | GitHub | `gh` | pull request |
| `dev.azure.com` / `*.visualstudio.com` | Azure DevOps | `az repos` (bundled `az-cli` skill) | pull request |
| `gitlab.com` / self-managed GitLab | GitLab | `glab` | merge request |
| anything else / CLI missing | generic | `git push`, then print the remote's compare/create URL for the user to finish | pull request |

"PR" below means pull request **or** merge request, whichever the host uses.

- **The PR target is always the protected default branch** (`main`/`master`). All changes
  land via PR, never a direct push to it. There is no shared integration branch.
- Branch off a freshly fetched default (`origin/main`) — a temporary `feature/*`/`bugfix/*`
  branch, or a persisted personal branch (e.g. `ossian-dev`).
- A logical change spanning repos gets one PR per repo.
- Conventional commits and value-first PR descriptions on every host.
- **Issue / work-item linking is optional and tracker-neutral.** Do not ask about,
  infer, or nag for one when opening a PR — teams use different trackers (GitHub Issues,
  Jira, Linear, Azure Boards, etc.). Link or reference a tracker item only when the user
  explicitly supplies an id, using that host's reference syntax (e.g. GitHub/GitLab
  `Closes #<id>`, Azure Boards `AB#<id>`). RAID assumes no particular tracker and no
  particular item-state model.

## Platform tiers

RAID is split into a core plugin, an optional full-pipeline plugin, and per-platform
tier plugins so an engagement carries only the skills it needs. `setup-raid` (and
`design-architecture`, when `raid-greenfield` is installed) records the active platform in
`.raid/config.yaml`.

Install `raid-core` plus exactly one tier: `raid-fabric`, `raid-gcp`, `raid-aws`, or
`raid-databricks`. Add `raid-greenfield` when the engagement needs the discovery-and-design
front end. Every other plugin depends on `raid-core`; `raid-core` depends on nothing and
is fully usable alone.
