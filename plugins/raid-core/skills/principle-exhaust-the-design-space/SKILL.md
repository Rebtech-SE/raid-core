---
name: principle-exhaust-the-design-space
description: "Use when facing a modelling or architectural decision with no precedent in the repo. Build two or three competing sketches and compare them before committing."
disable-model-invocation: true
---

# Exhaust the Design Space

When a novel interaction or architectural decision has no established precedent, explore several concrete alternatives before implementation. Building the wrong thing costs more than exploring three options.

**The rule.** When the right answer is not obvious, build 2-3 competing prototypes or sketches. Compare them side by side. Only then commit. Design it twice is this rule by another name. A second flavor of the first shape does not count.

**When it applies:**
- Novel UI interactions (no prior art in the codebase)
- Architectural choices with multiple viable approaches
- Product design decisions where user experience depends on feel, not logic

**When it doesn't:**
- Mechanical implementation where the pattern is established
- Bug fixes or refactors with a clear target state
- Changes where constraints dictate a single viable approach

## In data work

The decisions worth two or three sketches are the ones that are expensive to reverse:
medallion tiers versus a Kimball core, SCD2 versus a snapshot table, one wide fact versus
several conformed ones, streaming versus micro-batch. Sketch each against a real slice of
the source -- a few thousand rows is enough to expose a grain problem or a join that
fans out -- and compare on the things that will actually hurt: query cost, restatement
behaviour, and how the shape handles the next requirement.

A sketch is throwaway. Do not let one become the build because it was first.
