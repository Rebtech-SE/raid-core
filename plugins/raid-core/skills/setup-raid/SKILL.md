---
name: setup-raid
description: >-
  Use once at the start of an engagement, or when the user says 'set up RAID here',
  'initialise the engagement', 'raid setup'. Scaffolds a RAID engagement repo and
  confirms the active data platform and the engagement's issue tracker (Azure DevOps
  Boards, Jira, Linear, GitHub or GitLab), writes .raid/config.yaml, leaves a
  sentinel-delimited RAID pointer block in the repo's instruction files, checks the git
  host CLI and .venv environment, and verifies the right RAID platform-tier plugin is
  installed. Writes one config file plus the pointer block - nothing else.
argument-hint: "[optional: platform - fabric|gcp|aws|databricks]"
---

# RAID Setup

One-time engagement bootstrap. Replaces the multi-repo `init-customer-engagement`'s
heavy repo/skill-copy machinery -- skills now ship inside the installed plugins, so
setup just prepares the engagement repo and records what platform we're on, so the
build loop (`raid-mode` ... `review-changes`) knows which tier to use.

Idempotent: detect what already exists and only fill gaps. Never overwrite a populated
`config.yaml` or an existing doc without confirming.

## Workflow

### 1. Confirm the platform

**Ask -- do not decide silently.** Detection is good enough to recommend an answer and
not good enough to be one: a repo can carry dbt and BigQuery artifacts and still be an
engagement to build on Fabric, and getting this wrong loads the wrong tier for the whole
engagement.

- If `$ARGUMENTS` names a platform, or an existing `.raid/config.yaml` already records
  one, take it and move on -- that is an answer, not a guess.
- Otherwise scan the repo for a signal -- dbt + Fabric artifacts -> `fabric`;
  `dbt_project.yml` + a BigQuery profile / Dataform -> `gcp`; `databricks.yml` / DABs ->
  `databricks`; AWS data artifacts -> `aws` -- and put it to the user as a blocking
  question with that signal as the recommended option and what it was based on. With no
  signal, ask the same question with no recommendation.

Note which RAID tier plugin that platform needs (`raid-fabric`/`raid-gcp`/`raid-aws`/
`raid-databricks`). If it isn't installed, point the user at `INSTALL.md` in the plugin
repo (the source of truth for installing/updating/managing RAID on any harness) to add it
alongside `raid-core`.

### 2. Scaffold the engagement structure

Create what's missing (do not clobber existing content):

```
.raid/
  config.yaml   # engagement config (below)
```

`raid-core` scaffolds no `docs/` directories. Plans are in-session working artifacts, not
files in the customer's repo, and RAID keeps no learnings store -- durable findings belong
on the engagement's issue tracker.

**Scaffold only what the installed plugins produce.** The above is the `raid-core` set.
If `raid-greenfield` is installed, also create the two directories its artifacts need:

```
docs/
  inputs/       # customer-provided source material: originals + converted copies (ingest-requirements writes here)
  artifacts/    # RAID-generated HTML deliverables: requirements.html, assessment.html, architecture.html, design.html, testplan.html
```

Check for `raid-greenfield` by whether its skills are available to you (e.g. is
`assess-platform` in your skill list?) -- do not create `docs/inputs/` or `docs/artifacts/`
on a core-only install, where nothing would ever write to them. The inputs/artifacts
split is deliberate: customer material and generated deliverables never mix flat in
`docs/`. If an existing engagement has artifacts
flat in `docs/` (legacy layout), offer to move them into `docs/artifacts/` -- with
`git mv`, updating any links -- rather than scaffolding a parallel structure.

Point the user at "Choosing the route" in `raid-core`'s AGENTS.md: incremental work on
an existing build is driven from `raid-mode` and is the default; a new platform needs
`raid-greenfield` installed.

### 3. Write .raid/config.yaml

Record the engagement config the pipeline reads:

```yaml
# .raid/config.yaml - RAID engagement configuration
customer: <name>            # ask if unknown
platform: <fabric|gcp|aws|databricks>
git:
  provider: <github|azure-devops|gitlab|other>   # detect from `git remote get-url origin`; default github
  # provider sub-block: include ONLY for the detected host. Examples:
  #   github:                 # when provider is github
  #     owner: <org-or-user>  # e.g. github.com/<owner>/<repo>
  #   azure_devops:           # when provider is azure-devops
  #     org: <org>            # e.g. dev.azure.com/<org>
  #     project: <project>    # the Azure DevOps project for repos
tracker:                    # ASK, never infer -- see step 6
  provider: <azure-devops|jira|linear|github|gitlab|local>
  # provider sub-block: include ONLY the chosen one. Examples:
  #   azure_devops: { org: <org>, project: <project> }   # may differ from git.azure_devops
  #   jira:         { site: <site>, project_key: <KEY> }
  #   linear:       { team_key: <TEAM>, team_id: <uuid> }
  #   github:       { owner: <owner>, repo: <repo> }     # usually the git remote
  # labels:                 # ONLY when this tracker's strings differ from the canonical
  #   ready_for_agent: Ready  # roles (needs-triage, needs-info, ready-for-agent,
  #                           # ready-for-human, wontfix) -- omit the block otherwise
architecture: medallion     # medallion (default) | inmon | kimball -- see "Architecture style" below
naming:                     # layer naming per platform (defaults; confirm)
  # keys follow the architecture style:
  #   medallion -> bronze / silver / gold
  #   inmon     -> staging / edw / marts
  #   kimball   -> staging / dw   (dimensions + facts share the presentation layer)
  bronze: <prefix/location>
  silver: <prefix/location>
  gold: <prefix/location>
conventions:
  audit_columns: [_ingestion_timestamp, _source_system, _batch_id]
  scd_columns: [_valid_from, _valid_to, _is_current, _hash]
telemetry:                  # ONLY after an explicit yes (below); omit otherwise
  enabled: true
  engagement_id: <customer-or-engagement-slug>
```

Fill what's known from the repo/arguments; mark inferred values. Detect `git.provider`
from the `origin` remote (see the provider table in `raid-core/AGENTS.md`), defaulting to
`github` when ambiguous; add only the sub-block for the detected host (e.g. the
`azure_devops:` block, and confirm its project, when the host is Azure DevOps).

**Architecture style (`architecture:`).** RAID's default is **medallion** -- write
`medallion` and move on unless there is a reason not to. Do **not** ask about this at
setup. On the full pipeline `design-architecture` (in `raid-greenfield`) owns the decision
and will rewrite the key if it decides otherwise; on a core-only install the value you
write here stands until someone changes it. Set a non-default value here only when the repo already *is* that kind of warehouse:
`inmon` for a staging/EDW/marts layout, `edw_*` table names, or an existing
enterprise/subject-area model; `kimball` for a staging plus `dim_*`/`fct_*` presentation
layout with shared conformed dimensions and no normalized core. On brownfield, what the
repo does wins over the default. The key drives layer vocabulary and reviewer selection downstream, so an
engagement that omits it is treated as medallion.

**Telemetry opt-in (explicit, default off).** Ask the user once: RAID can send
anonymous usage telemetry to rebtech -- one event per skill invocation containing
only `{timestamp, skill name, plugin version, engagement id, session id,
installation id}`; never prompts, code, paths, names, or hostnames (full details
in the marketplace repo's PRIVACY.md). The `installation_id` is a random,
gitignored, engagement-scoped pseudonym (stored in `.raid/installation_id`) that
lets rebtech count *how many different people* worked on the engagement, not who
-- it is treated as personal data under the GDPR. Write the `telemetry:` block
only on an explicit yes; on no or no answer, omit the block entirely -- absence
means off. On client-owned devices, recommend leaving it off unless the
engagement agreement covers anonymised toolkit-usage metrics.

`setup-raid` owns the **per-repo** opt-in (`.raid/config.yaml`, written here). A
**global** opt-in (`~/.raid/config.yaml`, for a global install) is owned by the
install (`INSTALL.md`). The hook reads the per-repo file first and only falls back to the
global one when there is no per-repo config, so a per-repo `.raid/config.yaml` here always
takes precedence over any global opt-in -- keep the two consistent.

### 4. Environment health check

Report status (do not fail hard -- note what's missing):

- **git** -- is this a repo; what's the default branch; which provider hosts `origin`
  (GitHub / Azure DevOps / GitLab / other)? Record it as `git.provider`.
- **provider CLI** -- is the CLI for the detected provider installed and authed?
  GitHub -> `gh auth status`; Azure DevOps -> `az` + the `azure-devops` extension
  (`az extension show --name azure-devops`; point at the `az-cli` skill for setup);
  GitLab -> `glab auth status`. Note if missing — the PR flow falls back to printing a
  compare URL for the user.
- **Python** -- is there a `.venv`/`venv`? (Per `raid-core/AGENTS.md`, use the existing
  one; create only when the engagement needs Python.)
- **Platform tier plugin** -- is the platform's tier plugin installed?
- **Primed agent context** -- does the repo's instruction file carry a `map-repo`
  managed block? Check whichever convention the repo uses (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`, Cursor's rules) for the `<!-- prime-repo:start -->`
  sentinel (or the legacy `<!-- raid-prime:start -->`, which older engagements carry -- a
  repo with either is primed). The gap to flag is a **missing block**, not a missing file: a repo with a
  hand-written `AGENTS.md` and no managed block is the common case and needs mapping just as
  much as a repo with no file at all. `setup-raid` never writes it -- that's `map-repo`'s
  job (it explores the repo and writes the conventions). Note when the sentinel is absent
  and there is existing code, and point the user at `map-repo`, since the build loop
  (`raid-mode`/`review-changes`) reads and builds on it.

### 5. Pointers in the instruction files

A cold session should know this repo is a RAID engagement **before any skill
runs** -- that is why this pointer is written now and not lazily. (Everything
the pointer mentions as *owned elsewhere* is created lazily by the skill that
owns it; only the pointer itself is upfront, because nothing later in the
engagement would ever get around to writing it.)

Write a short managed block into whichever instruction files the repo uses
(`AGENTS.md`, `CLAUDE.md` -- or a symlink to it -- `.github/copilot-instructions.md`,
`.cursor/rules/`). Check what exists; create `AGENTS.md` only if the repo has no
instruction file at all. Sentinel-delimited so re-runs update in place and the
repo's own content is never touched:

```markdown
<!-- raid:start -->
This repo is run as a RAID engagement (rebtech RAID plugins).

- Entry point: `raid-mode` -- it picks the route and runs the build loop
  (`work -> simplify-code -> review-changes -> open-pull-request`).
- Engagement config: `.raid/config.yaml` -- active platform, git provider,
  issue tracker (+ triage label mapping), architecture style, layer naming.
- Domain vocabulary lives in `GLOSSARY.md` and decisions in `docs/adr/`,
  owned by `domain-modeling`. Both are created lazily -- never pre-create
  them, and never write an empty `GLOSSARY.md`.
- Repo conventions are captured by `map-repo` in a managed block in this
  file; the build loop reads and builds on them.
- Full pipeline: when `raid-greenfield` is installed, discovery-and-design
  artifacts live in `docs/artifacts/` and the chain starts at
  `assess-platform`.
<!-- raid:end -->
```

Adapt the block to what actually exists (drop the `raid-greenfield` line on a
core-only install -- step 2 already determined which plugins are present). Update an existing
block rather than appending a second one; if the repo carries the legacy
`<!-- raid-prime:start -->` or `<!-- prime-repo:start -->` block from `map-repo`,
leave it alone -- this pointer sits beside it, it does not replace it.

### 6. Issue tracker

RAID publishes specs and unit tickets to the engagement's own tracker -- that is where
work survives a session, since `raid-core` writes no plan or solution documents into the
customer's repo.

**Ask which tracker the engagement uses. Never infer it from the git remote.** Azure
DevOps Repos with Jira boards, and GitHub with Linear, are both common in enterprise
estates; guessing wrong sends a customer's specs into the wrong system. One blocking
question, the git host's own tracker offered as the recommended answer when nothing
suggests otherwise.

Record the answer as the `tracker:` block in `.raid/config.yaml` -- **provider plus the
identifiers only**. That is the whole per-repo config. The command recipes for each
tracker ship with this skill in [`references/trackers/`](./references/trackers/)
(`azure-devops.md`, `jira.md`, `linear.md`, `github.md`); a skill that needs to create or
read a ticket reads the file for the configured provider at the time it needs it. Nothing
is copied into the repo, so a template fix reaches every engagement on the next plugin
update instead of rotting in a hundred checkouts.

Fill in the identifiers the provider needs by asking, or by reading them off an existing
ticket the user names -- do not guess an org, project key or team id.

Two cases worth handling explicitly:

- **The tracker's labels differ from the canonical triage roles** (`needs-triage`,
  `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), or the project models
  state as workflow status and rejects unknown labels -- common on Jira and on customised
  Azure DevOps processes. Record the mapping under `tracker.labels`. Omit the block when
  the defaults work.
- **The tracker is unreachable from this machine** (no credentials, no network path).
  Say so and record `provider: local` -- tickets go to `docs/tickets/` until access
  exists. Do not silently fall back; which tracker an engagement uses is the customer's
  decision, not a default.

### 7. Confirm and hand off

Print what was created/detected (platform, config path, docs structure,
instruction-file pointers, environment gaps). Point the user at the next step: `map-repo` to capture an
unfamiliar repo's conventions, then `raid-mode` for incremental work -- or, when
`raid-greenfield` is installed and the platform decisions don't exist yet, `assess-platform`
to start discovery. Note any blocker (missing tier plugin, missing git host CLI) they
should resolve first.

## Rules

- Idempotent and non-destructive; confirm before overwriting.
- Repo-relative paths.
- Don't create a `.venv` unless the engagement actually needs Python yet.
