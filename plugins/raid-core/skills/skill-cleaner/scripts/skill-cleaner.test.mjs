import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const script = fileURLToPath(new URL("./skill-cleaner.mts", import.meta.url));
// Deliberately retain fixtures as inspectable scratch evidence; no user-tree cleanup.
const fixture = () =>
  fs.mkdtempSync(path.join(os.tmpdir(), "skill-cleaner-test-"));
function write(root, rel, body) {
  const file = path.join(root, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body);
  return file;
}
function makeSkill(root, rel = "skills/example", extra = "") {
  return write(
    root,
    `${rel}/SKILL.md`,
    `---\nname: example\ndescription: >-\n  Inspect the selected data.\n  Preserve audit-only scope.\ndisable-model-invocation: true\n---\n# Example\nRead and report.\n${extra}`
  );
}
function run(root, flags = []) {
  const result = spawnSync(
    process.execPath,
    [
      "--experimental-strip-types",
      script,
      "--json",
      "--context-tokens",
      "10000",
      ...flags,
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test("default is current checkout, folded metadata and explicit-only policy survive", () => {
  const root = fixture();
  makeSkill(root);
  write(
    root,
    "skills/example/agents/openai.yaml",
    "policy:\n  allow_implicit_invocation: false\n"
  );
  const report = run(root);
  assert.deepEqual(report.roots, [fs.realpathSync(root)]);
  assert.equal(report.skills.length, 1);
  assert.equal(
    report.skills[0].description,
    "Inspect the selected data. Preserve audit-only scope."
  );
  assert.equal(report.skills[0].explicitOnly, true);
  assert.equal(report.skills[0].codexImplicit, false);
  assert.equal(report.skills[0].enabled, null);
  assert.equal(report.usage, null);
  assert.deepEqual(report.logFiles, []);
});

test("instruction aliases share a source while nested and independent Claude files remain", () => {
  const root = fixture();
  write(root, "AGENTS.md", "Root scope.\n");
  fs.symlinkSync("AGENTS.md", path.join(root, "CLAUDE.md"));
  write(root, "nested/AGENTS.md", "Nested scope.\n");
  write(root, "nested/CLAUDE.md", "Claude adapter.\n");
  write(root, "agents/claude.md", "Named lowercase instruction file.\n");
  const report = run(root);
  assert.equal(report.instructions.length, 4);
  const main = report.instructions.find(
    (f) => f.path === fs.realpathSync(path.join(root, "AGENTS.md"))
  );
  assert.deepEqual(main.aliases, [
    path.join(fs.realpathSync(root), "CLAUDE.md"),
  ]);
});

test("selected roots exclude siblings and external symlinks until explicitly included", () => {
  const parent = fixture();
  const root = path.join(parent, "selected"),
    other = path.join(parent, "other");
  fs.mkdirSync(root);
  makeSkill(other);
  fs.symlinkSync(
    path.join(other, "skills/example/SKILL.md"),
    path.join(root, "SKILL.md")
  );
  const scoped = run(parent, ["--root", root]);
  assert.equal(scoped.skills.length, 0);
  assert.equal(scoped.roots.length, 1);
  assert.ok(scoped.warnings.some((w) => w.includes("outside root")));
  const expanded = run(parent, ["--root", root, "--root", other]);
  assert.equal(expanded.skills.length, 1);
});

test("only byte-identical managed fan-out collapses; description drift remains visible", () => {
  const root = fixture();
  const source = makeSkill(root);
  const prefix = ".codex/plugins/cache/market/plugin";
  write(
    root,
    `${prefix}/one/skills/example/SKILL.md`,
    fs.readFileSync(source, "utf8")
  );
  write(
    root,
    `${prefix}/two/skills/example/SKILL.md`,
    fs
      .readFileSync(source, "utf8")
      .replace("Inspect the selected data.", "Inspect different data.")
  );
  const report = run(root);
  assert.equal(report.skills.length, 2);
  assert.equal(
    report.skills.reduce((n, s) => n + s.aliases.length, 0),
    1
  );
  assert.equal(new Set(report.skills.map((s) => s.contentHash)).size, 2);
});

test("explicit config can disable a skill regardless of TOML key order", () => {
  const root = fixture();
  const file = makeSkill(root);
  const config = write(
    root,
    "chosen.toml",
    `[[skills.config]]\nenabled = false\npath = ${JSON.stringify(file)}\n`
  );
  const report = run(root, ["--codex-config", config]);
  assert.equal(report.skills[0].enabled, false);
  assert.equal(report.budget.includedSkills, 0);
  assert.equal(
    run(root, ["--codex-config", config, "--all"]).budget.includedSkills,
    1
  );
});

test("logs require opt-in and bounded scope; no-log mode makes no unused inference", () => {
  const root = fixture();
  makeSkill(root);
  const logs = path.join(root, "transcripts");
  write(root, "transcripts/one.jsonl", '{"text":"Use $example"}\n');
  assert.equal(run(root, ["--log-root", logs]).usage, null);
  const report = run(root, ["--logs", "--log-root", logs]);
  assert.equal(report.logFiles.length, 1);
  assert.ok(report.usage.example.dollar > 0);
  const limited = run(root, [
    "--logs",
    "--log-root",
    logs,
    "--max-log-mb",
    "0.000001",
  ]);
  assert.ok(limited.warnings.some((w) => w.includes("byte limit")));
});

test("budget assumptions are explicit and custom byte ratio changes estimates", () => {
  const root = fixture();
  makeSkill(root);
  write(root, "AGENTS.md", "åäö ".repeat(100));
  const four = run(root, ["--budget-percent", "3"]);
  const eight = run(root, ["--chars-per-token", "8"]);
  assert.equal(four.budget.contextSource, "--context-tokens");
  assert.equal(four.budget.budgetTokens, 300);
  assert.equal(four.assumptions.budgetIsSimulation, true);
  assert.equal(four.assumptions.inventoryIsLoadedState, false);
  assert.ok(
    eight.budget.unbudgetedFullTokens < four.budget.unbudgetedFullTokens
  );
  assert.ok(
    eight.instructions[0].estimatedTokens < four.instructions[0].estimatedTokens
  );
});

test("bad flags and conflicting scan modes fail before discovery", () => {
  const root = fixture();
  for (const flags of [
    ["--root"],
    ["--global", "--root-only"],
    ["--logs"],
    ["--context-tokens", "oops"],
    ["--budget-percent", "0"],
    ["--unknown"],
  ]) {
    const result = spawnSync(
      process.execPath,
      ["--experimental-strip-types", script, ...flags],
      { cwd: root, encoding: "utf8" }
    );
    assert.notEqual(result.status, 0, JSON.stringify(flags));
    assert.equal(result.stdout, "");
  }
});

test("directory symlink aliases remain visible without traversing cycles", () => {
  const root = fixture();
  makeSkill(root, ".agents/skills/example");
  fs.mkdirSync(path.join(root, ".claude"));
  fs.symlinkSync("../.agents/skills", path.join(root, ".claude/skills"));
  fs.symlinkSync(".", path.join(root, "cycle"));
  const report = run(root);
  assert.equal(report.skills.length, 1);
  assert.ok(
    report.skills[0].aliases.some((p) => p.includes("/.claude/skills/"))
  );
});

test("external metadata symlinks are reported without reading their policy", () => {
  const parent = fixture(),
    root = path.join(parent, "selected");
  makeSkill(root);
  write(
    parent,
    "external.yaml",
    "policy:\n  allow_implicit_invocation: true\n"
  );
  fs.mkdirSync(path.join(root, "skills/example/agents"));
  fs.symlinkSync(
    path.join(parent, "external.yaml"),
    path.join(root, "skills/example/agents/openai.yaml")
  );
  const report = run(parent, ["--root", root]);
  assert.equal(report.skills[0].codexImplicit, null);
  assert.ok(
    report.warnings.some(
      (w) => w.includes("openai.yaml") && w.includes("outside")
    )
  );
});

test("equal entrypoints with different bundled behavior are not collapsed", () => {
  const root = fixture();
  const source = makeSkill(root);
  write(root, "skills/example/references/workflow.md", "Original workflow.\n");
  const cache = ".codex/plugins/cache/market/plugin/one/skills/example";
  write(root, `${cache}/SKILL.md`, fs.readFileSync(source, "utf8"));
  write(root, `${cache}/references/workflow.md`, "Changed workflow.\n");
  assert.equal(run(root).skills.length, 2);
});

test("log read count excludes files rejected by the byte budget", () => {
  const root = fixture();
  makeSkill(root);
  write(root, "transcripts/one.jsonl", "Use $example\n");
  const report = run(root, [
    "--logs",
    "--log-root",
    path.join(root, "transcripts"),
    "--max-log-mb",
    "0.000001",
  ]);
  assert.equal(report.logFiles.length, 0);
});
