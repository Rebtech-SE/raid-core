# resolve-pr-feedback

Adapted from ossian-stack's skill of the same name, which is itself adapted from
EveryInc's compound-engineering plugin. Provenance and the pinned upstream commit are
in `plugins/sources.json`; the refresh workflow is `docs/skills-sources.md`.

GitHub/GHE uses the bundled helpers under `scripts/`. Azure DevOps Services dispatches
to `references/azure-devops.md` and the Python REST adapter under `scripts/azure/`.
Both providers share the same decision and pipeline residual contracts.

The Azure adapter uses REST 7.1 and existing az Entra authentication or a supplied
AZURE_DEVOPS_EXT_PAT. It does not support Server/custom hosts or fork mutations. Thread
writes have no atomic compare-and-swap guarantee, so readback and reassessment are
required. Offline fixtures do not establish live access or write success.

RAID-local changes -- preserve these on refresh:

- `scripts/get-pr-comments` and `scripts/get-thread-for-comment` merge their paginated
  GraphQL responses in **Python only**. Upstream prefers jq and falls back to Python;
  raid-core ships shell, Python and the provider's own CLI, not jq.
- `babysit` is the named unattended caller, in place of upstream's `babysit-pr`.
- Step 5 of full mode carries RAID's validate-against-real-data rule, and the fixer
  prompt's targeted-test examples are dbt and pytest.
- Judging stays central (the legitimacy gate plus `references/evaluation-rubric.md`) and
  fixers are generic subagents seeded with `references/agents/pr-comment-resolver.md`.
  RAID's former per-thread judging agent was removed with this skill's adoption.
- `SKILL.md` carries a Bundled helpers section indexing `scripts/`, without which the
  repo's validator warns that Copilot will not load them.
- GitLab is not supported here, unlike the host-agnostic git skills in raid-core.
