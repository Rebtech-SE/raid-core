---
name: principle-redesign-from-first-principles
description: "Use when integrating a new requirement into an existing design. Redesign as if the requirement had been foundational from day one, rather than bolting it on."
disable-model-invocation: true
---

# Redesign From First Principles

When integrating a change, don't bolt it onto the existing design. Redesign as if the requirement had been there from the start. The result should look like what we would have built if we'd known on day one.

- Read all affected files and understand the current design holistically
- Ask: "if we were writing this from scratch with this new requirement, what would we build?"
- Propagate the change through every reference: types, docs, examples, rationale sections
- Think about the redesign holistically, then deliver it incrementally

**On a customer estate the redesign stays inside the authorized scope.** Published tables, views, extracts and measures are deployed clients: keep the old surface as a view over the new shape (`refactoring`). Redesign within the repo's settled layering and conventions. A redesign wider than the ask is a proposal for the user, not a change you make.

This is the method for preserving option value when integrating changes into an existing design.
