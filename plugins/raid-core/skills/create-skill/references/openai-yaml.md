# `agents/openai.yaml`

Codex and the ChatGPT desktop app render a skill from this file, not from the `SKILL.md`
description. Claude Code and Cursor ignore it entirely. **Every skill under `plugins/`
ships one** -- `npm run validate` fails without it, because a skill missing the file shows
up in Codex as `Plugin Name: kebab-name` with the raw description and no summary, and the
~150-character routing truncation has nothing to fall back on.

Official docs: [Codex skills](https://developers.openai.com/codex/skills) ·
[ChatGPT skill building](https://learn.chatgpt.com/docs/build-skills). Note that the Agent
Plugins 1.0 spec does not cover `agents/` -- it is OpenAI-client-specific, not part of the
portable format, which is why it sits beside the SKILL.md rather than in it.

## Format

```yaml
interface:
  display_name: "Resolve PR Feedback"          # shown instead of the kebab name
  short_description: "Address reviewer feedback commit by commit"
  icon_small: "./assets/small-logo.svg"        # optional
  icon_large: "./assets/large-logo.png"        # optional
  brand_color: "#3B82F6"                       # optional
  default_prompt: "Optional prompt wrapper"    # optional

policy:
  allow_implicit_invocation: false             # default true

dependencies:
  tools:
    - type: "mcp"
      value: "someServer"
      description: "What it is for"
      transport: "streamable_http"
      url: "https://example.com/mcp"
```

Most RAID skills need only the two required `interface` fields. Reach for the rest when the
skill actually has an icon, a wrapper prompt, or a tool dependency worth declaring.

## Rules

1. **`display_name` is Title Case of the kebab name, acronyms restored.** `fabric-cli-core`
   -> "Fabric CLI Core", `az-cli` -> "Az CLI", `scd-pattern` -> "SCD Pattern". OpenAI's own
   generator uses Title Case with a small-word and acronym list; match it rather than
   inventing a house style.
2. **`short_description` is 25-64 characters, and both ends are enforced.** Under 25 it says
   nothing; over 64 Codex cuts it mid-word. Distill the SKILL.md description by hand -- do
   not paste its first sentence, and do not fall back on filler like "Helps with X tasks".
   Check the length before committing:

   ```bash
   sed -n 's/^  short_description: "\(.*\)"$/\1/p' \
     plugins/<plugin>/skills/<name>/agents/openai.yaml | tr -d '\n' | wc -c
   ```

3. **Policy pairing is enforced.** A skill that must not auto-route sets
   `disable-model-invocation: true` in its SKILL.md frontmatter *and*
   `policy.allow_implicit_invocation: false` here. Claude Code reads the first, Codex reads
   only the second, so a one-sided declaration means the two hosts disagree about whether
   the skill can fire on its own. `npm run validate` fails on the mismatch.
4. **Edit fields, never regenerate the file.** When one already exists, change the
   `interface` field you need and leave `policy:` and `dependencies:` alone. Regenerating
   silently drops an invocation policy, and that failure is invisible until Codex starts
   auto-firing a skill that was explicit-only.
5. **Keep it in sync with the name and description.** Renaming a skill or rewriting its
   description without touching this file leaves Codex showing the old one.
6. **Vendored skills.** Upstream usually ships no such file, so a local one is a local
   addition -- say so in the skill's `plugins/sources.json` notes, or the next refresh
   treats the skill as unmodified upstream and overwrites it. Where upstream *does* ship one
   (ossian-stack does), it comes across with the rest of the copy. Vendored skills get a
   warning rather than a failure on the 25-64 rule, the same carve-out the description rule
   gets: their metadata is upstream's and is not hand-edited.
