# Inventory and analyzer

Read for script usage, scan scope, alias handling, usage signals, and numeric
estimates. The helper is read-only and prints Markdown or JSON; it never rewrites
instructions, shortens descriptions, or deletes anything.

## Scoped by default

Invoke `scripts/skill-cleaner.mts` using the absolute skill directory as shown in
the entry point. With no roots, it scans the current directory. Repeat `--root`
for additional explicitly requested roots. `--root` now selects scope; unlike the
old checkout-only analyzer, it does not silently add global roots. `--root-only`
is an optional assertion and cannot be combined with `--global`.

The inventory includes skill entry points, root/nested AGENTS.md and CLAUDE.md,
byte/line counts, invocation metadata, duplicate candidates, and path aliases.
Managed fan-out collapses only after both entrypoints and bounded readable
resource trees match; differing or unverified bundles remain separate.
It resolves file symlinks, deduplicates by real source, skips traversal cycles,
and reports unreadable paths or depth limits. Symlinks outside a selected root
are reported and skipped; add their actual target as another root only when it
is in scope. Common generated/dependency directories are skipped. Arbitrary
instruction filenames require direct inspection if explicitly requested.

A discovered file is not proof the host loads it. `enabled: null` means unknown;
`false` reflects an explicit disabled entry in a supplied Codex config or the
Codex config consulted during an opted-in global scan. This is partial Codex
configuration evidence, not the complete runtime activation state.

## Optional broader evidence

- `--global`: add known installed skill/plugin roots and global AGENTS.md/CLAUDE.md
  locations. Use only for requested machine-wide audits; custom roots still need
  explicit `--root` arguments. It does not search every sibling project.
- `--logs --log-root <absolute transcript directory>`: opt into bounded usage
  evidence for a scoped audit. Without `--logs`, no transcripts are read.
- `--global --logs`: inspect known Codex/Claude transcript locations as well.
  `--deep-logs` also includes known archive locations in this mode.
- `--months 3 --max-log-mb 300`: bound the lookback and total bytes. File age is a
  heuristic; a recently modified transcript may contain older events. Explicit
  calls, skill paths, and textual mentions are weak signals, not proven invocations.
- `--codex-config <absolute config>`: opt into known-disabled entry inspection.
- `--all`: include known-disabled skills in candidate budget simulations.
- `--json`: structured evidence for a coverage ledger or comparison.

The helper reports gaps when transcript files exceed its limits. JSON separates
discovered transcript candidates from files successfully read. Do not label a
skill unused just because logs were not scanned or returned no matching mentions.
Redact any sensitive content before quoting evidence; reports need paths and
counts, not transcript dumps.

## Model and context estimates

`--model <id>` selects a record from the local Codex model cache when available.
`--context-tokens <count>` supplies a context estimate directly and avoids that
lookup. With neither, the fallback is explicitly illustrative, not an assumed
GPT/Astra context window. `--budget-percent` defaults to 2; `--chars-per-token`
is the legacy name for the UTF-8 bytes-per-token estimate and defaults to 4.

The historical Codex-style allocation simulator remains available for comparisons,
including full, truncated, and omitted descriptions. Its candidate catalogue comes
from discovery, not a captured runtime prompt. It does not predict every model's
actual tokens, prove host loading, or establish Claude/Cursor/Copilot budget rules.
Separate full skill-body size and active instruction size from catalogue estimates.
Explicit-only settings prevent implicit invocation where supported; hosts may
still display a short catalogue entry. Do not promise zero context cost.

## Runtime and fallback

The optional helper retains Node's type-stripping runtime (Node 22.6+, exercised
on Node 24) because the existing inventory, transcript heuristics, and budget
simulator are one dependency-free TypeScript tool. No Bun or package install is
needed. When Node is absent, do the scoped inventory with available filesystem
read/search tools and the same audit rubric. Report missing numeric simulations;
do not install a runtime merely to perform an instruction audit.
