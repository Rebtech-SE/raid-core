# The architecture doc map-repo keeps

The architecture doc says how the platform is built. It is read when a task needs it --
placing a new model, tracing a number, reviewing a change that crosses a layer -- not every
session, which is why it lives in its own file and `AGENTS.md` only points at it.

`map-repo` keeps the doc the repo already has (`ARCHITECTURE.md`, `docs/architecture.md`,
`docs/architecture/`) current, or creates `docs/architecture.md` when there is none. It
never edits `docs/artifacts/architecture.html`, which is a signed-off design deliverable.

## What it covers

Describe what the code does today, not what it was meant to do. Prefer tables and one
diagram to prose; drop a section the repo genuinely doesn't have.

- **Overview** -- two or three sentences: what the platform produces and for whom.
- **Stack** -- warehouse or lakehouse, transformation tool, orchestration, BI, with the
  versions that matter.
- **Architecture style and layers** -- name the style: medallion, Inmon EDW or Kimball
  dimensional. `review-changes` picks its layering reviewer from this line, so name it even
  when it is medallion. Then each layer: its directory, its responsibility, what it reads
  from.
- **Key models and grain** -- the facts and dimensions that matter, one row each: model,
  grain, SCD type, main consumers.
- **Sources and ingestion** -- each source, the tool that lands it, cadence, and the
  incremental approach.
- **Data flow** -- a mermaid flowchart when the flow is not obvious from the layer table;
  otherwise one line.
- **Schedules and dependencies** -- the jobs and their order, upstream systems, sibling
  repos, downstream consumers with a deadline.

What stays out: conventions (`codify-conventions` enforces them and keeps `CONVENTIONS.md`),
business definitions (`GLOSSARY.md`), decisions and their reasons (`docs/adr/`), and the
tech-debt findings list (`docs/audit/`). Point at those instead.

## Staying current

- A re-run compares the doc with the code and changes only what drifted: a new layer, a
  model whose grain changed, a source that moved.
- A hand-maintained doc keeps its structure and voice. Add what is missing where it
  belongs, and propose corrections rather than rewriting sections.
- Every path is repo-relative.

## Example

```markdown
# Architecture

Sales and customer marts for the Looker estate, rebuilt nightly from the ERP and the web
shop.

## Stack

BigQuery, dbt 1.8, Cloud Composer (Airflow 2.7), Fivetran, Looker.

## Architecture style and layers

Kimball dimensional: staging and intermediate models feed conformed dimensions and facts in
`models/marts/`; there is no normalized core.

| Layer | Directory | Responsibility | Reads from |
|---|---|---|---|
| Staging | `models/staging/` | one model per source table, renamed and typed | Fivetran raw datasets |
| Intermediate | `models/intermediate/` | joins and business logic shared by marts | staging |
| Marts | `models/marts/` | conformed dimensions and facts | staging, intermediate |

## Key models and grain

| Model | Grain | SCD | Consumers |
|---|---|---|---|
| `fct_orders` | one row per order line | - | Looker sales explores |
| `dim_customer` | one row per customer version | Type 2 | every mart |

## Sources and ingestion

| Source | Tool | Cadence | Incremental on |
|---|---|---|---|
| ERP (`erp_prod`) | Fivetran | daily 02:00 | `_fivetran_synced` |
| Web shop (`shop_events`) | Fivetran | hourly | `event_ts` |

## Schedules and dependencies

The Composer DAG `dbt_build` runs at 04:00 and must finish before the 06:00 Looker PDT
refresh. Reverse ETL to the CRM lives in the sibling repo `acme/crm-sync` and reads
`dim_customer`.
```
