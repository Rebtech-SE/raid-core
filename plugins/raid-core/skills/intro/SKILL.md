---
name: intro
description: >-
  Use when someone is new to RAID or asks how to use it -- '/intro', 'how do I use RAID',
  'what can RAID do', 'where do I start', 'which command should I run'. Gives a short,
  hands-on orientation: what RAID is, the one command to start with, the routes work
  takes, the commands worth knowing, and how to get help. Explains; changes nothing.
argument-hint: "[optional: your role or what you want to do, e.g. 'add a dbt model']"
---

# RAID intro

Orient someone who has not used RAID before, in one reply they can read in two minutes.
This is a guide, not a reference manual: lead with the one thing to do first, and leave
the rest for when they need it. Read-only -- do not touch the repo.

## Fit it to the person and the host

- **Their goal.** If `$ARGUMENTS` or the conversation says what they want to do ("add a
  dbt model", "I'm a PM", "new customer platform"), open with the route for that and keep
  the rest short. With no goal, give the general tour below.
- **What is installed.** Name only commands that are actually available in this session
  -- check your command/skill list. A tier (Fabric, Databricks, BigQuery, AWS) or
  `raid-greenfield` that is not installed gets one line on what it would add, not its
  commands.
- **How the host names things.** Use the host's own words and syntax. In RAID Agent these
  are built-in commands and built-in subagents. In Claude Code, Codex or Copilot they are
  the RAID plugin's skills; show the invocation the host uses (for example `/raid-mode`).
- **Say what a command is for, not how it works inside.** One line each. Never quote or
  walk through a command's own instructions.

## The tour

Cover these, in this order, as plain prose and a few short lists. Skip what does not
apply.

1. **What RAID is.** Rebtech's way of building and changing data platforms with an AI
   agent: dbt models, notebooks, pipelines, warehouse and lakehouse tables. It holds the
   agent to a few rules a good data engineer follows anyway.

2. **Start with `/raid-mode`.** Describe the task in plain words after it
   (`/raid-mode add a customer dimension with SCD2`). It reads the request, picks the
   route, says which one, and asks before anything risky. They can override the route.
   Calling other commands directly is for when they already know which one they want.

3. **The routes `raid-mode` picks from.**
   - **Direct** -- a typo, a rename, a config value. Just done.
   - **Incremental** (the everyday one) -- build in small verified units, then
     `/simplify-code` and `/review-changes`, then `/commit-push-pr`.
   - **Too big to see the end of** -- a migration, a new source system: `/wayfinder`
     charts the open decisions as tickets and works through them.
   - **Greenfield** -- a new platform or customer sign-off documents: the design stages
     from `/assess-platform` to `/design-data-model` (needs `raid-greenfield`), or
     `/ship-engagement` to run them end to end.

4. **What to expect.** RAID checks its work against real data when it can read the
   warehouse, and says so plainly when it cannot. It stops for approval before writes
   that matter and never touches production without a go-ahead. It keeps no plan file in
   the repo: the work lives in the conversation, or as tickets on the tracker when it has
   to outlive the session.

5. **Commands worth knowing.** Pick the handful that fit their goal from what is
   installed, grouped by situation, for example:
   - Getting started in a repo: `/setup-raid` (once per engagement), `/map-repo` (read an
     unfamiliar codebase).
   - Understanding, not changing: `/how`, `/why`, `/teach`.
   - When something is wrong: `/debug-data-issue`, `/check-platform-health`,
     `/tune-workload`.
   - Shipping: `/review-changes`, `/commit-push-pr`, `/resolve-pr-feedback`, `/babysit`.
   - Settling meaning: `/domain-modeling`, `/grill-me`.
   - The platform tier's own commands, if one is installed.

6. **Getting help.** Run `/intro` again any time, or just ask "which command should I use
   for X". If RAID itself misbehaves, `/report-raid-bug` files it for the RAID team.
   `/bro` restates the last answer in plain words.

End with one concrete next step tied to their goal, for example the exact `/raid-mode`
line to type for what they said they want to do.
