# mannered-prose

Adapted from [ossian-stack](https://github.com/ossianhempel/ossian-stack)
(`skills/mannered-prose`). The text it enforces is Anthropic's published definition of
mannered prose (*Prompting Claude Fable 5.1*, "Writing density"), reproduced in the
skill; the guidance around it is local.

RAID adaptation: the description is rewritten to the routing-cue form and names RAID's
surfaces (client-facing artifacts, stage replies, PR bodies). The body is unchanged.

There is no git upstream to pin — the source is a docs page, not a repo. Re-read
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>
if the "Writing density" section changes.

It complements `unslop`: `mannered-prose` constrains the sentences while they are being
written, `unslop` is the full pass over a finished draft.
