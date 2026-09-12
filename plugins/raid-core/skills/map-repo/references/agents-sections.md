# The router map-repo keeps in AGENTS.md

`map-repo` keeps the repo's root instruction file (`AGENTS.md`, or the substantive file
when a shim/symlink is in play) a short router: enough for a cold session to know where it
is, how to work here, and where to read more. Everything that is not needed in every
session lives in a doc the router points to. This reference covers what goes in, how it
merges with what the file already says, and a worked example.

## What goes in

Every line has to earn its place in every session. Strike any line an agent would have
followed without it.

- **What** -- the stack in a line; the top-level directories and what each is for, a few
  words each.
- **Why** -- one line on what the repo is for.
- **How** -- the commands to build, test, run and deploy, and what they need (a virtual
  environment, a profile directory, an env var, a CLI login). A long list becomes a pointer
  to a doc in `docs/`.
- **Where to read more** -- a pointer per doc, each saying what it answers:
  - the architecture doc (always -- `map-repo` creates one when the repo has none);
  - `CONVENTIONS.md`, `GLOSSARY.md`, `docs/adr/` and `docs/agents/issue-tracker.md` when
    they exist;
  - `docs/artifacts/` on a greenfield engagement.

What stays out, pointed at instead: layering, models, grain, sources and data flow (the
architecture doc); conventions (checks, and `CONVENTIONS.md`); domain vocabulary
(`GLOSSARY.md`); tech debt (the `docs/audit/` report).

## Merging with what is there

The file belongs to the repo, not to RAID. Every rule below follows from that.

- **Already said, still true:** leave it. Do not reword a hand-written line into this
  shape.
- **Said at length in the router:** when a hand-written section already holds what belongs
  in the architecture doc, leave it and propose moving it; do not move it unasked.
- **Said, but the code disagrees:** propose the correction and show both.
- **Not said anywhere:** add it under the heading where it belongs. When the file has no
  such heading, add one where it reads naturally.
- **No markers, no generated banner.** A re-run finds what to update by reading the file.
- **No instruction file at all:** create `AGENTS.md` holding the router. That is the whole
  step -- do not create a `CLAUDE.md`, a symlink, or any other harness-specific file.
  `AGENTS.md` is the open standard; a symlink does not survive a Windows checkout, and a
  second file is one more thing to drift. Add one only if the user explicitly asks.
- **Symlink/shim:** when `CLAUDE.md` is a symlink to `AGENTS.md` (RAID repos) or one file
  `@`-includes the other, edit the substantive file only; the symlink/shim carries the
  change automatically. Never create a competing second file.
- **Two independent instruction files:** when the repo genuinely maintains more than one
  (e.g. a hand-authored `AGENTS.md` *and* a `.github/copilot-instructions.md` that is not a
  shim), the router goes in **one** file -- `AGENTS.md` if it is among them, otherwise the
  substantive one -- and the others get a single pointer line
  (`See AGENTS.md for how this repo is laid out and run.`) if they don't already say
  something equivalent. Never write the same content twice; two copies drift.

## Worked example

Starting `AGENTS.md`, hand-authored; the repo has no architecture doc:

```markdown
# Acme Data Platform

Internal notes for the analytics warehouse. Ask #data-eng before touching prod.

## Conventions

- snake_case everywhere; `stg_`, `int_`, `fct_`, `dim_` prefixes.
```

After `map-repo`, which also created `docs/architecture.md`:

```markdown
# Acme Data Platform

Internal notes for the analytics warehouse: the sales and customer marts behind Looker.
Ask #data-eng before touching prod.

## Layout

- BigQuery + dbt 1.8 on Cloud Composer.
- `models/` -- the dbt project; `dags/` -- the Composer DAGs; `profiles/` -- dbt profiles.

## Commands

- `dbt build --select state:modified+` -- build and test what changed (`DBT_PROFILES_DIR=./profiles`).
- `pre-commit run --all-files` -- the gates every commit passes.

## Where to read more

- `docs/architecture.md` -- layers, key models and their grain, sources, the nightly schedule.

## Conventions

- snake_case everywhere; `stg_`, `int_`, `fct_`, `dim_` prefixes.
```

The purpose line gained what the warehouse serves; the layers, grain and schedule went to
the architecture doc and the router points there. The hand-written convention is untouched,
and the report marks the model prefixes as enforceable and offers `codify-conventions`,
which would add `CONVENTIONS.md` to "Where to read more" when it creates the file.
