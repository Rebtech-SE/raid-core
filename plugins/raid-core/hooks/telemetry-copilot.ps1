# RAID opt-in usage telemetry for GitHub Copilot on Windows. PowerShell port of
# telemetry-copilot.sh. See PRIVACY.md at the marketplace root.
#
# Why this file exists: Copilot CLI command hooks select the `bash` field on
# Linux/macOS and the `powershell` field on Windows. raid-core ships both, so a
# Windows Copilot session runs THIS script instead of trying (and failing) to
# spawn bash.exe. Behaviour is identical to telemetry-copilot.sh: ONE
# sessionStart event per RAID-configured Copilot session, the same opt-in gate,
# the same payload shape, and the same per-repo -> global config fallback.
#
# Sends NOTHING unless a per-repo .raid/config.yaml -- or, when there is none, a
# global config under ${RAID_GLOBAL_CONFIG_DIR:-${HOME:-$USERPROFILE}/.raid} --
# contains `telemetry: enabled: true`. Kill switch: RAID_TELEMETRY_DISABLED=1.
# Local debug: RAID_TELEMETRY_DEBUG=1 appends one decision line per run to a
# gitignored .raid/telemetry-debug.log (off by default, never transmitted).
#
# Hard rule (same as the bash hook): telemetry must never surface an error or add
# meaningful latency to a session. Every failure path ends in a silent `exit 0`
# (a top-level trap guarantees it). The POST goes through curl.exe (shipped on
# Windows 10 1803+ / Server 2019+) with a 3s cap; unlike the bash hook's
# nohup-backgrounded curl, the PowerShell port posts synchronously because
# reliable process detachment on Windows PowerShell 5.1 is fragile -- the 3s cap
# bounds it, and it only runs at all when explicitly opted in. Targets Windows
# PowerShell 5.1 for the widest reach (no 7-only syntax).

$ErrorActionPreference = 'SilentlyContinue'
trap { exit 0 }

$DebugLog = '.raid/telemetry-debug.log'

# Append a whole line to .raid/.gitignore once (idempotent, best-effort). Per-repo
# only; the global config dir is not a repo, so it gets no .gitignore.
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

# Opt-in local debug log (RAID_TELEMETRY_DEBUG): one decision line per run, capped
# to the last 500 lines. No-op unless debug is on; never alters the exit path.
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

# Free-form value interpolated into JSON: strip JSON-special and control chars and
# cap length so an odd id can't malform the body (mirrors the bash `tr`/`cut`).
function Protect-Field([string] $v, [int] $max) {
  if (-not $v) { return '' }
  # Strip backslash, double-quote, and control chars (0x00-0x1F plus DEL 0x7F) to
  # match the bash sanitizer's `tr -d '\\"[:cntrl:]'` exactly.
  $v = $v -replace '[\\"\x00-\x1F\x7F]', ''
  if ($v.Length -gt $max) { $v = $v.Substring(0, $max) }
  return $v
}

if ($env:RAID_TELEMETRY_DISABLED) { Exit-Dbg 'kill switch RAID_TELEMETRY_DISABLED set' }

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
# PostToolUse hook in telemetry.ps1 -- so it must not be emitted from a Claude
# session. Copilot sets COPILOT_CLI / COPILOT_PLUGIN_ROOT for plugin hooks; Claude
# sets neither. No Copilot marker, nothing to report.
if (-not ($env:COPILOT_CLI -or $env:COPILOT_PLUGIN_ROOT)) {
  Exit-Dbg 'not a Copilot session (no COPILOT_CLI/COPILOT_PLUGIN_ROOT)'
}

# curl.exe -- the real binary, NOT PowerShell's `curl` alias for Invoke-WebRequest.
$curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
if (-not $curl) { Exit-Dbg 'curl.exe not on PATH' }

$DefaultEndpoint = 'https://raid-plugin-telemetry.azurewebsites.net/api/ingest'
$stdin = [Console]::In.ReadToEnd()

# --- Config resolution: per-repo wins; else the global fallback. Identical rule
# to the bash hook: a per-repo .raid/config.yaml that EXISTS is authoritative even
# without a telemetry block, so global is consulted only when there is no per-repo
# config (a globally opted-in consultant never leaks telemetry into a client repo).
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

# --- Opt-in gate: `enabled: true` within the telemetry: block, scoped by
# indentation (contiguous indented lines under `telemetry:`). Same as the bash awk.
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

# engagement_id from the block; else per scope -- `customer:` for a repo, the
# "global" sentinel for a global config (so global usage never looks like an
# engagement and there is no `customer:` on a global config anyway).
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

# Session id from the sessionStart payload (accept camelCase and snake_case).
$session = ''
if ($stdin -match '"session_id"\s*:\s*"([^"]*)"') { $session = $matches[1] }
elseif ($stdin -match '"sessionId"\s*:\s*"([^"]*)"') { $session = $matches[1] }
$session = Protect-Field $session 200
if (-not $session) { $session = 'unknown' }

# Release identifier for plugin_version. Native manifests are version-less (the
# commit is the release), so resolve in order: RAID_PLUGIN_VERSION override, a
# release-looking segment anywhere in the plugin root path (its depth differs by
# host), the git HEAD of the plugin root, the install-time .raid-release stamp
# while the manifest has not been rewritten under it, then a gen-<manifest mtime>
# generation marker, else 'unknown'. See telemetry.sh for the full rationale --
# the two ports must resolve identically.
function Test-ReleaseMarker([string]$v) {
  if (-not $v) { return $false }
  if ($v -match '^\d+\.\d+[\.\d]*$') { return $true }
  if ($v -match '^[0-9a-f]{7,40}$') { return $true }
  return $false
}

$version = ''
$cands = @($env:RAID_PLUGIN_VERSION)
if ($env:CLAUDE_PLUGIN_ROOT) {
  # Leaf plus two parents -- see telemetry.sh for why the window stays narrow.
  # (The leaf itself was missing here before, which is why a Claude install whose
  # version segment IS the leaf never resolved on the PowerShell path.)
  $seg = $env:CLAUDE_PLUGIN_ROOT
  $depth = 0
  while ($seg -and $depth -lt 3) {
    $cands += (Split-Path -Leaf $seg)
    $parent = Split-Path -Parent $seg
    if (-not $parent -or $parent -eq $seg) { break }
    $seg = $parent
    $depth++
  }
}
foreach ($cand in $cands) {
  if (Test-ReleaseMarker $cand) { $version = $cand; break }
}

$manifest = ''
$stamp = ''
if ($env:CLAUDE_PLUGIN_ROOT) {
  $manifest = Join-Path $env:CLAUDE_PLUGIN_ROOT '.claude-plugin/plugin.json'
  $stamp = Join-Path $env:CLAUDE_PLUGIN_ROOT '.raid-release'
}

if (-not $version -and $env:CLAUDE_PLUGIN_ROOT) {
  $gitSha = (& git -C $env:CLAUDE_PLUGIN_ROOT rev-parse --short HEAD 2>$null)
  if ($LASTEXITCODE -eq 0 -and $gitSha) { $version = ("$gitSha").Trim() }
}

# The stamp is trusted only while it is newer than the manifest: a host-driven
# update re-copies the tree and would otherwise leave it naming a release that
# is no longer installed.
if (-not $version -and $stamp) {
  try {
    # -Force throughout: on Unix, PowerShell treats a dot-prefixed file as hidden
    # and Get-Item/Get-Content skip it without it (Test-Path does not), which
    # would silently drop every stamp on macOS and Linux.
    $stampItem = Get-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue
    $manifestItem = Get-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
    if ($stampItem -and (-not $manifestItem -or $manifestItem.LastWriteTimeUtc -le $stampItem.LastWriteTimeUtc)) {
      $stamped = @(Get-Content -LiteralPath $stamp -Force -ErrorAction SilentlyContinue)[0]
      if ($stamped) { $stamped = $stamped.Trim() }
      if (Test-ReleaseMarker $stamped) { $version = $stamped }
    }
  } catch {}
}

if (-not $version -and $manifest -and (Test-Path -LiteralPath $manifest)) {
  try {
    $mtime = (Get-Item -LiteralPath $manifest -Force -ErrorAction Stop).LastWriteTimeUtc
    # Floor, not a cast: [int64] rounds to even, which would make the PowerShell
    # port disagree with the bash hook's truncating `stat` on the same install.
    $epoch = [int64][Math]::Floor((($mtime - [datetime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc)).TotalSeconds))
    if ($epoch -gt 0) { $version = "gen-$epoch" }
  } catch {}
}

$version = Protect-Field $version 100
if (-not $version) { $version = 'unknown' }

# Pseudonymous installation id. Per-repo: random per checkout, gitignored (counts
# distinct people per engagement without identifying anyone). Global: a persistent
# per-machine pseudonym -- the deliberate exception disclosed in PRIVACY.md.
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
$event = '{"ts":"' + $ts + '","skill_name":"copilot:session-start","plugin_version":"' + $version + '","engagement_id":"' + $engagement + '","session_id":"' + $session + '","installation_id":"' + $install + '"}'

$endpoint = $env:RAID_TELEMETRY_ENDPOINT
if (-not $endpoint) { $endpoint = $DefaultEndpoint }

# POST via curl.exe with the body in a temp file -- avoids Windows PowerShell 5.1
# mangling embedded double-quotes when a JSON body is passed as a native arg.
Write-Dbg ("posting to {0}: {1}" -f $endpoint, $event)
try {
  $tmp = [System.IO.Path]::GetTempFileName()
  Set-Content -LiteralPath $tmp -Value $event -NoNewline
  & $curl.Source -s -m 3 -o NUL -X POST -H 'Content-Type: application/json' --data-binary "@$tmp" $endpoint 2>$null | Out-Null
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
} catch {}

exit 0
