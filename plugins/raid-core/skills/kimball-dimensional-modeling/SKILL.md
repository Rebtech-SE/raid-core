---
name: kimball-dimensional-modeling
description: >-
  Triggers: 'Kimball', 'dimensional model', 'bus matrix', 'conformed dimensions', 'star
  schema warehouse', 'bottom-up', 'declare the grain', 'fact table design', 'business
  process warehouse'. Kimball dimensional warehouse methodology: the conformed-dimension
  bus architecture, the four-step design process, grain discipline, fact and dimension
  patterns, and staging-to-presentation layering.
---

# Kimball Dimensional Modeling

Enterprise data warehouse methodology following Ralph Kimball's bottom-up approach:
model one business process at a time as a star schema, and integrate the whole
warehouse through **conformed dimensions** shared across those stars -- the *bus
architecture*. There is no normalized enterprise core; the dimensional models **are**
the warehouse.

## When to Use This Skill

Use this skill when users ask about:

- **Dimensional warehouse**: "How do I model this as a star schema warehouse?"
- **Bus architecture / bus matrix**: "How do the marts stay consistent without a core?"
- **Grain**: "What should the grain of this fact table be?"
- **Fact design**: "Transaction, snapshot, or accumulating snapshot?"
- **Dimension patterns**: "Role-playing / junk / degenerate / bridge dimensions"
- **Kimball vs Inmon vs medallion**: "Which warehouse methodology should I use?"

## Kimball vs the other RAID architectures

RAID supports three architecture styles; the one a repo uses is named in the
architecture doc its `AGENTS.md` points to, or shows in its layout (with no signal, medallion). `design-architecture` (in `raid-greenfield`) owns the choice on the
full pipeline and carries the full trigger
table -- this is the short version:

| Style | Core idea | Reach for it when |
|---|---|---|
| **Medallion** (default) | Bronze / Silver / Gold lakehouse layering | Fast, iterative analytics; lakehouse-native platform; a single team |
| **Inmon** | 3NF enterprise core, marts derived from it | Enterprise-wide single source of truth, heavy audit/lineage obligations |
| **Kimball** | Conformed-dimension bus; stars *are* the warehouse | BI/reporting is the product; deliver value per business process; analyst-facing model is the deliverable |

The honest distinction between Kimball and Inmon is **where integration happens**.
Inmon integrates in a normalized core and derives stars from it. Kimball integrates in
the *dimensions themselves* -- there is no core, and consistency is enforced by every
star reusing the same conformed dimension tables. Do not blend them by accident: a
"Kimball" warehouse that quietly grows a normalized integration layer is an Inmon
warehouse with extra steps, and should be recorded as such.

Kimball is **not** the same as "we have a star schema". Medallion Gold and Inmon marts
both produce stars. Kimball is the claim that those stars, integrated by a conformed
dimension bus, are the *entire* warehouse architecture.

## Core Principles

### 1. Business processes, not departments

Model what the business *does* -- an order placed, a shipment dispatched, a claim
settled -- not who reports on it. A process-shaped star serves every department that
asks about that process; a department-shaped mart serves one and duplicates the rest.

### 2. Conformed dimensions are the integration mechanism

A conformed dimension is one physical table, with one set of keys and one agreed
definition, reused by every fact that needs it. `dim_customer` in the sales star and
`dim_customer` in the support star are the *same table*, not two copies.

This is the load-bearing rule. Lose it and the warehouse silently becomes a pile of
disconnected marts that disagree with each other -- the exact failure Kimball's bus
architecture exists to prevent.

Rules:
- One physical table per conformed dimension, shared by all facts
- Surrogate keys minted once, in the dimension, never per fact or per mart
- Attribute definitions ("active customer", "fiscal period") centrally agreed
- A dimension may be conformed as a strict subset (a *shrunken* dimension) -- e.g. a
  month-grain `dim_date` rollup -- provided the shared attributes match exactly

### 3. Declare the grain, once, explicitly

The grain is the answer to "what does one row of this fact table mean?" Declare it in
one sentence before choosing dimensions or facts. An undeclared or drifting grain is
the single most common cause of double-counted measures.

Good grain statements are concrete: "one row per order line per shipment", not "sales
data". Every dimension must apply at the declared grain, and every measure must be
true at it.

### 4. Dimensions carry context, facts carry measurement

Facts hold numeric measures plus foreign keys to dimensions, and little else.
Descriptive text, hierarchies, flags, and groupings belong in dimensions -- where they
are cheap to store and fast to filter on. Wide, denormalized, text-rich dimensions are
correct here, not a smell.

### 5. The presentation layer is the contract

Analysts and BI tools consume the dimensional model directly. It is the product, not
an internal staging step -- so naming, grain, and attribute semantics are a public
interface and change like one.

## Architecture Overview

```
+------------+     +--------------+     +------------------------------------+
|            |     |              |     |   Presentation (dimensional)       |
|  Sources   |---->|   Staging    |---->|                                    |
|            |     |  (raw copy)  |     |   conformed dims + process stars   |
+------------+     +--------------+     +------------------------------------+
  ERP, CRM,        append-only,          dim_customer, dim_product, dim_date
  APIs, files      audit columns         fct_orders, fct_shipments, fct_returns
                                         (integrated by the conformed dim bus)
```

Two layers, not three. Staging is a raw landing zone with the same contract as Bronze;
everything else is the dimensional presentation layer. Where a project needs a place
for cleansing or de-duplication that is not yet dimensional, that is an ETL working
area -- keep it non-public and do not let BI tools read it.

### Layer Naming Conventions

| Layer | Databricks | Snowflake | Fabric | dbt |
|---|---|---|---|---|
| **Staging** | `staging.{source}_{entity}` | `RAW.{SOURCE}_{ENTITY}` | `staging_{source}_{entity}` | `stg_{source}__{entity}` |
| **Dimensions** | `dw.dim_{entity}` | `DW.DIM_{ENTITY}` | `dim_{entity}` | `dim_{entity}` |
| **Facts** | `dw.fct_{process}` | `DW.FCT_{PROCESS}` | `fct_{process}` | `fct_{process}` |

Facts are named for the **business process** (`fct_orders`, `fct_shipments`), never for
a report or a department (`fct_monthly_sales_report` is a defect).

## The Bus Matrix

The bus matrix is Kimball's architectural artifact: business processes down the rows,
conformed dimensions across the columns, an X where that process uses that dimension.
It *is* the warehouse plan -- it shows what exists, what is shared, and what order to
build in.

| Business process | Date | Customer | Product | Store | Employee | Supplier |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Orders | X | X | X | X | X | |
| Shipments | X | X | X | | | X |
| Returns | X | X | X | X | | |
| Inventory snapshot | X | | X | X | | X |

Read it two ways. Across a row: the dimensions one star needs. Down a column: every
star that must share that dimension -- which is exactly the list that breaks if someone
redefines it.

Build order falls out of the matrix: start with the process that is highest value and
whose dimensions are most reused, because those dimensions are then already conformed
for everything after it.

Fill the matrix during `design-architecture` and carry it into `architecture.html` (full
pipeline), or record it in the plan's modeling section on incremental work --
it is the Kimball equivalent of a tier inventory. See
[bus-matrix.md](references/bus-matrix.md) for construction, worked examples, and how
to keep it honest as the warehouse grows.

## The Four-Step Design Process

Apply to every fact table, in this order. The order matters -- each step constrains
the next.

1. **Select the business process.** One real activity the business performs and
   measures. If you cannot name the event, you are modeling a report, not a process.
2. **Declare the grain.** One sentence, atomic by default. Prefer the finest grain the
   source supports -- you can always aggregate up, never down.
3. **Identify the dimensions.** Everything that describes the context of that grain.
   Each must be single-valued at the grain; anything many-valued needs a bridge.
4. **Identify the facts.** The numeric measures true at that grain. Check each for
   additivity (fully / semi / non-additive) and record which is which.

See [dimensional-design-process.md](references/dimensional-design-process.md) for the
step-by-step with worked examples and the grain-check questions.

## Fact Tables

Four types, chosen by what the process looks like over time:

| Type | One row per | Use for | Additivity note |
|---|---|---|---|
| **Transaction** | Discrete event at a point in time | Orders, clicks, payments | Measures usually fully additive |
| **Periodic snapshot** | Entity per fixed period | Balances, inventory levels, headcount | Semi-additive -- never sum across time |
| **Accumulating snapshot** | Pipeline instance, updated in place | Order-to-cash, claims, onboarding | Row is revisited; milestone dates fill in |
| **Factless** | Occurrence with no measure | Attendance, eligibility, promotion coverage | Count rows; watch for the denominator case |

The accumulating snapshot is the one exception to insert-only discipline: its rows are
deliberately updated as the pipeline advances. Record that in the design so nobody
"fixes" it into an append-only table.

Star schema construction, fact table DDL, and pre-aggregation code are already covered
in `medallion-architecture`'s `references/gold-patterns.md` -- use it rather than
reinventing; the mechanics are identical, only the surrounding architecture differs.

## Dimensions

| Pattern | What it solves |
|---|---|
| **Conformed** | Shared meaning across stars -- the integration mechanism (see Core Principles) |
| **Role-playing** | One physical dimension used in several roles (order date / ship date / due date) via views or aliases |
| **Degenerate** | An operational identifier with no attributes (order number) -- keep it on the fact, no dimension table |
| **Junk** | Bundle low-cardinality flags and indicators into one small dimension instead of many tiny ones |
| **Bridge** | Many-to-many between a fact and a dimension (a patient with several diagnoses), with a weighting factor where double counting matters |
| **Mini-dimension** | Split rapidly changing attributes out of a large dimension to stop SCD2 row explosion |
| **Date** | The universal conformed dimension -- build it once, generate it, never derive dates ad hoc in queries |

See [dimension-patterns.md](references/dimension-patterns.md) for each with modeling
examples and the trade-offs.

### Slowly changing dimensions

Dimension history uses the framework-wide SCD columns and mechanics -- `_valid_from`,
`_valid_to`, `_is_current`, `_hash` -- defined in
[scd-pattern](../scd-pattern/SKILL.md). That skill covers merge logic, hash-based change
detection, and testing for Types 1, 2 and 3, which cover almost every real case.

Kimball's wider catalogue matters mainly as vocabulary in customer conversations:
Type 0 (retain original), Type 4 (history in a separate table -- the mini-dimension),
and Type 6 (a hybrid carrying both current and historical attributes on the row). If a
customer asks for Type 6, implement it as Type 2 plus a current-value column maintained
by the same merge -- do not invent a parallel mechanism.

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|---|---|---|
| Department-shaped facts | Duplicated logic; marts disagree | Model the business process, not the org chart |
| Undeclared or drifting grain | Double counting, unexplainable totals | Declare the grain in one sentence before modeling |
| Per-star dimension copies | Conflicting definitions; the bus breaks | One conformed table per dimension, shared |
| Summing a periodic snapshot across time | Nonsense totals | Mark semi-additive measures; average or take period-end |
| Normalized integration layer creeping in | It is now Inmon, undocumented | Either commit to Inmon and record it, or keep integration in the dimensions |
| Aggregate-only facts | Cannot drill down; new questions need new ETL | Keep atomic grain; add aggregates alongside, never instead |
| Snowflaking dimensions by reflex | Extra joins, analyst confusion, negligible storage win | Denormalize dimensions; snowflake only for a real, stated reason |
| BI reading staging | Bypasses conformance and history | Consumers read the presentation layer only |
| Smart surrogate keys | Meaning embedded in a key ages badly | Meaningless surrogate keys; business keys stay as attributes |

## Related Skills

- [scd-pattern](../scd-pattern/SKILL.md) - SCD mechanics and column conventions for dimension history
- [medallion-architecture](../medallion-architecture/SKILL.md) - alternative layered approach; its `gold-patterns.md` carries the star schema implementation code
- [inmon-data-warehouse](../inmon-data-warehouse/SKILL.md) - alternative top-down approach with a normalized core
- [data-quality-checks](../data-quality-checks/SKILL.md) - grain uniqueness, referential integrity, and conformance tests
- [build-ingestion-pipeline](../build-ingestion-pipeline/SKILL.md) - staging layer patterns
- [dead-letter-queue](../dead-letter-queue/SKILL.md) - handling rows that fail dimension lookup
- [data-platform-orchestration](../data-platform-orchestration/SKILL.md) - dimensions-before-facts load ordering

## References

- [Bus Matrix](references/bus-matrix.md) - construction, worked example, build sequencing, keeping it honest
- [Dimensional Design Process](references/dimensional-design-process.md) - the four steps with worked examples and grain checks
- [Dimension Patterns](references/dimension-patterns.md) - role-playing, junk, degenerate, bridge, mini-dimension, date
