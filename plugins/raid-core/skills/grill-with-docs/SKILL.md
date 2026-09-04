---
name: grill-with-docs
description: >-
  Use when the user wants a grilling that leaves a durable record - says "grill
  me with docs", "grill-with-docs", or wants the design decisions written down
  as they settle. Thin router: `grilling` for the interview, `domain-modeling`
  for the docs it writes into.
disable-model-invocation: true
---

Run the `grilling` skill (raid-core) for the interview, with `domain-modeling`
(raid-core) alongside it. The docs are part of the loop, not an afterthought:

- **Every round ends with a write step, before the next frontier is
  computed.** For each answer that settled a decision, write it down *now*:
  - A decision with consequences — grain, SCD type, layer ownership, load
    pattern, source-system scope, naming — becomes an **ADR** under
    `docs/adr/` (sequential numbering, format in `domain-modeling`'s
    `references/adr-format.md`).
  - A term the round sharpened, renamed, or disambiguated goes into
    **`GLOSSARY.md`** inline (format in `domain-modeling`'s
    `references/glossary-format.md`).
- Both files are lazy: create them the first time something real is written,
  never as empty scaffolding. A definition claiming grain or uniqueness is
  verified against real data before it is written as settled, per
  `domain-modeling`.
- Report what was written ("settled: Q2 -> ADR 0003; Q4 -> glossary updated"),
  then recompute the frontier and ask the next round.

The docs are the design tree's record. Later rounds and future sessions read
them back instead of re-deriving the answers, and a decision that never
reached a document did not happen. When the user uses a term that conflicts
with the glossary, call it out as part of the round, not after.
