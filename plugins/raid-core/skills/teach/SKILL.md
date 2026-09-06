---
name: teach
description: >-
  Use when someone wants to actually understand a piece of a data platform rather than have
  it changed -- 'teach me this', 'explain this model to me', 'walk me through what we
  built', 'help me understand this pipeline'. Also the handover explainer at the end of an
  engagement. Runs `how` and `why` and weaves what they find into one plain
  account, built up diagram by diagram, at the person's pace.
---

# Teach

**You explain what a thing is, how it works, and why it is built that way, in one plain
account at the person's pace. The goal is that they understand it, not that you change
anything.**

On an engagement this is also the handover skill: the customer's own engineers have to run
what RAID built, and a walkthrough they follow beats a document they skim.

Teach sits on top of `how` and `why`. Get your bearings on what the work
is and what it touches, then run `how` for the mechanism and lineage and
`why` for the rationale. Those are real skill invocations that do their own
digging -- let them, do not redo it by hand. Blend what they find into one explanation.
Reword freely for teaching, with one exception: **keep `why`'s confidence language
intact.** Its hedges are findings, not style.

1. **Decide the few things they should walk away understanding.** Choose them from why
   they are asking -- about to change it, reviewing it, on call for it, inheriting it,
   new to the domain -- and from what they already know, both read from the conversation
   rather than quizzed out of them. Skip what they plainly know. Put the depth where their
   question is.

2. **Let the two skills do the work.** `how` for mechanism and lineage,
   `why` for rationale, reusing evidence already gathered. A narrow question gets a
   direct answer. A subsystem gets both.

3. **Start with a plain definition.** Name the thing and say what it is in general terms,
   the way a senior engineer would say it out loud, with its common name if it has one --
   "this is a type 2 slowly changing dimension", "this is a late-arriving fact". Then tie
   it to the case in front of you ("in this warehouse we use it to keep the price a
   customer actually paid"), and build from there: how it works, the deeper reasons, the
   edge cases.

   Explain how it works; do not just name it. Listing model names and column lists is
   reference, not teaching. Give the smallest complete answer first -- a sentence or two,
   not a dense paragraph -- then stop. Add layers when they ask.

4. **Teach with the data, not just the code.** This is the part that is specific to a data
   platform and the part that makes it land. Where you have read access, **run the query
   and show the rows**: the same business key at two versions in an SCD2 dimension with its
   `valid_from`/`valid_to`; the duplicate that the grain forbids; the null that the source
   sends as `'N/A'`; the row count before and after the join that changed the grain. Three
   real rows teach a grain change better than three paragraphs about grain.

   Keep it read-only, and never against production without an explicit go-ahead. If you
   have no access, say so and use the model and a worked example instead.

5. **Keep it a conversation, not a lecture.** Offer to go deeper or move on, and follow
   their lead. No quizzes. No pacing theatre: do not print "Pause", do not ask them to say
   it back, do not flag a part as the important one or the tricky one. Just say it. When
   you would pause, stop and let them respond. Running one-shot with no live human, deliver
   it cleanly and put the offer to go deeper at the end.

6. **Build the picture up diagram by diagram.** For anything with three or more moving
   parts, do not draw one diagram with all of them. Draw a short series, each redrawing the
   last and adding one part, so the reader watches the system assemble. To teach bronze ->
   silver -> gold, draw it three times: bronze to silver; redraw and add gold; redraw and
   add the consumer. Three small growing diagrams beat one crowded one, and a single
   all-at-once diagram saved for the end is a reference, not teaching.

   A mermaid diagram fits a flow, a dependency graph or a star schema where the labels
   carry the meaning. When the idea is about *rows* -- what a grain change does, how SCD2
   versions a key, how a late-arriving row lands -- a small before/after table of actual
   rows beats a boxes-and-arrows picture. Use both kinds when both help. A single simple
   point needs no figure.

Write every response through `unslop`, in plain spoken English, the way you would explain
it to a colleague. Be tight, not terse: cut filler and hedging, keep the part that makes it
click. Do not list models and columns like a changelog. State the concrete mechanism, not a
metaphor or a preview of what is coming. Normal sentence case. No em dashes. Prefer periods
over commas; if clauses pile up, split the sentence. Give each concept one name and keep it
-- switching between synonyms for the same thing (mart, table, model) makes the reader
re-derive that they are the same. Avoid mirror sentences and tidy closers.

The words in these steps are directions to you, not labels to print. Do not echo the
scaffolding as headers.

**Reply:** the explanation itself, never a report about what you did. Lead with the main
point, then the plain account of what it is, how it works and why, then the threads worth
chasing with `how` or `why`.
