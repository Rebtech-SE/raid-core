# unslop

Adapted from [cursor/plugins](https://github.com/cursor/plugins)
(`pstack/skills/unslop`). On 2026-08-28 the former local `ai-slop-reviewer`
skill was merged into it, so this is now one skill for both the write-through
style pass and the audit/cleanup job.

Upstream's pattern list is kept verbatim and numbered (rules 1–31); local
additions continue at 32. The bundled linter (`scripts/ai_slop_lint.py`) parses
its word lists from `references/ai-slop-checklist.md`.

To refresh from upstream — **diff by hand before overwriting**, rules beyond 31
and everything under `scripts/` and `references/` are local:

```bash
npx skills add cursor/plugins -y --skill unslop
cp -R .agents/skills/unslop/. skills/unslop/
```
