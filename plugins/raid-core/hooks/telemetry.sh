#!/usr/bin/env bash
# RAID opt-in usage telemetry. See PRIVACY.md at the marketplace repo root.
#
# Sends NOTHING unless the engagement repo's .raid/config.yaml contains
# `telemetry: enabled: true` (written by setup-raid after an explicit opt-in).
# Kill switch: set RAID_TELEMETRY_DISABLED=1.
# Local debug: set RAID_TELEMETRY_DEBUG=1 to append one decision line per run to a
# gitignored .raid/telemetry-debug.log (the gate that caused an early exit, or the
# payload it dispatched). Local-only, off by default, never transmitted.
#
# Payload when opted in -- and nothing else:
#   {ts, skill_name, plugin_version, engagement_id, session_id, installation_id}
# installation_id is a random, engagement-scoped, gitignored pseudonym -- it lets
# analysis count DISTINCT people per engagement, but is NOT a global machine id
# (see PRIVACY.md). No prompts, no code, no paths, no names/usernames/hosts/IPs.
#
# Plain shell + curl only (no python/node). Fire-and-forget: the POST runs
# backgrounded with a 3s cap and all failure paths end in silent exit 0 --
# telemetry must never add latency or surface errors in the session.

set -u

# Append a pattern to .raid/.gitignore once (idempotent, best-effort). Order-
# independent, so neither installation_id nor the debug log can be left un-ignored
# depending on which writer ran first. Assumes .raid/ exists (callers ensure it).
# Returns 0 ONLY when the pattern is confirmed present in .raid/.gitignore --
# callers use that as a gate before writing anything into the repo. A silent
# best-effort append was not enough: on a read-only or permission-denied .raid/
# the append fails, and the file it was meant to ignore would then be written
# anyway and could be committed into a customer's repository.
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
command -v curl >/dev/null 2>&1 || dbg_exit "curl not on PATH"

DEFAULT_ENDPOINT="https://raid-plugin-telemetry.azurewebsites.net/api/ingest"
INPUT=$(cat)

# Config resolution. Hooks run from the session's project root. Prefer the
# per-repo engagement config; when there is none, fall back to a global opt-in
# config under ${RAID_GLOBAL_CONFIG_DIR:-${HOME:-$USERPROFILE}/.raid} so a global
# install (the default on Copilot) can report. Precedence is deliberate: a
# per-repo .raid/config.yaml that EXISTS is authoritative -- even without a
# telemetry block -- so global is consulted ONLY when no per-repo config is
# present. That keeps a globally opted-in consultant from ever leaking telemetry
# into a client engagement repo that didn't opt in. RAID_GLOBAL_CONFIG_DIR also
# lets the test suite point the global path at an empty dir (hermetic tests).
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

# Opt-in gate: an `enabled: true` within the telemetry: block, scoped by
# indentation (contiguous indented lines under `telemetry:`) -- a fixed
# line window could match an `enabled:` belonging to an adjacent block.
TELEMETRY_BLOCK=$(awk '/^telemetry:/{f=1;next} f&&/^[^ \t]/{exit} f' "$CFG" 2>/dev/null)
[ -n "$TELEMETRY_BLOCK" ] || dbg_exit "no telemetry block in config"
printf '%s' "$TELEMETRY_BLOCK" | grep -Eq '^[[:space:]]+enabled:[[:space:]]*true[[:space:]]*$' || dbg_exit "telemetry.enabled not true"

ENGAGEMENT=$(printf '%s' "$TELEMETRY_BLOCK" | sed -n 's/^[[:space:]]*engagement_id:[[:space:]]*//p' | head -1)
# Fall back per scope: a per-repo config without an explicit id uses `customer:`;
# a global config uses the sentinel "global" so global usage never masquerades as
# engagement data (and there is no `customer:` on a global config anyway).
if [ -z "$ENGAGEMENT" ]; then
  if [ "$SCOPE" = "global" ]; then
    ENGAGEMENT="global"
  else
    ENGAGEMENT=$(sed -n 's/^customer:[[:space:]]*//p' "$CFG" | head -1)
  fi
fi
# Free-form config value interpolated into JSON: strip JSON-special and
# control chars (and cap length) so an odd id can't malform the body.
ENGAGEMENT=$(printf '%s' "$ENGAGEMENT" | tr -d '\\"[:cntrl:]' | cut -c1-200)
[ -n "$ENGAGEMENT" ] || ENGAGEMENT="unknown"

# Skill name + session id out of the hook's single-line JSON payload (skill
# names and session ids are plain slugs, so a narrow sed match is safe). Both
# clients carry the invoked skill in tool_input.skill -- Claude via PostToolUse
# matcher "Skill", Copilot via matcher "skill" (verified Copilot CLI 1.0.64,
# 2026-06-24: Copilot DOES expose a `skill` tool and fires PostToolUse for it).
SKILL=$(printf '%s' "$INPUT" | sed -n 's/.*"skill"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$SKILL" ] || dbg_exit "no skill in payload"

# RAID skills only. The matcher fires for EVERY skill load (one Skill/skill tool
# serves them all); names of non-RAID skills -- the user's own, other plugins',
# a client's -- are none of our business and outside the PRIVACY.md disclosure.
# Two payload dialects identify a RAID skill differently:
#   - Claude namespaces skills by plugin (raid-core:<skill>, raid-fabric:<skill>),
#     so the namespace prefix itself proves provenance -- keep it as-is.
#   - Copilot passes the BARE skill name (no plugin prefix). Resolve it back to a
#     SKILL.md under a sibling raid-* plugin install dir (CLAUDE_PLUGIN_ROOT's
#     parent holds raid-core + the tiers) and namespace it the same way, so the
#     two clients' events line up in analytics. If it resolves to no RAID plugin,
#     it isn't ours -- drop it.
case "$SKILL" in
  raid-[a-z]*:*) : ;;  # already namespaced by Claude
  *)
    PLUGINS_DIR=$(dirname "${CLAUDE_PLUGIN_ROOT:-.}")
    OWNER=""
    for d in "$PLUGINS_DIR"/raid-*; do
      [ -f "$d/skills/$SKILL/SKILL.md" ] || continue
      OWNER=$(basename "$d"); break
    done
    [ -n "$OWNER" ] || dbg_exit "skill '$SKILL' not a RAID plugin skill"
    SKILL="$OWNER:$SKILL"
    ;;
esac
# Sanitize every field interpolated into the JSON body, not just the two that
# come from config. skill/session/version are read out of the hook payload and
# the plugin manifest, so a stray backslash would malform the body and the event
# would be dropped at the ingest validator. telemetry.ps1 and
# telemetry-copilot.sh already do this; keep the four hooks identical.
SKILL=$(printf '%s' "$SKILL" | tr -d '\\"[:cntrl:]' | cut -c1-200)
[ -n "$SKILL" ] || dbg_exit "skill empty after sanitizing"

SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
SESSION=$(printf '%s' "$SESSION" | tr -d '\\"[:cntrl:]' | cut -c1-200)
[ -n "$SESSION" ] || SESSION="unknown"

# Release identifier for plugin_version. Native manifests are version-less (the
# commit is the release), so resolve in order: an explicit RAID_PLUGIN_VERSION
# (testing/host override), the install-cache version segment one or two levels
# above the plugin root (Claude keys a git-marketplace install by the adopted
# version -- the short commit SHA when version-less; the exact cache depth differs
# by host and marketplace layout), the git HEAD of the plugin root (authoring
# checkouts and directory-marketplace sources), else "unknown". Every candidate is
# sanitized like the other interpolated fields so the JSON-safety guarantee holds.
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

# Engagement-scoped pseudonymous id: a random value generated once per checkout
# and stored (gitignored) in .raid/installation_id. It lets analysis count
# DISTINCT people on an engagement (COUNT(DISTINCT installation_id) per
# engagement_id) without identifying anyone. Deliberately NOT a global machine
# id: scoped to this engagement repo and regenerated per checkout, so one
# person's activity is never linkable across engagements. The GLOBAL config is
# the deliberate exception: ~/.raid/installation_id is a persistent per-machine
# pseudonym (there is no per-checkout boundary off a repo), disclosed as such in
# PRIVACY.md and used only under the same explicit opt-in. ID_FILE was selected
# above by scope (per-repo vs global).
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
  # Persist only when we can guarantee it will not be committed. For a per-repo
  # checkout that means the .gitignore entry must be confirmed FIRST; if it
  # cannot be written, the id stays in memory for this run only. A fresh id next
  # run costs a little DISTINCT-person precision, which is strictly preferable to
  # leaving a rebtech artifact behind in a customer's repository. The global id
  # lives outside any repo, so there is nothing to ignore.
  mkdir -p "$(dirname "$ID_FILE")" 2>/dev/null || true
  if [ "$SCOPE" != "repo" ] || gi_add installation_id; then
    ( umask 077; printf '%s\n' "$INSTALL" > "$ID_FILE" ) 2>/dev/null || true
  fi
fi
INSTALL=$(printf '%s' "$INSTALL" | tr -d '\\"[:cntrl:]' | cut -c1-64)
[ -n "$INSTALL" ] || INSTALL="unknown"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EVENT=$(printf '{"ts":"%s","skill_name":"%s","plugin_version":"%s","engagement_id":"%s","session_id":"%s","installation_id":"%s"}' \
  "$TS" "$SKILL" "$VERSION" "$ENGAGEMENT" "$SESSION" "$INSTALL")

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
