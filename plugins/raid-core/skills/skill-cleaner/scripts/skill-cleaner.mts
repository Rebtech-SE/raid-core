#!/usr/bin/env -S node --experimental-strip-types
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";

type Skill = {
  name: string;
  baseName: string;
  description: string;
  path: string;
  realPath: string;
  dir: string;
  root: string;
  realRoot: string;
  scope: string;
  enabled: boolean | null;
  explicitOnly: boolean;
  codexImplicit: boolean | null;
  aliases: string[];
  contentHash: string;
  bodyLines: number;
  bodyBytes: number;
  descChars: number;
  lineChars: number;
  lineBytes: number;
  bodyHash: string;
  bodyKey: string;
  descKey: string;
};

type Usage = {
  dollar: number;
  fileRead: number;
  text: number;
};

type Budget = {
  model: string;
  contextTokens: number;
  contextSource: string;
  effectivePercent: number | null;
  effectiveContextTokens: number | null;
  budgetPercent: number;
  budgetTokens: number;
  effectiveBudgetTokens: number | null;
  renderedLineChars: number;
  unbudgetedFullTokens: number;
  minimumTokens: number;
  budgetedTokens: number;
  charsPerToken: number;
  unbudgetedBudgetUsedRatio: number;
  budgetedBudgetUsedRatio: number;
  effectiveBudgetUsedRatio: number | null;
  unbudgetedContextUsedRatio: number;
  budgetedContextUsedRatio: number;
  effectiveContextUsedRatio: number | null;
  remainingBudgetTokens: number;
  remainingEffectiveBudgetTokens: number | null;
  includedSkills: number;
  omittedSkills: number;
  truncatedDescriptionChars: number;
  truncatedDescriptionCount: number;
};

const home = os.homedir();
const args = new Set(process.argv.slice(2));

function argValue(name: string, fallback: string): string {
  const raw = process.argv.slice(2);
  const index = raw.indexOf(name);
  return index >= 0 && raw[index + 1] ? raw[index + 1] : fallback;
}

const months = Number(argValue("--months", "3"));
const noLogs = !args.has("--logs") || args.has("--no-logs");
const globalScan = args.has("--global");
const scanWarnings: string[] = [];
const deepLogs = args.has("--deep-logs");
const json = args.has("--json");
const includeAll = args.has("--all");
const model = argValue("--model", "unspecified");
const budgetPercent = Number(argValue("--budget-percent", "2"));
const contextTokensOverride = argValue("--context-tokens", "");
const charsPerToken = Number(argValue("--chars-per-token", "4"));
const maxLogBytes = Number(argValue("--max-log-mb", "300")) * 1024 * 1024;
const cutoffMs = Date.now() - Math.max(0, months) * 31 * 24 * 60 * 60 * 1000;
const extraRoots = process.argv
  .slice(2)
  .flatMap((arg, index, all) =>
    arg === "--root" && all[index + 1] ? [all[index + 1]] : []
  );

if (args.has("--help") || args.has("-h")) {
  console.log(`Usage: node --experimental-strip-types skill-cleaner.mts [options]
  --root PATH              Audit only this root (repeatable); default: current directory
  --root-only              Explicit scoped mode; incompatible with --global
  --global                 Add known installed-skill roots and global instruction files
  --logs                   Opt in to bounded recent transcript usage heuristics
  --no-logs                Disable transcript reads (default)
  --log-root PATH          Transcript root (repeatable, requires --logs)
  --months N               Usage lookback, default 3
  --max-log-mb N            Maximum transcript bytes, default 300
  --deep-logs              Include archive roots with --global --logs
  --model ID               Model-cache lookup for illustrative Codex budget simulation
  --context-tokens N       Explicit context estimate; avoids model-cache lookup
  --budget-percent N       Illustrative metadata budget, default 2
  --chars-per-token N      UTF-8 bytes per estimated token, default 4
  --codex-config PATH      Optional Codex config for known disabled entries
  --all                    Include known-disabled skills in budget candidates
  --json                   Structured inventory; never edits files
Global/config/log scans are opt-in. Inventory is not proof a host loads a file.
Budget simulation is not measured usage and does not describe every host.`);
  process.exit(0);
}
const valueFlags = new Set([
  "--root",
  "--log-root",
  "--months",
  "--max-log-mb",
  "--model",
  "--context-tokens",
  "--budget-percent",
  "--chars-per-token",
  "--codex-config",
]);
const boolFlags = new Set([
  "--root-only",
  "--global",
  "--logs",
  "--no-logs",
  "--deep-logs",
  "--all",
  "--json",
]);
for (let i = 2; i < process.argv.length; i++) {
  const flag = process.argv[i];
  if (valueFlags.has(flag)) {
    if (!process.argv[i + 1] || process.argv[i + 1].startsWith("--"))
      throw new Error(`Missing value for ${flag}`);
    i++;
  } else if (!boolFlags.has(flag)) throw new Error(`Unknown argument: ${flag}`);
}
if (globalScan && args.has("--root-only"))
  throw new Error("--root-only cannot be combined with --global");
for (const [flag, value] of [
  ["--months", months],
  ["--max-log-mb", maxLogBytes],
  ["--budget-percent", budgetPercent],
  ["--chars-per-token", charsPerToken],
] as const) {
  if (!Number.isFinite(value) || value <= 0)
    throw new Error(`${flag} must be positive`);
}
if (
  contextTokensOverride &&
  (!Number.isFinite(Number(contextTokensOverride)) ||
    Number(contextTokensOverride) <= 0)
)
  throw new Error("--context-tokens must be positive");
const logRoots = process.argv
  .slice(2)
  .flatMap((arg, i, all) => (arg === "--log-root" ? [all[i + 1]] : []));
if (!noLogs && !globalScan && logRoots.length === 0)
  throw new Error(
    "Scoped --logs needs --log-root; global logs require --global --logs"
  );

function expandHome(input: string): string {
  return input.replace(/^~(?=$|\/)/, home);
}

function exists(input: string): boolean {
  try {
    fs.accessSync(input);
    return true;
  } catch {
    return false;
  }
}

function numberArg(value: string, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function findModelRecord(
  value: unknown,
  target: string
): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findModelRecord(item, target);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const names = [record.slug, record.id, record.model, record.name]
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.toLowerCase());
  if (names.includes(target.toLowerCase())) return record;
  for (const item of Object.values(record)) {
    const found = findModelRecord(item, target);
    if (found) return found;
  }
  return null;
}

function codexModelContext(modelName: string): {
  tokens: number;
  source: string;
  effectivePercent: number | null;
} {
  const override = numberArg(contextTokensOverride, 0);
  if (override > 0)
    return {
      tokens: override,
      source: "--context-tokens",
      effectivePercent: null,
    };

  const cache = path.join(home, ".codex/models_cache.json");
  if ((globalScan || modelName !== "unspecified") && exists(cache)) {
    try {
      const record = findModelRecord(
        JSON.parse(fs.readFileSync(cache, "utf8")),
        modelName
      );
      const tokens = Number(record?.context_window);
      const effectivePercent = Number(record?.effective_context_window_percent);
      if (Number.isFinite(tokens) && tokens > 0) {
        return {
          tokens,
          source: cache,
          effectivePercent:
            Number.isFinite(effectivePercent) && effectivePercent > 0
              ? effectivePercent
              : null,
        };
      }
    } catch {}
  }

  return {
    tokens: 272_000,
    source: "illustrative fallback; no model context verified",
    effectivePercent: null,
  };
}

function walkFiles(
  root: string,
  predicate: (file: string) => boolean,
  maxDepth = 10
): string[] {
  const out: string[] = [];
  const ancestors = new Set<string>();
  const absolute = exists(root) ? fs.realpathSync(root) : path.resolve(root);
  const within = (target: string) =>
    target === absolute || target.startsWith(absolute + path.sep);
  function walk(file: string, depth: number) {
    try {
      const real = fs.realpathSync(file);
      if (!within(real)) {
        scanWarnings.push(
          `Skipped symlink outside root: ${file}; add its target as --root to inspect it`
        );
        return;
      }
      const stat = fs.statSync(file);
      if (stat.isFile()) {
        if (predicate(file)) out.push(file);
        return;
      }
      if (!stat.isDirectory()) return;
      if (ancestors.has(real)) {
        scanWarnings.push(`Directory cycle skipped: ${file}`);
        return;
      }
      if (depth > maxDepth) {
        scanWarnings.push(`Depth limit: ${file}`);
        return;
      }
      ancestors.add(real);
      for (const entry of fs.readdirSync(file, { withFileTypes: true })) {
        if (
          [
            "node_modules",
            ".git",
            ".venv",
            "venv",
            "__pycache__",
            ".build",
            "DerivedData",
          ].includes(entry.name)
        )
          continue;
        walk(path.join(file, entry.name), depth + 1);
      }
      ancestors.delete(real);
    } catch {
      scanWarnings.push(`Unreadable or broken link: ${file}`);
    }
  }
  walk(absolute, 0);
  return out;
}

function sanitizeSingleLine(value: string): string {
  return value
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseYamlScalar(raw: string): string {
  const value = raw.trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    if (value.startsWith('"')) {
      try {
        return JSON.parse(value);
      } catch {}
    }
    return value.slice(1, -1).replace(/''/g, "'");
  }
  return value;
}

function parseFrontmatter(
  file: string
): {
  name?: string;
  description?: string;
  body: string;
  explicitOnly: boolean;
} | null {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split(/\r?\n/);
  if (lines[0]?.trim() !== "---") return null;
  const fm: string[] = [];
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") {
      end = i;
      break;
    }
    fm.push(lines[i] ?? "");
  }
  if (end < 0) return null;
  let name: string | undefined;
  let description: string | undefined;
  for (let i = 0; i < fm.length; i++) {
    const line = fm[i] ?? "";
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!match) continue;
    const key = match[1];
    const raw = match[2] ?? "";
    if (key === "name") name = sanitizeSingleLine(parseYamlScalar(raw));
    if (key === "description") {
      if (/^[|>][-+]?$/.test(raw.trim())) {
        const block: string[] = [];
        for (let j = i + 1; j < fm.length; j++) {
          if (/^[A-Za-z0-9_-]+:\s*/.test(fm[j] ?? "")) break;
          block.push((fm[j] ?? "").replace(/^\s{2}/, ""));
        }
        description = sanitizeSingleLine(block.join(" "));
      } else {
        description = sanitizeSingleLine(parseYamlScalar(raw));
      }
    }
  }
  return {
    name,
    description,
    body: lines.slice(end + 1).join("\n"),
    explicitOnly: fm.some((line) =>
      /^disable-model-invocation:\s*true\s*(?:#.*)?$/.test(line)
    ),
  };
}

function fnv1a(input: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function normalizeWords(input: string): string {
  return input
    .toLowerCase()
    .replace(/[`"'’().,;:!?/\\[\]{}_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function wordSet(input: string): Set<string> {
  return new Set(
    normalizeWords(input)
      .split(" ")
      .filter((word) => word.length >= 2)
  );
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let intersection = 0;
  for (const item of a) {
    if (b.has(item)) intersection++;
  }
  return intersection / (a.size + b.size - intersection);
}

// Prefer a source checkout over a managed install for display only. This never
// authorizes deletion and does not imply any host actually loads that checkout.
function isRepoSource(p: string): boolean {
  if (p.includes(`${path.sep}plugins${path.sep}cache${path.sep}`)) return false;
  let dir = path.dirname(p);
  while (dir !== path.dirname(dir)) {
    if (
      exists(path.join(dir, "skills/sources.json")) &&
      [
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json",
        ".cursor-plugin/plugin.json",
        ".gemini-plugin/plugin.json",
      ].some((f) => exists(path.join(dir, f)))
    )
      return true;
    dir = path.dirname(dir);
  }
  return false;
}

function skillRootScope(root: string): string {
  const normalized = root.split(path.sep).join("/");
  if (normalized.includes("/.codex/plugins/cache")) return "codex-plugin";
  if (
    /\/\.(claude|cursor|copilot)\/plugins\/(cache|marketplaces)/.test(
      normalized
    )
  )
    return "managed-plugin";
  if (isRepoSource(path.join(normalized, "SKILL.md"))) return "repo";
  if (normalized.includes("/.claude/skills")) return "claude";
  if (normalized.includes("/.gemini/antigravity-cli/skills"))
    return "antigravity";
  if (normalized.includes("/.agents/skills")) return "agents"; // cross-tool fan-out (Codex/Gemini/Cursor/Copilot/Windsurf)
  if (normalized.includes("/.codex/skills")) return "codex";
  if (normalized.includes("/Dropbox/")) return "dropbox";
  return "extra";
}

// Display preference only; source ownership must be verified before any edit.
function deletePriority(skill: Skill): number {
  if (isRepoSource(skill.realPath)) return 0;
  return ["codex-plugin", "managed-plugin"].includes(skill.scope) ? 2 : 1;
}

function preferredKeepSkill(list: Skill[]): Skill {
  return [...list].sort((a, b) => {
    const byPriority = deletePriority(a) - deletePriority(b);
    if (byPriority !== 0) return byPriority;
    return (
      a.realPath.length - b.realPath.length ||
      a.realPath.localeCompare(b.realPath)
    );
  })[0]!;
}

function displayPathPriority(skill: Skill): number {
  if (skill.path.includes("/.codex/skills/agent-scripts/")) return 10;
  if (skill.path === skill.realPath) return 0;
  return 1;
}

function preferredDisplaySkill(a: Skill, b: Skill): Skill {
  const byDisplay = displayPathPriority(a) - displayPathPriority(b);
  if (byDisplay < 0) return a;
  if (byDisplay > 0) return b;
  return a.path.length <= b.path.length ? a : b;
}

function pluginPrefixFor(file: string): string | null {
  if (
    !/\/\.(codex|claude|cursor|copilot)\/plugins\/cache\//.test(
      file.split(path.sep).join("/")
    )
  )
    return null;
  const parts = file.split(path.sep);
  const cache = parts.indexOf("cache");
  const skills = parts.lastIndexOf("skills");
  if (cache >= 0 && skills > cache + 1) {
    const maybePlugin = parts[cache + 2];
    if (maybePlugin && maybePlugin !== "plugin-install-VGdwGs")
      return maybePlugin;
    return parts[cache + 3] ?? null;
  }
  return null;
}

function disabledPluginMatches(
  disabledPlugin: string,
  pluginPrefix: string
): boolean {
  return (
    disabledPlugin === pluginPrefix ||
    disabledPlugin.startsWith(`${pluginPrefix}@`)
  );
}

function configState(): {
  disabledPaths: Set<string>;
  disabledPlugins: Set<string>;
} {
  const disabledPaths = new Set<string>();
  const disabledPlugins = new Set<string>();
  const config = argValue(
    "--codex-config",
    globalScan ? path.join(home, ".codex/config.toml") : ""
  );
  if (!config) return { disabledPaths, disabledPlugins };
  if (!exists(config)) return { disabledPaths, disabledPlugins };
  const text = fs.readFileSync(config, "utf8");
  // Match settings within each table independently; TOML key order is irrelevant.
  for (const block of text.split(/(?=^\[)/m)) {
    if (!/^enabled\s*=\s*false\s*(?:#.*)?$/m.test(block)) continue;
    if (/^\[\[skills\.config\]\]/.test(block)) {
      const match = /^path\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*')/m.exec(block);
      if (match) {
        const configured = path.resolve(expandHome(parseYamlScalar(match[1])));
        disabledPaths.add(
          exists(configured) ? fs.realpathSync(configured) : configured
        );
      }
    } else {
      const match = /^\[plugins\."([^"\n]+)"\]/.exec(block);
      if (match) disabledPlugins.add(match[1]);
    }
  }
  return { disabledPaths, disabledPlugins };
}

function discoverRoots(): string[] {
  const requested = extraRoots.length
    ? extraRoots.map(expandHome)
    : [process.cwd()];
  const roots = [...requested];
  if (globalScan)
    roots.push(
      ...[
        ".claude/skills",
        ".agents/skills",
        ".codex/skills",
        ".copilot/skills",
        ".cursor/skills",
        ".gemini/antigravity-cli/skills",
        ".gemini/config/plugins",
        ".codex/plugins/cache",
        ".claude/plugins/cache",
        ".cursor/plugins/cache",
        ".copilot/plugins",
        ".codex/AGENTS.md",
        ".claude/CLAUDE.md",
      ].map((relative) => path.join(home, relative))
    );
  const found = new Set<string>();
  for (const root of roots) {
    try {
      found.add(fs.realpathSync(root));
    } catch {
      if (requested.includes(root))
        scanWarnings.push(`Requested root missing: ${root}`);
    }
  }
  return [...found].sort();
}

const roots = discoverRoots();
const inventoryFiles = roots.flatMap((root) =>
  walkFiles(root, (f) => /^(SKILL|AGENTS|CLAUDE)\.md$/i.test(path.basename(f)))
);

type InstructionFile = {
  path: string;
  aliases: string[];
  kind: string;
  bytes: number;
  lines: number;
  estimatedTokens: number;
  contentHash: string;
};
function discoverInstructions(): InstructionFile[] {
  const found = new Map<string, InstructionFile>();
  for (const file of inventoryFiles.filter((f) =>
    /^(AGENTS|CLAUDE)\.md$/i.test(path.basename(f))
  )) {
    try {
      const real = fs.realpathSync(file);
      const existing = found.get(real);
      if (existing) {
        if (file !== real && !existing.aliases.includes(file))
          existing.aliases.push(file);
        continue;
      }
      const text = fs.readFileSync(file, "utf8");
      found.set(real, {
        path: real,
        aliases: file === real ? [] : [file],
        kind: path.basename(file),
        bytes: Buffer.byteLength(text),
        lines: text.split(/\r?\n/).length,
        estimatedTokens: tokenCost(text),
        contentHash: createHash("sha256").update(text).digest("hex"),
      });
    } catch {
      scanWarnings.push(`Could not read instruction file: ${file}`);
    }
  }
  return [...found.values()].sort((a, b) => a.path.localeCompare(b.path));
}

function discoverSkills(): Skill[] {
  const { disabledPaths, disabledPlugins } = configState();
  const skillsByRealPath = new Map<string, Skill>();
  for (const root of roots) {
    for (const file of inventoryFiles.filter(
      (candidate) =>
        path.basename(candidate) === "SKILL.md" &&
        (candidate === root || candidate.startsWith(root + path.sep))
    )) {
      const parsed = parseFrontmatter(file);
      if (!parsed) {
        scanWarnings.push(`Missing or invalid frontmatter: ${file}`);
        continue;
      }
      const baseName = parsed.name || path.basename(path.dirname(file));
      const pluginPrefix = pluginPrefixFor(file);
      const name = pluginPrefix ? `${pluginPrefix}:${baseName}` : baseName;
      const description = parsed.description ?? "";
      const rendered = description
        ? `- ${name}: ${description} (file: ${file})`
        : `- ${name}: (file: ${file})`;
      const disabledByPath =
        disabledPaths.has(file) || disabledPaths.has(path.dirname(file));
      const disabledByPlugin =
        pluginPrefix != null &&
        [...disabledPlugins].some((plugin) =>
          disabledPluginMatches(plugin, pluginPrefix)
        );
      const bodyKey = normalizeWords(parsed.body);
      const skill: Skill = {
        name,
        baseName,
        description,
        path: file,
        realPath: fs.realpathSync(file),
        dir: path.dirname(file),
        root,
        realRoot: fs.realpathSync(root),
        scope: skillRootScope(file),
        enabled: disabledByPath || disabledByPlugin ? false : null,
        explicitOnly: parsed.explicitOnly,
        codexImplicit: (() => {
          const yaml = path.join(path.dirname(file), "agents/openai.yaml");
          if (!exists(yaml)) return null;
          const real = fs.realpathSync(yaml);
          if (
            !roots.some(
              (root) => real === root || real.startsWith(root + path.sep)
            )
          ) {
            scanWarnings.push(
              `Skipped metadata outside selected roots: ${yaml}`
            );
            return null;
          }
          const match =
            /^\s+allow_implicit_invocation:\s*(true|false)\s*(?:#.*)?$/m.exec(
              fs.readFileSync(yaml, "utf8")
            );
          return match ? match[1] === "true" : null;
        })(),
        aliases: [],
        contentHash: createHash("sha256")
          .update(fs.readFileSync(file))
          .digest("hex"),
        bodyLines: parsed.body.split(/\r?\n/).length,
        bodyBytes: Buffer.byteLength(parsed.body),
        descChars: [...description].length,
        lineChars: [...`${rendered}\n`].length,
        lineBytes: Buffer.byteLength(`${rendered}\n`, "utf8"),
        bodyHash: fnv1a(bodyKey),
        bodyKey,
        descKey: normalizeWords(description),
      };
      const existing = skillsByRealPath.get(skill.realPath);
      if (existing) {
        const chosen = preferredDisplaySkill(existing, skill);
        chosen.aliases = [
          ...new Set([...existing.aliases, existing.path, skill.path]),
        ].filter((p) => p !== chosen.path);
        skillsByRealPath.set(skill.realPath, chosen);
      } else skillsByRealPath.set(skill.realPath, skill);
    }
  }
  return collapseManagedFanout([...skillsByRealPath.values()]);
}

// Fingerprint only when entrypoint matches suggest fan-out. Missing, external,
// unreadable or oversized resources mean identity is unproven; keep both copies.
function bundleFingerprint(skill: Skill): string | null {
  const root = fs.realpathSync(skill.dir);
  const warningsBefore = scanWarnings.length;
  const files = walkFiles(root, () => true).sort();
  if (scanWarnings.length !== warningsBefore) return null;
  const hash = createHash("sha256");
  let bytes = 0;
  try {
    for (const file of files) {
      const stat = fs.statSync(file);
      const size = stat.size;
      bytes += size;
      if (size > 20 * 1024 * 1024 || bytes > 50 * 1024 * 1024) {
        scanWarnings.push(
          `Bundle comparison size limit: ${root}; identity unproven`
        );
        return null;
      }
      hash.update(path.relative(root, file));
      hash.update(String(stat.mode & 0o111));
      hash.update("\0");
      hash.update(fs.readFileSync(file));
      hash.update("\0");
    }
    return hash.digest("hex");
  } catch {
    scanWarnings.push(`Incomplete bundle comparison: ${root}`);
    return null;
  }
}

function collapseManagedFanout(skills: Skill[]): Skill[] {
  const groups = groupBy(skills, (s) => `${s.baseName}\0${s.contentHash}`);
  return [...groups.values()].flatMap((group) => {
    if (
      group.length < 2 ||
      !group.some((s) => ["codex-plugin", "managed-plugin"].includes(s.scope))
    )
      return group;
    const bundles = groupBy(group, (skill) => {
      const hash = bundleFingerprint(skill);
      return hash
        ? `${hash}:${skill.enabled}:${skill.codexImplicit}`
        : skill.realPath;
    });
    return [...bundles.values()].map((copies) => {
      const keep = preferredKeepSkill(copies);
      keep.aliases = [
        ...new Set(copies.flatMap((s) => [s.path, ...s.aliases])),
      ].filter((p) => p !== keep.path);
      return keep;
    });
  });
}

function recentLogFiles(): string[] {
  if (noLogs) return [];
  const files = new Set<string>();
  // Usage evidence comes from supported-agent session logs (docs/supported-agents.md).
  // Claude Code and Codex keep full-turn JSONL; the other runtimes log only user prompts
  // or binary/SQLite, so they can't show skill-use traces.
  const roots = [
    ...logRoots.map(expandHome),
    ...(globalScan
      ? [
          path.join(home, ".codex/sessions"),
          path.join(home, ".claude/projects"),
        ]
      : []),
  ];
  if (deepLogs && globalScan) {
    roots.push(
      path.join(home, ".codex/archived_sessions"),
      path.join(home, ".openclaw"),
      path.join(home, ".clawd")
    );
  }
  const history = path.join(home, ".codex/history.jsonl");
  if (globalScan && exists(history) && fs.statSync(history).mtimeMs >= cutoffMs)
    files.add(history);
  for (const root of roots) {
    for (const file of walkRecentFiles(
      root,
      (candidate) => candidate.endsWith(".jsonl") || candidate.endsWith(".log"),
      8
    )) {
      try {
        if (fs.statSync(file).mtimeMs >= cutoffMs) files.add(file);
      } catch {}
    }
  }
  return [...files].sort();
}

function walkRecentFiles(
  root: string,
  predicate: (file: string) => boolean,
  maxDepth = 8
): string[] {
  return walkFiles(root, predicate, maxDepth).filter((file) => {
    try {
      return fs.statSync(file).mtimeMs >= cutoffMs;
    } catch {
      return false;
    }
  });
}

const scannedLogFiles: string[] = [];

function scanUsage(skills: Skill[], logFiles: string[]): Map<string, Usage> {
  const aliases = new Map<string, string[]>();
  for (const skill of skills) {
    const values = new Set([
      skill.name,
      skill.baseName,
      skill.name.split(":").at(-1) ?? skill.name,
    ]);
    aliases.set(
      skill.name,
      [...values].map((value) => value.toLowerCase())
    );
  }
  const usage = new Map<string, Usage>();
  for (const skill of skills)
    usage.set(skill.name, { dollar: 0, fileRead: 0, text: 0 });
  let consumedBytes = 0;
  for (const file of logFiles) {
    let text = "";
    try {
      const stat = fs.statSync(file);
      if (stat.size > 150 * 1024 * 1024) {
        scanWarnings.push(`Oversized transcript skipped: ${file}`);
        continue;
      }
      if (consumedBytes + stat.size > maxLogBytes) {
        scanWarnings.push(
          "Transcript byte limit reached; usage coverage is partial"
        );
        break;
      }
      consumedBytes += stat.size;
      text = fs.readFileSync(file, "utf8");
      scannedLogFiles.push(file);
    } catch {
      scanWarnings.push(`Unreadable transcript: ${file}`);
      continue;
    }
    const dollarCounts = countTokens(
      [...text.matchAll(/\$([A-Za-z][A-Za-z0-9_.:-]{1,80})/g)].map((m) =>
        (m[1] ?? "").toLowerCase()
      )
    );
    const pathCounts = countTokens(
      [
        ...text.matchAll(
          /(?:^|[/"'`\\])(?:\.agents\/)?skills\/([^/"'`\\\s]+)\/SKILL\.md/g
        ),
      ].map((m) => (m[1] ?? "").toLowerCase())
    );
    const textCounts = countTokens(
      [
        ...text.matchAll(
          /\b(?:use|using|load|read)\s+`?\$?([A-Za-z][A-Za-z0-9_.:-]{1,80})`?/gi
        ),
      ].map((m) => (m[1] ?? "").toLowerCase())
    );
    for (const [name, names] of aliases) {
      const item = usage.get(name);
      if (!item) continue;
      for (const candidate of names) {
        item.dollar += dollarCounts.get(candidate) ?? 0;
        item.fileRead += pathCounts.get(candidate) ?? 0;
        item.text += textCounts.get(candidate) ?? 0;
      }
    }
  }
  return usage;
}

function countTokens(values: string[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const value of values) map.set(value, (map.get(value) ?? 0) + 1);
  return map;
}

function groupBy<T>(items: T[], key: (item: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const item of items) {
    const value = key(item);
    map.set(value, [...(map.get(value) ?? []), item]);
  }
  return map;
}

function similarity(
  a: Skill,
  b: Skill
): { description: number; body: number; overall: number } {
  const description = jaccard(wordSet(a.description), wordSet(b.description));
  const body =
    a.bodyHash === b.bodyHash
      ? 1
      : jaccard(wordSet(a.bodyKey), wordSet(b.bodyKey));
  return {
    description,
    body,
    overall: body * 0.8 + description * 0.2,
  };
}

function formatPct(value: number): string {
  return `${Math.round(value * 100)}%`;
}

function formatOnePct(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function formatNumber(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}

function tokenCost(text: string): number {
  return Math.ceil(Buffer.byteLength(text, "utf8") / charsPerToken);
}

function skillOrderRank(skill: Skill): number {
  if (skill.path.includes("/.codex/skills/.system/")) return 0;
  if (skill.scope === "codex-plugin") return 1;
  if (skill.scope === "repo") return 2;
  return 3;
}

function orderedSkillsForBudget(skills: Skill[]): Skill[] {
  return [...skills].sort((a, b) => {
    const byScope = skillOrderRank(a) - skillOrderRank(b);
    if (byScope !== 0) return byScope;
    return a.name.localeCompare(b.name) || a.path.localeCompare(b.path);
  });
}

function renderSkillLine(skill: Skill, description: string): string {
  return description
    ? `- ${skill.name}: ${description} (file: ${skill.path})`
    : `- ${skill.name}: (file: ${skill.path})`;
}

function renderSkillDescriptionPrefix(
  skill: Skill,
  descriptionChars: number
): string {
  if (descriptionChars <= 0) return "";
  return [...skill.description].slice(0, descriptionChars).join("");
}

function lineTokenCost(line: string): number {
  return tokenCost(`${line}\n`);
}

function minimumLineTokenCost(skill: Skill): number {
  return lineTokenCost(renderSkillLine(skill, ""));
}

function fullLineTokenCost(skill: Skill): number {
  return lineTokenCost(renderSkillLine(skill, skill.description));
}

function extraDescriptionCosts(skill: Skill): number[] {
  const minimumLine = renderSkillLine(skill, "");
  const minimumBytes = Buffer.byteLength(`${minimumLine}\n`, "utf8");
  const minimumCost = Math.ceil(minimumBytes / charsPerToken);
  const costs = [0];
  let prefixBytes = 0;
  for (const char of skill.description) {
    prefixBytes += Buffer.byteLength(char, "utf8");
    const renderedBytes = minimumBytes + prefixBytes + 1;
    costs.push(Math.ceil(renderedBytes / charsPerToken) - minimumCost);
  }
  return costs;
}

function codexBudgetedSkillCost(
  skills: Skill[],
  budgetTokens: number
): {
  fullTokens: number;
  minimumTokens: number;
  budgetedTokens: number;
  includedSkills: number;
  omittedSkills: number;
  truncatedDescriptionChars: number;
  truncatedDescriptionCount: number;
} {
  const ordered = orderedSkillsForBudget(skills);
  const fullTokens = ordered.reduce(
    (sum, skill) => sum + fullLineTokenCost(skill),
    0
  );
  if (fullTokens <= budgetTokens) {
    return {
      fullTokens,
      minimumTokens: ordered.reduce(
        (sum, skill) => sum + minimumLineTokenCost(skill),
        0
      ),
      budgetedTokens: fullTokens,
      includedSkills: ordered.length,
      omittedSkills: 0,
      truncatedDescriptionChars: 0,
      truncatedDescriptionCount: 0,
    };
  }

  const minimumTokens = ordered.reduce(
    (sum, skill) => sum + minimumLineTokenCost(skill),
    0
  );
  if (minimumTokens <= budgetTokens) {
    const remainingByIndex = ordered.map(
      (skill) => [...skill.description].length
    );
    const allocatedByIndex = ordered.map(() => 0);
    const currentExtraCosts = ordered.map(() => 0);
    const extraCostsByIndex = ordered.map(extraDescriptionCosts);
    let remaining = budgetTokens - minimumTokens;
    while (true) {
      let changed = false;
      for (let index = 0; index < ordered.length; index++) {
        if (allocatedByIndex[index] >= remainingByIndex[index]) continue;
        const nextChars = allocatedByIndex[index] + 1;
        const nextCost =
          extraCostsByIndex[index]?.[nextChars] ?? currentExtraCosts[index];
        const delta = nextCost - currentExtraCosts[index];
        if (delta <= remaining) {
          allocatedByIndex[index] = nextChars;
          currentExtraCosts[index] = nextCost;
          remaining -= delta;
          changed = true;
        }
      }
      if (!changed) break;
    }

    const rendered = ordered.map((skill, index) =>
      renderSkillLine(
        skill,
        renderSkillDescriptionPrefix(skill, allocatedByIndex[index] ?? 0)
      )
    );
    const truncatedDescriptionChars = ordered.reduce(
      (sum, skill, index) =>
        sum +
        Math.max(
          0,
          [...skill.description].length - (allocatedByIndex[index] ?? 0)
        ),
      0
    );
    const truncatedDescriptionCount = ordered.filter(
      (skill, index) =>
        (allocatedByIndex[index] ?? 0) < [...skill.description].length
    ).length;
    return {
      fullTokens,
      minimumTokens,
      budgetedTokens: rendered.reduce(
        (sum, line) => sum + lineTokenCost(line),
        0
      ),
      includedSkills: ordered.length,
      omittedSkills: 0,
      truncatedDescriptionChars,
      truncatedDescriptionCount,
    };
  }

  let budgetedTokens = 0;
  let includedSkills = 0;
  let omittedSkills = 0;
  let truncatedDescriptionChars = 0;
  let truncatedDescriptionCount = 0;
  for (const skill of ordered) {
    const cost = minimumLineTokenCost(skill);
    if (budgetedTokens + cost <= budgetTokens) {
      budgetedTokens += cost;
      includedSkills++;
    } else {
      omittedSkills++;
    }
    const descriptionChars = [...skill.description].length;
    truncatedDescriptionChars += descriptionChars;
    if (descriptionChars > 0) truncatedDescriptionCount++;
  }
  return {
    fullTokens,
    minimumTokens,
    budgetedTokens,
    includedSkills,
    omittedSkills,
    truncatedDescriptionChars,
    truncatedDescriptionCount,
  };
}

function skillBudget(skills: Skill[]): Budget {
  const context = codexModelContext(model);
  const tokenRatio = numberArg(String(charsPerToken), 4);
  const percent = numberArg(String(budgetPercent), 2);
  const renderedLineChars = skills.reduce(
    (sum, skill) => sum + skill.lineChars,
    0
  );
  const effectiveContextTokens = context.effectivePercent
    ? Math.floor(context.tokens * (context.effectivePercent / 100))
    : null;
  const budgetTokens = Math.floor(context.tokens * (percent / 100));
  const effectiveBudgetTokens = effectiveContextTokens
    ? Math.floor(effectiveContextTokens * (percent / 100))
    : null;
  const codexCost = codexBudgetedSkillCost(skills, budgetTokens);
  return {
    model,
    contextTokens: context.tokens,
    contextSource: context.source,
    effectivePercent: context.effectivePercent,
    effectiveContextTokens,
    budgetPercent: percent,
    budgetTokens,
    effectiveBudgetTokens,
    renderedLineChars,
    unbudgetedFullTokens: codexCost.fullTokens,
    minimumTokens: codexCost.minimumTokens,
    budgetedTokens: codexCost.budgetedTokens,
    charsPerToken: tokenRatio,
    unbudgetedBudgetUsedRatio: codexCost.fullTokens / budgetTokens,
    budgetedBudgetUsedRatio: codexCost.budgetedTokens / budgetTokens,
    effectiveBudgetUsedRatio: effectiveBudgetTokens
      ? codexCost.budgetedTokens / effectiveBudgetTokens
      : null,
    unbudgetedContextUsedRatio: codexCost.fullTokens / context.tokens,
    budgetedContextUsedRatio: codexCost.budgetedTokens / context.tokens,
    effectiveContextUsedRatio: effectiveContextTokens
      ? codexCost.budgetedTokens / effectiveContextTokens
      : null,
    remainingBudgetTokens: budgetTokens - codexCost.budgetedTokens,
    remainingEffectiveBudgetTokens: effectiveBudgetTokens
      ? effectiveBudgetTokens - codexCost.budgetedTokens
      : null,
    includedSkills: codexCost.includedSkills,
    omittedSkills: codexCost.omittedSkills,
    truncatedDescriptionChars: codexCost.truncatedDescriptionChars,
    truncatedDescriptionCount: codexCost.truncatedDescriptionCount,
  };
}

function isLikelyCopy(score: { description: number; body: number }): boolean {
  return (
    score.body >= 0.95 || (score.body >= 0.85 && score.description >= 0.85)
  );
}

function duplicateReviewCandidates(groups: [string, Skill[]][]): string[] {
  const lines: string[] = [];
  for (const [name, list] of groups.slice(0, 80)) {
    const keep = preferredKeepSkill(list);
    const candidates = list
      .filter((skill) => skill.realPath !== keep.realPath)
      .map((skill) => ({ skill, score: similarity(keep, skill) }))
      .filter(({ score }) => isLikelyCopy(score))
      .sort(
        (a, b) =>
          b.score.body - a.score.body ||
          b.score.description - a.score.description
      );
    if (candidates.length === 0) continue;
    lines.push(`- ${name}`);
    lines.push(`  keep: ${keep.scope}: ${keep.path}`);
    for (const { skill, score } of candidates) {
      lines.push(
        `  compare: ${skill.scope}: ${skill.path} (similarity body=${formatPct(score.body)}, description=${formatPct(score.description)}); verify required behavior in every intended host before removal`
      );
    }
  }
  return lines.length ? lines : ["- none"];
}

function render(
  skills: Skill[],
  usage: Map<string, Usage>,
  logFiles: string[]
): string {
  const enabled = skills.filter(
    (skill) => skill.enabled !== false || includeAll
  );
  const roots = groupBy(skills, (skill) => skill.root);
  const byBase = [
    ...groupBy(enabled, (skill) => skill.baseName.toLowerCase()).entries(),
  ].filter(([, list]) => list.length > 1);
  const byBody = [
    ...groupBy(enabled, (skill) => skill.bodyHash).entries(),
  ].filter(([hash, list]) => hash !== "811c9dc5" && list.length > 1);
  const longDescriptions = enabled
    .filter((skill) => skill.descChars >= 110 || skill.lineChars >= 180)
    .sort((a, b) => b.descChars - a.descChars)
    .slice(0, 30);
  const unused = (logFiles.length && !noLogs ? enabled : [])
    .filter((skill) => {
      const item = usage.get(skill.name);
      return !item || item.dollar + item.fileRead + item.text === 0;
    })
    .sort(
      (a, b) => a.scope.localeCompare(b.scope) || a.name.localeCompare(b.name)
    )
    .slice(0, 80);
  const totalLineChars = enabled.reduce(
    (sum, skill) => sum + skill.lineChars,
    0
  );
  const totalDescChars = enabled.reduce(
    (sum, skill) => sum + skill.descChars,
    0
  );
  const budget = skillBudget(enabled);
  const lines: string[] = [];
  lines.push("# Skill Cleaner Report", "");
  lines.push(`generated: ${new Date().toISOString()}`);
  lines.push(`months: ${months}`);
  lines.push(
    `skills: ${skills.length} discovered, ${enabled.length} considered`
  );
  lines.push(`description_chars: ${totalDescChars}`);
  lines.push(`rendered_line_chars: ${totalLineChars}`);
  lines.push(`log_files_scanned: ${logFiles.length}`, "");

  lines.push(
    "## Illustrative Codex-style Budget (not measured host usage)",
    ""
  );
  lines.push(
    "Discovered files are not a confirmed loaded catalogue. Host loading and explicit-only visibility vary."
  );
  lines.push(`model: ${budget.model}`);
  lines.push(`context_tokens: ${formatNumber(budget.contextTokens)}`);
  lines.push(`context_source: ${budget.contextSource}`);
  lines.push(
    `${budget.budgetPercent}%_budget_tokens: ${formatNumber(budget.budgetTokens)}`
  );
  lines.push(`codex_cost_rule: ceil(utf8_bytes / ${budget.charsPerToken})`);
  lines.push(
    `unbudgeted_full_tokens: ${formatNumber(budget.unbudgetedFullTokens)}`
  );
  lines.push(
    `minimum_no_description_tokens: ${formatNumber(budget.minimumTokens)}`
  );
  lines.push(`budgeted_tokens_used: ${formatNumber(budget.budgetedTokens)}`);
  lines.push(
    `used_of_metadata_budget: ${formatOnePct(budget.budgetedBudgetUsedRatio)}`
  );
  lines.push(
    `unbudgeted_used_of_metadata_budget: ${formatOnePct(budget.unbudgetedBudgetUsedRatio)}`
  );
  lines.push(
    `used_of_context: ${formatOnePct(budget.budgetedContextUsedRatio)}`
  );
  lines.push(
    `remaining_metadata_budget_tokens: ${formatNumber(budget.remainingBudgetTokens)}`
  );
  lines.push(`included_skills_after_budget: ${budget.includedSkills}`);
  lines.push(`omitted_skills_after_budget: ${budget.omittedSkills}`);
  lines.push(
    `truncated_description_chars: ${formatNumber(budget.truncatedDescriptionChars)}`
  );
  if (
    budget.effectiveContextTokens &&
    budget.effectiveBudgetTokens &&
    budget.remainingEffectiveBudgetTokens != null
  ) {
    lines.push(
      `effective_context_tokens: ${formatNumber(budget.effectiveContextTokens)} (${budget.effectivePercent}%)`
    );
    lines.push(
      `effective_metadata_budget_tokens: ${formatNumber(budget.effectiveBudgetTokens)}`
    );
    lines.push(
      `used_of_effective_metadata_budget: ${formatOnePct(budget.effectiveBudgetUsedRatio ?? 0)}`
    );
    lines.push(
      `remaining_effective_metadata_budget_tokens: ${formatNumber(budget.remainingEffectiveBudgetTokens)}`
    );
  }
  lines.push("");

  lines.push("## Description Candidates", "");
  for (const skill of longDescriptions) {
    lines.push(`- ${skill.name}`);
    lines.push(`  path: ${skill.path}`);
    lines.push(
      `  chars: description=${skill.descChars}, rendered_line=${skill.lineChars}`
    );
    lines.push(`  current: ${skill.description}`);
    lines.push(
      "  review: preserve task, important exclusions and explicit-only policy; propose a concise description after reading the skill"
    );
  }
  if (longDescriptions.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Duplicates By Name", "");
  for (const [name, list] of byBase.slice(0, 40)) {
    lines.push(`- ${name}`);
    const keep = preferredKeepSkill(list);
    lines.push(`  keep-default: ${keep.scope}: ${keep.path}`);
    for (const skill of list) {
      const score =
        skill.realPath === keep.realPath
          ? { body: 1, description: 1 }
          : similarity(keep, skill);
      lines.push(
        `  - ${skill.scope}: ${skill.path} (body=${formatPct(score.body)}, description=${formatPct(score.description)})`
      );
    }
  }
  if (byBase.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Duplicate Review Candidates (not deletion authority)", "");
  lines.push(...duplicateReviewCandidates(byBase));
  lines.push("");

  lines.push("## Duplicates By Body Hash", "");
  for (const [, list] of byBody.slice(0, 30)) {
    lines.push(`- ${list.map((skill) => skill.name).join(", ")}`);
    for (const skill of list) lines.push(`  - ${skill.scope}: ${skill.path}`);
  }
  if (byBody.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Usage Review Candidates", "");
  lines.push(
    noLogs
      ? "Transcript scanning disabled; no usage conclusions."
      : "No matching usage trace is not proof a skill is unused; inspect coverage and intended hosts."
  );
  for (const skill of unused) {
    const item = usage.get(skill.name) ?? { dollar: 0, fileRead: 0, text: 0 };
    lines.push(
      `- ${skill.name}: ${skill.scope}; usage=$${item.dollar}, reads=${item.fileRead}, text=${item.text}; ${skill.path}`
    );
  }
  if (unused.length === 0) lines.push("- none");
  lines.push("");

  lines.push("## Root Summary", "");
  for (const [root, list] of [...roots.entries()].sort(
    (a, b) => b[1].length - a[1].length
  )) {
    const disabled = list.filter((skill) => skill.enabled === false).length;
    lines.push(
      `- ${root}: ${list.length} skills${disabled ? `, ${disabled} disabled` : ""}`
    );
  }
  lines.push(
    "",
    "## Agent Instruction Files",
    "",
    "Symlinks share one source; assess nested scope before changing instructions."
  );
  for (const file of instructions) {
    lines.push(
      `- ${file.path}: ${file.lines} lines, ~${file.estimatedTokens} estimated tokens`
    );
    for (const alias of file.aliases) lines.push(`  alias: ${alias}`);
  }
  if (!instructions.length) lines.push("- none in selected roots");
  lines.push("", "## Inventory Gaps", "");
  lines.push(
    ...(scanWarnings.length
      ? [...new Set(scanWarnings)].map((w) => `- ${w}`)
      : ["- none detected within selected roots and depth limits"])
  );
  return lines.join("\n");
}

const instructions = discoverInstructions();
const skills = discoverSkills();
const logFiles = recentLogFiles();
const usage = scanUsage(skills, logFiles);
const consideredSkills = skills.filter(
  (skill) => skill.enabled !== false || includeAll
);
const budget = skillBudget(consideredSkills);
const output = json
  ? JSON.stringify(
      {
        roots,
        skills,
        instructions,
        usage: noLogs ? null : Object.fromEntries(usage),
        logFiles: scannedLogFiles,
        discoveredLogFiles: logFiles,
        budget,
        warnings: [...new Set(scanWarnings)],
        assumptions: {
          inventoryIsLoadedState: false,
          budgetIsSimulation: true,
          logsEnabled: !noLogs,
        },
      },
      null,
      2
    )
  : render(skills, usage, scannedLogFiles);
console.log(output);
