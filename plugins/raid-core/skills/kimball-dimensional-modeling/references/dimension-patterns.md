# Dimension Patterns

The dimension shapes Kimball warehouses rely on. Star schema DDL, SCD merge code, and
date-dimension generation are already covered by `medallion-architecture`'s
`references/gold-patterns.md` and by `scd-pattern` -- this file covers the modeling
decisions those do not.

## Conformed dimensions

One physical table per dimension, shared by every fact that needs it. This is the
integration mechanism of the whole architecture, not an optimisation.

- Surrogate keys minted once, in the dimension
- Attribute definitions agreed centrally, changed deliberately
- A **shrunken** conformed dimension is a strict subset -- a month-grain `dim_date` for
  a monthly snapshot fact, or a brand-grain `dim_product` for a planning fact. Legal
  precisely when the shared attributes match exactly; a shrunken dimension that renames
  or redefines an attribute is a fork, not a rollup.

Conformance is a contract across teams. When two teams need different definitions of
"active customer", the answer is two clearly named attributes on one dimension, not two
dimensions.

## Role-playing dimensions

One physical dimension used in several roles by the same fact: order date, ship date,
and due date all point at `dim_date`.

Implement as views or aliases over the single physical table -- `dim_order_date`,
`dim_ship_date` -- so BI tools and joins stay unambiguous while there is still one
table to maintain. Never copy the table per role.

## Degenerate dimensions

An operational identifier with no attributes of its own: order number, invoice number,
ticket id. Keep it as a column on the fact table. Creating a dimension table whose only
column is its own key adds a join and no information.

They are useful: grouping by order number on an order-line-grain fact is how you get
back to order-level questions without a second fact table.

## Junk dimensions

Low-cardinality flags and indicators -- order status, payment type, shipping priority,
gift-wrap flag -- bundled into one small dimension rather than scattered as many tiny
ones or as raw flags on the fact.

Build it as the set of combinations that actually occur (not the cartesian product,
which is mostly empty). Typically a few hundred rows. It keeps the fact narrow and
gives analysts one obvious place to filter.

## Bridge tables

For genuine many-to-many between a fact and a dimension: a patient visit with several
diagnoses, a sale attributed to several promotions, an account with several holders.

The fact points at a group key; the bridge maps that group to its members. Where
double-counting matters, carry a **weighting factor** on the bridge that sums to 1
across the group, so a correctly-weighted allocation is available alongside the
unweighted count.

Bridges are the correct answer to a many-valued relationship. The wrong answers, both
common: putting the many-valued attribute on the fact (multiplies measures), or
inventing `diagnosis_1`, `diagnosis_2`, `diagnosis_3` columns (breaks the moment there
is a fourth).

## Mini-dimensions

When a large dimension has a handful of rapidly changing attributes, SCD2 on the whole
row produces a version explosion -- millions of rows differing by one attribute.

Split the volatile attributes into a small mini-dimension, banded where continuous
(age band, income band, score band rather than raw values), and have the fact carry
foreign keys to both the base dimension and the mini-dimension. The base dimension
stays stable; the volatile combination is picked up per fact row.

This is Kimball's Type 4. It trades a little query complexity for a dimension that
stays a sane size.

## The date dimension

The universal conformed dimension. Build it once, generate it, share it everywhere.

- Generate rows for the full range the warehouse will ever need, past and future
- Carry every calendar attribute analysts ask for -- fiscal period, quarter, week,
  holiday flags, day-of-week, period-end flags -- so nobody writes date arithmetic in
  a report
- Use a readable surrogate key (`20260818`) rather than a sequence; it makes partition
  pruning and debugging easier
- Include reserved rows for unknown and not-applicable dates
- Where a time-of-day grain is needed, model it as a *separate* `dim_time` at second or
  minute grain -- never explode the date dimension by 86,400

Generation code is in `medallion-architecture`'s `references/gold-patterns.md`.

## Unknown and not-applicable members

Every dimension needs reserved members with fixed surrogate keys -- conventionally `-1`
for unknown and `-2` for not applicable.

Facts then never carry NULL foreign keys, inner joins never silently drop rows, and a
late-arriving dimension row can be resolved later by updating the fact's key rather
than by re-running the load. Rows that cannot be resolved at all go to the dead-letter
queue with their source key preserved -- see `dead-letter-queue`.
