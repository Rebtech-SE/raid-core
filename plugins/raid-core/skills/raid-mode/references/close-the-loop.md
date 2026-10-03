# Close the loop

A unit built for a ticket is not done when its tests go green. It is done when the record
says so: the ledger, the ticket, and the session file. This page is the detail behind the
"Close the loop" step in `raid-mode` and the claim step in `wayfinder`.

With no `docs/agents/issue-tracker.md`, there is no ticket to close: write the ledger lines
and skip the rest silently.

## At claim

Claim the ticket with the tracker's **Claim** recipe (`setup-raid`'s
`references/trackers/<provider>.md`), then record it in `.raid/session.json`, so the Stop
hook and `commit-push-pr` know about it. Ignore the file before writing it:

```bash
mkdir -p .raid
grep -qxF session.json .raid/.gitignore 2>/dev/null || printf 'session.json\n' >> .raid/.gitignore
```

The file is local state, never committed. One ticket per line inside `tickets`, so the hook
can read it without a JSON parser:

```json
{"tickets": [
{"id": "412", "provider": "azure-devops", "status": "claimed", "planned_ids": ["TP-customer-01", "TP-customer-02"], "base": "<git rev-parse HEAD at claim>", "ledger_lines": 37}
]}
```

| Field | Meaning |
|---|---|
| `id` | The tracker id as the tracker writes it (`412`, `DATA-17`, `ENG-123`) |
| `provider` | From `docs/agents/issue-tracker.md` |
| `status` | `claimed` -> `resolved` once the Resolve comment is posted, or `released` when the ticket is handed back unfinished with a comment saying why |
| `planned_ids` | The TP ids (or Acceptance lines) the ticket covers, per `references/planned-tests.md`. Empty for a `wayfinder` decision ticket |
| `base` | The commit the work started from; the hook diffs against it |
| `ledger_lines` | `wc -l < docs/testing/test-results.jsonl` at claim, `0` when the file is absent |

Add a line per claimed ticket; never delete one. Change only its `status`.

## At done

1. **The ledger.** One line per covered planned test, with `planned_id` and `ticket` set
   (`write-test-report`'s `references/results-ledger.md`). A planned test that could not be
   built gets no fake line -- it goes in the Resolve comment instead.
2. **The Resolve comment** on the ticket, with the tracker's **Resolve** recipe: what was
   built, which planned ids are green and which are red or not built (and why), and whether
   it was verified against real data or is "not validated against data".
3. **The state.** Move the ticket to the done state -- the recipe's Close, read through the
   `mapping` block and any `## Types and states` in `docs/agents/issue-tracker.md` -- **or**
   leave it open for the PR merge to close: `commit-push-pr` links a ticket this session
   claimed (`AB#<id>`, `Closes #<id>`). Say which in the comment.
4. **The session file.** Set the ticket's `status` to `resolved`.

## The Stop hook

On Claude Code, `raid-core`'s Stop hook (`hooks/close-the-loop.sh`) reads
`.raid/session.json` when the agent tries to end its turn. It exits silently when the file
is absent, and otherwise blocks the stop, once per stop, when:

- a ticket is still `claimed`, or
- model files changed since a ticket's `base` and the ledger has no lines beyond its
  `ledger_lines`.

Stopping to wait for the user -- an approval gate, a question, a push that needs a
go-ahead -- is legitimate: say so, and the next stop goes through. Codex and Copilot CLI do
not run this hook, so there the steps above are the whole mechanism.
