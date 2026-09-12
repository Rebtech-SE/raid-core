---
name: report-raid-bug
description: >-
  Use when a RAID skill or agent did the wrong thing and the user says 'report this
  bug', 'file a bug for RAID', 'this skill is broken - log it'. Files a bug against the
  RAID plugin itself (a skill, agent, or convention that misbehaved) as a tracker item
  on whatever host the plugin repo uses - GitHub issue, Azure Boards work item, or
  GitLab issue - with environment context and a minimal reproduction gathered
  automatically.
argument-hint: "[short description of what went wrong; optional: --project <name>]"
---

# RAID Report Bug

Capture a defect in the RAID plugin -- a skill that did the wrong thing, an agent that
returned malformed output, a convention that contradicts itself -- as a well-formed
tracker item so it can be triaged and fixed. This is about the **plugin tooling**, not
the customer's data work (a data bug is `debug-data-issue`).

**Tracker (detect first).** File to the issue tracker of whatever host the plugin repo
uses — detect from `git remote get-url origin` (see the provider table in
`raid-core/AGENTS.md`): GitHub -> an issue (`gh issue create`); Azure DevOps -> a Boards
work item (`az boards`, `az-cli` skill's `references/boards.md`); GitLab -> an issue
(`glab issue create`). If the host is none of these, assemble the report and hand it to
the user to file manually.

## Workflow

### 1. Understand the defect

From `$ARGUMENTS` and the recent session, pin down:

- **What happened** -- the skill/agent involved and the observed wrong behavior.
- **What was expected** instead.
- **Reproduction** -- the steps or the invocation that triggered it; the smallest
  version that still shows the problem.
- **Impact** -- did it block work, produce wrong output, or just annoy?

Ask only if a load-bearing detail is missing.

### 2. Gather environment context (automatically)

Collect what a maintainer will need, so they don't have to ask:

- RAID plugin version(s) installed (`raid-core` + the active tier) and the platform
  the repo is built on.
- The skill/agent name and, if known, the reference file involved.
- Relevant tool/CLI versions if implicated (`az version`, `git --version`, Python
  version) -- only those plausibly related to the bug.
- A trimmed transcript excerpt or error text showing the failure (ASCII; redact any
  secrets, tokens, or customer data before including it).

### 3. Build the tracker item

Compose the bug:

- **Title:** `bug(<skill-or-agent>): <concise symptom>`.
- **Body:** sections for Observed / Expected / Reproduction / Environment / Impact.
  Repo-relative paths; ASCII only; no customer data. GitHub and GitLab take Markdown;
  Azure Boards takes HTML — render the body to match the target.
- **Labels/tags:** `raid-plugin`, `bug`, plus the component (`raid-core`/`raid-fabric`/...).

### 4. Confirm, then create

Show the assembled item and **confirm before creating** (filing is an outward action).
Then create it on the detected host:

```bash
# GitHub:
gh issue create --title "bug(<component>): <symptom>" --body-file <body.md> \
  --label raid-plugin --label bug --label <component>

# Azure DevOps — resolve the project (--project, else ask). New work items start in
# state New (do not set an invalid state). If Bug is not an available type, fall back to Issue/Task and say so.
az boards work-item create \
  --title "bug(<component>): <symptom>" --type Bug --project "<project>" \
  --description "<html>" \
  --fields "System.Tags=raid-plugin;bug;<component>" -o json

# GitLab:
glab issue create --title "bug(<component>): <symptom>" --description "$(cat <body.md>)" \
  --label "raid-plugin,bug,<component>"
```

### 5. Report

Print the created item id/number, title, URL, and labels/tags. If the bug has an obvious
local workaround, state it. Note that filing logs the report only -- it does not fix the
plugin.

## Rules

- This is for RAID plugin defects, not customer data bugs (`debug-data-issue`).
- Redact secrets and customer data from any included transcript/error text.
- Confirm before creating the item; create only -- never close or delete here.
- Repo-relative paths. On Azure Boards the valid initial state is New.
