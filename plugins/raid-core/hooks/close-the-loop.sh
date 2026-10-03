#!/usr/bin/env bash
# RAID close-the-loop Stop hook. See skills/raid-mode/references/close-the-loop.md.
#
# Does NOTHING unless the engagement repo has a .raid/session.json -- the gitignored
# file raid-mode and wayfinder write when a session claims a ticket. With one, it
# blocks the agent's stop (Claude Code's {"decision":"block"} output) when:
#   - a ticket in it is still "claimed" (no Resolve comment recorded), or
#   - model files changed since a ticket's "base" commit and the results ledger has
#     no lines beyond the "ledger_lines" count taken at claim.
# Kill switch: set RAID_CLOSE_LOOP_DISABLED=1.
#
# One block per stop: when Claude is already continuing because of a Stop hook
# (stop_hook_active), the stop goes through, so an agent that legitimately stops to
# wait for the user is reminded once and never looped.
#
# session.json keeps one ticket object per line, so plain sed reads it -- no jq, no
# python. Every failure path ends in a silent exit 0: this hook must never break a
# session.

set -u

[ -n "${RAID_CLOSE_LOOP_DISABLED:-}" ] && exit 0
SESSION_FILE=".raid/session.json"
[ -f "$SESSION_FILE" ] || exit 0

INPUT=$(cat 2>/dev/null)
printf '%s' "$INPUT" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

LEDGER="docs/testing/test-results.jsonl"
LEDGER_NOW=0
[ -f "$LEDGER" ] && LEDGER_NOW=$(wc -l < "$LEDGER" 2>/dev/null | tr -cd '0-9')
[ -n "$LEDGER_NOW" ] || LEDGER_NOW=0

IN_GIT=0
git rev-parse --git-dir >/dev/null 2>&1 && IN_GIT=1

# A string field of one ticket line; sanitized because it ends up in JSON output.
field() {
  printf '%s' "$2" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | head -1 | tr -d '\\"[:cntrl:]' | cut -c1-100
}

# Model files changed since BASE: committed, staged, unstaged and untracked. Docs, RAID
# state and build output are not models.
models_changed() {
  {
    git diff --name-only "$1" -- 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | grep -Ev '^(docs/|\.raid/|target/|dbt_packages/|logs/)' \
    | grep -Eq '(\.sql|\.ipynb|notebook-content\.py)$|(^|/)models/'
}

REASONS=""
add_reason() { REASONS="${REASONS:+$REASONS }$1"; }

while IFS= read -r LINE; do
  case "$LINE" in *'"id"'*) ;; *) continue ;; esac
  ID=$(field id "$LINE")
  [ -n "$ID" ] || continue
  STATUS=$(field status "$LINE")
  [ "$STATUS" = "released" ] && continue

  if [ "$STATUS" = "claimed" ]; then
    add_reason "Ticket $ID is claimed but not resolved: post the tracker's Resolve comment (what was built, which planned ids are green or red, verified against data or not), move it to done or leave it for the PR merge, then set its status to resolved in .raid/session.json."
  fi

  BASE=$(field base "$LINE" | tr -cd '0-9a-f')
  LEDGER_AT_CLAIM=$(printf '%s' "$LINE" | sed -n 's/.*"ledger_lines"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
  [ -n "$LEDGER_AT_CLAIM" ] || LEDGER_AT_CLAIM=0
  if [ "$IN_GIT" = 1 ] && [ -n "$BASE" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null \
    && [ "$LEDGER_NOW" -le "$LEDGER_AT_CLAIM" ] && models_changed "$BASE"; then
    add_reason "Model files changed since ticket $ID was claimed, but $LEDGER has no new lines: append one line per test run, with planned_id and ticket set."
  fi
done < "$SESSION_FILE"

[ -n "$REASONS" ] || exit 0

REASONS="RAID close the loop: $REASONS If you are stopping to wait for the user, say so and stop again."
printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$REASONS" | tr -d '\\"[:cntrl:]')"
exit 0
