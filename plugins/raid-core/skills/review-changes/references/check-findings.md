# Verify and report findings

Use the finding fields and action-class rubric from `review-changes`. Its JSON
output section defines the combined report envelope.

1. Locate every P0/P1 on the reviewed version. Verify the claim against the
   relevant baseline, requirement, caller or upstream input. Cite the evidence
   and explain the failure scenario.
2. Run targeted read-only probes for data-dependent claims when access exists.
   Record any unavailable checks in Coverage. A data-dependent suspicion you
   could have verified but did not stays at 50 or lower. Code-proven defects
   retain their evidence-based anchor.
3. Deduplicate by cause and location. Keep the strongest supported severity and
   confidence, plus applicable check IDs. Use 75 for a confirmed failure scenario,
   100 for a conclusive reproduction or proof, and 50 for substantiated uncertainty.
   Suppress primary findings below 75 except P0 at 50+. Put advisory testing and
   maintainability issues in testing gaps or residual risks.
4. List pre-existing issues separately. Use the stricter route where actions
   differ. Sort by severity, descending confidence, file and line. Assign stable
   numbers once. Put `gated_auto` and `manual` findings with owner
   `downstream-resolver` in `actionable_findings`.

## Independent check

For an irreversible migration or backfill, risky production rollout or high-stakes
design decision, identify the concrete question that would benefit from independent
context. If the user and host allow it, use at most one read-only subagent for that
question. Give it the exact revision or document, source inputs, constraints and
read-only query access when available. Ask for evidence and a conclusion. Give it
no authority to edit, deploy or resolve findings. Verify its evidence in the current
session and report whether the independent check ran.
