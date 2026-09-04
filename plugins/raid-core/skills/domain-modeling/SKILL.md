---
name: domain-modeling
description: >-
  Use when the business language of a data platform is being settled or is in dispute --
  what "net sales", "active customer" or "order line" actually means, what the grain of a
  table is, or when a decision needs recording. Triggers: 'what do we call this', 'define
  this term', 'the glossary', 'write an ADR', 'record this decision'. Challenges terms
  against GLOSSARY.md, sharpens fuzzy language, verifies checkable claims against real
  data, and writes the glossary and ADRs as they crystallise.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active*
discipline: challenging terms, inventing edge-case scenarios, and writing the glossary and
decisions down the moment they crystallise. (Merely *reading* `GLOSSARY.md` for vocabulary
is not this skill -- that's a one-line habit any skill can do. This skill is for when you
are changing the model, not just consuming it.)

On a data platform the glossary is not a nicety. "Net sales", "active customer" and
"order line" mean different things in finance, supply chain and marketing, and a warehouse
that ships all three definitions under one column name is a warehouse nobody trusts. The
glossary is where that gets settled once.

## File structure

Most repos have a single context:

```
/
├── GLOSSARY.md
├── docs/
│   └── adr/
│       ├── 0001-medallion-over-kimball-core.md
│       └── 0002-scd2-on-dim-customer.md
└── models/
```

If a `GLOSSARY-MAP.md` exists at the root, the repo has multiple contexts -- typically one
per business domain or subject area. The map points to where each one lives and how they
relate. See [glossary-format](./references/glossary-format.md).

**Create files lazily -- only when you have something real to write.** If no `GLOSSARY.md`
exists, create it when the first term is resolved. If no `docs/adr/` exists, create it when
the first ADR is needed. Never create either one empty: an empty `GLOSSARY.md` is a file
that gets read, believed, and found empty.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `GLOSSARY.md`, call
it out immediately. "Your glossary defines 'active customer' as one order in 12 months, but
you seem to mean one order in 90 days -- which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're
saying 'sales' -- do you mean gross, net of returns, or net of returns and discounts?
Those are three different measures."

### Discuss concrete scenarios

Stress-test relationships with specific scenarios that probe edge cases and force
precision about the boundaries between concepts. On data work the sharpest ones are almost
always about **grain and time**: what happens to the row when an order line is partially
returned? When a customer merges with another? When a late-arriving fact lands after the
period closed?

### Cross-reference with the code *and* the data

When the user states how something works, check whether the code agrees, and surface any
contradiction: "The model dedupes on `order_id`, but you just said an order can appear
twice with different versions -- which is right?"

**A definition that makes a checkable claim is not settled until it is checked against real
data.** "One row per order line", "customer_id is unique in the dimension", "returns are
excluded" -- those are queries, not opinions. Run them where you have read access (dispatch
the platform expert -- `fabric-cli-expert`, `databricks-expert`, `bigquery-expert` -- if one
is installed) before writing the term down as settled. Where you cannot, write the term
down and mark it explicitly as unverified rather than silently asserting it.

### Update GLOSSARY.md inline

When a term is resolved, update `GLOSSARY.md` right there. Don't batch these up -- capture
them as they happen. Use the format in [glossary-format](./references/glossary-format.md).

`GLOSSARY.md` is a glossary and nothing else. Keep implementation detail out of it: no
table names, no SQL, no column lists, no pipeline mechanics. If you're tempted to write
"stored in `gold.dim_customer` as SCD2", that belongs in the model's own documentation or
an ADR, not here.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** -- the cost of changing your mind later is meaningful.
2. **Surprising without context** -- a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** -- there were genuine alternatives and you picked one.

If any of the three is missing, skip the ADR. Use the format in
[adr-format](./references/adr-format.md).

## How this fits the rest of RAID

- `map-repo` maps a repo's architecture and conventions into AGENTS.md. Domain vocabulary
  is **not** its job: it should point at `GLOSSARY.md`, not copy terms into AGENTS.md. Two
  homes for the same term is how they drift apart.
- `raid-mode` and `wayfinder` *consume* the glossary -- units, tickets and models use its
  terms. They do not maintain it; that is this skill.
- On the full pipeline, `ingest-requirements` and `design-data-model` (both in
  `raid-greenfield`, when installed) surface most of the terms worth capturing. Run this
  skill alongside them rather than after.
