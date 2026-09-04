# Migration from Medallion

Guidance for migrating from medallion architecture to Inmon EDW, or running both in a hybrid pattern.

## Architecture Mapping

| Medallion Layer | Inmon Layer | Structural Similarity | Key Difference |
|---|---|---|---|
| Bronze | Staging | Identical | Same purpose: raw capture |
| Silver | EDW (3NF) | Moderate | Silver is often partially denormalized; EDW is strict 3NF |
| Gold | Data Marts | High | Both serve business users with dimensional models |

The mapping is not 1:1 at Silver/EDW -- Silver layers often carry some denormalization and may not enforce strict enterprise-wide conformance. The Inmon EDW adds enterprise modeling, conformed dimensions, and formal subject area decomposition.

## When to Migrate vs When to Coexist

### Migrate to Inmon When

- Multiple teams are building conflicting Silver definitions for the same entities
- Regulatory requirements demand a single auditable source of truth
- Conformed dimensions are needed across 3+ business domains
- The organization has matured beyond single-team analytics

### Stay on Medallion When

- Single team or domain owns the entire pipeline
- Speed of delivery is more important than cross-domain conformance
- Data volume is low and 3NF overhead is not justified
- No regulatory requirement for enterprise-wide audit trail

### Coexist (Hybrid) When

- Some domains need enterprise conformance, others are self-contained
- Migration must be incremental (cannot stop everything and rebuild)
- Teams have different maturity levels

## 4-Phase Migration Strategy

### Phase 1: Assess

1. Inventory all Silver entities across the platform
2. Identify overlapping definitions (e.g., two teams defining "customer" differently)
3. Map Silver entities to enterprise subject areas
4. Identify conformed dimension candidates
5. Estimate effort per subject area

Deliverable: migration backlog prioritized by business value and conformance pain.

### Phase 2: Parallel Build

Build the EDW layer alongside existing Silver, without disrupting current pipelines.

```
Sources -> Bronze/Staging (shared) -> Silver (existing, unchanged)    -> Gold (existing)
                                   -> EDW (new, 3NF, subject areas)  -> Marts (new)
```

Steps:
1. Create EDW schema/database alongside Silver
2. Build EDW entities for the first subject area (e.g., Customer)
3. Build a new mart that reads from EDW instead of Silver
4. Run both old Gold and new Mart in parallel, validate results match

### Phase 3: Redirect Marts

Once EDW entities are validated, redirect existing Gold tables to read from EDW instead of Silver.

```sql
-- Before: Gold reads from Silver
SELECT * FROM silver.customers WHERE _is_current = TRUE

-- After: Gold reads from EDW
SELECT * FROM edw.customer_customer WHERE _is_current = TRUE
```

Steps:
1. Update Gold/mart models to reference EDW entities
2. Validate output matches previous Gold
3. Remove dependency on Silver for migrated entities
4. Repeat for each subject area

### Phase 4: Consolidate

Once all marts read from EDW, decommission redundant Silver entities.

Steps:
1. Verify no downstream consumers read from Silver directly
2. Archive Silver tables (do not delete -- keep for rollback)
3. Remove Silver pipeline schedules for migrated entities
4. Update documentation and data catalog

## Hybrid Architecture Pattern

For organizations that need both medallion agility and Inmon conformance, run a hybrid architecture.

```
+------------+    +-------------------+
|            |    |                   |
|  Sources   +--->|  Staging / Bronze |
|            |    |    (shared)       |
+------------+    +--------+----------+
                           |
              +------------+------------+
              |                         |
     +--------v---------+    +---------v--------+
     |                  |    |                  |
     |  Silver          |    |  EDW (3NF)       |
     |  (team-owned,    |    |  (enterprise,    |
     |   domain-scoped) |    |   conformed)     |
     |                  |    |                  |
     +--------+---------+    +---------+--------+
              |                         |
              +------------+------------+
                           |
                  +--------v---------+
                  |                  |
                  |  Data Marts      |
                  |  (unified)       |
                  |                  |
                  +------------------+
```

### Rules for Hybrid

1. **Shared staging**: Both Silver and EDW read from the same staging layer
2. **No cross-reads**: Silver does not read from EDW; EDW does not read from Silver
3. **Conformed dimensions from EDW**: Any dimension used by 2+ domains must come from EDW
4. **Team-scoped Silver**: Silver is for domain-specific transformations that do not need enterprise conformance
5. **Unified marts**: All marts can reference both EDW dimensions and Silver-derived facts

### Which Entities Go Where?

| Entity Type | Silver (Team-Owned) | EDW (Enterprise) |
|---|---|---|
| Shared business entities (customer, product) | No | Yes |
| Domain-specific metrics (campaign scores) | Yes | No |
| Reference data (country, currency) | No | Yes |
| Transaction data used by 1 domain | Yes | No |
| Transaction data used by 2+ domains | No | Yes |

## dbt Project Structure for Hybrid

```
dbt_project/
  models/
    staging/                    -- Shared staging (Bronze)
      stg_crm__customers.sql
      stg_erp__orders.sql
      stg_marketing__campaigns.sql

    edw/                        -- Enterprise Data Warehouse (3NF)
      customer/
        edw_customer__customer.sql
        edw_customer__address.sql
      product/
        edw_product__product.sql
        edw_product__category.sql
      transaction/
        edw_transaction__order_header.sql
        edw_transaction__order_line.sql

    intermediate/               -- Silver (team-owned, domain-scoped)
      marketing/
        int_campaign_scores.sql
        int_email_engagement.sql

    marts/                      -- Unified marts
      shared/                   -- Conformed dims (from EDW)
        dim_customer.sql
        dim_product.sql
        dim_date.sql
      sales/                    -- Sales mart (EDW-sourced facts)
        fct_sales.sql
      marketing/                -- Marketing mart (Silver-sourced facts + EDW dims)
        fct_campaigns.sql       -- Joins EDW dim_customer with Silver campaign data
```

### Example: Marketing Mart Using Both

```sql
-- models/marts/marketing/fct_campaigns.sql
{{ config(materialized='table', tags=['mart', 'marketing']) }}

SELECT
    cs.campaign_id,
    cs.campaign_date,
    c.customer_id,
    c.customer_name,
    c.segment,             -- From EDW conformed dimension
    cs.engagement_score,   -- From Silver (team-owned)
    cs.conversion_flag,    -- From Silver (team-owned)
    cs.revenue_attributed  -- From Silver (team-owned)
FROM {{ ref('int_campaign_scores') }} cs                -- Silver
JOIN {{ ref('dim_customer') }} c ON cs.customer_id = c.customer_id  -- EDW
```

This pattern gives the marketing team agility (own their campaign logic in Silver) while ensuring customer definitions are consistent with the rest of the organization (via EDW conformed dimension).
