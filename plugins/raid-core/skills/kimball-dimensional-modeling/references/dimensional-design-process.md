# The Four-Step Dimensional Design Process

Apply to every fact table, in order. Each step constrains the next, so doing them out
of order produces a model that has to be rebuilt.

## Step 1: Select the business process

A business process is an activity the organisation *performs and measures*, captured by
an operational system: an order is placed, a shipment leaves, a claim is settled, a
subscription renews.

Checks:
- Can you name the event and point at the system that records it? If not, you are
  modeling a report.
- Is it one activity? "Sales and returns" is two processes, two fact tables, sharing
  conformed dimensions.
- Would several departments ask questions of it? Good -- that is the sign of a process
  rather than a departmental view.

**Not a business process:** "Monthly management reporting", "the CFO dashboard",
"customer 360". Those are consumers of processes. Modeling them directly produces a
fact table that cannot answer the next question.

## Step 2: Declare the grain

State in one sentence what a single row means. Do this before choosing dimensions or
facts -- the grain determines both.

Good grain statements:
- "One row per order line."
- "One row per shipment per package."
- "One row per policy per month-end."
- "One row per candidate per stage transition."

Bad grain statements: "sales data", "one row per order" when the source is order lines,
"one row per customer per day, or per order, depending".

**Go atomic by default.** The finest grain the source supports is the flexible one --
you can aggregate up but never drill down. Pre-aggregated facts answer today's question
and block tomorrow's.

Grain checks:
- Can two source records collapse into one row? Then the grain is coarser than you
  said -- restate it or split them.
- Does every dimension apply to *every* row at this grain? A dimension that only
  sometimes applies means the grain is wrong or the dimension needs a not-applicable
  member.
- Is there a natural key at this grain? Its uniqueness is the test that guards it -- add
  it as a data-quality assertion, not a comment.

## Step 3: Identify the dimensions

Everything that describes the context of the grain: who, what, where, when, why, how.

- Each dimension must be **single-valued at the grain**. Many-valued relationships (a
  patient with several diagnoses, a sale with several promotions) need a bridge table --
  putting them on the fact silently multiplies measures.
- Reuse **conformed** dimensions from the bus matrix. Only create a new one when the
  matrix genuinely lacks it, and add it to the matrix in the same change.
- Prefer **wide and denormalized**. Storage is cheap; joins and analyst confusion are
  not.
- Give every dimension a **not-applicable / unknown member** with a reserved surrogate
  key (often `-1`), so facts never carry NULL foreign keys and inner joins do not drop
  rows.

## Step 4: Identify the facts

The numeric measures true at the declared grain. Anything not true at the grain belongs
in a different fact table.

Classify each measure's additivity and record it -- this is what stops a BI tool
producing a confidently wrong number:

| Additivity | Meaning | Example | Rule |
|---|---|---|---|
| **Fully additive** | Sums across every dimension | Sales amount, quantity | Sum freely |
| **Semi-additive** | Sums across some, not time | Account balance, inventory on hand | Never sum across time; average, or take period-end |
| **Non-additive** | Never meaningfully summed | Unit price, ratio, percentage | Store components; compute the ratio at query time |

Practical rules:
- Store the **components** of a ratio (numerator and denominator), not the ratio.
- Keep **degenerate dimensions** (order number, invoice number) on the fact -- an
  operational identifier with no attributes needs no dimension table.
- Do not park descriptive text on the fact because it was convenient. It belongs in a
  dimension.

## Worked example

**Step 1 -- process:** a customer places an order in the ecommerce platform.

**Step 2 -- grain:** one row per order line.

**Step 3 -- dimensions:** date (order date, role-playing with ship date), customer,
product, promotion, sales channel. Degenerate: order number. Basket-level promotions
that apply to several lines go through a bridge rather than onto the line.

**Step 4 -- facts:** quantity (fully additive), extended list price (fully additive),
discount amount (fully additive), extended net amount (fully additive), unit price
(non-additive -- derived at query time from net amount / quantity).

Note what did *not* happen: no "monthly revenue" measure, and no customer lifetime
value column. Both are computed from this atomic grain rather than baked into it.

## After the four steps

- Write the grain statement into `design.html` next to the entity. It is the single
  most useful line in the document.
- Add the grain uniqueness test as a data-quality assertion -- see `data-quality-checks`.
- Load **dimensions before facts** so every foreign key resolves; route unresolvable
  keys to the unknown member or the dead-letter queue, never silently drop them.
