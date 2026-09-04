# Autoreview Skill

- Canonical source: `openclaw/agent-skills`, under `skills/autoreview`.
- Before editing any copy, fast-forward a checkout of `openclaw/agent-skills` from `origin/main`.
- Make and validate shared changes in canonical `skills/autoreview` first, then sync the complete directory into downstream repos.
- Never create repo-local behavior variants; downstream differences belong in repo-level validation, not the skill.

## RAID divergence (deliberate)

This copy is `adapted`, not `vendored` — it carries one repo-local behavior variant, against
the rule above: the **`copilot` engine**, which upstream removed because Copilot's file tools
could not be confined to the reviewed bundle. RAID needs it because plugin users on GitHub
Copilot CLI may have no other review engine installed.

The variant is a sandbox plus a scan, not a change to review semantics. Every RAID addition
carries a `RAID:` comment. On refresh, re-apply by hand:

- `ENGINES`, `DEFAULT_MODEL_BY_ENGINE`, `DEFAULT_THINKING_BY_ENGINE`, `THINKING_LEVELS_BY_ENGINE`
- `copilot_allowed_exact` in the reviewer env allowlist
- `restrict_permissions`, `stage_changed_files`, `scan_sandbox_tree`, `run_copilot`
- the `run_engine` dispatch branch and `--copilot-bin`
- the `sandbox_paths` / `sandbox_rev` wiring in `main_impl`

`scan_sandbox_tree` is the security-relevant one: the sandbox hands the engine whole-file
content that never appears in the prompt, so it would otherwise be an egress path that
`scan_outgoing_review_pack` does not cover. Do not drop it.

Upstream's own suite must pass after any refresh:

```bash
uvx pytest tests/test_autoreview_hardening.py scripts/autoreview_test.py -q
```

Provenance and the pinned upstream rev live in `plugins/sources.json`; see
`docs/skills-sources.md`.
