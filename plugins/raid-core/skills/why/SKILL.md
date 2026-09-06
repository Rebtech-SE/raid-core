---
name: why
description: >-
  Use for 'why is it built this way' questions about a data platform -- why this grain, why
  SCD2 here, why this column is nullable, why the load is full and not incremental, why
  this number differs from the old report. Finds the recorded rationale in ADRs, the
  glossary, decision artifacts, git history and the tracker, cites it, and labels inference
  as inference. Read-only. Use `how` for mechanism, `debug-data-issue` when
  something is actually broken.
---

# Why

Find the evidence behind a modelling decision, a threshold, or a discrepancy. `how`
explains the mechanism; this explains the motivation, without inventing it.

Read-only. An explanation does not authorize a change.

## Follow the evidence

1. **Anchor the question** in a concrete object: a model, a column, a measure, a grain, a
   number that two reports disagree on. Use the conversation to resolve obvious context;
   ask only when the target is materially ambiguous.

2. **Read the recorded decisions first**, in this order, because on a RAID engagement the
   answer is usually already written down:
   - `docs/adr/` -- the hard decisions, with their consequences.
   - `GLOSSARY.md` -- the settled definition of the term the question turns on. A "why is
     revenue different" question is very often a two-definitions question.
   - `docs/artifacts/*.html` (`architecture.html`, `design.html`, `assessment.html`,
     `testplan.html`) -- on a greenfield engagement these fix the tier, grain, naming,
     audit columns, load modes and wave order, and they record the option that was
     rejected.
   - `AGENTS.md` and any `CONVENTIONS.md` -- a decision that became a standing rule.
   - `docs/testing/test-results.jsonl` -- when the question is "did this ever work",
     the ledger is the only record that a check failed before it went green.

3. **Answer directly** when an explicit record covers it and nothing contradicts it.
   Verify the record still applies to this version of the model. Do not search every
   system by ritual.

4. **Expand** when the record is missing, indirect or conflicting:
   - `git log -p` and `git log --follow` on the model or notebook, and the PR or merge
     commit that introduced the shape. The commit that *introduced* a predicate is worth
     more than the ten that touched the file afterwards.
   - The tracker: the ticket, the agent brief, the wayfinder decision ticket that settled
     it. RAID's own `wayfinder` maps record the route actually walked, including what was
     ruled out of scope and why.
   - Data-shaped evidence, which is this skill's version of reading the incident log: a
     nullable column whose nulls all predate a date is a backfill boundary; a `case` that
     special-cases three source ids is an upstream data quality workaround; a dropped
     partition is a retention policy. Where you have read access, **query for the shape
     that would explain the decision** and say what you found.

5. **Reconcile before writing.** Surface competing explanations rather than picking the
   tidy one. Model shape describes behaviour; it rarely proves motivation.

## For a discrepancy between two numbers

The most common form of this question on an engagement, and it has a specific method.
Do not answer it from rationale alone -- find the mechanical difference first, then explain
why it exists:

- Compare the two **definitions** (`GLOSSARY.md`, the semantic model, the old report's
  SQL) before comparing the numbers. Different measures with the same name is the modal
  cause.
- Compare **grain**, **filters**, **date basis** (event date vs load date vs effective
  date), **currency and rounding**, and **late-arriving or restated rows**.
- Compare **as-of semantics**: an SCD2 dimension read without `is_current` against one read
  with it will disagree forever, and neither is wrong.
- Then reconcile numerically where you have access: total, then by the dimension that
  splits them, until the delta localises to one hop. Hand the mechanism to `how`
  if the trace itself is the missing piece.

State the mechanical cause and the rationale separately. "The old report used booking date;
we moved to event date in ADR-004" is an answer. "They use different logic" is not.

## Evidence standard

Cite every claim about intent to a commit, PR, ADR, ticket, artifact section or explicit
comment. Distinguish direct evidence from inference and match your language to it.

A failed search means no matching record was found **in that search** -- not that the
decision was never recorded. Say which sources you consulted, which returned nothing, and
which you could not reach. Never imply you checked a source you did not.

Do not infer intent from today's model shape, and do not confirm the user's hypothesis
without testing it. "No recorded rationale; here is what the evidence is consistent with,
labelled as inference" is a good answer and a common one.

## Answer

Lead with the supported answer. Then the anchors (repo-relative paths, commit shas, ADR
numbers), the direct evidence, clearly labelled inference, unresolved competing
explanations, and the concrete gaps.

If the answer turns out to be **undocumented and worth keeping**, offer to record it:
`domain-modeling` writes the term or the ADR. Offer, do not write it unasked.

If the question precedes a requested change, translate the findings into preserve / change
/ avoid / risk constraints for that work.

Related: `how`, `teach`, `domain-modeling`, `data-investigator`,
`debug-data-issue`, `principle-declare-the-grain`.
