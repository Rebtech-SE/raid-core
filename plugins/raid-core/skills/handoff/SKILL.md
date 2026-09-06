---
name: handoff
description: >-
  Use to compact the current session into a handoff another agent or person can pick up --
  'write a handoff', 'I'm running out of context', 'hand this to someone else', 'pick this
  up tomorrow'. Summarises where the work stands, what is verified against real data and
  what is not, and which gated actions are still queued. Points at artifacts rather than
  copying them, and redacts anything from the customer estate.
argument-hint: "[what the next session will focus on]"
---

# Handoff

Write a document that lets a fresh agent, or a colleague on Monday, continue this work
without re-deriving it.

Save it to the **operating system's temporary directory**, not the customer's repo. A
handoff is session scratch; it is not an engagement artifact and it must not land in a
commit. Print the path.

If the user passed arguments, treat them as what the next session will focus on and tailor
the document to that.

## What goes in

- **Where the work stands.** The route being run (`raid-mode`'s direct / incremental /
  wayfinder / greenfield), the unit in flight, the units finished, the branch or worktree.
- **What is verified and what is not.** Be exact and be honest. Which checks ran, against
  which environment, with what result; what was checked against real data and what was only
  compiled or reviewed. A handoff that presents unverified work as verified is worse than
  no handoff, because the next agent builds on it.
- **What is queued behind a gate.** Every hard pause under `raid-core/AGENTS.md` that this
  session parked -- a production write, a deploy, a backfill, a push or PR -- with what you
  would do and why, so the operator clears the batch in one pass.
- **Decisions taken in this session that are not yet written down anywhere.** Then say
  where each one belongs: `GLOSSARY.md`, `docs/adr/`, `AGENTS.md`, the tracker. If a
  decision is durable and the session is ending, offer to write it to its home *before*
  writing the handoff, so the handoff can point at it instead of carrying it.
- **Open threads and known-but-unfixed issues**, each with enough context to act on.
- **Suggested skills** -- which RAID skills the next session should invoke, and for what.

## What stays out

- **Anything already captured elsewhere.** Specs, ADRs, glossary entries, decision
  artifacts, tickets, commits, diffs. Reference them by repo-relative path, tracker id or
  URL. A handoff that duplicates an artifact goes stale against it within a day.
- **A turn-by-turn replay.** Outcomes and current state, not a transcript.

## Redact

This runs on a customer engagement, and the document leaves the session.

Strip connection strings, keys, tokens, service-principal secrets, passwords inside
connection strings, and personal data pulled out of the warehouse during investigation.
**Never paste real customer rows into it** -- describe the shape ("three duplicates on
`customer_key` in the 2026-08 partition") rather than the rows. Name environments and
workspaces by their configured names, not by embedding credentials that reach them.

## Reply

The path to the document, and a three-line summary of where the work stands: what is done,
what is next, what is blocked.

Related: `raid-mode`, `review-sessions`, `domain-modeling`, `to-tickets`.
