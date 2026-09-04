---
name: review-sessions
description: >-
  Use when the user says 'what did we do recently', 'review past sessions', 'what should
  we capture from this work', 'any loose ends from last session'. Reviews recent Claude
  Code session history for this project and surfaces what should be compounded or
  followed up - solved problems and non-obvious fixes, durable decisions, and unfinished
  threads - that the in-the-moment workflow didn't capture. Read-only retrospective
  feeding the next piece of work.
argument-hint: "[optional: how far back - 'last session', 'last 3', a date; or a topic to focus on]"
---

# RAID Sessions

A retrospective sweep over recent work to catch what the in-the-moment pipeline missed. People
forget to note a fix while shipping, and "next steps" mentioned mid-session evaporate
when the session ends. This skill reads the session history, finds those items, and routes each
to where it belongs -- it is the safety net that keeps the compounding loop from leaking.

It is **read-only over history** and does not itself write learnings or tasks -- it surfaces
candidates and hands off (`raid-mode`
captures the work). That keeps one owner for each output.

## Inputs

<input> #$ARGUMENTS </input>

Scope: "last session", "last N", a date/range, or a topic to focus on. Default: the current
session plus the few most recent.

## Workflow

### 1. Locate the session transcripts

Claude Code stores per-project session transcripts as JSONL files. The project directory is
derived from the working-directory path with `/` replaced by `-`, under
`~/.claude/projects/<project-slug>/` (e.g. this repo ->
`~/.claude/projects/-Users-<user>-rebtech-raid-plugin/`). List the `*.jsonl` files there, newest
first (by mtime), and select the set in scope. If the directory or files can't be found, say so
and ask the user to confirm the path rather than guessing.

### 2. Read and extract (don't replay)

Read the selected transcripts for *outcomes and decisions*, not a turn-by-turn replay. You are
mining for four buckets:

- **Solved problems / non-obvious fixes** -- a bug root-caused, an auth quirk worked around, an
  SCD edge case handled. Worth raising with the team or filing on the tracker.
- **Durable decisions & conventions** -- an architecture choice, a naming/grain decision, a
  "we always do X here" that is worth writing into the repo's own conventions doc.
- **Unfinished threads** -- "next we should...", a deferred TODO, a known-but-unfixed issue, a
  scope boundary that was parked. Candidates for the next unit of work, or a tracker ticket.
- **Recurring friction** -- the same mistake or question across sessions. A process learning,
  and a signal something in the skills/docs is unclear.

Ground each item in the session it came from; skip the trivial and the already-captured (cross-
check the repo's own docs and the issue tracker so you don't re-surface something already written).

### 3. Report the digest

Group the findings by bucket; for each item give a one-line summary, the source session, and a
recommended action:

```
Session review - <scope> (<n> sessions)

To compound (solved problems / decisions):
  - <one-line> [<session>] -> file on the tracker
Unfinished threads:
  - <one-line> [<session>] -> raid-mode
Recurring friction:
  - <one-line> (<n> sessions) -> <skill/doc to clarify>
```

If nothing meaningful surfaced, say so -- don't invent retrospective findings.

### 4. Hand off (with consent)

Offer to act on the clear ones, but let the user choose:

- For confident, clearly-novel learnings: offer to file one tracker item per learning.
- For unfinished work: offer to pick it up in `raid-mode`, or publish it as a tracker ticket.

Do not auto-write a pile of learnings or create tracker items unprompted -- propose, then act on
what's confirmed.

## Rules

- Read-only over transcripts; surface candidates, delegate the writing (the tracker owns learnings, plan/boards own tasks).
- Ground every item in a real session; never fabricate retrospective findings; report "nothing notable" honestly.
- Don't re-surface already-captured learnings -- check the tracker and the repo's docs first.
- Detect the transcript path; if absent, ask rather than guess. Repo-relative paths.
