# RAID routing hook (SessionStart), PowerShell twin of raid-mode-routing.sh -- see that file.
# Adds one line to a Claude Code session's context so data-platform work starts in
# raid-mode. Prints nothing on other hosts (they read the line from AGENTS.md). Not
# telemetry; kill switch RAID_ROUTING_DISABLED=1. Never fails.
try {
  if ($env:RAID_ROUTING_DISABLED) { exit 0 }
  if ($env:COPILOT_CLI -or $env:COPILOT_PLUGIN_ROOT) { exit 0 }
  if (-not ($env:CLAUDECODE -or $env:CLAUDE_CODE_ENTRYPOINT)) { exit 0 }
  [Console]::Out.WriteLine('{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"RAID is installed. For data-platform work in this repo (pipelines, notebooks, dbt, lakehouse or warehouse tables, data quality), start with the raid-mode skill."}}')
} catch { }
exit 0
