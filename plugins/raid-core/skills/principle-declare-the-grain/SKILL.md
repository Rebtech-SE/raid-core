---
name: principle-declare-the-grain
description: "Use before writing any model, fact or dimension, and whenever a join or aggregate changes what a row means. Say what one row is, in business terms, and prove it with a uniqueness test."
disable-model-invocation: true
---

# Declare the Grain

**State what one row of this table means, in a single sentence, before you write a line of
it.** "One row per order line." "One row per customer per day." "One row per shipment event."

Grain is the most expensive thing in a warehouse to change. Every downstream join,
aggregate, test and report is built on the assumption, and the assumption is usually
implicit -- which is why it is usually wrong somewhere.

## Apply it

- **Write the grain down where the model lives** -- the model's `schema.yml` description,
  the notebook header. Not in a plan, not in a ticket: next to the thing it describes.
- **Prove it, don't assert it.** A grain claim is a uniqueness test. Add it as one
  (`unique` on the key or key combination) in the same unit that creates the model. A grain
  with no test is a comment.
- **Name the grain change at every join and aggregate.** A join to a many-side table
  changes the grain; so does a window function that emits one row per partition. If the
  output grain differs from the input grain, say so in the code.
- **Two definitions of the same word means two grains.** When finance's "order" is a
  header and logistics' "order" is a shipment, you have two tables, not one with a flag.
  Settle the term with `domain-modeling` first.

## The failure it prevents

Silent fan-out. A join adds rows, the sum doubles, and nothing errors -- the pipeline is
green and the number is wrong. Nobody finds it until someone reconciles against the source
system, which is the other half of this: see `principle-reconcile-against-source`.

Related: `kimball-dimensional-modeling` (the four-step design process starts with grain),
`data-quality-checks`, `domain-modeling`.
