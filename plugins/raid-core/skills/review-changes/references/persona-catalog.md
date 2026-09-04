# Persona Catalog

RAID's data-platform reviewer personas, organized into always-on and conditional
layers, plus CE-style synthesis agents. The `review-changes` orchestrator uses this
catalog to select which reviewers to spawn for each review.

> **Build status:** this catalog is the contract the persona *agent files*
> (`raid-core/agents/raid-*-reviewer.md`) conform to, and the selection logic the
> orchestrator applies. Until an agent file exists, the orchestrator skips that persona
> and notes it in Coverage.

## Always-on (6 personas)

Spawned on every review regardless of diff content (subject to the review depth --
Lean trims this floor; see `## Review depth` below).

**Persona agents (structured JSON output, conform to `findings-schema.json`):**

| Persona | Agent | Focus |
|---------|-------|-------|
| `correctness` | `raid-correctness-reviewer` | Logic errors in transforms: grain fan-out, wrong filters, null propagation, aggregation mistakes, window frames, date/tz bugs, intent-vs-implementation mismatch |
| `testing` | `raid-testing-reviewer` | Missing/weak dbt tests + DQ assertions, untested branches, reconciliation gaps, vacuous tests |
| `maintainability` | `raid-maintainability-reviewer` | Model/notebook structural quality, duplicated transforms, CTE/cell sprawl, wrong-layer logic, dead models, premature abstraction |
| `project-standards` | `raid-project-standards-reviewer` | `CLAUDE.md`/`AGENTS.md` compliance -- repo-relative paths, conventional commits, provider-agnostic git workflow (GitHub-first default; flag single-host hardwiring), naming |
| `data-integrity` | `raid-data-integrity-reviewer` | Nulls/dupes on keys, referential integrity, audit columns (`_ingestion_timestamp`, `_source_system`, `_batch_id`), idempotency/re-run safety, grain preservation, merge/transaction atomicity |
| `compliance-traceability` | `raid-compliance-traceability-reviewer` | Requirements <-> implementation: does the build cover what the plan/the prestudy specified (the heart of the old `/review-compliance`) |


## Conditional (8 personas + 1 synthesis agent)

Spawned when the orchestrator identifies relevant patterns in the diff. The
orchestrator reads the full diff and reasons about selection -- this is agent
judgment, not keyword matching. These fire on their own diff signals in **either**
review depth -- the depth only trims the always-on floor, never a warranted conditional.

**Persona agents:**

| Persona | Agent | Select when the diff touches... |
|---------|-------|---------------------------------|
| `scd-correctness` | `raid-scd-correctness-reviewer` | Slowly-changing-dimension logic -- a dimension build, an SCD2 merge, effective-dating columns (`_valid_from`/`_valid_to`/`_is_current`), surrogate keys, change detection. Also spawn (with `data-integrity`) on any diff touching **incremental predicates/anti-joins** -- their failure shapes (NOT IN NULL-poison, partial event-identity keys) are latent: every build verification passes while current data is clean, and only multi-perspective review catches them |
| `pipeline-reliability` | `raid-pipeline-reliability-reviewer` | Ingestion/orchestration code, retries, dead-letter handling, incremental watermarks, scheduling, source-freshness, error handling in pipelines |
| `cost-perf` | `raid-cost-perf-reviewer` | Large scans, missing partition/cluster pruning, small-file/shuffle problems, broadcast joins, `SELECT *` on wide tables, warehouse sizing, full rebuilds where incremental is possible |
| `data-security` | `raid-data-security-reviewer` | PII columns, secrets/credentials, access scopes/grants, masking, GDPR-relevant data (e.g. min-prilla, crm), cross-tenant exposure |
| `data-contract` | `raid-data-contract-reviewer` | Table/view schema changes, dbt model contracts, renamed/dropped/retyped columns, event schemas, anything a downstream consumer depends on |
| `data-migration` | `raid-data-migration-reviewer` | Schema migrations, backfills, data transformations on persisted tables, structure changes -- **not** model/query-only changes without migration artifacts |
| `adversarial` | `raid-adversarial-reviewer` | Diff has >=50 changed non-test, non-generated lines, OR touches high-risk domains (financial aggregations, PII, irreversible backfills, external-source ingestion) |
| `medallion-architecture` | `raid-medallion-architecture-reviewer` | The diff **crosses or defines a layer/tier boundary** -- a new model placed in a layer, logic moved across layers, a changed cross-layer reference, a skipped tier -- **AND** the repo uses a medallion-style architecture (tier language in `architecture.html`, `.raid/config.yaml`, or an observable layered directory layout such as Bronze/Silver/Gold or staging/intermediate/marts). Skip for in-layer-only edits, and for repos whose settled architecture is not medallion (e.g. an Inmon EDW or a Kimball dimensional warehouse -- use `inmon-architecture` / `kimball-architecture` below -- Data Vault, or a flat dbt marts layout). Focus when selected: tier-boundary discipline, layering violations, business logic in the wrong tier |
| `inmon-architecture` | `raid-inmon-architecture-reviewer` | Same boundary trigger as `medallion-architecture`, but for repos whose settled architecture is an **Inmon EDW** (`architecture: inmon` in `.raid/config.yaml`, staging/EDW/marts language in `architecture.html`, or an observable `edw_*` / subject-area layout). **Mutually exclusive with `medallion-architecture`** -- pick the one matching the repo's architecture, never both. Focus when selected: marts reading staging instead of the EDW, denormalization in the 3NF core, entities outside a subject area, destructive updates breaking non-volatility, per-mart dimensions that should be conformed |
| `kimball-architecture` | `raid-kimball-architecture-reviewer` | Same boundary trigger, but for repos whose settled architecture is a **Kimball dimensional warehouse** (`architecture: kimball` in `.raid/config.yaml`, staging plus `dim_*`/`fct_*` presentation language in `architecture.html`, conformed dimensions and no normalized core). **Mutually exclusive with `medallion-architecture` and `inmon-architecture`** -- exactly one layering persona applies. Focus when selected: undeclared or drifting fact grain, per-star dimension copies breaking conformance, many-valued attributes flattened onto facts, aggregate-only facts, semi-additive measures summed across time, BI reading staging |

**Synthesis agent:**

| Agent | Focus |
|-------|-------|
| `raid-deploy-verification-agent` | Go/No-Go checklist with SQL verification queries, baseline counts, backfill and rollback procedures. Spawn when the change is a risky deploy (destructive DDL, backfills, grain changes, NOT-NULL adds without default). Output surfaces in the Deployment Notes section, not as findings. |

## Platform experts (conditional, platform-gated)

Spawned only when the active platform (from `.raid/config.yaml`) matches and the diff
involves platform-specific execution. These live in the platform tier plugins, not
`raid-core`.

| Agent | Plugin | Select when... |
|-------|--------|----------------|
| `fabric-cli-expert` | `raid-fabric` | The diff touches Fabric notebooks, deployment, or `fab` CLI usage |
| *(future)* `databricks-expert` | `raid-databricks` | Databricks jobs/DABs/pipelines |
| *(future)* `bigquery-expert` | `raid-gcp` | BigQuery DDL/scheduled queries |

## Review depth

The review **depth** scales the always-on floor to the size and risk of the change, so a
small brownfield edit is not reviewed as heavily as a new greenfield build. There are
two floors:

| Depth | Always-on floor | When |
|-------|-----------------|------|
| **Full** | `correctness`, `testing`, `maintainability`, `project-standards`, `data-integrity`, `compliance-traceability` | A greenfield build; large diffs (>= the `adversarial` line threshold); high-risk domains (PII, financial aggregation, irreversible backfill, migration, new source); or any time the depth is ambiguous. **This is the default.** |
| **Lean** | `correctness`, `data-integrity`, `project-standards`, `compliance-traceability` | Small, brownfield-incremental diffs: roughly <=5 files, no new source/platform, no migration, conventions observable in the repo. |

The **Lean** floor drops `testing` and `maintainability` (and the layering persona --
`medallion-architecture`, `inmon-architecture` or `kimball-architecture` -- is conditional
at both depths, so it is naturally absent from an in-layer edit). Dropping
`testing` at Lean is deliberate: the `raid-mode` work loop already runs per-unit `dbt
build`/tests + DQ assertions as it builds, so a standalone testing-reviewer on the lean
in-loop pass is largely redundant; `correctness` and `data-integrity` still probe the
data. The **Direct** route (1-2 trivial files, per `raid-core`'s "Choosing the route")
reviews on the **Lean** floor -- no separate third profile.

**The depth trims only the always-on floor.** Every conditional persona still fires on
its own diff signal at either depth (a Lean diff that touches PII still pulls
`data-security`; one with a migration still pulls `data-migration`). The depth can make
review lighter, never blind to a warranted specialist.

**Depth resolution (precedence, highest first):**

1. **Explicit `depth:` token** (`depth:full` / `depth:lean`) passed to the skill -- a
   deliberate override that always wins.
2. **High-risk diff -> Full.** When the diff is large (>= the `adversarial` line
   threshold) or touches a high-risk domain (PII, financial aggregation, irreversible
   backfill, migration, new source), force **Full** -- this overrides an announced or
   inferred Lean so a risky change can never run on the trimmed floor by accident.
3. **The plan's announced tier**, discovered in Stage 2b (a plan that announces Lean
   -> `lean`; a greenfield build -> `full`).
4. **Diff-scope heuristic:** **Lean** when the diff is small and brownfield-incremental
   (the high-risk case is already handled at 2).
5. **Default Full.** When inference is ambiguous, choose Full -- never silently
   under-review.

Even when the floor lands on **Lean**, the conditional personas still fire on their own
signals (rule 2 below), so a Lean diff that does touch a specialist's domain is not
left unreviewed -- the depth trims the floor, the conditionals are the safety net.

The resolved depth is **announced** with the team (Stage 3 / rule 8), never asked.

## Selection rules

1. **Spawn the always-on floor for the resolved review depth** (see `## Review depth`)
   **Full** runs all 6 always-on personas; **Lean** trims to `correctness`, `data-integrity`,
   `project-standards`, and `compliance-traceability`. Skip any whose agent file does
   not yet exist and note that in Coverage. **For `scd-correctness`**, spawn when the
   diff touches dimension/SCD/merge logic **or any incremental predicate/anti-join**
   (latent silent-failure shapes that build verification on clean data cannot catch).
2. **For each conditional persona**, the orchestrator reads the diff and decides
   whether the persona's domain is relevant. This is a judgment call, not a keyword
   match.
3. **For `data-migration`**, spawn only when the diff includes migration/backfill/
   schema-change artifacts -- not for model-only or query-only changes.
4. **For the layering persona**, spawn only when **both** conjuncts hold: the diff
   crosses or defines a layer boundary, **and** the repo has a layered architecture.
   Then pick the **one** persona matching that architecture -- `medallion-architecture`
   for medallion repos, `inmon-architecture` for Inmon EDW repos,
   `kimball-architecture` for Kimball dimensional repos (`architecture:` in
   `.raid/config.yaml` decides it; absent = medallion). **Never spawn more than one.**
   A skip here is an ordinary conditional non-selection (an in-layer edit, or a repo on
   none of the three) -- **not** a missing-agent-file Coverage note, and not a
   gap. Do not record it in Coverage.
5. **For `data-security`**, spawn when the diff touches PII, secrets, grants, or
   regulated data; on GDPR-relevant repos default to spawning it.
6. **For the platform expert**, spawn only when `.raid/config.yaml` names that
   platform AND the diff involves its execution surface.
7. **For `raid-deploy-verification-agent`**, spawn when the change is a risky deploy
   (destructive DDL, backfills, grain/NOT-NULL changes).
8. **Announce the team and the depth** before spawning, with a one-line justification
   per conditional reviewer selected and the one-line reason the depth was inferred.

## Distinguishing the two agent kinds

- **Persona agents** emit JSON conforming to `findings-schema.json`; their findings go
  through merge -> validate -> synthesis.
- **Synthesis agents** (`raid-deploy-verification-agent`)
  return prose/checklists that the orchestrator places in their own report sections
  (Deployment Notes) -- they are not merged into the
  findings tables.
