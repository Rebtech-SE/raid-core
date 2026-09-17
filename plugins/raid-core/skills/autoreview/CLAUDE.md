# Autoreview Skill

- Canonical source: `openclaw/agent-skills`, under `skills/autoreview`.
- Before editing any copy, fast-forward a checkout of `openclaw/agent-skills` from `origin/main`.
- Make and validate shared changes in canonical `skills/autoreview` first, then sync the complete directory into downstream repos.
- Never create repo-local behavior variants; downstream differences belong in repo-level validation, not the skill.

## RAID divergence (deliberate)

This copy is `adapted`, not `vendored`. It carries two repo-local variants, against the rule
above. Every RAID change in `scripts/autoreview` carries a `RAID:` comment.

1. **The `copilot` engine**, which upstream removed because Copilot's file tools could not be
   confined to the reviewed bundle. RAID needs it because plugin users on GitHub Copilot CLI
   may have no other review engine installed. It is confined like upstream's Codex: the
   bundle alone, in an empty per-run workspace, with no repository file mirrored, so
   upstream's scanner-free policy holds.
2. **Claude defaults to `claude-fable-5-1`** (`CLAUDE_FABLE_MODELS` keeps `claude-fable-5`
   mapping to the CLI's `fable` alias too). Drop this once upstream moves.

On refresh, re-apply by hand: `ENGINES`, `DEFAULT_MODEL_BY_ENGINE`,
`DEFAULT_THINKING_BY_ENGINE`, `THINKING_LEVELS_BY_ENGINE`, `CLAUDE_FABLE_MODELS` and its two
uses, `copilot_allowed_exact`, `run_copilot` + `COPILOT_NO_TOOLS_MESSAGE`, the `run_engine`
and `resolve_engine_binary` copilot branches, `--copilot-bin`, and the `--model` help text.
In `SKILL.md`: the description, the Claude/Copilot defaults line, the Copilot table row and
paragraph.

Upstream's own suite must pass after any refresh:

```bash
uvx pytest --import-mode=importlib tests/ scripts/autoreview_test.py -q
```

Provenance and the pinned upstream rev live in `plugins/sources.json`; see
`docs/skills-sources.md`.
