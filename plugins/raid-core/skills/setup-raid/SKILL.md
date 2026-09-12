---
name: setup-raid
description: >-
  Use once at the start of an engagement, or when the user says 'set up RAID here',
  'initialise the engagement', 'raid setup', 'set up the issue tracker'. Prepares an
  engagement repo: the telemetry opt-in in .raid/config.yaml, one sentence in AGENTS.md when
  the git host is not GitHub, and -- only when the team wants tickets -- the issue tracker in
  docs/agents/issue-tracker.md. Checks the git host CLI and the Python environment.
---

# RAID Setup

Prepares an engagement repo to be worked with RAID. Skills ship inside the installed
plugins, so nothing is copied in. Setup records only what an agent cannot see from the repo
itself: whether telemetry is on, a git host that is not the GitHub an agent assumes, and
where tickets live.

Everything else is read off the repo when it is needed -- the platform from its files, the
architecture from its layout, the conventions from the code and the checks that enforce
them. Setup writes none of it down.

Idempotent: detect what already exists and fill only the gaps. Never overwrite an existing
file or line without confirming.

## Workflow

### 1. Scaffold what the installed plugins produce

`raid-core` scaffolds no `docs/` directories. Plans are in-session working artifacts, not
files in the customer's repo, and RAID keeps no learnings store -- durable findings belong
on the engagement's issue tracker.

If `raid-greenfield` is installed, create the two directories its artifacts need:

```
docs/
  inputs/       # customer-provided source material: originals + converted copies (ingest-requirements writes here)
  artifacts/    # RAID-generated HTML deliverables: requirements.html, assessment.html, architecture.html, design.html, testplan.html
```

Check for `raid-greenfield` by whether its skills are available to you (e.g. is
`assess-platform` in your skill list?) -- do not create `docs/inputs/` or `docs/artifacts/`
on a core-only install, where nothing would ever write to them. The inputs/artifacts
split is deliberate: customer material and generated deliverables never mix flat in
`docs/`.

### 2. Telemetry opt-in

`.raid/config.yaml` holds the telemetry opt-in and nothing else.

Ask the user once: RAID can send anonymous usage telemetry to rebtech -- one event per
skill invocation containing only `{timestamp, skill name, plugin version, engagement id,
session id, installation id}`; never prompts, code, paths, names, or hostnames (full
details in the marketplace repo's PRIVACY.md). The `installation_id` is a random,
gitignored, engagement-scoped pseudonym (stored in `.raid/installation_id`) that lets
rebtech count *how many different people* worked on the engagement, not who -- it is
treated as personal data under the GDPR. On client-owned devices, recommend leaving it off
unless the engagement agreement covers anonymised toolkit-usage metrics.

On an explicit yes:

```yaml
# .raid/config.yaml - RAID telemetry opt-in
telemetry:
  enabled: true
  engagement_id: <customer-or-engagement-slug>
```

On a no, or no answer, write the same file with `enabled: false` and no id. Do not skip the
file: the telemetry hook reads a per-repo `.raid/config.yaml` first and only falls back to a
global `~/.raid/config.yaml` when there is none, so without it a globally opted-in
consultant would report from this repo. `setup-raid` owns this per-repo opt-in; the global
one, for a global install, is owned by the install (`INSTALL.md`).

### 3. Environment health check

Report status (do not fail hard -- note what's missing):

- **git** -- is this a repo; what's the default branch; which provider hosts `origin`
  (GitHub / Azure DevOps / GitLab / other)?
- **provider CLI** -- is the CLI for the detected provider installed and authed?
  GitHub -> `gh auth status`; Azure DevOps -> `az` + the `azure-devops` extension
  (`az extension show --name azure-devops`; point at the `az-cli` skill for setup);
  GitLab -> `glab auth status`. Note if missing — the PR flow falls back to printing a
  compare URL for the user.
- **Python** -- is there a `.venv`/`venv`? (Per `raid-core/AGENTS.md`, use the existing
  one; create only when the engagement needs Python.)
- **Orientation** -- does the repo's instruction file tell an agent what the repo is and
  how to build and test it, and point at an architecture doc? When there is existing code
  and it does not, point the user at `map-repo`.

### 4. A git host that is not GitHub

Agents assume GitHub and reach for `gh`. When `origin` is anywhere else, add one sentence to
the repo's instruction file naming the host, where the repo lives there, and the CLI to use:

```markdown
The repo is hosted on Azure DevOps (`dev.azure.com/acme/Data`); use `az repos` for pull
requests, not `gh`.
```

Put it where the file already talks about branches, pull requests or tooling; with no such
place, near the top. Use the instruction file the repo already has (`AGENTS.md`;
`CLAUDE.md` or a symlink to it; `.github/copilot-instructions.md`; `.cursor/rules/`) and
edit the substantive file, not a shim that includes it; create `AGENTS.md` only when the
repo has none. Skip this step when the host is GitHub or the file already says it.

### 5. Issue tracker (optional)

A tracker is where work outlives a session: tickets someone else picks up, `wayfinder`'s
map of open decisions, `to-tickets` and `triage`, and the claim that stops two agents
building the same unit. Without one, `raid-mode` keeps the breakdown in the conversation,
which is fine for work that finishes in a session.

**Ask whether the team wants RAID to use an issue tracker**, and give that reason in a
sentence. On a no, skip this step -- nothing else depends on it, and a skill that later
needs a tracker says so and points back here.

On a yes, **ask which tracker. Never infer it from the git remote.** Azure DevOps Repos
with Jira boards, and GitHub with Linear, are both common in enterprise estates; guessing
wrong sends a customer's specs into the wrong system. One blocking question, the git
host's own tracker offered as the recommended answer when nothing suggests otherwise.

Record the answer in `docs/agents/issue-tracker.md`. The file documents the setup -- which
tracker, where in it, and how RAID's triage roles map onto it; the tickets themselves live
in the tracker. The command recipes are not copied: they ship with this skill in
[`references/trackers/`](./references/trackers/) (`azure-devops.md`, `jira.md`,
`linear.md`, `github.md`) and a skill reads the one for the recorded provider when it needs
it, so a recipe fix reaches every engagement on the next plugin update. The file's format
is in [`references/trackers/README.md`](./references/trackers/README.md).

Fill in the identifiers by asking, or by reading them off an existing ticket the user
names -- do not guess an org, project key or team id. Then point the instruction file at
it, in one sentence placed where the file talks about how work is organised:

```markdown
Issues live in Jira project `DATA`; `docs/agents/issue-tracker.md` has the details.
```

Two cases worth handling explicitly:

- **The tracker already has its own conventions** -- a board whose columns model state,
  a controlled label vocabulary, bug-vs-story as issue types. Common on Jira and on
  customised Azure DevOps processes. RAID's defaults are plain labels (the canonical
  roles `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`;
  `bug` / `enhancement`; `wayfinder:map` / `wayfinder:<type>`). Where a default does
  not fit, record what that role *means* in this tracker in the file's `mapping` block: a
  status, a label, or both (a shared "Ready" column plus an `agent` label is how
  ready-for-agent stays distinct from ready-for-human). Read the live statuses and issue
  types off the tracker first (each recipe says how) rather than guessing names. Map only
  the entries that differ; omit the block when the defaults work.
- **The tracker is unreachable from this machine** (no credentials, no network path).
  Say so and record `local` as the provider -- tickets go to `docs/tickets/` until access
  exists. Do not silently fall back; which tracker an engagement uses is the customer's
  decision, not a default.

### 6. Confirm and hand off

Print what was written -- `.raid/config.yaml`, the git host sentence and the tracker
pointer with the file that holds them, `docs/agents/issue-tracker.md`, the `docs/`
directories -- and the environment gaps. Point the user at the next step: `map-repo` when
the instruction file does not yet orient an agent, then `raid-mode` for the work -- or, when
`raid-greenfield` is installed and the platform decisions do not exist yet,
`assess-platform` to start discovery.

## Rules

- Idempotent and non-destructive; confirm before overwriting.
- Record only what the repo cannot show. The platform, architecture, naming and
  conventions are never written down by setup.
- Anything added to the instruction file is merged into its own structure and voice -- no
  generated sections, no markers.
- Repo-relative paths.
- Don't create a `.venv` unless the engagement actually needs Python yet.
