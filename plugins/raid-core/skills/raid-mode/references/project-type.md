# Project type

The one definition of how `raid-mode` learns how RAID is used in a repo. The project type
picks the default route and decides how much process RAID suggests. It is chosen per repo,
never at install time, and it guides without blocking.

## The four types

| Type | Value | What it means | Default route |
|---|---|---|---|
| Direct | `direct` | The build loop with its tests and review, and no plan, documents or reminders | **Direct** or **Incremental** |
| Maintenance | `maintenance` | New requirements in an existing architecture | **Maintenance** |
| Migration | `migration` | Requirements live in a legacy system, the architecture is new | **Migration** |
| New build | `new-build` | Requirements and architecture are both new | **Greenfield** |

A **Question** is answered on any type and never needs a type.

## Where the type lives

Read the first that exists:

1. **`project.type` in `docs/artifacts/trace.json`** (format in `references/trace-file.md`).
   Written by the planning stage when there is one; it wins when present.
2. **One line in the repo's root `AGENTS.md`**: `RAID project type: <value>`, optionally
   followed by `(changed from <old> <YYYY-MM-DD>)`. `raid-mode` writes this line; it is the
   only thing it writes about the type.

Without the trace file, the `AGENTS.md` line is the source and nothing else changes.

`raid-mode` never writes `trace.json`, and the type never goes in `.raid/config.yaml`
(telemetry only).

## When to ask

- **Ask once, on the first piece of work that would change something**, when neither
  source has a type. One question, four choices, with the one-line meanings above. Use the
  host's blocking question tool when it has one.
- **Do not ask** for a Question, or when the user has already said how they work ("just
  hack it", "this is a migration") -- take that as the answer and say which type you
  recorded.
- After the answer, add the `AGENTS.md` line (create the file with that line if the repo
  has none) and tell the user in one line what you recorded and how to change it.
- **Direct:** go straight to the build loop. Never suggest planning stages, documents
  or the trace file again unless the user asks or changes the type.
- **Any other type:** when `plan-project` is available, suggest it once as the next step,
  so the project plan records the development process for this type. When
  `raid-greenfield` is not installed, say on one line that it adds planning for this type,
  and carry on with core.

## Changing the type

The user can change it at any time ("this has become a migration"). Update the
`AGENTS.md` line with the new value and `(changed from <old> <date>)`. When the trace file
exists, tell the user its `project.type` is updated by the planning stage, and route on the
new type from now on. Nothing is redone automatically.

## Guiding, never blocking

The type sets defaults: the suggested route, which skills are offered, and whether RAID
reminds about missing steps. The user can override any of it per request, and RAID
announces the route it picked so they can.
