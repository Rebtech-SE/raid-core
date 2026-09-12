---
name: codify-conventions
description: >-
  Use to turn how a data repo actually behaves into rules something checks -- 'what are our
  conventions', 'enforce our naming', 'every model should have tests', 'write this down so
  it stops happening'. Audits the repo for the patterns that already hold or interviews the
  user for the ones they want, writes CONVENTIONS.md, and wires each enforceable rule into
  sqlfluff, dbt, a linter or a pre-commit hook -- then proves the check actually fires.
---

# Codify Conventions

Turn the way a repo behaves into rules something actually checks. A convention nobody
enforces is a wish. This skill gives every rule a place where it is enforced, or at least
seen.

It is the mechanism behind `principle-encode-lessons-in-structure`: the second time you
write the same correction, it becomes a check instead of more prose.

`map-repo` **observes** conventions and lists them in its report, without writing them into
`AGENTS.md`. This skill **enforces** them, so neither a human nor an agent can skip them. Run
`map-repo` first on an unfamiliar repo and start from the conventions it reported.

Two entry points, one artifact:

- **Audit mode** (default when nothing is codified): read the repo, find the patterns that
  already hold, propose codifying them.
- **Grill mode** (when the user has opinions the audit cannot see): interview them rule by
  rule, using the technique from `grilling`.

Both converge on the same artifact and the same wiring. **Confirm before writing anything**;
every rule lands with the user's yes.

## The artifact: `CONVENTIONS.md`

Project-root `CONVENTIONS.md`, created **lazily** -- never pre-create it empty. An empty
conventions file gets read, believed, and found empty. Create it when the first real rule
lands, and add one line pointing at it to the repo's `AGENTS.md`, where the file routes to
its docs.

Two classes of rule, clearly separated:

1. **Enforced by tooling** -- something fails when it is violated. Each rule names where it
   is enforced: the config file and the rule id.
2. **Judgment calls** -- no linter can catch it, so a reviewer or an agent must. Write these
   as a checkable question, not a vibe: "every fact model states its grain in a header
   comment and its `unique` test matches that grain", not "models should be well modelled".

Never drop a rule silently because no tool supports it. Judgment rules exist so that nothing
the user cares about goes unseen -- and they are what the reviewer subagents in
`review-changes` read.

One rule per line where possible. Each rule states what to do, not what not to do, and links
to an example model or commit where one exists.

## Mode 1: Audit

1. **Sample broadly.** Recent commits and diffs; model and file naming; the layer
   directories; how sources are declared; test coverage per layer; where tests live; SQL
   style (case, CTE vs subquery, join style, trailing commas); how incremental models are
   predicated; how audit columns are named; notebook structure; commit message shape. Read
   the idioms from the repo, not from a style guide you remember.

2. **Find the patterns that hold.** A rule is a candidate only if it holds across the strong
   majority. Holding half the time is not a convention yet -- it is a choice the user gets
   to make, which is grill-mode material.

3. **Distinguish convention from accident.** Three models doing the same thing by
   coincidence is not a convention. Look for repetition across authors, across time, and in
   deliberately-written places (`dbt_project.yml`, CI config, the README) over incidental
   ones.

4. **Propose.** A table: pattern, evidence, enforceable now or judgment call, proposed
   enforcement. The user strikes and amends; nothing is written until they say so.

Audit mode never invents rules the repo does not follow. If the user wants the code to
*start* behaving a certain way, mark it as a new rule so they know it will fight existing
code, and offer to fix the existing violations in the same pass.

## Mode 2: Grill

When the user arrives with opinions, or the audit leaves gaps only they can fill:

- One question at a time, concrete examples over abstractions: "when a source sends `'N/A'`
  for a missing value, do we keep it in bronze and clean it in silver, or clean it on
  landing?"
- Classify each answer immediately: tooling or judgment.
- Batch-confirm before writing. Show the full list, let them strike and amend, write once.

## What is enforceable in a data repo

More than people expect. Inventory what the project already has before proposing anything
-- do not import an ecosystem:

| Rule shape | Where it gets enforced |
|---|---|
| SQL style: keyword case, CTE naming, join style, no `select *` | `sqlfluff` rules in `.sqlfluff` |
| Model, column and layer naming (`stg_`, `int_`, `dim_`, `fct_`) | `dbt` model contracts, a `sqlfluff` rule, or a small check script |
| Every model has a description and an owner | `dbt-checkpoint`-style check, or a script over the manifest |
| Every model has a `unique` + `not_null` on its grain key | a script over `manifest.json` in CI |
| Every foreign key has a `relationships` test | same |
| Source freshness declared on every source | same |
| Warnings are not allowed to pass | `dbt build --warn-error` in CI |
| Python style in notebooks and jobs | `ruff` / `black`, existing config |
| Secrets never committed | the repo's existing secret scan |
| Commit message shape | `commit-msg` hook |

A rule that maps to none of these is a judgment rule. Visible beats enforced badly.

## Wiring

This skill owns the whole path from rule to check.

1. **Inventory first.** Which linters, formatters and hook managers does the repo already
   use? Check config files, `pyproject.toml`, `package.json`, `.pre-commit-config.yaml`, the
   CI definition. A repo on `sqlfluff` does not get a second SQL linter. A repo with no hook
   manager gets the lightest wiring its ecosystem supports, or a plain script under
   `.githooks/` enabled with `git config core.hooksPath .githooks`.

2. **Map rules to enforcement.** Each enforceable rule becomes a specific rule id, a hook
   check, or a small script. Scripts are POSIX shell or a single-file Python with no
   third-party imports -- a customer's build agent has `bash`, a `python3`, and its
   platform's CLI, and nothing you are allowed to install on it.

3. **Wire without clobbering.** Add to existing config, never replace it. Show the diff
   before writing. If a proposed rule contradicts an existing one, surface the contradiction
   -- the user resolves it, not you.

4. **Verify the check actually fires.** Write a deliberate violation into a scratch file,
   watch the hook or the lint run block it, then revert and remove the scratch file. A check
   that has never blocked anything is decoration. Report what you verified.

5. **Degrade loudly.** Where a check can be skipped (`--no-verify`) or cannot run (CI has no
   warehouse credentials, so the manifest checks run only locally), say so in the artifact.
   A rule enforced 80% of the time is worth having; the user should know which 20% it misses.

6. **Do not turn a green repo red.** Codifying a rule the existing code violates comes with
   a decision: fix the violations in the same pass, or scope the rule to new files. Ask
   which; never leave the build broken.

## Adding a rule later

The common case, and it stays cheap:

1. The user states the rule, or a violation annoys them.
2. Classify: tooling or judgment.
3. Add one line to `CONVENTIONS.md` under the right heading, wire it if tooling, verify it
   fires.
4. Done. No re-audit, no re-interview.

When `CONVENTIONS.md` already exists, start here, not from the audit.

## Verify

- Every rule is either wired into tooling or written as a judgment rule. Nothing orphaned.
- The check blocks a real violation -- tested, not assumed.
- The existing lint and build still pass.

Related: `map-repo`, `principle-encode-lessons-in-structure`, `grilling`, `review-changes`,
`domain-modeling`.
