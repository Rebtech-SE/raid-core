# The Bus Matrix

The bus matrix is the Kimball warehouse plan on one page: business processes as rows,
conformed dimensions as columns, a mark where a process uses a dimension. It is what
`architecture.html` carries for a Kimball engagement, in place of a medallion tier
inventory or an Inmon subject-area map.

## Why it exists

Kimball has no normalized core to enforce consistency, so consistency has to come from
the dimensions being genuinely shared. The matrix makes that shareability visible
*before* anything is built: a dimension used by five processes is a five-way contract,
and the matrix is where you notice that.

## Building it

1. **List the business processes.** Real activities the business performs and measures
   -- an order placed, a shipment dispatched, a payment received. Source them from the
   value chain, not from the reporting backlog. One process becomes one fact table.
2. **List the candidate dimensions.** The descriptive entities those processes share --
   date, customer, product, location, employee, supplier.
3. **Mark the intersections.** X where the process has that dimension at its grain.
4. **Read the columns.** Any dimension marked more than once must be conformed. That is
   your integration workload, and it is the part that fails silently if skipped.
5. **Read the rows.** Each row is a star's dimension list -- the input to step 3 of the
   four-step design process.

## Worked example: a distributor

| Business process | Date | Customer | Product | Warehouse | Employee | Supplier | Promotion |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Orders | X | X | X | | X | | X |
| Shipments | X | X | X | X | | | |
| Returns | X | X | X | X | | | |
| Inventory snapshot | X | | X | X | | X | |
| Purchase orders | X | | X | X | X | X | |

What it tells you:

- **Date, Product** appear in all five -- build and conform them first; everything
  depends on them.
- **Customer** spans Orders, Shipments, Returns. One definition of "customer" has to
  satisfy all three, including the awkward cases (a return from a customer who has
  since been merged into another account).
- **Promotion** touches one process. It does not need conforming yet, but it goes on
  the matrix so the next promotion-aware process inherits it rather than inventing one.
- **Inventory snapshot** has no Customer -- correct: stock on hand is not customer-
  scoped. An X there would signal a grain error.

## Build sequencing

Order the build by value against conformance leverage:

1. The process with the highest business value whose dimensions are most reused.
2. Then processes that reuse the dimensions already conformed -- these are cheap,
   because the expensive part is done.
3. Processes needing new dimensions come later, unless business value overrides.

The second star should be materially cheaper than the first. If it is not, the
dimensions from the first were probably not conformed properly.

## Keeping it honest

The matrix rots the moment it becomes documentation rather than a plan. Guard it:

- **Update it in the same change that adds a fact or dimension.** A star that is not on
  the matrix is invisible to the next person planning conformance.
- **A new column is an architectural event.** Adding a dimension used by one process is
  routine; adding one that overlaps an existing dimension's meaning is a fork of the
  bus, and needs a decision, not a merge.
- **Two columns that mean nearly the same thing** (`Customer` and `Account`) are the
  early form of the failure the bus exists to prevent. Resolve to one conformed
  dimension, or write down explicitly why they are genuinely different entities.
- **Never let a fact table quietly stop using a conformed dimension** and grow its own
  copy of those attributes. That is the bus breaking, and it shows up later as two
  reports that disagree.

## Where it lives

- **`architecture.html`** -- the matrix itself, in the layer inventory section, as the
  Kimball view of what will be built.
- **`design.html`** -- the per-star detail: grain statement, dimension list, fact list,
  and load order (dimensions before facts).
