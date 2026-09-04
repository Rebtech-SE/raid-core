# GLOSSARY.md Format

## Structure

```md
# {Context Name}

{One or two sentence description of what this context is and why it exists.}

## Language

**Order**:
A customer's committed request for goods, at the header level. One order has one or more
order lines.
_Avoid_: Purchase, transaction, basket

**Order Line**:
A single product at a single price on an order. The grain of most sales facts.
_Avoid_: Item, row, SKU line

**Net Sales**:
Gross sales less returns and discounts, excluding tax and freight.
_Avoid_: Sales, revenue, turnover

**Active Customer**:
A customer with at least one non-returned order in the trailing 12 months.
_Avoid_: Live customer, engaged customer
```

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the best one and
  list the others under `_Avoid_`. On a data platform the `_Avoid_` list is doing most of
  the work -- it is what stops the third team inventing a fourth name for net sales.
- **Keep definitions tight.** One or two sentences max. Define what it IS, not what it does.
- **State the grain when a term has one.** "One row per order line" is the single most
  useful sentence in a data glossary, and the one most often left implicit.
- **A definition with a threshold or a filter in it is a claim about the data.** Verify it
  against real data before writing it as settled, or mark it unverified.
- **Only include terms specific to this project's context.** General data-engineering
  concepts (SCD2, watermark, incremental load, backfill) do not belong here even if the
  project uses them constantly -- they belong to the wider practice, not this business.
  Before adding a term, ask: is this a concept unique to this business, or is it something
  any warehouse would have? Only the former belongs.
- **Group terms under subheadings** when natural clusters emerge -- often by subject area
  (Sales, Supply Chain, Finance). If all terms belong to a single cohesive area, a flat
  list is fine.
- **No implementation detail.** No table names, no SQL, no column lists.

## Single vs multi-context repos

**Single context (most repos):** one `GLOSSARY.md` at the repo root.

**Multiple contexts:** a `GLOSSARY-MAP.md` at the repo root lists the contexts, where they
live, and how they relate. On a data platform the contexts are usually subject areas, and
the relationships are usually conformed dimensions and shared keys:

```md
# Context Map

## Contexts

- [Sales](./models/sales/GLOSSARY.md): orders, returns and the revenue measures
- [Supply Chain](./models/supply_chain/GLOSSARY.md): purchase orders, inbound, stock on hand
- [Finance](./models/finance/GLOSSARY.md): the ledger view and period close

## Relationships

- **Sales <-> Supply Chain**: share the conformed `dim_product` and `dim_date`
- **Sales -> Finance**: Finance restates Sales' net sales on a closed-period basis; the
  two disagree intentionally between close and restatement
- **Supply Chain -> Finance**: stock valuation is derived from Supply Chain's on-hand
  quantities at Finance's own cost basis
```

The skill infers which structure applies:

- If `GLOSSARY-MAP.md` exists, read it to find contexts.
- If only a root `GLOSSARY.md` exists, single context.
- If neither exists, create a root `GLOSSARY.md` lazily when the first term is resolved.

When multiple contexts exist, infer which one the current topic relates to. If unclear, ask.
Where two contexts genuinely define the same word differently, that is a fact about the
business, not an error -- record both and note the disagreement in the map's Relationships.
