# RAID core

RAID is [Rebtech](https://rebtech.se)'s framework for building data analytics platforms
with AI-assisted development. This repository is the **public mirror of `raid-core`**:
the build loop (pick the lane, build, simplify, review, ship, close the loop), a library of tech-agnostic
data-platform skills (medallion architecture, ingestion, SCD, data quality, dbt,
orchestration), and a panel of data-platform reviewer subagents.

It installs natively into **Claude Code, Codex, GitHub Copilot CLI and Cursor** from this
repo. No registry, no build step, no account with Rebtech.

> **This is a one-way mirror.** The source of truth lives in Rebtech's Azure DevOps and is
> synced here on every merge. Issues and discussion are welcome; pull requests are
> mirrored back by hand, so open an issue first for anything beyond a typo.

## What is in the box

| Part | Contents |
|---|---|
| `plugins/raid-core/skills/` | Workflow skills (`raid-mode`, `build-dbt-models`, `build-ingestion-pipeline`, `simplify-code`, `review-changes`, `commit-push-pr`, `close-the-loop`, ...) and knowledge skills (`medallion-architecture`, `scd-pattern`, `kimball-dimensional-modeling`, `data-quality-checks`, ...) |
| `plugins/raid-core/agents/` | Reviewer personas (correctness, data integrity, medallion boundaries, SCD, reliability, cost, security, ...) and researcher subagents |
| `plugins/raid-core/hooks/` | The **opt-in** usage telemetry hook. Off by default. See [PRIVACY.md](PRIVACY.md). |
| `plugins/raid-core/AGENTS.md` | The engagement rules the skills assume (git workflow, conventional commits, paths) |

The platform tiers (`raid-fabric`, `raid-gcp`, `raid-aws`, `raid-databricks`) and the
greenfield discovery-and-design stages are **not** in this mirror. `raid-core` depends on
nothing and is fully usable on its own. The tiers are installed *on top of* this repo's
`raid-core@raid-core` - they declare it as a dependency against this marketplace - so this
is the right place to install core from even when a tier follows.

## Install

Pick your harness. `rebtech-se/raid-core` below is this repository.

**Claude Code**

```bash
claude plugin marketplace add rebtech-se/raid-core --scope local   # user | project | local
claude plugin install raid-core@raid-core --scope local
```

Claude Code auto-updates git-sourced marketplaces in the background at startup. The
manifests are version-less on purpose: the commit is the release, so every sync here
reaches every install.

**Codex**

```bash
codex plugin marketplace add rebtech-se/raid-core
codex plugin add raid-core@raid-core
codex plugin marketplace upgrade      # later, to update
```

**GitHub Copilot CLI** (>= 1.0.63)

```bash
copilot plugin marketplace add https://github.com/rebtech-se/raid-core
copilot plugin install raid-core@raid-core
copilot plugin update raid-core@raid-core   # later, to update
```

**Cursor** (2.6+, Teams/Enterprise): add `rebtech-se/raid-core` as a team marketplace in
Cursor settings (it reads `.cursor-plugin/marketplace.json`), then install `raid-core`.
Individuals can also copy `plugins/raid-core/skills/*` into `~/.cursor/skills/`.

**Any coding agent, no terminal:** paste this prompt.

```text
Install RAID core from https://github.com/rebtech-se/raid-core.
Read INSTALL.md at that repo's root and follow it exactly. It will ask me which
harness, global vs project scope, and telemetry on/off, then run the commands.
```

Then start a new session and run `/raid-mode` (or `/setup-raid` first in an engagement
repo). Details, verification and uninstall are in [INSTALL.md](INSTALL.md).

## Telemetry

`raid-core` ships two opt-in telemetry hooks -- one per RAID skill invocation, one per
session. By default they send nothing. They report a skill name (or a session-start
sentinel) and a pseudonymous installation id only after you write
`telemetry: enabled: true` into `.raid/config.yaml` or `~/.raid/config.yaml`. Kill switch:
`RAID_TELEMETRY_DISABLED=1`. Full disclosure in [PRIVACY.md](PRIVACY.md).

## License

See [LICENSE](LICENSE). Vendored skills keep their upstream licenses; provenance is
listed in the skills' own `SKILL.md` frontmatter.
