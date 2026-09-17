# bro

Vendored verbatim from [dmmulroy/skills](https://github.com/dmmulroy/skills) (`bro`,
MIT), by way of [ossian-stack](https://github.com/ossianhempel/ossian-stack), whose copy
is also verbatim.

Restates the agent's previous message in plain human language, without jargon. It is
user-invoked only (`disable-model-invocation: true`) and never fires on its own.

It earns its place in `raid-core` because a RAID answer is often read by someone who is
not an engineer -- a stakeholder in a workshop, a customer's analyst reading a lineage
trace or a grain decision. `teach` walks a person through a subject from scratch; `bro`
just says the thing that was already said, again, plainly.

**Do not hand-edit `SKILL.md`.** A refresh is a straight copy, which is what keeps the
provenance in `plugins/sources.json` honest.

To update:

```bash
npx skills add dmmulroy/skills -y --skill bro
cp -R .agents/skills/bro/SKILL.md plugins/raid-core/skills/bro/SKILL.md
rm -rf .agents/skills/bro
scripts/check-upstream.sh --record bro
```
