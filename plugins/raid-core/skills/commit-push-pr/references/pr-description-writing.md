# PR Description Writing

## The core principle

The diff is already visible in the PR. The description exists to explain
what the diff cannot show: what was impossible before and is now possible, what was
broken and is now fixed, what shape changed. Cut any sentence a reader could reconstruct
from the diff itself.

- Bad: "Adds `ingest_orders.py`, modifies the pipeline to call it, and updates two tests."
- Good: "Orders now land in Bronze on the nightly run; the pipeline picks them up
  automatically. Backfill of the 2024 history is included and row-count reconciled."

If the lead sentence describes what was moved, renamed, or added rather than what's now
possible or fixed, rewrite it. This applies to every section, not just the opening --
restating the diff is the failure mode this skill exists to prevent.

---

## Step Pre-A: Resolve the range and base

Two modes:

- **Current-branch mode** (default) -- describe HEAD vs `main`.
- **PR mode** -- describe a specific PR. Triggered when the caller passes a PR id.

For PR mode, fetch metadata first using the provider detected from the remote (see the
provider table in `raid-core/AGENTS.md`):

```bash
# GitHub:
gh pr view <id> --json title,state,headRefName,baseRefName,url
# Azure DevOps:
az repos pr show --id <id> --query "{title:title,status:status,source:sourceRefName,target:targetRefName,url:repository.webUrl}" -o json
# GitLab:
glab mr view <iid>
```

If the PR is not open/active, report and stop -- do not invent a description. Use the
target branch as `<base>` and the source/head branch as `<head>` (Azure DevOps returns
`refs/heads/...` -- strip the prefix).

For current-branch mode, `<base>` is `main` (RAID's protected target) and `<head>` is
`HEAD`:

```bash
git fetch --no-tags origin main
git log --oneline "origin/main..HEAD"
git diff "origin/main...HEAD"
```

If the commit list is empty, report "No commits to describe" and stop.

---

## Step A: Size the description

Match weight to weight. When in doubt, shorter wins. Subtract fix-up commits (review
fixes, lint, rebase resolutions) when sizing -- they're invisible to the reader. Large
PRs need more selectivity, not more content.

| Change profile | Description approach |
|---|---|
| Small + simple (typo, config, dep bump) | 1-2 sentences, no headers. Under ~300 characters. |
| Small + non-trivial (bugfix, behavioral change) | 3-5 sentences. No headers unless two distinct concerns. |
| Medium feature or refactor | Narrative frame, then what changed and why. Call out design decisions. |
| Large or architecturally significant | Narrative frame + 3-5 design-decision callouts + brief test summary. Target ~100 lines, cap ~150. For PRs with many mechanisms, use a Summary table; do not create an H3 per mechanism. |
| Data / model / migration change | Add a verification line: what was validated against real data (row-count parity, grain/key uniqueness, null rates, FK integrity, before/after parity, tests/DQ green). For migrations/backfills also state risk & rollback. |
| Performance improvement | Include before/after measurements as a markdown table. |

For small + simple PRs, the value-led sentence is the entire description.

---

## Step B: Compose the title

`type: description` or `type(scope): description`.

- Type by intent, not file extension. When `fix` and `feat` both seem to fit, default to
  `fix` -- adding code to remedy missing behavior is `fix`. Reserve `feat` for capabilities
  the user could not previously accomplish. Use `refactor`/`docs`/`chore`/`perf`/`test`
  when more precise.
- Scope (optional): narrowest useful label. Omit when no single label adds clarity.
- Description: imperative, lowercase, under 72 chars, no trailing period.
- Match repo conventions visible in recent commits.
- **Never use `!` or `BREAKING CHANGE:` without explicit user confirmation** -- they can
  trigger automated major-version bumps.

---

## Step C: Assemble the body

In order: opening -> body sections that earn their keep -> verification / test plan if
non-obvious -> linked tracker item (`Closes #<id>`) *only if one was explicitly supplied
via `--work-items`* -> RAID badges after a `---` rule. Never add a tracker line otherwise.

The opening goes under `## Summary` if the body uses any `##` headings; bare paragraph
otherwise. No orphaned opening paragraphs above the first heading.

**Verification handling (RAID):** for data changes, state what was checked against real
data and the result; if you lacked read access to validate, say so and label the result
"not validated against data." Never present an unverified-against-data claim as verified.

**Visual aids:** reach for a diagram or table when it conveys the change faster than prose
-- relationships, flows, state transitions, sequences, trade-offs, before/after data, or
any structure prose would have to enumerate. Mermaid and markdown tables cover most
shapes. Place inline at the point of relevance. Skip for simple, prose-clear, or
rename/dep-bump changes. Prose is authoritative when it conflicts with a visual.

**Tracker links (only if an id was explicitly supplied):** use the host's reference
syntax -- GitHub/GitLab `Closes #<id>` / `#<id>`, Azure Boards `AB#<id>` (explicit `AB#123`
form so the link is unambiguous). Never invent one. **ASCII only** (Windows CI
agents choke on non-ASCII); keep emojis out of any text that could reach console/log
output.

**Slop gate (after Step D, before applying):** run the final body -- badges included --
through the `unslop` skill (raid-core) as a write-through pass, including its bundled
linter (`scripts/ai_slop_lint.py`, piped the body file) as the mechanical gate. Fix every
hit (banned vocabulary, filler, em dashes, rule-of-three cadence, chatbot phrases), then
hand-check its judgment tells. A clean lint is necessary but not sufficient: the
description must read like a colleague wrote it, not a chatbot. Skip badge and `---`
lines when reading lint output — badge URLs can contain flagged substrings.

---

## Step D: Badges

End the body with the RAID attribution badges after a `---` rule (skip them if refreshing a body that already carries them): the RAID badge, plus a harness/model badge for the agent that built the PR.

```markdown
---

[![Built with RAID](https://img.shields.io/badge/Built_with-RAID-b59b6a)](https://dev.azure.com/rebtech/RAID/_git/raid-plugin)
![Harness](https://img.shields.io/badge/<MODEL_SLUG>-<COLOR>?logo=<LOGO>&logoColor=white)
```

Pick the harness row for whatever agent is generating the PR:

| Harness | `LOGO` | `COLOR` |
|---|---|---|
| Claude Code | `claude` | `D97757` |
| GitHub Copilot | `githubcopilot` | `000000` |
| Gemini CLI | `googlegemini` | `4285F4` |
| Codex | (omit `?logo=`) | `000000` |

`MODEL_SLUG`: the active model with spaces as underscores; URL-encode literal parens as `%28` / `%29` (e.g. `Opus_4.8_%281M%29`, `GPT-5`, `Gemini_3_Pro`). These badges are plain markdown images — they render the same on GitHub and in Azure DevOps PRs.

Skip the badges if regenerating a body that already contains them.
