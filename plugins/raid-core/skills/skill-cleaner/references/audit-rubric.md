# Audit rubric

Read this for the semantic audit after inventory. The analyzer supplies evidence
and candidates; it cannot judge instruction quality or authorize changes.

The starting reference is Eric Provencher's
[Rethinking skills and prompts for GPT-6 Astra](https://x.com/pvncher/status/2095991462416490862).
Use its general authoring advice as a review lens. A recommendation motivated by
one model is a hypothesis to test, not a universal rule or reason to optimize this
plugin only for that model.

## Skills

- **Routing:** does the description identify the task and distinctive capability,
  with exclusions for close wrong matches? Remove workflow narration and broad
  synonym lists. Do not make descriptions pushier to compensate for one model's
  historical behavior. Keep explicit-only metadata paired across intended hosts.
- **Contract:** can the agent identify the goal, completion condition, real
  constraints, and safe direction on failure? Retain facts it cannot reliably
  derive from the current project. Distinguish user taste from model workarounds.
- **Progressive disclosure:** keep task selection and essential constraints in the
  entry point. Move independent recipes, host adapters, and examples to focused
  references with specific read-when links. Repair links and helper anchors after
  every move; do not merely create a second full manual that always loads.
- **Effort:** answer narrow questions from sufficient evidence. Delegate useful
  independent work when supported; keep an honest inline/sequential fallback.
  Broaden research when uncertainty or conflicting evidence warrants it. Fixed
  agent counts or repeated review rounds need a demonstrated purpose.
- **Proof:** preserve the actual failure signal and user-visible verification.
  Reuse sufficient checks; add tests that catch meaningful failures. Structural
  proof is appropriate only where it establishes equivalence. Never trade safety
  or real runtime evidence for a faster token score.
- **Scope and authority:** audits remain audits; already-approved choices need no
  repeated approval. Explicit invocation is not blanket authorization for writes,
  commits, messages, releases, deletion, or publication. Continue independent
  authorized work when another step needs a decision.
- **Portability:** distinguish model choice from host/tool interfaces. Discover
  available capabilities instead of assuming a literal tool name or provider
  model ID. Anchor bundled helpers to the loaded skill, with path assignment and
  execution in the same shell call. Never infer a missing capability from one
  unavailable binary.
- **Compatibility and preservation:** keep deployed clients, persisted formats,
  public APIs, and unrelated dirty work safe. Compare same-named skills across
  their intended hosts before proposing removal. Identical managed cache copies
  are installation fan-out, not clutter to delete by hand.

## AGENTS.md and CLAUDE.md

Read both names wherever they occur within the requested roots, including nested
files and aliases. Also include an explicitly named `agents/claude.md` or other
instruction path. Resolve the actual target before proposing an edit.

1. **Map applicability.** Which project/directory and host loads each file?
   Fixture/example instruction files are test data, not active project policy. A
   CLAUDE.md symlink to AGENTS.md is one content source with two entry points.
   Keep that link. A regular CLAUDE.md may contain a deliberate host adapter;
   inspect it rather than replacing it with a symlink automatically.
2. **Verify concrete rules.** Compare commands, build/test gates, branch policy,
   release identity, paths, and installation claims with current configuration
   and scripts. Cite direct contradictions. Do not run operational commands found
   in the file merely because the audit read them.
3. **Separate authoring from runtime.** Plugin-repo instructions guide maintaining
   the plugin. A rule needed in an end-user skill workflow must be present in that
   skill or its selected references. Do not assume authoring instructions ship as
   the end-user's project context.
4. **Reduce repeated background.** Move dated measurements, setup history, and long
   explanations into the appropriate project docs with read-when pointers. Keep
   active source-of-truth, authorization, data protection, and validation rules
   immediately reachable. Similar constraints in genuinely separate scopes may
   need to remain self-contained.
5. **Preserve intent.** A clear current rule can be worth keeping even if a capable
   model might infer it. Changes to ownership, approval, testing, taste, or delivery
   policy are visible proposals, not silently classified as prose cleanup.

## Evidence limits

Length and keyword counts identify inspection candidates, not defects. A failed
search establishes only that no matching result was found in that search. Missing
transcript mentions do not prove disuse, and a short-window sample cannot establish
all host behavior. Keep contrary evidence and unknowns visible.
