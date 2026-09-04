# Recipes: GitHub Issues (via `gh`)

Used when `.raid/config.yaml` has `tracker.provider: github`. Run inside the clone
and `gh` infers the repo from the remote.
## Where work lives

Issues live as GitHub issues on this repo. Use the `gh` CLI;
run inside the clone and it infers the repo from the remote.

## Conventions

- **Create**: `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies).
- **Read**: `gh issue view <number> --comments`.
- **List**: `gh issue list --state open --json number,title,body,labels,assignees --jq '[.[] | {number, title, labels: [.labels[].name]}]'`,
  with `--label` / `--state` filters.
- **Comment**: `gh issue comment <number> --body "..."`.
- **Labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

## Pull requests as a request surface

**No.** _(Set to `yes` if this engagement treats external PRs as incoming
requests.)_ When `yes`, PRs run through the same labels and states as issues via
the `gh pr` equivalents: `gh pr view <n> --comments`, `gh pr diff <n>`,
`gh pr comment`, `gh pr edit --add-label`, `gh pr close`. List external PRs with
`gh pr list --state open --json number,title,author,authorAssociation` and keep
only `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR` or `NONE`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be
either -- resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

`gh issue view <number> --comments`; summarise before building.

## Wayfinding operations

The **map** is one issue; each implementation unit is a child issue.

- **Map**: an issue labelled `wayfinder:map`, its body carrying the plan's scope,
  decisions and open questions.
- **Unit ticket**: an issue linked to the map as a **sub-issue**
  (`gh api --method POST repos/<owner>/<repo>/issues/<map>/sub_issues -F sub_issue_id=<child-db-id>`).
  Where sub-issues are not enabled, add the child to a task list in the map body
  and put `Part of #<map>` at the top of the child body. Label `wayfinder:<type>`.
- **Blocking**: GitHub's **native issue dependencies** --
  `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`,
  where `<blocker-db-id>` is the blocker's numeric **database id**
  (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`), *not* the `#number` or the
  `node_id`. GitHub then reports `issue_dependencies_summary.blocked_by`, counting
  open blockers only. Fall back to a `Blocked by: #<n>, #<n>` line at the top of
  the child body.
- **Frontier query**: the map's open children, dropping any with
  `issue_dependencies_summary.blocked_by > 0` (or an open issue in the `Blocked by`
  line) or an assignee.
- **Claim**: `gh issue edit <n> --add-assignee @me` -- the session's first write.
- **Resolve**: `gh issue comment <n> --body "<what was built and how it was verified>"`,
  then `gh issue close <n>`.
