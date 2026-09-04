# RAID opt-in usage telemetry on Windows. PowerShell port of telemetry.sh (the
# per-skill PostToolUse hook). See PRIVACY.md at the marketplace root.
#
# Why this file exists: Copilot CLI command hooks select the `bash` field on
# Linux/macOS and the `powershell` field on Windows. raid-core ships both, so a
# Windows Copilot session runs THIS script for the per-skill (PostToolUse,
# matcher "skill") hook instead of failing to spawn bash.exe. Behaviour is
# identical to telemetry.sh: one event per RAID skill invocation, the same opt-in
# gate, the same payload shape, and the same per-repo -> global config fallback.
# (Claude Code on Windows routes hooks through its own bash and uses telemetry.sh;
# this port is for Copilot's powershell field.)
#
# Sends NOTHING unless a per-repo .raid/config.yaml -- or, when there is none, a
# global config under ${RAID_GLOBAL_CONFIG_DIR:-${HOME:-$USERPROFILE}/.raid} --
# contains `telemetry: enabled: true`. Kill switch: RAID_TELEMETRY_DISABLED=1.
# Local debug: RAID_TELEMETRY_DEBUG=1. Every failure path ends in a silent
# `exit 0`. Targets Windows PowerShell 5.1. POST and detachment notes: see
# telemetry-copilot.ps1 (same approach).

$ErrorActionPreference = 'SilentlyContinue'
trap { exit 0 }

$DebugLog = '.raid/telemetry-debug.log'

# Returns $true ONLY when the pattern is confirmed present in .raid/.gitignore --
# callers gate repo writes on it. A silent best-effort append was not enough: on a
# read-only or permission-denied .raid/ the append fails, and the file it was meant
# to ignore would be written anyway and could be committed into a customer repo.
function Add-GitIgnore([string] $pattern) {
  try {
    $existing = @()
    if (Test-Path '.raid/.gitignore') { $existing = @(Get-Content -LiteralPath '.raid/.gitignore') }
    if ($existing -contains $pattern) { return $true }
    Add-Content -LiteralPath '.raid/.gitignore' -Value $pattern
    $after = @(Get-Content -LiteralPath '.raid/.gitignore')
    return ($after -contains $pattern)
  } catch { return $false }
}

function Write-Dbg([string] $msg) {
  if (-not $env:RAID_TELEMETRY_DEBUG) { return }
  try {
    New-Item -ItemType Directory -Force -Path '.raid' | Out-Null
    # No ignore entry, no log: the debug log carries full payloads, so it must
    # never be writable-but-committable inside a customer repo.
    if (-not (Add-GitIgnore 'telemetry-debug.log')) { return }
    $ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content -LiteralPath $DebugLog -Value ("{0} {1}" -f $ts, $msg)
    $tail = @(Get-Content -LiteralPath $DebugLog -Tail 500)
    Set-Content -LiteralPath $DebugLog -Value $tail
  } catch {}
}
function Exit-Dbg([string] $reason) { Write-Dbg "exit: $reason"; exit 0 }

function Protect-Field([string] $v, [int] $max) {
  if (-not $v) { return '' }
  # Strip backslash, double-quote, and control chars (0x00-0x1F plus DEL 0x7F) to
  # match the bash sanitizer's `tr -d '\\"[:cntrl:]'` exactly.
  $v = $v -replace '[\\"\x00-\x1F\x7F]', ''
  if ($v.Length -gt $max) { $v = $v.Substring(0, $max) }
  return $v
}

if ($env:RAID_TELEMETRY_DISABLED) { Exit-Dbg 'kill switch RAID_TELEMETRY_DISABLED set' }

$curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
if (-not $curl) { Exit-Dbg 'curl.exe not on PATH' }

$DefaultEndpoint = 'https://raid-plugin-telemetry.azurewebsites.net/api/ingest'
$stdin = [Console]::In.ReadToEnd()

# --- Config resolution: per-repo wins; else the global fallback (see telemetry.sh). ---
$globalDir = $env:RAID_GLOBAL_CONFIG_DIR
if (-not $globalDir) {
  $base = $env:HOME
  if (-not $base) { $base = $env:USERPROFILE }
  $globalDir = Join-Path $base '.raid'
}
$scope = 'repo'
if (Test-Path '.raid/config.yaml') {
  $cfg = '.raid/config.yaml'
  $idFile = '.raid/installation_id'
} elseif (Test-Path (Join-Path $globalDir 'config.yaml')) {
  $cfg = Join-Path $globalDir 'config.yaml'
  $idFile = Join-Path $globalDir 'installation_id'
  $scope = 'global'
} else {
  Exit-Dbg "no .raid/config.yaml (and no global $globalDir/config.yaml)"
}

# --- Opt-in gate: `enabled: true` within the telemetry: block (indentation-scoped). ---
$lines = @(Get-Content -LiteralPath $cfg)
$block = @()
$inBlock = $false
foreach ($line in $lines) {
  if (-not $inBlock) {
    if ($line -match '^telemetry:') { $inBlock = $true }
    continue
  }
  if ($line -match '^[^ \t]') { break }
  $block += $line
}
if ($block.Count -eq 0) { Exit-Dbg 'no telemetry block in config' }
$enabled = $false
foreach ($b in $block) { if ($b -match '^[ \t]+enabled:[ \t]*true[ \t]*$') { $enabled = $true } }
if (-not $enabled) { Exit-Dbg 'telemetry.enabled not true' }

$engagement = ''
foreach ($b in $block) { if (-not $engagement -and $b -match '^[ \t]*engagement_id:[ \t]*(.+?)[ \t]*$') { $engagement = $matches[1] } }
if (-not $engagement) {
  if ($scope -eq 'global') {
    $engagement = 'global'
  } else {
    foreach ($l in $lines) { if (-not $engagement -and $l -match '^customer:[ \t]*(.+?)[ \t]*$') { $engagement = $matches[1] } }
  }
}
$engagement = Protect-Field $engagement 200
if (-not $engagement) { $engagement = 'unknown' }

# --- Skill name out of the PostToolUse payload. Both clients carry the invoked
# skill in tool_input.skill. Drop anything that isn't a RAID skill. ---
$skill = ''
if ($stdin -match '"skill"\s*:\s*"([^"]*)"') { $skill = $matches[1] }
if (-not $skill) { Exit-Dbg 'no skill in payload' }

# Claude namespaces by plugin (raid-core:<skill>); keep as-is. Copilot passes the
# BARE name -- resolve it to a SKILL.md under a sibling raid-* plugin dir
# (CLAUDE_PLUGIN_ROOT's parent holds raid-core + the tiers) and namespace it the
# same way so both clients' events line up. If it resolves to no RAID plugin, drop.
if ($skill -notmatch '^raid-[a-z][^:]*:') {
  $pluginRoot = $env:CLAUDE_PLUGIN_ROOT
  if (-not $pluginRoot) { $pluginRoot = '.' }
  $pluginsDir = Split-Path -Parent $pluginRoot
  # Split-Path -Parent '.' returns '' where bash `dirname .` returns '.'; normalize
  # so a missing CLAUDE_PLUGIN_ROOT still scans the current dir (fail-open parity).
  if (-not $pluginsDir) { $pluginsDir = '.' }
  $owner = ''
  try {
    foreach ($d in Get-ChildItem -LiteralPath $pluginsDir -Directory -Filter 'raid-*' -ErrorAction SilentlyContinue) {
      if (Test-Path (Join-Path $d.FullName "skills/$skill/SKILL.md")) { $owner = $d.Name; break }
    }
  } catch {}
  if (-not $owner) { Exit-Dbg "skill '$skill' not a RAID plugin skill" }
  $skill = "${owner}:${skill}"
}
$skill = Protect-Field $skill 200

$session = ''
if ($stdin -match '"session_id"\s*:\s*"([^"]*)"') { $session = $matches[1] }
$session = Protect-Field $session 200
if (-not $session) { $session = 'unknown' }

# Release identifier for plugin_version. Native manifests are version-less (the
# commit is the release), so resolve: RAID_PLUGIN_VERSION override, the
# install-cache version segment one or two levels above the plugin root (short
# commit SHA), the git HEAD of the plugin root, else 'unknown'.
$version = ''
$cands = @($env:RAID_PLUGIN_VERSION)
if ($env:CLAUDE_PLUGIN_ROOT) {
  $cands += (Split-Path -Leaf (Split-Path -Parent $env:CLAUDE_PLUGIN_ROOT))
  $cands += (Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $env:CLAUDE_PLUGIN_ROOT)))
}
foreach ($cand in $cands) {
  if ($cand -and ($cand -match '^\d+\.\d+[\.\d]*$' -or $cand -match '^[0-9a-f]{7,40}$')) {
    $version = $cand
    break
  }
}
if (-not $version -and $env:CLAUDE_PLUGIN_ROOT) {
  $gitSha = (& git -C $env:CLAUDE_PLUGIN_ROOT rev-parse --short HEAD 2>$null)
  if ($LASTEXITCODE -eq 0 -and $gitSha) { $version = ("$gitSha").Trim() }
}
$version = Protect-Field $version 100
if (-not $version) { $version = 'unknown' }

# Pseudonymous installation id (see telemetry-copilot.ps1 for the per-repo vs
# global distinction).
$install = ''
if (Test-Path -LiteralPath $idFile) {
  $install = @(Get-Content -LiteralPath $idFile)[0]
} else {
  $install = [guid]::NewGuid().ToString()
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $idFile) | Out-Null
    # Persist only when it is guaranteed not to be committed -- for a per-repo
    # checkout the .gitignore entry must land FIRST. Otherwise the id stays in
    # memory for this run only. See telemetry.sh for the full rationale.
    if ($scope -ne 'repo' -or (Add-GitIgnore 'installation_id')) {
      Set-Content -LiteralPath $idFile -Value $install
    }
  } catch {}
}
$install = Protect-Field $install 64
if (-not $install) { $install = 'unknown' }

$ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$event = '{"ts":"' + $ts + '","skill_name":"' + $skill + '","plugin_version":"' + $version + '","engagement_id":"' + $engagement + '","session_id":"' + $session + '","installation_id":"' + $install + '"}'

$endpoint = $env:RAID_TELEMETRY_ENDPOINT
if (-not $endpoint) { $endpoint = $DefaultEndpoint }

Write-Dbg ("posting to {0}: {1}" -f $endpoint, $event)
try {
  $tmp = [System.IO.Path]::GetTempFileName()
  Set-Content -LiteralPath $tmp -Value $event -NoNewline
  & $curl.Source -s -m 3 -o NUL -X POST -H 'Content-Type: application/json' --data-binary "@$tmp" $endpoint 2>$null | Out-Null
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
} catch {}

exit 0
