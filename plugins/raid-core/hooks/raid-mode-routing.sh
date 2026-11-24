#!/usr/bin/env bash
# RAID routing hook (SessionStart). Adds one line to the session's context so data-platform
# work starts in raid-mode instead of depending on the model picking it from a long skill
# list: in RAID's own task eval raid-mode was opened in 1 of 6 headless runs, with
# nothing in the session pointing at it.
#
# Claude Code only: it reads SessionStart hookSpecificOutput.additionalContext. Other hosts
# get the same sentence from the engagement repo's AGENTS.md, which setup-raid writes; this
# hook prints nothing there (Copilot is checked first because it also sets
# CLAUDE_PLUGIN_ROOT for plugin hooks). Not telemetry: RAID_TELEMETRY_DISABLED does not
# silence it. Kill switch: RAID_ROUTING_DISABLED=1. Sends nothing anywhere, never fails.
set -u
[ -n "${RAID_ROUTING_DISABLED:-}" ] && exit 0
[ -n "${COPILOT_CLI:-}${COPILOT_PLUGIN_ROOT:-}" ] && exit 0
[ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ] || exit 0
cat >/dev/null 2>&1 || true
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"RAID is installed. For data-platform work in this repo (pipelines, notebooks, dbt, lakehouse or warehouse tables, data quality), start with the raid-mode skill."}}'
exit 0
