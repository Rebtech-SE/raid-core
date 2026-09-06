# Data map: shape and a worked example

The map lives at `<skills-dir>/verify-<platform>/data-map/`: a `README.md` index plus one
file per consumer-facing mart or domain. Written from the **consumer's** point of view --
what the thing means and what makes it right -- not from the implementation's.

## README.md (the index)

```md
# Data map: <platform name>

What this platform delivers, and how to prove each piece is correct. One file per
consumer-facing mart. Verifying a change to any model means running the proof for every
mart downstream of it, not just the one you edited.

| Mart | Grain | Read by | Proof |
| --- | --- | --- | --- |
| [Sales](./sales.md) | one row per order line per day | Finance dashboard, Sales Power BI model | parity vs `erp.order_lines` |
| [Inventory](./inventory.md) | one row per SKU per location per day | Ops report, replenishment job | on-hand ties to `wms.stock_snapshot` |
| [Customer](./customer.md) | one row per customer version (SCD2) | CRM export, Sales model | one current row per customer |

**Not mapped yet:** <marts that exist but have no proof -- name them; an unmapped mart is
an unverified mart, and saying so is better than implying coverage.>
```

## One mart file

```md
# Sales

## What it means

Completed customer sales at order-line level, net of returns and discounts, excluding tax
and freight. "Net sales" here is the `GLOSSARY.md` definition -- Finance's closed-period
restatement is a *different* number and lives in the Finance mart. They disagree between
close and restatement, on purpose.

## Grain

One row per order line per business date. A partially returned line keeps one row; the
returned quantity is a measure, not a second row.

## Who reads it

- `Sales.pbix` semantic model (Direct Lake) -- breaks on a column rename
- The Finance dashboard's revenue tile
- `int_margin_by_category`, downstream in this warehouse

## The query that proves it right

Run all four. Any failure is a real failure, not a threshold to tune.

**1. Grain holds** -- must return zero rows.

```sql
select order_line_id, business_date, count(*) as n
from gold.fct_sales
group by 1, 2
having count(*) > 1;
```

**2. Row parity against the source** -- the ERP is the authority, not another model
derived from the same load.

```sql
-- expect: source_lines = mart_lines for the window
select
  (select count(*) from erp.order_lines
    where order_date between '2026-08-01' and '2026-08-31' and status = 'COMPLETED') as source_lines,
  (select count(*) from gold.fct_sales
    where business_date between '2026-08-01' and '2026-08-31') as mart_lines;
```

**3. Measure totals tie** -- within rounding, and state the tolerance you accept and why.

```sql
-- expect: abs(diff) < 0.01 (cent rounding on the discount allocation)
select
  sum(s.net_amount) - sum(e.line_total - e.discount_total) as diff
from gold.fct_sales s
join erp.order_lines e on e.order_line_id = s.order_line_id
where s.business_date between '2026-08-01' and '2026-08-31';
```

**4. No orphans** -- every FK resolves, or the orphans are counted and explained.

```sql
select count(*) as orphaned_customers
from gold.fct_sales s
left join gold.dim_customer d
  on d.customer_key = s.customer_key
where d.customer_key is null;
```

## Gotchas

- Late-arriving returns land up to 5 days after the order date, so a parity check on
  yesterday will show a difference that is correct. Reconcile on a window closed at least a
  week ago.
- `dim_customer` is SCD2. Join on `customer_key`, never `customer_id`, or the fact fans out
  across historical versions -- this has caused a doubled revenue number before.
```

## Rules for writing one

- **The proof queries must run as written**, against the real object names in this
  warehouse. A query with a placeholder table name has not been tested and will not be run.
- **State the expected result**, not just the query. "Must return zero rows", "expect the
  two counts to match", "abs(diff) < 0.01 because of cent rounding". A query whose passing
  condition is unstated is a query whose failure nobody notices.
- **Compare against the source system** where one exists. Comparing a mart against another
  model built from the same load proves only that the load was consistent, not correct.
- **Gotchas are the highest-value section.** Late arrivals, SCD joins, timezone boundaries,
  the partition that must be filtered -- these are what make a correct-looking check wrong,
  and they are exactly what the next agent will not know.
- Keep it to what a consumer would recognise. Intermediate models are implementation and do
  not get map files; they get tests.
