#!/usr/bin/env bash
# RAID opt-in usage telemetry: the SESSION hook. See PRIVACY.md at the marketplace root.
#
# NAME IS HISTORICAL. This was Copilot-only when it was written and the filename kept
# that; it now runs on BOTH hosts. Renaming it would break the one place a path to it
# is recorded outside the plugin tree -- the user-level Copilot hooks config that
# INSTALL.md writes as a workaround for copilot-cli#3659 -- which a plugin update does
# not rewrite, so the rename would silently kill session telemetry on those machines.
#
# SESSION hook (supplementary -- NOT the per-skill path):
#   - Fires on SessionStart and reports ONE event per RAID-configured session on either
#     host: the session/installation denominator, distinct from per-skill usage. Without
#     it a session is only visible when a skill happened to run, so no rate ("RAID was
#     used in N of M sessions") is computable -- only totals, which also rise when a new
#     engagement is signed.
#   - Per-skill telemetry is handled by telemetry.sh on BOTH hosts, NOT here. Earlier
#     notes claimed per-skill was "structurally impossible" on Copilot; that was WRONG.
#     Re-verified on Copilot CLI 1.0.64 (2026-06-24): Copilot DOES expose a `skill` tool
#     and fires PostToolUse for it, so hooks.json registers a `matcher:"skill"` entry ->
#     telemetry.sh that captures real per-skill events. This hook only counts sessions
#     where RAID was configured, including those where no skill ran.
#   - The payload is the five fields the ingest backend requires plus the optional
#     installation_id (the backend accepts that one extra key and rejects any other). The
#     event grain is encoded in `skill_name` as the sentinel "claude:session-start" or
#     "copilot:session-start" -- clearly not real skills, so they never pollute
#     skill-usage analytics. Downstream MUST exclude them from skill facts and use them
#     as the session denominator instead; raid-telemetry's ingest notebook does.
#   - plugin_version is resolved at runtime (RAID_PLUGIN_VERSION override, the
#     install-cache version segment -- the short commit SHA, the git HEAD of the
#     plugin root, else "unknown"); manifests are version-less by policy.
#
# Sends NOTHING unless the engagement repo's .raid/config.yaml contains
# `telemetry: enabled: true`. Kill switch: RAID_TELEMETRY_DISABLED=1.
# Local debug: set RAID_TELEMETRY_DEBUG=1 to append one decision line per run to a
# gitignored .raid/telemetry-debug.log (the gate that caused an early exit, or the
# payload it dispatched). Local-only, off by default, never transmitted.
# Plain shell + curl; fire-and-forget; every failure path exits 0 silently.

set -u

# Append a pattern to .raid/.gitignore once (idempotent). Order-independent, so
# neither installation_id nor the debug log can be left un-ignored depending on
# which writer ran first. Assumes .raid/ exists (callers ensure it).
#
# Returns 0 ONLY when the pattern is confirmed present -- callers use that as a
# gate before writing anything into the repo. A silent best-effort append was not
# enough: on a read-only or permission-denied .raid/ the append fails, and the
# file it was meant to ignore would then be written anyway and could be committed
# into a customer's repository.
gi_add() {
  grep -qxF "$1" .raid/.gitignore 2>/dev/null && return 0
  printf '%s\n' "$1" >> .raid/.gitignore 2>/dev/null || return 1
  grep -qxF "$1" .raid/.gitignore 2>/dev/null
}

# Opt-in LOCAL debug log (RAID_TELEMETRY_DEBUG=1): one decision line per run in a
# gitignored .raid/telemetry-debug.log -- either the gate that caused an early exit
# or the payload it dispatched. Independent of the opt-in gate and the kill switch
# (so it can record "disabled"/"not opted in" too), off by default, never leaves the
# machine, capped to the last 500 lines. dbg() is a no-op unless debug is on, so the
# normal path is unchanged. All paths swallow errors and never alter the exit code.
DEBUG_LOG=".raid/telemetry-debug.log"
dbg() {
  [ -n "${RAID_TELEMETRY_DEBUG:-}" ] || return 0
  mkdir -p .raid 2>/dev/null || return 0
  # No ignore entry, no log: the debug log carries full payloads, so it must
  # never be writable-but-committable inside a customer repo.
  gi_add telemetry-debug.log || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$DEBUG_LOG" 2>/dev/null || true
  tail -n 500 "$DEBUG_LOG" 2>/dev/null > "$DEBUG_LOG.tmp" \
    && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG" 2>/dev/null || true
}
dbg_exit() { dbg "exit: $1"; exit 0; }

[ -n "${RAID_TELEMETRY_DISABLED:-}" ] && dbg_exit "kill switch RAID_TELEMETRY_DISABLED set"
# Host gate. hooks.json registers this under the capitalised `SessionStart` key in
# Claude's nested {hooks: [...]} shape, because that is the one form BOTH hosts
# accept. Claude Code validates hook event names against a fixed enum and fails the
# WHOLE plugin on an unknown key -- the old lowercase `sessionStart` made every
# Claude install fail with "Hook load failed", taking the pipeline, skills and
# reviewer agents down with it (`claude plugin validate` on 2.1.237:
# "hooks.sessionStart: Invalid key in record"). Copilot accepts either spelling and
# both shapes (verified 1.0.80), so capitalised+nested costs it nothing.
#
# Both hosts fire this hook, and BOTH now report -- the sentinel names which one.
#
# This used to be Copilot-only, on the reasoning that Claude "reports its own usage
# per-skill". That was the wrong call for measurement: without a session event a
# Claude session only exists in the data if a RAID skill happened to run, so there
# is no denominator and no rate is computable -- "RAID was used in 6 of 10 sessions,
# up from 3" cannot be expressed at all, only ever-rising totals that also rise when
# a new engagement is signed. One event per session fixes that, and per-skill
# telemetry is unchanged.
#
# The host is named in the sentinel rather than inferred downstream, because the
# analytics side cannot tell them apart from any other field. Detection is by env
# marker: Copilot sets COPILOT_CLI / COPILOT_PLUGIN_ROOT for plugin hooks; Claude
# Code sets CLAUDECODE / CLAUDE_CODE_ENTRYPOINT. Copilot is checked FIRST because it
# also sets CLAUDE_PLUGIN_ROOT for plugin hooks (which is why that variable is not a
# usable Claude marker). An unrecognised host exits rather than guessing: a
# mislabelled session biases exactly the Claude-vs-Copilot comparison this event is
# for, and a missing row is recoverable where a wrong one is not.
if [ -n "${COPILOT_CLI:-}${COPILOT_PLUGIN_ROOT:-}" ]; then
  SENTINEL="copilot:session-start"
elif [ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  SENTINEL="claude:session-start"
else
  dbg_exit "unrecognised host (no COPILOT_CLI/COPILOT_PLUGIN_ROOT, no CLAUDECODE/CLAUDE_CODE_ENTRYPOINT)"
fi
command -v curl >/dev/null 2>&1 || dbg_exit "curl not on PATH"

DEFAULT_ENDPOINT="https://raid-plugin-telemetry.azurewebsites.net/api/ingest"
INPUT=$(cat)

# Config resolution. Copilot runs the hook with cwd at the workspace root (the
# entry sets cwd "."). Prefer the per-repo engagement config; when there is none,
# fall back to a global opt-in config under
# ${RAID_GLOBAL_CONFIG_DIR:-${HOME:-$USERPROFILE}/.raid} so a global install (the
# default on Copilot) can report. A per-repo .raid/config.yaml that EXISTS is
# authoritative -- even without a telemetry block -- so global is consulted ONLY
# when no per-repo config is present (a globally opted-in consultant never leaks
# telemetry into a client repo that didn't opt in). RAID_GLOBAL_CONFIG_DIR also
# keeps the test suite hermetic. Identical resolution to the Claude hook.
GLOBAL_DIR="${RAID_GLOBAL_CONFIG_DIR:-${HOME:-${USERPROFILE:-}}/.raid}"
SCOPE="repo"
if [ -f ".raid/config.yaml" ]; then
  CFG=".raid/config.yaml"
  ID_FILE=".raid/installation_id"
elif [ -f "$GLOBAL_DIR/config.yaml" ]; then
  CFG="$GLOBAL_DIR/config.yaml"
  ID_FILE="$GLOBAL_DIR/installation_id"
  SCOPE="global"
else
  dbg_exit "no .raid/config.yaml (and no global $GLOBAL_DIR/config.yaml)"
fi

# Opt-in gate: `enabled: true` within the telemetry: block, scoped by indentation
# (contiguous indented lines under `telemetry:`). Identical to the Claude hook.
TELEMETRY_BLOCK=$(awk '/^telemetry:/{f=1;next} f&&/^[^ \t]/{exit} f' "$CFG" 2>/dev/null)
[ -n "$TELEMETRY_BLOCK" ] || dbg_exit "no telemetry block in config"
printf '%s' "$TELEMETRY_BLOCK" | grep -Eq '^[[:space:]]+enabled:[[:space:]]*true[[:space:]]*$' || dbg_exit "telemetry.enabled not true"

ENGAGEMENT=$(printf '%s' "$TELEMETRY_BLOCK" | sed -n 's/^[[:space:]]*engagement_id:[[:space:]]*//p' | head -1)
# Per-repo without an explicit id falls back to `customer:`; a global config uses
# the sentinel "global" so global usage never masquerades as engagement data.
if [ -z "$ENGAGEMENT" ]; then
  if [ "$SCOPE" = "global" ]; then
    ENGAGEMENT="global"
  else
    ENGAGEMENT=$(sed -n 's/^customer:[[:space:]]*//p' "$CFG" | head -1)
  fi
fi
# Free-form config value interpolated into JSON: strip JSON-special and control chars
# (and cap length) so an odd id can't malform the body.
ENGAGEMENT=$(printf '%s' "$ENGAGEMENT" | tr -d '\\"[:cntrl:]' | cut -c1-200)
[ -n "$ENGAGEMENT" ] || ENGAGEMENT="unknown"

# Session id from the sessionStart payload. Copilot emits two payload shapes -- camelCase
# ("sessionId") and snake_case ("session_id") -- so accept either.
SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$SESSION" ] || SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
# Same JSON-safety sanitization applied to engagement_id: strip JSON-special and control
# chars (a trailing backslash would otherwise malform the body) and cap length.
SESSION=$(printf '%s' "$SESSION" | tr -d '\\"[:cntrl:]' | cut -c1-200)
[ -n "$SESSION" ] || SESSION="unknown"

# Release identifier for plugin_version. Native manifests are version-less (the
# commit is the release), so resolve in order:
#   1. RAID_PLUGIN_VERSION -- explicit override (testing, or a host that knows).
#   2. A release-looking segment ANYWHERE in the plugin root path. Claude keys a
#      git-marketplace install by the adopted version (the short commit SHA when
#      version-less), but its depth differs by host and marketplace layout --
#      Claude puts it BELOW the plugin name (.../raid-core/<ver>), Copilot has no
#      such segment at all -- so walk every segment instead of guessing a depth.
#   3. git HEAD of the plugin root -- authoring checkouts and directory sources.
#   4. .raid-release: the SHA stamped into the install root at install time (see
#      INSTALL.md), used ONLY while it is still fresh. Hosts update plugins on
#      their own (Claude Code auto-updates git marketplaces at startup; Copilot
#      does with autoUpdate), re-copying the tree without re-running any step of
#      ours and leaving the stamp describing a release that is no longer
#      installed. A re-copy rewrites .claude-plugin/plugin.json, so a manifest
#      newer than the stamp means the stamp is stale -- discard it. Reporting
#      some *other* release is worse than reporting none.
#   5. gen-<plugin.json mtime, epoch seconds> -- no SHA is recoverable (a Copilot
#      install carries neither a version segment nor a .git), but the manifest's
#      mtime still identifies THIS installed generation and changes on every
#      update. Stale by construction is impossible, which is what makes it the
#      floor rather than "unknown".
#   6. "unknown" -- no plugin root, or an unreadable one.
# Every candidate is sanitized like the other interpolated fields so the
# JSON-safety guarantee holds.
is_release_marker() {
  [ -n "${1:-}" ] || return 1
  # semver-ish: leading digit, digits and dots only, at least one dot (1.2, 1.2.3).
  case "$1" in
    [0-9]*)
      if [ -z "$(printf '%s' "$1" | tr -d '0-9.')" ] && [ "$1" != "${1%.*}" ]; then
        return 0
      fi
      ;;
  esac
  # commit SHA: 7-40 chars, lowercase hex throughout. Checking the WHOLE segment
  # matters now that every path segment is a candidate -- a prefix-only match
  # would accept any directory that happens to start with seven hex characters.
  if [ ${#1} -ge 7 ] && [ ${#1} -le 40 ] && [ -z "$(printf '%s' "$1" | tr -d '0-9a-f')" ]; then
    return 0
  fi
  return 1
}

VERSION=""
CANDIDATES="$(printf '%s' "${RAID_PLUGIN_VERSION:-}" | tr -d '\\"[:cntrl:]' | cut -c1-100)"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # Leaf first, then two parents -- the only positions a host has ever put the
  # version segment in (Claude puts it at the leaf, .../raid-core/<ver>). The
  # window stays narrow on purpose: every extra segment is another chance for an
  # unrelated directory that happens to be lowercase hex to be read as a SHA.
  SEG="$CLAUDE_PLUGIN_ROOT"
  DEPTH=0
  while [ -n "$SEG" ] && [ "$SEG" != "/" ] && [ "$SEG" != "." ] && [ "$DEPTH" -lt 3 ]; do
    CANDIDATES="$CANDIDATES
$(basename "$SEG" | tr -d '\\"[:cntrl:]' | cut -c1-100)"
    SEG=$(dirname "$SEG")
    DEPTH=$((DEPTH + 1))
  done
fi
while IFS= read -r CAND; do
  if is_release_marker "$CAND"; then VERSION="$CAND"; break; fi
done <<EOF
$CANDIDATES
EOF

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  MANIFEST="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  STAMP="$CLAUDE_PLUGIN_ROOT/.raid-release"
else
  MANIFEST=""
  STAMP=""
fi

if [ -z "$VERSION" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  VERSION=$(git -C "${CLAUDE_PLUGIN_ROOT}" rev-parse --short HEAD 2>/dev/null | cut -c1-100)
  VERSION=$(printf '%s' "$VERSION" | tr -d '\\"[:cntrl:]')
fi

# The stamp, only while the manifest has not been rewritten under it. `find
# -newer` is the portable mtime comparison -- `stat` flags differ between BSD
# and GNU, and we need this one to work everywhere the hook runs.
if [ -z "$VERSION" ] && [ -n "$STAMP" ] && [ -f "$STAMP" ]; then
  if [ ! -f "$MANIFEST" ] || [ -z "$(find "$MANIFEST" -newer "$STAMP" 2>/dev/null)" ]; then
    VERSION=$(head -1 "$STAMP" 2>/dev/null | tr -d '\\"[:cntrl:]' | cut -c1-100)
    is_release_marker "$VERSION" || VERSION=""
  fi
fi

if [ -z "$VERSION" ] && [ -n "$MANIFEST" ] && [ -f "$MANIFEST" ]; then
  # GNU dialect FIRST, then BSD. The reverse order looks equivalent and is not:
  # BSD stat rejects `-c`, but GNU stat accepts `-f` as a *filesystem*-status
  # request, succeeds, and prints an unrelated filesystem id -- so trying BSD
  # first silently yields a constant that never changes when the file does.
  MTIME=$(stat -c %Y "$MANIFEST" 2>/dev/null || stat -f %m "$MANIFEST" 2>/dev/null)
  MTIME=$(printf '%s' "${MTIME:-}" | tr -cd '0-9' | cut -c1-20)
  # Accept only a plausible Unix timestamp -- exactly ten digits, so 2001-09
  # through 2286-11. Belt and braces after the above: whatever an unexpected
  # stat dialect prints, it does not get to masquerade as an mtime.
  case "$MTIME" in
    [1-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) VERSION="gen-$MTIME" ;;
  esac
fi

[ -n "$VERSION" ] || VERSION="unknown"

# Engagement-scoped pseudonymous id -- random, generated once per checkout, stored
# (gitignored) in .raid/installation_id. Counts DISTINCT people per engagement
# (COUNT(DISTINCT installation_id) per engagement_id) without identifying anyone.
# For a per-repo checkout this is NOT a global machine id: scoped to the
# engagement and regenerated per checkout, so a person is never linkable across
# engagements. The GLOBAL config is the deliberate exception (a persistent
# per-machine pseudonym; see PRIVACY.md). ID_FILE was selected above by scope.
# Identical resolution to the Claude hook.
if [ -f "$ID_FILE" ]; then
  INSTALL=$(head -1 "$ID_FILE" 2>/dev/null)
else
  if command -v uuidgen >/dev/null 2>&1; then
    INSTALL=$(uuidgen | tr 'A-Z' 'a-z')
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    INSTALL=$(cat /proc/sys/kernel/random/uuid)
  else
    INSTALL=$(head -c16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
  fi
  # Persist only when we can guarantee it will not be committed -- for a per-repo
  # checkout the .gitignore entry must be confirmed FIRST. If it cannot be
  # written, the id stays in memory for this run only. See telemetry.sh.
  mkdir -p "$(dirname "$ID_FILE")" 2>/dev/null || true
  if [ "$SCOPE" != "repo" ] || gi_add installation_id; then
    ( umask 077; printf '%s\n' "$INSTALL" > "$ID_FILE" ) 2>/dev/null || true
  fi
fi
INSTALL=$(printf '%s' "$INSTALL" | tr -d '\\"[:cntrl:]' | cut -c1-64)
[ -n "$INSTALL" ] || INSTALL="unknown"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EVENT=$(printf '{"ts":"%s","skill_name":"%s","plugin_version":"%s","engagement_id":"%s","session_id":"%s","installation_id":"%s"}' \
  "$TS" "$SENTINEL" "$VERSION" "$ENGAGEMENT" "$SESSION" "$INSTALL")

ENDPOINT="${RAID_TELEMETRY_ENDPOINT:-$DEFAULT_ENDPOINT}"
# Logged as an ATTEMPT, not a delivery: the POST is fire-and-forget (backgrounded,
# never waited on), so the hook never learns whether curl succeeded. A "posting"
# line means all gates passed and the POST was dispatched to $ENDPOINT -- if the
# event never lands, the failure is downstream (network/endpoint/validator), not
# the hook's gating.
dbg "posting to $ENDPOINT: $EVENT"
nohup curl -s -m 3 -o /dev/null -X POST -H "Content-Type: application/json" \
  -d "$EVENT" "$ENDPOINT" >/dev/null 2>&1 &

exit 0
