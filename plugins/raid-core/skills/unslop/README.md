# unslop

Adapted from [cursor/plugins](https://github.com/cursor/plugins)
(`pstack/skills/unslop`). On 2026-08-28 the former local `ai-slop-reviewer`
skill was merged into it, so this is now one skill for both the write-through
style pass and the audit/cleanup job. On 2026-10-23 the former local
`mannered-prose` skill was folded in as well, along with a deslopify mode and
before/after examples, following the same merge in
[ossian-stack](https://github.com/ossianhempel/ossian-stack) (`skills/unslop`).

The "Mannered prose" section quotes Anthropic's published definition
(*Prompting Claude Fable 5.1*, "Writing density"). There is no git upstream for
it; re-read
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>
if that section changes.

Upstream's pattern list is kept verbatim and numbered (rules 1–31); local
additions continue at 32. The bundled linter (`scripts/ai_slop_lint.py`) parses
its word lists from `references/ai-slop-checklist.md`.

To refresh from upstream, **diff by hand before overwriting**: rules beyond 31
and everything under `scripts/` and `references/` are local.

```bash
npx skills add cursor/plugins -y --skill unslop
cp -R .agents/skills/unslop/. skills/unslop/
```
