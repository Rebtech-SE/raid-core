# Install RAID core

This file is the single source of truth for installing, updating and removing `raid-core`
from this public mirror on any harness. It is a document rather than a skill on purpose:
the install has to work *before* the plugin exists.

**If you are an agent reading this:** ask the questions under *The flow*, then run the
commands for the user's harness yourself. Do not hand the user a menu of commands.

## What gets installed

One plugin, `raid-core`: skills, reviewer/researcher agents, and the opt-in telemetry
hooks. Marketplace name `raid-core`, plugin name `raid-core`, so the install id on every
harness is `raid-core@raid-core`.

## The flow - ask in order (blocking)

1. **Harness** - Claude Code, Codex, GitHub Copilot CLI, Cursor, or something else.
2. **Scope** - global (every project on this machine) or this project only. Claude Code is
   the only harness with a real per-project scope; Codex and Copilot installs are
   user-global.
3. **Telemetry** - on or off. Explain in one sentence: an opt-in hook that reports which
   RAID skill ran plus a pseudonymous machine id to Rebtech, nothing else, see
   `PRIVACY.md`. Default to **off**. Never enable it on a device you do not own without
   the owner's agreement.

## Install - per harness

`rebtech-se/raid-core` is this repository. Public: no git credentials needed.

### Claude Code (full: skills + agents + hooks)

Scope map: global -> `user`; this project, just me -> `local`; this project, whole team ->
`project`. Run from the project directory for `local` / `project`.

```bash
claude plugin marketplace add rebtech-se/raid-core --scope <user|project|local>
claude plugin install raid-core@raid-core --scope <user|project|local>
claude plugin list
```

Restart the session to load skills, agents and hooks. Claude Code auto-updates
git-sourced marketplaces at startup; a local-directory source never auto-updates.

### Codex (app first; CLI inherits)

```bash
codex plugin marketplace add rebtech-se/raid-core
codex plugin add raid-core@raid-core
codex plugin list
```

CLI < 0.139.0 lacks `plugin add`: launch `codex`, run `/plugins`, install there. Update
with `codex plugin marketplace upgrade`. To declare it for every collaborator of a repo,
commit `.agents/plugins/marketplace.json` with a `git-subdir` entry pointing at
`https://github.com/rebtech-se/raid-core`, path `./plugins/raid-core`, ref `main`.

Caveat: Codex does not register plugin agents, so the reviewer panel runs inline rather
than as parallel subagents. Codex asks you to trust plugin hooks before it runs them.

### GitHub Copilot (CLI + VS Code Chat)

Copilot CLI >= 1.0.63 installs natively from `.claude-plugin/marketplace.json`.

```bash
copilot plugin marketplace add https://github.com/rebtech-se/raid-core
copilot plugin install raid-core@raid-core
copilot plugin list
```

Installs are user-global (`~/.copilot`). To declare it for a repo, commit
`.github/copilot/settings.json` with `extraKnownMarketplaces` pointing at this repo and
`"enabledPlugins": { "raid-core@raid-core": true }`. Update with
`copilot plugin update raid-core@raid-core`.

If flat RAID skill folders from an older install sit in `~/.copilot/skills/`, they shadow
the plugin silently. Move them aside.

### Cursor

Cursor 2.6+ team marketplaces import from GitHub: add `rebtech-se/raid-core` as a team
marketplace (Teams/Enterprise plan plus the Cursor GitHub App) and install `raid-core`.
Without a team plan, copy the skill folders:

```bash
SKILLS_ROOT="$HOME/.cursor/skills"   # or <project>/.cursor/skills
mkdir -p "$SKILLS_ROOT"
git clone --depth 1 https://github.com/rebtech-se/raid-core /tmp/raid-core
cp -R /tmp/raid-core/plugins/raid-core/skills/* "$SKILLS_ROOT/"
```

Cursor also reads `~/.claude/skills/`, so an existing Claude Code install is picked up
automatically. Plugin subagents are not registered; review runs inline.

### Other agents

Clone the repo and wire `plugins/raid-core/skills/` into however the harness loads
`SKILL.md` folders. Skip agent and hook wiring that does not port.

## Telemetry (only when the user said yes)

Project scope -> `.raid/config.yaml`; global scope -> `~/.raid/config.yaml`. Create or
merge, never clobber other keys:

```yaml
telemetry:
  enabled: true
  engagement_id: <short-slug>   # optional; omitted -> "global"
```

A per-repo `.raid/config.yaml` always governs alone when it exists, so a global opt-in
never leaks into a repo that did not opt in. With neither file, nothing is ever sent.
Kill switch: `export RAID_TELEMETRY_DISABLED=1`.

### Stamp the release (optional, telemetry only)

A Copilot install carries no `.git` and no version segment in its path, so
`plugin_version` reports a `gen-<mtime>` generation marker instead of a commit. To report
the SHA, write it into the install root after installing:

```bash
SHA=$(git ls-remote <SOURCE> HEAD | cut -f1 | cut -c1-12)
for root in ~/.copilot/installed-plugins/*/raid-core ~/.claude/plugins/cache/*/raid-core \
            ~/.claude/plugins/cache/*/raid-core/* ~/.codex/plugins/*/raid-core; do
  [ -f "$root/hooks/telemetry.sh" ] || continue
  printf '%s\n' "$SHA" > "$root/.raid-release"
done
```

The stamp is self-expiring: a host-driven update rewrites the plugin manifest, the hook
sees a stamp older than it, and falls back to the generation marker rather than naming a
release that is no longer installed. Re-run after a manual update. Skip this when
telemetry is off.


## Verify

| Harness | Check |
|---|---|
| Claude Code | `claude plugin list` shows `raid-core` enabled; `/plugin` lists it; `/raid-mode` responds |
| Codex | `codex plugin list` shows `installed, enabled` |
| Copilot | `copilot plugin list` shows `raid-core` |
| Cursor | skill folders exist under the skills root; new session reloads |

## Manage an existing install

| Action | Claude Code | Codex | Copilot |
|---|---|---|---|
| Update | automatic at startup, or `claude plugin marketplace update raid-core` | `codex plugin marketplace upgrade` | `copilot plugin update raid-core@raid-core` |
| Disable | `claude plugin disable raid-core@raid-core` | `~/.codex/config.toml` | `copilot plugin disable raid-core@raid-core` |
| Uninstall | `claude plugin uninstall raid-core@raid-core` then `claude plugin marketplace remove raid-core` | `codex plugin remove raid-core@raid-core` | `copilot plugin uninstall raid-core@raid-core` |

Telemetry off: set `enabled: false` or delete the `telemetry:` block.
