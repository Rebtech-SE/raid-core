---
name: create-skill
description: >-
  Use when writing a new skill, editing or improving an existing one, or generating a
  project-local skill into a customer repo -- 'write a skill', 'turn this into a skill',
  'my skill never triggers', 'fix this description'. Carries RAID's authoring rules: the
  description is the entire routing surface and Codex/Copilot truncate it near ~150
  characters, so it leads with when-to-use; flat one-level skill layout; verb-first names;
  cross-plugin references by name, never by path; shell and single-file Python only.
  Measuring a skill is `raid-eval`'s job, not this one.
---

# Write a Skill

A skill is a prompt with progressive disclosure. The model sees a name and a description
all the time; it reads the body only when it decides the skill applies; it reads bundled
files only when the body sends it there. Almost everything that makes a skill good or
useless follows from that structure.

Two things make authoring here different from authoring a skill anywhere else:

- **What you write ships to every customer.** A skill in `plugins/` installs on every
  engagement, so a hostname, a connection string or a customer-shaped assumption carried
  out of one estate lands in someone else's. Never put a customer's material in a
  contributed skill; `bash scripts/tests/test-secret-scan.sh` enforces the mechanical half.
- **Three hosts read it.** Claude Code, Codex and GitHub Copilot CLI all install from
  `plugins/` natively. The strictest host's limits are the repo's limits -- see below.

## 1. The description is the entire routing surface

**This is the rule that matters most, and it is the one most often got wrong.**

Codex and Copilot CLI render the skill list inside a hard budget (2% of the context
window). When the shipped skills overflow it, they do not drop skills -- they truncate
*every* description to a uniform length, **keeping the prefix**. A `raid-core` + one-tier
install lands near a **~150-character cutoff**. Anything after that character is invisible
to routing on two of the three hosts.

So:

- **Lead with when to use it.** Start with `Use when ...`, `Use to ...`, `Triggers: ...`
  or `Invoke when ...`. `scripts/validate.js` fails the build if the description starts
  any other way -- that regex exists precisely because "This skill helps you ..." spends
  the surviving 150 characters saying nothing.
- **Put the trigger phrases in the first sentence**, in the words a user would actually
  type. Mechanism, artifacts and caveats go after; they are for the model that already
  decided to read the body.
- **Cap the whole description at 600 characters.** Enforced. (Copilot's own hard limit is
  1024; ours is stricter on purpose.)
- Claude Code applies no such budget, but `plugins/` is the single source of truth for all
  three distributions, so the rule holds everywhere.

### How triggering actually works

The model sees name + description in its available-skills list and decides whether to
consult the skill. Two consequences worth designing around:

- **It only reaches for a skill on work it cannot trivially do itself.** "Read this file"
  will not trigger a skill however well the description matches. Substantial, multi-step or
  specialised requests will.
- **Models under-trigger more often than they over-trigger.** A description may be a little
  pushy about the cases it owns -- naming the situations, not just the artifact. Prefer
  "Use when a platform has no scripted way to prove its data is right, or the user says
  'how do I check this is correct'" over "Builds verification tooling."

### Write it against intent, not keywords

The description competes with every other skill for attention, so it has to be
*distinctive*, and it has to describe the user's intent rather than your implementation.
When a description is not triggering the way you want, test it the way it will be used:

1. Write ~20 realistic queries, roughly half **should-trigger** and half
   **should-not-trigger**. Realistic means concrete: file paths, table and column names, a
   platform, a bit of backstory, lowercase and typos where a real person would have them.
   `"Format this data"` tests nothing. `"the gold mart dim_customer has 40k rows but the
   source CRM export has 41,203 -- where are they going"` tests something.
2. Make the negatives **near-misses**. A query that shares vocabulary with the skill but
   genuinely needs something else is the only kind of negative worth writing. "Write a
   fibonacci function" as a negative for a data-quality skill proves nothing.
3. Judge each query against the description alone, and rewrite the description toward the
   *category* of intent that failed -- not toward the individual query. An
   ever-growing list of specific phrasings overfits, and it burns the character budget
   that every other skill is also competing for.

### When a skill should not compete for routing at all

Set `disable-model-invocation: true` on any skill that is only ever reached by name or by
the user: leaf reference material another skill cites (`principle-*`), an entry point the
user invokes deliberately (`raid-mode`, which also sets `mode: true`), a heavy workflow
another skill dispatches. It stays fully usable by name and stops spending routing budget.
Roughly: if nothing in the description should ever cause a spontaneous trigger, set it.

## 2. Where it lives and what it is called

**Discovery is flat.** A skill is `skills/<name>/SKILL.md`, exactly one level deep. There
is no recursion -- a `SKILL.md` nested any deeper is simply never loaded. Group related
skills by *name prefix* (`fabric-*`, `principle-*`), never by subfolder. `references/`,
`scripts/` and `assets/` inside a single skill are fine and are the only nesting there is.

**Name it for what it does, not what it belongs to.** Action skills take a verb-first name
(`build-ingestion-pipeline`, `deploy-fabric-notebook`, `review-changes`). Knowledge skills
that are a body of reference rather than an action keep their noun
(`medallion-architecture`, `scd-pattern`, `az-cli`). A plugin install already namespaces a
skill, so a `raid-` prefix buys nothing but length -- only `raid-mode` and `setup-raid`
carry it, because RAID is the object of the verb. Subagents under `agents/` do keep the
`raid-` prefix: they are dispatched by name across plugins and are not namespaced.

**Pick the plugin deliberately:**

| The skill is | It goes in |
| --- | --- |
| tech-agnostic, or part of the build loop | `raid-core` |
| specific to one platform | that tier (`raid-fabric`, `raid-gcp`, `raid-aws`, `raid-databricks`) |
| a discovery/design stage producing a client-facing HTML artifact | `raid-greenfield` |

`raid-core` must stay standalone: nothing in it may hard-depend on a skill or agent from
`raid-greenfield` or a tier. Optional use is fine when it is guarded ("when
`review-document` is available"). Dependencies point one way.

The name is also a promise to `plugins/sources.json`. If the skill is vendored or adapted
from upstream, add an entry there in the same change -- origin, repo, path, license,
`upstreamRev`, and notes saying what was taken, what was deliberately dropped and why.
Vendored skills keep their upstream names so a refresh stays a clean copy.

## 3. Structure: what goes in the body, what goes in a file

Three loading levels, and the cost of each is different:

1. **name + description** -- always in context, for every skill, on every request. The most
   expensive real estate there is. Section 1 is about this.
2. **SKILL.md body** -- loaded whenever the skill triggers. Aim under ~500 lines.
3. **`references/`, `scripts/`, `assets/`** -- loaded only when the body sends the model
   there. Effectively free until used.

Split into `references/` when a chunk is **large and conditionally needed** -- one variant
out of several, a schema, a worked example, a lookup table. The classic shape is a body
that carries the workflow and the selection logic, with one reference file per variant:

```
close-the-loop/
├── SKILL.md                        # workflow + which platform, which guarantees
└── references/
    └── data-map-example.md         # the shape, read only when writing one
```

Do **not** split just to get under a line count. A body that has been hollowed out into
pointers costs a read round-trip for every step and reads worse than the long version. If a
reference file is over ~300 lines, give it a table of contents.

**Link every bundled file from the body.** `npm run validate` warns when a file under
`references/`, `scripts/` or `assets/` is not referenced from `SKILL.md`, because VS Code
Copilot only loads what the body links. An unlinked file is dead weight on two hosts.

## 4. The runtime constraint

**Shipped skills run on shell, Python, and the provider's own CLI or REST API -- nothing
else.** A customer's build agent has `bash`, a `python3`, and whatever CLI its git host and
data platform ship (`gh` / `az` / `glab`, `fab` / `databricks` / `bq`). It does not have
Bun, Node, or permission to install a package manager.

- **Prefer no script at all.** Most skills are prose plus commands, and that is the right
  answer far more often than it feels like it is.
- When a script is genuinely needed: POSIX shell, or a **single-file Python script with no
  third-party imports**. No `pip install`, no SDK, no framework.
- Reach for the host's REST API through `curl` / `az rest` before adding a dependency.
- **This bites hardest when porting.** Upstream helpers are frequently TypeScript or Bun.
  The port drops them and re-expresses the logic in the host CLI -- it does not carry the
  runtime across. Say so in the `sources.json` notes.

The repo's own dev tooling is exempt: `scripts/`, tests and CI may use whatever the
maintainers like. This rule is about what ships inside `plugins/`.

## 5. Referencing other skills

**Across plugins, cite a skill by name in backticks -- never by relative path.**
`raid-core` and a tier install into separate directories, so `../medallion-architecture/SKILL.md`
from a raid-fabric skill resolves to nothing on a real install. Write
`` `medallion-architecture` `` (add the tier in parentheses when it is not obvious).
Both plugins are active together, so the model resolves the name.

Relative links are valid only *within* one skill, pointing at its own `references/`,
`scripts/` or `assets/`. `npm run validate` fails on a link that escapes its plugin.

## 6. Write for an agent reading it cold

The reader is not you and has no context. It is an agent, mid-task, that has never seen
this repo or this platform, reading the skill once and acting on it.

- **Imperative, and explain the why.** "Run the doctor first" beats "you may wish to
  consider running the doctor". But rigid ALL-CAPS `MUST`/`NEVER` scaffolding is a yellow
  flag: today's models have good theory of mind and follow a reason further than a command.
  Tell them what breaks if they skip it. Reserve the emphatic register for the two or three
  things that genuinely are load-bearing.
- **No placeholders.** `<your-warehouse-here>` is where a skill dies. Every command in a
  skill that describes *this* repo or *this* engagement must be the real command, with the
  real dataset, table and branch names, verified by running it.
- **Frontmatter or it never registers.** A generated skill without `name` and `description`
  is invisible -- not degraded, invisible. Check it first, every time.
- **Show the invocation of anything you bundle**, and make scripts executable.
- **Define the output format explicitly** when the output has a shape:

  ```markdown
  ## Report structure
  Use this template:
  # <title>
  ## What was checked
  ## Findings
  ## Evidence
  ```

- **Examples earn their space** when they show a judgement call, not when they restate the
  rule. One good input/output pair beats three paragraphs of description.
- **A skill must not surprise the user in its intent.** No malware, no exfiltration, no
  "helpful" destructive defaults. If a skill deletes, drops or pushes, that is in the
  description.

This section applies double to a **project-local skill generated into a customer's repo**
-- see `close-the-loop`, which writes a `verify-<platform>` skill into the engagement.
Nobody reviews that file the way a PR to this repo gets reviewed, so the discipline has to
be in the generator: resolve the real skills directory rather than assuming one, write real
commands taken from the repo you just interviewed, and **run the generated skill's own
instructions end to end once before handing it over**. A generated skill that was never
executed is a draft, and a draft that claims to verify things is worse than nothing.

## 7. Creating one, start to finish

1. **Capture the intent.** Often the conversation already contains the workflow -- "turn
   this into a skill" means the commands, the corrections and the output format are in the
   history. Mine that first, then confirm the gaps. Ask: what should this let the agent do,
   when should it trigger, what does it produce.
2. **Interview and research before drafting.** Edge cases, input and output formats,
   dependencies, what "done" looks like. Come with the research already done -- dispatch
   subagents in parallel where that helps -- rather than making the user supply it.
3. **Check for prior art.** `ossian-stack` (<https://github.com/ossianhempel/ossian-stack>)
   is the reference implementation for the non-data workflow skills; the existing skills in
   `plugins/raid-core/skills/` are the reference for tone and shape. Adapting beats
   inventing, and adapting means crediting it in `plugins/sources.json`.
4. **Draft the frontmatter and the body**, applying sections 1-6.
5. **Re-read it cold.** Draft, then look at it as if you had never seen it. This is the
   single highest-yield step and it costs one pass.
6. **Run `npm run validate`** and fix everything. It checks manifests, frontmatter, the
   routing cue and the 600-character cap, duplicate skill names, links that escape their
   plugin, `sources.json` provenance and the `CLAUDE.md` symlinks. It runs on pre-commit
   and in CI, so a failure here is a failure there.
7. **Update the inventory.** New or renamed skills belong in
   the repo's `docs/skills/README.md` inventory, and a change to
   user-facing behavior belongs on the project wiki alongside the PR.

## 8. Improving one

This is where most of the value is; a first draft is rarely the skill.

- **Generalise from the failure, do not patch the instance.** A skill is used across
  thousands of prompts and you are looking at three. Fiddly, overfitted rules and
  ever-longer prohibition lists make it worse everywhere else. When something is stubbornly
  wrong, try a different framing or metaphor rather than another clause.
- **Keep it lean.** Cut anything not pulling its weight. If the skill sends the model down
  an unproductive path, delete that part and see what happens -- removal is a real edit.
- **Explain the why.** If you catch yourself writing `ALWAYS` in caps, ask what would
  happen if the model understood the reason instead. Usually the reason is shorter and
  works better.
- **Watch for repeated work.** If every run of the skill has the model writing the same
  helper by hand, write it once into `scripts/` and point at it -- within the runtime
  constraint in section 4.
- **Change one thing at a time** when you are trying to find out what helped.

## 9. Measuring it

**Evaluating a skill is `raid-eval`'s job, not this one.** This repo already has an eval
harness -- reviewer fixtures, the golden engagement, a judge panel -- as a **dev skill at
`.claude/skills/raid-eval`** (non-shipped, backed by `eval/`). Use it for a baseline before
editing a reviewer or skill prompt, and again after, to see whether the change actually
regressed anything.

That is deliberately not part of this skill, and the omission is not an oversight: the
upstream this skill was adapted from carries its own harness that shells out to `claude -p`
and imports third-party Python, neither of which survives RAID's three-host,
no-dependencies constraints. `raid-eval` dispatches in-session subagents instead.

## 10. Communicating while you work

People reach for this skill from very different starting points. Read the cues. In the
default case: "description", "trigger" and "frontmatter" are fine to use plainly;
"progressive disclosure", "routing budget" and "eval harness" are worth a half-sentence
gloss the first time unless the user has already used them. It costs nothing to define a
term briefly and it costs a lot to leave someone behind.

Be flexible about process, too. If the user wants to think out loud about what the skill
should be rather than march through section 7, do that -- the structure is here so nothing
gets forgotten, not to be recited.

---

Related: `raid-mode` (routes work, and is itself an example of a
`disable-model-invocation` entry point), `close-the-loop` (generates a project-local skill
into a customer repo), `simplify-code` (the same subtract-first instinct, applied to code).
