# Azure DevOps Services feedback

Use this reference for Azure Services instead of the GitHub full/targeted references.
The same evaluation rubric, fixer prompt, inherited action scope, and pipeline
needs-human contract apply. Do not use gh, GraphQL, GitHub review IDs, or GitHub
resolution semantics on this path. Do not merge, arm auto-complete, alter reviewer
votes, approve CI, bypass policy, retarget, rebase, or force-push.

## Resolve identity and fetch

Use the explicit full Services PR URL (dev.azure.com or the organization's legacy
visualstudio.com URL). Otherwise combine the verified project remote/configuration
with the PR ID. Organization, project, repository and PR ID must all be known;
never search other organizations using the number alone. The local adapter accepts
a Services HTTPS/SSH repository remote with `--pr`, canonicalizes names to returned
IDs, verifies identity and URL-encodes components. Custom/Server hosts are unsupported.
An unknown forge or inaccessible API is a reported blocker, not a GitHub fallback.

A full PR URL selects all unresolved discussions. An explicit thread ID with that
URL, or its discussionId query parameter, selects **only that thread**. Conflicting
IDs fail. For a link whose target cannot be resolved, request the exact thread ID
instead of broadening scope. The adapter's thread URLs use the documented thread
REST resource so source IDs remain stable across inline and general discussions.

```bash
SKILL_DIR="<absolute directory containing the resolve-pr-feedback SKILL.md just read>";
python3 "$SKILL_DIR/scripts/azure/feedback.py" list --url "<full-pr-url>"
```

Add `--thread-id <id>` for targeted scope. Authentication uses an existing az Entra
session or a supplied AZURE_DEVOPS_EXT_PAT environment variable; stored CLI PATs are
not read. No account configuration or token output occurs.

The response includes exact PR identity, head commit, PR metadata, and threads with
source_id, thread_url, thread_id, expected_thread digest, and feedback. Inline
locations live in threadContext; general discussions have no file location. Preserve
iteration/tracking context when assessing outdated comments; do not assume an old
line number names the current code. Fetch complete conversation replies. Deleted
threads/comments and system events are excluded, but a deleted root must not hide
live replies. All authors matter, including the PR author and bots. Unknown comment
schemas fail closed; unknown thread state stays unresolved for assessment.

## Judge, fix, and verify

Read `evaluation-rubric.md` before judging. In pipeline mode also read
`pipeline-mode.md`. Consolidate related findings centrally; dispatch the bundled
`agents/pr-comment-resolver.md` prompt only for approved fixes. Pass Azure identity,
source IDs and resolved locations; inline and general Azure discussions both use
feedback_type review_thread because both have a thread resource.

Confirm the local checkout is the PR source repository and head before edits. Fix
only in inherited scope, validate the combined change, commit and push if authorized.
Do not copy the GitHub fetch/reply/resolve commands. Re-fetch after a push: both the
expected head and thread digest must describe the newly assessed state. The adapter
supports mutation only on active, same-repository PRs; fork PRs need a reported
limitation rather than guessing the owning checkout.

For each decision compose a natural reply that quotes the concern and cites the
pushed fix or concrete disproof. Use a UTF-8 body file, never interpolate comment text
into shell source. With explicit inherited reply permission:

```bash
SKILL_DIR="<absolute directory containing the resolve-pr-feedback SKILL.md just read>";
python3 "$SKILL_DIR/scripts/azure/feedback.py" reply --url "<full-pr-url>" --thread-id <id> --expected-head "<assessed-sha>" --expected-thread "<assessed-digest>" --body-file "<reply-file>"
```

The reply result contains the new thread digest. Inspect it before resolving. With
inherited resolution permission:

```bash
SKILL_DIR="<absolute directory containing the resolve-pr-feedback SKILL.md just read>";
python3 "$SKILL_DIR/scripts/azure/feedback.py" resolve --url "<full-pr-url>" --thread-id <id> --expected-head "<assessed-sha>" --expected-thread "<post-reply-digest>" --status fixed
```

Use fixed for a verified fix; byDesign for evidenced intentional behavior; wontFix
only for a legitimate, authorized decision not to apply; closed for an answered
non-actionable discussion. Never select a resolved status simply to clear a policy.
Human decisions stay active/pending. A needs-human reply carries decision context
and leaves the thread unresolved; return the rubric's typed residual **unchanged**,
using stable Azure thread URLs in sources and thread_urls. Missing action permission
narrows the run; it does not become implicit permission to reply or resolve.

The adapter refuses writes when the source head or assessed thread changed, and
reads back each result. Azure thread writes have no documented compare-and-swap
precondition here; the final read/write race remains a live limitation. If a write
fails ambiguously, fetch before retrying to avoid duplicate replies. Adapter errors
are evidence for the caller, not precomposed decision residuals.

After processing, re-fetch the same full/targeted scope and account for every remaining
item. If a committed fix closes an existing Unapplied review findings checkbox,
tick only that item through `az repos pr update` with the exact organization/PR and
a safely passed description, preserving the rest. Do not create a residual body
section. Report fixed/dismissed/replied items, verification, unresolved decisions,
and the final head to the owning babysitter so it can rearm its provider watcher.

## API contracts

All thread calls use REST 7.1:

- [Threads List](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/list?view=azure-devops-rest-7.1) and [Thread Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/get?view=azure-devops-rest-7.1): inline and general discussion, deleted flags, comment type and iteration context.
- [Comments Create](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-thread-comments/create?view=azure-devops-rest-7.1): POST a JSON object with content, parentCommentId, commentType 1.
- [Threads Update](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads/update?view=azure-devops-rest-7.1): PATCH only status, then GET to verify; states include active, pending, fixed, wontFix, closed, byDesign, unknown.
- [PR Get](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-request?view=azure-devops-rest-7.1), [Refs List](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/refs/list?view=azure-devops-rest-7.1), [Entra token authentication](https://learn.microsoft.com/en-us/azure/devops/cli/entra-tokens?view=azure-devops).
