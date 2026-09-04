---
name: principle-model-the-domain
description: "Use when writing stateful logic, or when code branches a lot or repeats a shape assumption across files. Encode the domain in a structure instead of scattered conditionals."
disable-model-invocation: true
---

# Model the Domain

Encode the real domain in a data structure instead of scattering it across conditionals.

**Why:** Scattered booleans, repeated shape assumptions, and branching spread across files are accidental complexity. A structure that matches the domain makes invalid states unrepresentable and deletes branches. Choosing it at write time is cheap; recovering it later reads as a refactor and gets deferred.

**Reach for structures like these:**

- A state machine instead of scattered booleans, phases, or lifecycle checks.
- A typed object/model instead of loose parameters or repeated shape assumptions.
- A map, registry, lookup table, or discriminated union instead of branching spread across files.
- A reducer or command/event model instead of ad hoc state mutations.
- A module organized around one body of domain knowledge instead of a sequence such as load, validate, transform, and save. Execution order is not ownership.
- A small module boundary that gathers repeated behavior, ownership, or invariants.
- A queue, cache, index, graph/tree, or normalized collection where the data access pattern calls for it.
- Any other structure that fits. The list above covers the common cases only. When none fits, work out what the code must never allow and how the data gets read, then find the structure that encodes exactly that.

Do not force an abstraction. Prefer boring code if the current shape is already clear, local, and unlikely to grow. Be skeptical of an abstraction that adds indirection without removing branches, duplicated rules, invalid states, or lifecycle risk.

**In a warehouse, the structure is the model.** The equivalents:

- A **dimension with an SCD type** instead of a `CASE` chain reconstructing history.
- A **conformed dimension** instead of the same lookup re-derived in four marts.
- A **declared grain** with a uniqueness test instead of a `DISTINCT` defending a join
  (`principle-declare-the-grain`).
- A **seed or mapping table** instead of a hard-coded `WHEN ... THEN` list that someone
  must edit in three models when the business adds a category.
- A **typed staging contract** -- explicit columns and casts at the bronze/silver boundary
  -- instead of every downstream model re-parsing the same raw string.
- A **layer** instead of a flag: if a query needs a `WHERE is_current = 1` everywhere, the
  current view belongs in its own model.

The tell that you skipped this is a new feature that grows an existing if/else chain by one more branch, or a second boolean that must stay in sync with the first. Temporal decomposition is another tell. Phase-named modules repeat the same domain rules across steps.
