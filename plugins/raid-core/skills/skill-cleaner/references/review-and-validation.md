# Review and validation

Read when presenting the audit, applying approved changes, or verifying a changed
skill/instruction contract.

## Make the result reviewable

State selected paths and intended hosts/models. List reviewed entry points and
instruction files, resolving aliases to their source; mark anything unreviewed.
For each actionable finding provide:

- File and line evidence, with the current instruction's intended purpose.
- The defect or unnecessary burden and confidence in that diagnosis.
- Concrete replacement wording, reference move, or removal candidate.
- Constraints preserved and any workflow/product choice that needs a decision.
- A relevant verification case and the expected before/after behavior.

Group direct repairs, description/routing changes, content moves, and optional
policy changes so the user can approve a coherent subset. Include important
instructions to keep. Avoid inferring approval from agreement with the article.
If the user already approved implementation, apply that subset without asking
again; keep unapproved policy choices as proposals.

## Validate the changed behavior

Use representative positive requests and close negative matches, especially
neighboring skills, explicit-only boundaries, audit-only scope, and already-given
authorization. Compare to the baseline on intended available hosts/models in
fresh contexts. Exercise the selected reference path for moved workflows and
check that important constraints remain reachable. Model-specific optimizers
must receive IDs supported by their actual provider.

When only a supplied-catalogue routing or planning simulation is feasible, label
it as such; it is not a native invocation or real workflow test. A capability or
account limit is missing coverage, not a pass. Do not execute publication,
production writes, destructive cleanup, or another skill's operational workflow
just to test its instructions without the corresponding task authority.

For helper changes, use isolated fixtures with scoped roots. Cover root selection,
AGENTS/CLAUDE aliases and nested scope, identical versus drifted copies, invocation
metadata, optional usage evidence, missing paths, and budget assumptions. Existing
helper tests run from any cwd:

```sh
SKILL_DIR="<absolute directory containing the loaded SKILL.md>";
node --test "$SKILL_DIR/scripts/skill-cleaner.test.mjs"
```

After edits, inspect the actual diff, preserve symlinks and unrelated work, check
local reference/helper paths, and run the project's required validation and map
or manifest generation. Do not broaden test or review rounds after clean relevant
checks unless new edits, failures, or uncertainty justify them. Report changes,
verification, remaining limits, and uncommitted/committed state accurately.
