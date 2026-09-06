---
name: how
description: >-
  Use for a question about how something in a data platform works or where a number comes
  from -- 'where does this metric come from', 'what feeds this table', 'how does this
  pipeline run', 'what breaks if I drop this column', 'who owns this model'. Traces
  lineage backwards from the consumer to the source, names the transform and the grain at
  each hop, and explains the mechanism from the real models. Answers, it does not change
  anything. Use `why` for rationale, `debug-data-issue` when something is broken.
---

# How

Answer how a data platform behaves, from the actual models, pipelines and platform
metadata. Build the mental model at the depth the question needs.

**A question is not authorization to change anything.** Explaining is the whole job. If the
answer exposes a bug, say so and stop; the user decides whether to route it to
`debug-data-issue`.

Use `why` for motivation -- why this grain, why this SCD type, why this column is
nullable. Model shape shows behaviour and never proves intent.

## Investigate in proportion to the question

- **A single model, column or ownership question** -- read the model and its direct
  consumers and answer. No ceremony.
- **A metric, a report figure, a "where does this come from"** -- run the lineage trace
  below. This is the common case and the one worth doing properly.
- **A whole subsystem** -- trace the primary path end to end, then name the branches you
  did not walk rather than implying you covered them.

Delegate independent slices to subagents when a host supports it and separate context
genuinely helps -- one per source system, one per layer. Give each a distinct scope and
concrete paths. Reconcile what comes back and follow unresolved links yourself; a
delegate's summary is not evidence.

State a reasonable reading of an ambiguous target and proceed. Ask only when the missing
decision changes which model you would open.

## The lineage trace

The highest-value thing this skill does, and the thing nobody writes down. Work
**backwards from what the consumer actually reads**, because that is where the question
started and it is the only end that is unambiguous.

At each hop, name four things:

1. **The object** -- model, notebook, view, table, measure. With its repo-relative path
   when it lives in the repo, and its platform name when it does not.
2. **The transform** -- what this hop does to the data in one line: filters, joins,
   aggregates, deduplicates, applies SCD2, casts, renames.
3. **The grain** -- what one row means here. Call out **every hop where the grain
   changes**, and say what changed it. A grain change at a join or an aggregate is where
   metric discrepancies are born, and it is the single most useful thing in the trace.
4. **The filter or predicate that drops rows** -- a `where`, an inner join, a
   `is_current = true`, a date window, an incremental predicate. A number that "looks too
   low" is almost always one of these, three hops up.

Walk it: consumer (report, semantic model, API, extract) -> gold mart -> silver conform ->
bronze load -> source system object. Stop at the boundary you can actually see, and say
where you stopped.

Read the platform's own lineage or dependency metadata where it exists -- `dbt` manifest
and `ref()` graph, the platform's lineage view, a pipeline's activity dependencies -- and
treat it as a starting map, not as the answer. It records edges, not what happens on them.

**Dispatch the tier's platform expert** (`fabric-cli-expert`, `databricks-expert`,
`bigquery-expert`) rather than guessing CLI or metadata-query syntax.

Where you have read access, **check the trace against real data** -- row counts at each
hop, key uniqueness at the grain you claimed, the null rate on the column in question.
A trace that has been checked against the actual numbers is worth several times one read
off the SQL, and a hop where the counts do not reconcile is the answer to most "why is
this number wrong" questions. Say plainly when you did not have access.

## Beyond lineage

The same proportionality applies to the other how-questions:

- **How does it run?** The orchestrator's schedule and dependencies, the trigger, what
  runs on failure, what the retry does, where the logs land. Read the actual pipeline or
  job definition, not the README's description of it.
- **What breaks if I change this?** Downstream consumers, from the dependency graph *and*
  from a grep for the object's name in reports, notebooks and ad-hoc SQL that the graph
  cannot see. Say which of the two found each consumer, because the second is never
  complete.
- **Who owns it?** Recent authorship on the model, the pipeline's service principal, the
  team named in the repo's own conventions. Attribute carefully and neutrally.

## Answer

Lead with the answer, then the trace or the mechanism that supports it. Reference the
models and paths that let the reader check you -- repo-relative, never absolute.

Say what you did not cover: the branch you did not walk, the source system you could not
see, the hop you inferred from the dependency graph rather than reading. Never imply
coverage you did not get.

Use the project's own vocabulary from `GLOSSARY.md`. If the trace turns up a term doing
real work with no settled definition, name it and offer `domain-modeling` -- do not settle
it yourself mid-explanation.

If the question precedes a change the user has asked for, close by turning the findings
into constraints for that work: what must be preserved, what will move, what is risky.

Related: `why`, `teach`, `data-investigator`, `domain-modeling`,
`debug-data-issue`, `principle-declare-the-grain`.
