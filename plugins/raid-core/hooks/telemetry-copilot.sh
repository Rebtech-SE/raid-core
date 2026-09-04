#!/usr/bin/env bash
# RAID opt-in usage telemetry for GitHub Copilot. Ported from the Claude Code telemetry
# hook and shipped as-is. See PRIVACY.md at the marketplace root.
#
# Copilot SESSION hook (supplementary -- NOT the per-skill path):
#   - Fires on `sessionStart` and reports ONE event per RAID-configured Copilot session:
#     a session/installation denominator, distinct from per-skill usage.
#   - Per-skill telemetry on Copilot is handled by telemetry.sh, NOT here. Earlier notes
#     claimed per-skill was "structurally impossible" on Copilot; that was WRONG.
#     Re-verified on Copilot CLI 1.0.64 (2026-06-24): Copilot DOES expose a `skill` tool
#     and fires PostToolUse for it, so hooks.json registers a `matcher:"skill"` entry ->
#     telemetry.sh that captures real per-skill events. This hook remains only to count
#     sessions where RAID was configured even when no skill ran.
#   - The payload is the five fields the ingest backend requires plus the optional
#     installation_id (the backend accepts that one extra key and rejects any other). The
#     event grain is encoded in `skill_name` as the sentinel "copilot:session-start" --
#     clearly not a real skill, so it never pollutes skill-usage analytics.
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
# The consequence is that Claude now fires this hook too. The event below is a
# Copilot-only session denominator -- Claude reports its own usage per-skill via the
# PostToolUse hook in telemetry.sh -- so it must not be emitted from a Claude
# session. Copilot sets COPILOT_CLI / COPILOT_PLUGIN_ROOT for plugin hooks; Claude
# sets neither. No Copilot marker, nothing to report.
[ -n "${COPILOT_CLI:-}${COPILOT_PLUGIN_ROOT:-}" ] || dbg_exit "not a Copilot session (no COPILOT_CLI/COPILOT_PLUGIN_ROOT)"
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
# commit is the release), so resolve in order: an explicit RAID_PLUGIN_VERSION
# (testing/host override), the install-cache version segment one or two levels
# above the plugin root (the short commit SHA when version-less; cache depth
# differs by host), the git HEAD of the plugin root (directory sources and
# authoring checkouts), else "unknown". Copilot sets ${CLAUDE_PLUGIN_ROOT} for
# plugin hooks, same as Claude. Sanitized like the other interpolated fields so
# the JSON-safety guarantee holds uniformly.
VERSION=""
CANDIDATES="$(printf '%s' "${RAID_PLUGIN_VERSION:-}" | tr -d '\\"[:cntrl:]' | cut -c1-100)"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  CANDIDATES="$CANDIDATES
$(basename "$CLAUDE_PLUGIN_ROOT" | tr -d '\\"[:cntrl:]' | cut -c1-100)
$(basename "$(dirname "$CLAUDE_PLUGIN_ROOT")" | tr -d '\\"[:cntrl:]' | cut -c1-100)
$(basename "$(dirname "$(dirname "$CLAUDE_PLUGIN_ROOT")")" | tr -d '\\"[:cntrl:]' | cut -c1-100)"
fi
while IFS= read -r CAND; do
  # semver-ish (1.2 / 1.2.3) or a >=7-char lowercase hex commit SHA; anything
  # else (a plugin/marketplace name, "plugins", "/") is not a release marker.
  case "$CAND" in
    [0-9]*.[0-9]*[0-9]*|[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) VERSION="$CAND"; break ;;
  esac
done <<EOF
$CANDIDATES
EOF
if [ -z "$VERSION" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  VERSION=$(git -C "${CLAUDE_PLUGIN_ROOT}" rev-parse --short HEAD 2>/dev/null | cut -c1-100)
  VERSION=$(printf '%s' "$VERSION" | tr -d '\\"[:cntrl:]')
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
  "$TS" "copilot:session-start" "$VERSION" "$ENGAGEMENT" "$SESSION" "$INSTALL")

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
