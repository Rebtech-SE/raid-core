---
name: create-verification-skill
description: >-
  Use when a platform has no scripted way to prove its data is right, or the user says
  'close the loop', 'build a verification tool', 'how do I check this is correct', 'make a
  query tool for this repo'. Run once per engagement; `maintain-verification-skill` keeps
  it honest after. Builds two things into the repo: a guarded read-only query tool the
  agent can run safely against the warehouse, and a project-local verify skill plus a data
  map that says, per mart, the query that proves it correct. Turns 'validate against real
  data' from a rule into something an agent can actually run.
disable-model-invocation: true
---

# Create Verification Skill

`raid-core`'s hard rule says validate against real data. `principle-reconcile-against-source`
says which probes to run. Neither says *how* on **this** platform -- so every session
re-derives the connection, the safety limits and the reconciliation query from scratch,
badly, and the expensive ones get skipped.

This skill closes that gap once per engagement. It builds:

1. **A guarded query tool** -- the thing an agent can point at a customer's warehouse
   without anyone holding their breath.
2. **A project-local `verify-<platform>` skill** -- how to run the pipeline, how to check
   it, where the evidence goes.
3. **A data map** -- one file per mart or domain: what it means, its grain, who consumes
   it, and **the query that proves it is right**.

Write all of it for the next agent, not for a human. It will be read cold, mid-task, by an
agent that has never seen this platform.

## 0. Resolve where project-local skills live

Do not assume a path. Write into the first of these that already exists: `.agents/skills/`,
`.claude/skills/`, `.cursor/skills/`. If none exists, create `.agents/skills/` -- Codex and
Cursor both read it; Claude Code does not, so when the project is also used with Claude
Code add `.claude/skills` as a **symlink** to it rather than a second copy, so one tree
serves every runtime. Say which directory you resolved, once, before you write anything.

Everything below writes `<skills-dir>/verify-<platform>/`.

## 1. Interview the repo and the platform, not the user

Answer these from the repo, its `AGENTS.md`, and read-only probes. Ask only what you
genuinely cannot observe.

- **Surface.** What do consumers actually read? The gold marts, the semantic model, the
  reports, an API. Not the intermediate models -- those are implementation. Name the
  primary surface and note the rest.
- **Run.** How does the pipeline run locally or in dev? `dbt build --select ...`,
  a transformation-tool build, a job run, a notebook, an orchestrator trigger. Prefer the
  repo's own documented command over one you compose. Note env vars, profiles, auth.
- **Query.** How does an agent get a result set out of the warehouse? Existing wrappers
  first -- the repo may already have one. Then whatever client the platform offers.
  Dispatch the tier's expert agent rather than guessing syntax; it tracks the current
  command shapes and you do not.
- **Observe.** What evidence can be captured? Row counts, key uniqueness, measure totals,
  null and sentinel rates, freshness timestamps, `dbt` `run_results.json`, job status,
  query cost.
- **Isolate.** **This is the one that matters most, and it has no equivalent in application
  work.** Is there a personal or dev dataset/schema to build into, separate from anything a
  consumer reads? If there is not, say so loudly in the generated skill -- a verification
  loop that has nowhere safe to write is read-only forever, which is a real and acceptable
  answer, but it must be stated rather than discovered.
- **Cost and blast radius.** What does a careless query cost here, and what is the unit --
  data scanned, compute time, a cluster left running, nothing? The answer decides which
  guard in step 2 is even meaningful. Find the real numbers on this platform; do not assume
  a billing model.

If you cannot connect and run `SELECT 1` as-is, fix that first or report it precisely. A
verify skill written against a connection nobody has tested teaches wrong steps.

## 2. Build the guarded way to query

An agent that cannot run a query cannot verify anything. So the loop needs one thing above
all: **a single command that asks the platform a question and returns an answer, safe to
hand an agent unattended.** Building that command is the substance of this step.

What that *is* depends entirely on the platform. Do not carry a recipe across from another
engagement -- dialects differ, CLIs differ, some platforms expose no usable CLI at all, and
the way a given guarantee is enforced is different on every one. **Dispatch the tier's
expert agent to establish the real surface before writing anything**; the command shapes
move, and the expert skills track them.

### First: decide what the command has to carry

In order of preference, stop at the first that works:

1. **A read-only credential.** The strongest guarantee available, and the only one
   independent of the platform: a principal granted read and nothing else. No parser can be
   fooled and no flag can be forgotten. Where the engagement can provision one, do that and
   whatever you build carries no safety burden at all.
2. **Something the repo already has.** A wrapper, a make target, a transformation tool's
   own read path. Extend it rather than adding a second way to do the same thing.
3. **A read-only surface the platform already exposes.** Some endpoints are read-only for
   table data by design. Pointing at one is a stronger guarantee than anything you could
   enforce yourself.
4. **Build the command**, carrying whichever guarantees the platform has not already given
   you. This is the usual outcome -- the steps above narrow what it has to enforce, they
   rarely remove the need for it.

### What it has to guarantee

These are the requirements. How each is met is a per-platform question, and answering it is
part of the work.

- **Reads only.** Nothing the agent runs through it can change data or schema. Prefer a
  credential that cannot write. Where the guarantee has to live in the tool instead, it
  allows only the statement forms that are read-only **in this platform's dialect** -- a
  set you derive from the platform, never copy.
- **One statement per invocation.** Whatever is submitted must be a single statement, with
  comments stripped before that is judged. This one holds everywhere, because the risk it
  addresses -- something appended after a legitimate query -- does not depend on the engine.
- **The cost is known before the query runs.** Find out what this platform actually charges
  for -- scanned data, compute time, a running cluster, nothing at all -- and surface that
  estimate ahead of execution. A cost model borrowed from a different warehouse measures the
  wrong thing.
- **A ceiling the engine enforces.** Not a limit the tool prints and hopes for. The test is
  whether the platform itself will refuse or stop the query, and the mechanism differs:
  a billing cap, a governor, a timeout, a compute-size bound. Find the one this platform
  honours. Row limits are not cost limits -- capping rows returned rarely caps work done.
- **A doctor.** One read-only check answering "is this connection worth using?" -- client
  present, auth valid, target resolves, a trivial query returns. It separates "the platform
  is broken" from "your token expired", and an agent runs it first whenever anything is off.
- **Legible output.** The statement that ran, whatever the platform reports about cost, the
  row count, and the result -- readable by an agent without a human interpreting it.

### There is almost always a programmatic surface. Find it and build on it.

A warehouse that no program can talk to is not a warehouse anyone runs a platform on.
Essentially every provider exposes at least one of these, and usually several:

- a command-line client;
- a SQL execution REST API;
- a wire protocol a generic client already speaks;
- a driver or SDK the engagement's runtime already has.

**Your job is to put a single consistent command in front of whichever of those exists**,
so the agent drives and verifies through one interface with the guarantees attached, rather
than improvising a different invocation each session. That command is the deliverable.
Building it is the expected outcome of this step, not a fallback.

Prefer them in this order, since each one costs less to maintain than the next:

1. **A command-line client the platform ships.** Least code, but confirm the commands
   exist -- CLI surfaces move, and a plausible-looking command may never have been real.
2. **The SQL execution REST API**, driven by a shell HTTP client and the standard library.
   More verbose, usually better documented and more stable than the CLI, and it typically
   exposes timeout and row-limit parameters that serve as guards for free.
3. **A generic client that speaks the platform's wire protocol**, where the engagement
   already has one installed.

Only when every one of those is genuinely unavailable -- no network path, no credentials
that can be provisioned, a locked-down environment -- do you stop. Then say so plainly in
the generated skill: verification runs through the tier's expert agent by hand, and the
map's proof queries are still written down so nobody re-derives them. That is a real
outcome, but it is rare, and it is a constraint of the engagement rather than of the
platform. Do not reach for it because the first client you tried was awkward.

Per the repo's runtime rule, whatever you build is POSIX shell or a single-file Python
script with no third-party imports. Not a package, not a framework, no SDK install.

Worked examples of these guarantees on specific platforms -- including where the obvious
approach does not transfer -- are in
[platform-notes](./references/platform-notes.md). Read the entry for your platform if one
exists; treat it as illustration, not as a template to copy.

### Prove the guards

Run the doctor. Run a real read. Then run one statement that **must** be refused, and watch
it get refused. A guard nobody has watched refuse something is not a guard.

Record in the generated skill which guarantees this platform actually gave you and which it
could not. The next agent needs to know what is enforced and what is merely intended.

## 3. Generate the verify skill

Write `<skills-dir>/verify-<platform>/SKILL.md` with frontmatter (`name: verify-<platform>`
and a description naming the platform, the warehouse and when to reach for it -- without
frontmatter it never registers), grounded in what the interview actually found. No
placeholders.

**Use `create-skill` for the mechanics of writing it** -- how a description gets the skill
found, what belongs in the body versus a reference file, and the discipline for a skill
that will be read cold by an agent that has never seen this platform. This step decides
*what* the generated skill says; `create-skill` covers *how to write it so it works*.

- **Doctor.** The one read-only command that answers "is this connection worth using?"
  Usually the tool's `--check`.
- **Run.** The exact command that builds or refreshes the thing being verified, and how to
  tell it finished rather than merely returned. A job that reports success and produced no
  rows is a failure this section must be able to catch.
- **Check.** The tool invocation, with real dataset and table names from this repo, not
  examples. Include the six probes from `principle-reconcile-against-source` as runnable
  queries against the real objects: row counts, grain uniqueness, measure totals, null and
  sentinel rates, referential integrity, before/after parity.
- **Evidence.** Where results land and what a proof consists of. State the standards:
  query the real consumer-facing object, never a convenient intermediate; capture the query
  text alongside the numbers; compare against the **source system** where one exists, not
  against another model derived from the same bad load. Mocked or sampled data proves
  nothing about production grain.
- **Cleanup.** Drop the scratch tables the run created -- by name, never by pattern, and
  never anything you did not create. **Cleanup never removes the evidence.**
- **Helpers.** Any script it ships is executable, and its invocation is shown in the body.

## 4. Seed the data map

Create `<skills-dir>/verify-<platform>/data-map/README.md` plus one file per consumer-facing
mart or domain -- aim for the three to five that matter most, from the gold layer, the
semantic model, or whatever the reports actually read. Shape in
[data-map-example](./references/data-map-example.md).

Four sections per file: **What it means** (business terms, from `GLOSSARY.md` where one
exists), **Grain** (one sentence, per `principle-declare-the-grain`), **Who reads it**, and
**The query that proves it right**.

The proof query is the section that earns the map. It is the one nobody writes down and
everybody re-derives.

**The map is the platform's maintained verification source, and coverage is the bar:
verifying the model you changed does not discharge the check when the map lists three marts
downstream of it.**

## 5. Prove the generated skill before handing it over

Run its own instructions end to end, once: doctor, run, check **one** mapped mart, capture
evidence, clean up. One is enough -- the map exists so later runs cover the rest. Confirm
the evidence still exists after cleanup; a cleanup that eats the proof fails this step.

Fix what fails and re-run. **A generated skill that was never executed is a draft, not a
deliverable** -- and on a customer's platform, a draft that claims to verify things is worse
than nothing.

## 6. Hand it to the maintenance loop

The map rots the moment a mart changes grain or a new one ships, and a stale map that
claims to verify things is worse than none. This skill does not own that upkeep --
`maintain-verification-skill` does. Point the user at it once, here, and say when to run
it: after any change to the gold layer, and at the end of an engagement so whoever
inherits the platform inherits a working check.

Related: `maintain-verification-skill`, `principle-reconcile-against-source`,
`principle-prove-it-works`, `principle-declare-the-grain`, `data-quality-checks`,
`write-test-report`.
