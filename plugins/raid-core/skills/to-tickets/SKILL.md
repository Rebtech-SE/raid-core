---
name: to-tickets
description: >-
  Use to turn a plan, a design artifact or the current conversation into tickets on the
  engagement's issue tracker -- 'break this down', 'write the tickets', 'publish these
  units', 'make this into work items'. Cuts the work into vertical slices that each land
  bronze-to-gold with their tests, declares the blocking edges, and publishes each in the
  standard ticket-brief shape so any agent can pick one up cold. Sequences a wide schema
  change as expand-migrate-contract instead.
---

# To Tickets

RAID writes **no plan file into a customer's repo**. Work that must outlive the session
lives on the engagement's issue tracker, as tickets an agent can claim. This skill is how
it gets there.

The tracker is the provider in `docs/agents/issue-tracker.md`; the command recipes are in
`setup-raid`'s `references/trackers/` (`azure-devops.md`, `github.md`, `jira.md`,
`linear.md`). If that file is absent, say so and point at `setup-raid` -- do not pick
one, and do not silently fall back to local files.

Every ticket body uses the standard shape: **Goal, Scope, Context, Acceptance, Verify,
Forbidden, Blocked by**. Read [`references/ticket-brief.md`](./references/ticket-brief.md)
before writing the first one; it defines each section and what "filled" means for data
work.

## 1. Gather context

Work from what is already in the conversation. If the user passes a reference -- a path, an
issue id, a URL, `design.html` -- read it in full, including comments.

Where the greenfield artifacts exist, they are the input and they are binding:
`architecture.html` fixes tier, grain, naming and audit columns; `design.html` fixes the
entity model, the load modes and the **wave order**. The wave order is usually most of the
dependency graph already -- do not re-derive it.

## 2. Read the repo before slicing

Ticket titles and bodies use the project's vocabulary from `GLOSSARY.md`, and respect the
ADRs in the area. Look for prefactoring that makes the rest easy -- extract the shared
staging model, add the missing source freshness config -- and make it the first ticket.
Make the change easy, then make the easy change.

## 3. Cut vertical slices

Each ticket is a **tracer bullet**: a narrow but complete path through every layer.

- Vertical, not horizontal. "Customer dimension end to end, bronze land through silver
  conform to `dim_customer`, with its tests" is a slice. "All of bronze" is not: it is a
  layer, it demos nothing, and it cannot be verified against anything.
- **A slice includes its tests and its data checks.** Not "later", not a separate ticket.
  A slice whose tests are someone else's ticket cannot satisfy its own Acceptance.
- Each slice is verifiable on its own, against real data.
- Each slice fits one fresh context window.
- Prefactoring first.

Give each ticket its **blocking edges** -- the tickets that must complete before it can
start. A ticket with no blockers can start immediately. Conformed dimensions block the
facts that reference them; a shared staging model blocks everything downstream of it.

### Wide schema changes are the exception

A **wide change** is one mechanical change whose blast radius fans across the platform:
rename a column, change a type, split a key, relabel a status enum. A single edit breaks
every downstream model, report and extract at once, and no vertical slice can land green.
Do not force it into a tracer bullet. Sequence it as **expand - migrate - contract**:

1. **Expand** -- add the new form beside the old. Both populate; nothing downstream breaks.
   One ticket, and it blocks the rest.
2. **Migrate** -- move consumers over in batches sized by blast radius: per layer, per
   domain, per report. Each batch is its own ticket, blocked by the expand. The build stays
   green batch to batch because the old form still exists.
3. **Contract** -- drop the old form once no consumer remains, in a ticket blocked by every
   migrate batch. Its Acceptance includes the search that proves nothing still reads it --
   the dependency graph *and* a grep across reports, notebooks and ad-hoc SQL, because the
   graph does not see those.

For a change to persisted history -- a restated dimension, a corrected fact -- the contract
ticket also names the backfill, which is a hard pause under `raid-core/AGENTS.md` and
belongs in Forbidden on every other ticket in the sequence.

## 4. Quiz the user

Present the breakdown as a numbered list. Per ticket: **Title**, **Blocked by**, and **what
it delivers** end to end. Then ask:

- Is the granularity right -- too coarse, too fine?
- Are the blocking edges real, or did a ticket inherit a blocker it does not need?
- Should any be merged or split?

Iterate until the user approves. Do not publish an unapproved breakdown.

## 5. Publish

Publish in dependency order, blockers first, so each ticket's edges reference real ids.

- Use the tracker's **native** blocking or parent relation where it has one -- it renders
  the frontier visually in the tracker's own UI. Otherwise write the Blocked by section and
  reference the ids.
- Apply the `ready-for-agent` role (resolved through the `mapping` block in `docs/agents/issue-tracker.md`)
  **only when every brief section is filled**. A ticket missing Verify or Forbidden is not
  agent-ready, whatever else is true about it.
- Do not close or modify a parent issue.

Then work the **frontier**: any ticket whose blockers are all done. `raid-mode` claims one
before building it, which is also how two agents avoid colliding.

Avoid file paths and code snippets in ticket bodies -- they go stale fast. The exception is
a snippet that encodes a decision more precisely than prose can: a grain declaration, a
key definition, a schema shape, an SCD comparison rule. Inline it, trimmed to the decision.

Related: `raid-mode`, `wayfinder`, `triage`, `setup-raid`, `domain-modeling`,
`principle-sequence-verifiable-units`.
