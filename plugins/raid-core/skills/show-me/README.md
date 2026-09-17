# show-me

Port of [humanlayer/skills](https://github.com/humanlayer/skills)
(`plugins/show-me/skills/show-me`), reached via ossian-stack, which carries the same
copy verbatim. The name is kept as upstream so a refresh is a straight copy.

RAID adaptations (both must survive a refresh):

- The description is rewritten to RAID's routing-cue form (`Use when ...`), so the skill
  is discoverable by the model, not only by someone who knows it exists.
- The final "open it for the user" step no longer hard-codes Claude's `Bash(open ...)`
  notation. RAID installs natively on Claude Code, Codex and Copilot CLI, so it names the
  host's file-open command and says to report the path when there is none.
- The boundary paragraph is local: presents, does not investigate.

To refresh, diff against upstream by hand — the two adaptations above are the only local
differences.

```bash
npx skills add humanlayer/skills -y --skill show-me
cp -R .agents/skills/show-me/* plugins/raid-core/skills/show-me/
rm -rf .agents/skills/show-me
```
