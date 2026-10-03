# RAID close-the-loop Stop hook on Windows. PowerShell port of close-the-loop.sh;
# see skills/raid-mode/references/close-the-loop.md.
#
# Does NOTHING unless the engagement repo has a .raid/session.json -- the gitignored
# file raid-mode and wayfinder write when a session claims a ticket. With one, it
# blocks the agent's stop ({"decision":"block"}) when a ticket in it is still
# "claimed", or when model files changed since a ticket's "base" commit and the
# results ledger has no lines beyond the "ledger_lines" count taken at claim.
# Kill switch: RAID_CLOSE_LOOP_DISABLED=1. One block per stop: stop_hook_active lets
# the next stop through.
#
# Hard rule (same as the bash hook): never break a session. Every failure path ends
# in a silent `exit 0` (a top-level trap guarantees it). Targets Windows PowerShell
# 5.1 for the widest reach (no 7-only syntax).

$ErrorActionPreference = 'SilentlyContinue'
trap { exit 0 }

if ($env:RAID_CLOSE_LOOP_DISABLED) { exit 0 }
$sessionFile = '.raid/session.json'
if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) { exit 0 }

$stdin = [Console]::In.ReadToEnd()
if ($stdin -match '"stop_hook_active"\s*:\s*true') { exit 0 }

$ledger = 'docs/testing/test-results.jsonl'
$ledgerNow = 0
if (Test-Path -LiteralPath $ledger -PathType Leaf) {
  $ledgerNow = @(Get-Content -LiteralPath $ledger).Count
}

$inGit = $false
git rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $inGit = $true }

# A string field of one ticket line; sanitized because it ends up in JSON output.
function Get-Field([string] $name, [string] $line) {
  if ($line -match ('"' + $name + '"\s*:\s*"([^"]*)"')) {
    $v = $matches[1] -replace '[\\"\p{Cc}]', ''
    if ($v.Length -gt 100) { $v = $v.Substring(0, 100) }
    return $v
  }
  return ''
}

# Model files changed since $base: committed, staged, unstaged and untracked. Docs,
# RAID state and build output are not models.
function Test-ModelsChanged([string] $base) {
  $files = @(git diff --name-only $base -- 2>$null) + @(git ls-files --others --exclude-standard 2>$null)
  foreach ($f in $files) {
    if ($f -match '^(docs/|\.raid/|target/|dbt_packages/|logs/)') { continue }
    if ($f -match '(\.sql|\.ipynb|notebook-content\.py)$' -or $f -match '(^|/)models/') { return $true }
  }
  return $false
}

$reasons = @()
foreach ($line in Get-Content -LiteralPath $sessionFile) {
  if ($line -notmatch '"id"') { continue }
  $id = Get-Field 'id' $line
  if (-not $id) { continue }
  $status = Get-Field 'status' $line
  if ($status -eq 'released') { continue }

  if ($status -eq 'claimed') {
    $reasons += "Ticket $id is claimed but not resolved: post the tracker's Resolve comment (what was built, which planned ids are green or red, verified against data or not), move it to done or leave it for the PR merge, then set its status to resolved in .raid/session.json."
  }

  $base = (Get-Field 'base' $line) -replace '[^0-9a-f]', ''
  $ledgerAtClaim = 0
  if ($line -match '"ledger_lines"\s*:\s*([0-9]+)') { $ledgerAtClaim = [int] $matches[1] }
  if ($inGit -and $base -and $ledgerNow -le $ledgerAtClaim) {
    git cat-file -e "$base^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-ModelsChanged $base)) {
      $reasons += "Model files changed since ticket $id was claimed, but $ledger has no new lines: append one line per test run, with planned_id and ticket set."
    }
  }
}

if ($reasons.Count -eq 0) { exit 0 }

$reason = 'RAID close the loop: ' + ($reasons -join ' ') + ' If you are stopping to wait for the user, say so and stop again.'
$reason = $reason -replace '[\\"\p{Cc}]', ''
[Console]::Out.WriteLine('{"decision":"block","reason":"' + $reason + '"}')
exit 0
