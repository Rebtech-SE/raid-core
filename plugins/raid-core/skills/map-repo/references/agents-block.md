# The map-repo managed block

`map-repo` writes the repo's operative architecture and conventions into a **delimited
managed block** in the root instruction file (`AGENTS.md`, or the substantive file when a
shim/symlink is in play). This reference defines the marker, the section schema, and the
merge behavior. Render the block from this shape; keep the markers exact.

## Marker format

The block is delimited by an HTML-comment sentinel pair so it is invisible in rendered
markdown and trivially machine-locatable. Blocks written before 2026-08-29 use the skill's
former name (`raid-prime:start` / `raid-prime:end`) -- readers must match either pair, and
a rewrite migrates the old pair to the new one in place rather than adding a second block:

```markdown
<!-- prime-repo:start -->
## Repo map (maintained by map-repo)

...block content...
<!-- prime-repo:end -->
```

- The sentinels are the contract. The write replaces only the text **between** them.
- There is exactly **one** block per file. A re-run refreshes its content in place; it
  never appends a second block.
- The `## Repo map (maintained by map-repo)` heading sits inside the block (between the
  sentinels) and signals to a human reader that the section is generated.

## Section schema

The block carries two parts and nothing else. Keep it terse - this is read every session.

```markdown
<!-- prime-repo:start -->
## Repo map (maintained by map-repo)

### Architecture
- **Stack:** <warehouse/lakehouse, orchestration, transformation tool, key versions>
- **Layering:** <tier structure (bronze/silver/gold or staging/intermediate/marts); directory-to-responsibility map>
- **Key models & grain:** <the important fact/dimension tables, their grain, SCD usage>
- **Sources & ingestion:** <sources, tools, cadence, incremental approach>
- **Data flow:** <one line, or a small mermaid flowchart only when the flow is non-trivial>

### Conventions & standards
- **Naming:** <table/column/file naming patterns>
- **Layering rules:** <what belongs in each tier; what must not cross>
- **Testing:** <dbt tests / DQ assertions / unit-test approach the repo uses>
- **Config & secrets:** <how they are managed>
- **Commits & branches:** <conventional-commit usage, branch/PR workflow if stated>
- **Stated rules:** <rules the repo already documents in CLAUDE.md/AGENTS.md/README worth surfacing operatively>
<!-- prime-repo:end -->
```

Drop any sub-bullet the repo genuinely doesn't have rather than padding it. Include the
mermaid data-flow line only when prose can't carry the flow at a glance.

**No tech debt here.** The block records how the repo *is* built and how to work with the
grain of it. Problems go to the tech-debt report (`references/techdebt-report.md`). The
only debt-adjacent content allowed is an operative consequence that changes agent behavior
- e.g. "the `customer` dim in `models/marts/` is the source of truth; the legacy
`dim_cust` is deprecated" - never a findings list.

## Merge behavior (the byte-level contract)

- **First run, the repo has no instruction file at all:** create `AGENTS.md` whose entire
  content is the block (sentinels included). That is the whole step -- do not create a
  `CLAUDE.md`, a symlink, or any other harness-specific file. `AGENTS.md` is the open
  standard; a symlink does not survive a Windows checkout, and a second file is one more
  thing to drift. Add one only if the user explicitly asks.
- **First run, the file exists with hand-authored content and no prior block:** append the
  block at the end of the file (after one blank line), leaving every existing line
  unchanged. Ask once before writing (see SKILL.md Phase 2a).
- **Re-run, a prior block exists:** replace only the text between the existing sentinels.
  Do not touch the sentinels' position, the surrounding content, or the file's other
  formatting.
- **Symlink/shim:** when `CLAUDE.md` is a symlink to `AGENTS.md` (RAID repos) or one file
  `@`-includes the other, edit the substantive file only; the symlink/shim carries the
  change automatically. Never create a competing second file.
- **Two independent instruction files:** when the repo genuinely maintains more than one
  (e.g. a hand-authored `AGENTS.md` *and* a `.github/copilot-instructions.md` that is not a
  shim), the block goes in **one** file -- `AGENTS.md` if it is among them, otherwise the
  substantive one -- and the others get a single pointer line
  (`See AGENTS.md for the repo's architecture and conventions.`) if they don't already say
  something equivalent. Never write the block twice; two copies drift.

The discipline is: **scope the edit to exactly the managed region**. A blanket rewrite of
the file is how hand-authored conventions get silently corrupted.

## Worked example

Starting file `AGENTS.md` (hand-authored, no prior block):

```markdown
# Acme Data Platform

Internal notes for the analytics warehouse. Ask #data-eng before touching prod.
```

After the first `map-repo` run:

```markdown
# Acme Data Platform

Internal notes for the analytics warehouse. Ask #data-eng before touching prod.

<!-- prime-repo:start -->
## Repo map (maintained by map-repo)

### Architecture
- **Stack:** BigQuery + dbt 1.8, orchestrated by Cloud Composer (Airflow 2.7)
- **Layering:** staging -> intermediate -> marts under `models/`; sources in `models/staging/_sources.yml`
- **Key models & grain:** `fct_orders` (one row per order line), `dim_customer` (SCD2)
- **Sources & ingestion:** Fivetran -> raw datasets, daily; incremental models keyed on `_loaded_at`
- **Data flow:** raw (Fivetran) -> staging -> intermediate -> marts -> Looker

### Conventions & standards
- **Naming:** `stg_`, `int_`, `fct_`, `dim_` prefixes; snake_case columns
- **Layering rules:** staging is 1:1 with sources, no joins; business logic only in intermediate+
- **Testing:** dbt `unique`/`not_null` on every primary key; `dbt build` gates CI
- **Config & secrets:** dbt profiles via env vars; no secrets in repo
- **Commits & branches:** conventional commits; PRs target `main`
- **Stated rules:** see `README.md` - never query `raw` datasets directly from Looker
<!-- prime-repo:end -->
```

Every line above the first sentinel is identical to the original. A second run rewrites
only the lines between the sentinels.
