# Review-bot triage

Used by `babysit` when handling comments from review automation -- Bugbot, GitHub Copilot
code review, Azure DevOps PR bots, GitLab suggestions, or an agentic security review. The
goal is not to ignore the bot by default. The goal is to stop treating every comment as a
required code change.

The same rubric works on any host: what differs is only how you fetch and reply to the
thread (see the babysit SKILL.md for the per-host commands).

## Decision rubric

Classify each thread before acting:

- **`fix`** -- the comment identifies a plausible correctness, security, privacy, data-loss,
  auth, billing, migration, idempotency, race, **grain, SCD, referential-integrity or
  data-retention** issue. Fix it in the lowest owning PR, then reply with the commit id and
  resolve the thread.
- **`dismiss`** -- the comment matches a documented low-risk noisy pattern and the current
  code proves the concern needs no change. Reply with the short concrete disproof, then
  resolve.
- **`ask`** -- the comment is novel, high-severity, security/privacy/data-related, or
  ambiguous. Ask the user instead of guessing.

When in doubt, ask. Skipping a noisy code-quality comment is cheap; skipping a real data or
security bug is not -- on a customer's platform a wrong number reaches a report before
anyone notices.

## Verify before you classify

A claim about data is cheap to check and expensive to guess at. If a bot claims a join
fans out, a key is not unique, a column can be null, or a filter drops rows, **run the
query** against the real table before classifying (the validate-against-real-data rule in
`raid-core/AGENTS.md`). A row count is a concrete disproof; an opinion is not. If you have
no read access, say so and classify `ask`, never `dismiss`.

## Learned pattern format

Add future patterns in this shape:

```markdown
### <short pattern name>

- Confidence: candidate | recurring | strong
- Skip when: <conditions that must be true>
- Do not skip when: <risk boundaries>
- Example signal: <phrases or code context that identify the pattern>
- Source: <PR/comment reference or short historical note>
```

Use `candidate` for one or two examples. Use `recurring` after multiple real dismissals. Use
`strong` only when the pattern is narrow, repeatedly verified, and low-risk.

## Recurring skip candidates

### Upstack or stack-local usage the bot cannot see

- Confidence: candidate
- Skip when: the bot flags a model, macro, helper, export or file as unused, and the stack's
  upper diffs (or the PR base/head chain) show it is consumed by a later PR.
- Do not skip when: the PR is not part of a stack, the symbol is a published contract (a
  gold-layer table, a shared macro, a public API), or the supposed upstack use cannot be
  verified.
- Example signal: "model is never referenced" on an intermediate model a later PR builds on.

### Temporary duplication during a parallel migration

- Confidence: candidate
- Skip when: the PR intentionally duplicates a small amount of logic to keep a new path
  parallel to an old path that is being deleted, replaced, or run side-by-side for parity
  checking.
- Do not skip when: the duplicated logic touches security, billing, access control, a shared
  business definition, or a metric definition that would then drift between the two copies.
- Example signal: "duplicated transformation logic" on a dual-run migration PR whose
  description says the legacy path is deleted in a follow-up.

### An upstream contract already guarantees the invariant

- Confidence: candidate
- Skip when: the concern is already enforced upstream and visible -- a not-null or unique
  test on the source model, a NOT NULL column, a primary key, a schema contract, or a type
  invariant in the current diff.
- Do not skip when: the invariant is assumed rather than enforced, lives in a system you do
  not control (a landing zone, a vendor extract), depends on load order, or crosses an
  incremental/full-refresh boundary where the guarantee only holds on a full run.
- Example signal: "this join could produce duplicates" where the right-hand model already
  carries a `unique` test on the join key -- confirm the test exists and is not disabled.

### Owner-declared follow-up or deferred cleanup

- Confidence: candidate
- Skip when: the PR owner explicitly says the issue is a known follow-up, the behavior is not
  made worse by this PR, and the area is not high-risk.
- Do not skip when: you are acting without owner input, the issue is medium/high-severity
  product or data behavior, or deferring would merge a new regression.
- Example signal: "we'll backfill that properly later" in the PR description.

### Self-withdrawn or explicit false-positive comments

- Confidence: recurring
- Skip when: the comment body, or a later reply from the same bot, says the finding is
  withdrawn, compliant, or a false positive, and you can verify the relevant rule locally.
- Do not skip when: the only evidence is a human saying "false positive" on a high-risk issue
  without explanation.
- Example signal: a naming-convention comment whose own body notes the file already complies.

### Stale finding already fixed later in the same PR

- Confidence: candidate
- Skip when: the bot (or a security review) claims a missing check, and the current PR tip
  clearly contains that exact check with a test -- typically added in a hardening commit that
  postdates the review run.
- Do not skip when: the cited guard is a no-op for the case under discussion, runs *after*
  the side effect it is meant to guard, or covers only part of the claimed surface.
- Example signal: a HIGH "missing authorization check" while the guard is called before the
  side effect on the tip.

### Widening a deliberately narrow error condition would mask the real error

- Confidence: candidate
- Skip when: the finding asks to broaden a narrow error condition (a specific error code,
  status class, or exception type) into a catch-all, and the narrowness encodes a real
  distinction -- "the dependency is not installed" is not "the command ran and failed", and a
  broad retry would re-run a legitimate failure and then report the fallback's error instead
  of the true one.
- Do not skip when: the narrow condition misses a case in the *same* category, the unhandled
  path loses data or leaves partial state (a half-written load, an unreleased lock), or the
  retry is idempotent **and** the original error is still surfaced.
- Example signal: "only retries on ENOENT" pointing at a fallback that exists for a missing
  binary rather than a failed command.

## Ask by default

Do not auto-skip these categories, even if a previous PR dismissed something similar:

- Security, privacy, auth, billing, permission-boundary, data-retention and PII findings.
- High-severity findings.
- Migration, schema-change, idempotency, concurrency and cross-system behavior findings.
- **Data-shaped findings:** grain or uniqueness claims, SCD effective-dating and
  current-flag logic, incremental vs full-refresh divergence, late-arriving or
  out-of-order data, timezone and watermark handling, referential integrity across the
  medallion layers, and anything that changes a metric definition.
- Comments where the suggested fix is small and clearly reduces risk without changing intent.

Humans sometimes dismiss security and data-flow comments on their own repos. Treat those as
owner judgment calls, not team-wide skip rules.

## Candidate learnings

Append new candidate learnings here during or after a babysit when they look reusable but not
yet mature. Promote a candidate into the section above once several PRs confirm it. Anything
durable enough to change how the next engagement works belongs in `docs/solutions/` instead,
and anything carrying a customer's names, hostnames or data never leaves the engagement repo.
