# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.

Create the `docs/adr/` directory lazily -- only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

That's it. An ADR can be a single paragraph. The value is in recording *that* a decision was
made and *why*, not in filling out sections.

## Optional sections

Only include these when they add genuine value. Most ADRs won't need them.

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`):
  useful when decisions are revisited.
- **Considered Options**: only when the rejected alternatives are worth remembering.
- **Consequences**: only when non-obvious downstream effects need to be called out.

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When to offer an ADR

All three of these must be true:

1. **Hard to reverse** -- the cost of changing your mind later is meaningful.
2. **Surprising without context** -- a future reader will look at the models and wonder
   "why on earth did they do it this way?"
3. **The result of a real trade-off** -- there were genuine alternatives and you picked one
   for specific reasons.

If a decision is easy to reverse, skip it -- you'll just reverse it. If it's not surprising,
nobody will wonder why. If there was no real alternative, there's nothing to record beyond
"we did the obvious thing."

### What qualifies on a data platform

- **Architecture style.** "Medallion, not a Kimball core." "The gold layer is
  Kimball-dimensional; bronze and silver are not modelled." Also the `architecture:` key in
  `.raid/config.yaml` when it deviates from the default.
- **Grain decisions.** "The sales fact is at order-line grain, not shipment grain, because
  returns reference the line." Grain is the most expensive thing in a warehouse to change.
- **History and SCD choices.** "`dim_customer` is SCD2 on address only; name changes
  overwrite." Whoever inherits this will otherwise assume full history.
- **Layer boundary and ownership.** "Business logic never lives in bronze." "The Sales
  context owns `dim_product`; other domains reference it, never redefine it." The explicit
  no-s are as valuable as the yes-s.
- **Load and refresh patterns that constrain everything downstream.** Full reload vs
  incremental with a watermark, late-arriving-fact handling, whether the platform promises
  restatement or append-only history.
- **Technology choices that carry lock-in.** Warehouse engine, orchestrator, ingestion
  framework, transformation tool. Not every library -- the ones that would take a quarter to
  swap out.
- **Deliberate deviations from the obvious path.** "Materialized as a view, not a table,
  because the source is already columnar and the cost is in the scan." Anything where a
  reasonable reader would assume the opposite -- these stop the next engineer from "fixing"
  something that was deliberate.
- **Constraints not visible in the models.** "PII cannot leave the EU tenant." "The source
  API allows 2 requests/second, which is why ingestion is chunked the way it is."
- **Definitions that were contested and settled.** When two departments wanted different
  numbers under the same name and one won, record who lost and why -- otherwise it reopens
  every quarter. The term itself goes in `GLOSSARY.md`; the *decision* goes here.
