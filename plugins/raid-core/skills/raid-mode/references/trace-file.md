# Trace file

The one definition of `docs/artifacts/trace.json`: the index that ties requirements,
architecture decisions, designs and planned tests together, plus the project's type and
step status. Writers and readers both follow this file rather than describing the format
themselves.

## Who writes it, who reads it

- **Written by the stage that owns an artifact**, when that stage renders it: requirements
  from the requirements stage, `ADR` entries from the architecture and design stages, `TP`
  entries from the test plan stage. Each writer updates only its own section and keeps the
  rest of the file as it found it.
- **Read by core when the file exists**: `raid-mode`, `review-changes`, `write-test-report`
  and `to-tickets`. Trigger on the file, not on which plugins are installed: a core-only
  session can inherit a trace file from an earlier run.
- **When the file is missing, nothing changes.** Readers fall back to what they did before
  (the test plan's TP ids, the ticket's Acceptance, the conversation) and never ask for the
  file, create it, or report its absence as a problem.

## What it is and is not

- It is an **index**: ids, titles, versions, status and links. The content lives in the
  HTML artifacts (`requirements.html`, `architecture.html`, `design.html`, `testplan.html`),
  which stay what people read and sign off.
- It is **not a status board for tests.** Whether a TP id passed lives in the ledger
  (`write-test-report`'s `references/results-ledger.md`), joined on the TP id. Never copy
  outcomes into the trace file.
- It is **not configuration.** `.raid/config.yaml` stays telemetry only.

## Ids

Keep the ids the artifacts already use, so no template or running engagement breaks:

| Section | Id | Defined in |
|---|---|---|
| `requirements` | `FR-n`, `NFR-n` | `requirements.html` |
| `architecture` | `ADR-nnn` | `architecture.html`, `design.html` |
| `design` | `D-n` (one short design per requirement) | the design step |
| `tests` | `TP-<entity>-NN`, `TP-<gate>-NN` | `testplan.html` |

Ids are never renumbered or reused. A dropped item's id is retired.

## Shape

```json
{
  "schema_version": "1.0",
  "project": {
    "type": "migration",
    "type_history": [{ "type": "migration", "date": "2026-11-24", "reason": "Initial choice" }],
    "steps": [
      { "step": "assessment", "status": "done", "approved": { "role": "Customer project manager", "date": "2026-11-28", "doc_version": 2 } },
      { "step": "architecture", "status": "skipped", "reason": "Read from completed POC", "date": "2026-11-29" }
    ],
    "waivers": [{ "date": "2026-12-02", "item": "FR-7", "reason": "Design agreed in workshop, written later" }]
  },
  "requirements": [
    { "id": "FR-7", "title": "Monthly revenue per region", "version": 2, "status": "approved", "source": "legacy:SSAS/Sales/Revenue", "needs_review": false }
  ],
  "architecture": [{ "id": "ADR-004", "title": "Streaming ingestion for sensor data", "requirements": ["FR-12"], "status": "approved" }],
  "design": [{ "id": "D-7", "title": "gold.revenue_region_month", "requirements": ["FR-7"], "requirement_versions": { "FR-7": 2 }, "status": "draft" }],
  "tests": [
    { "id": "TP-revenue-01", "title": "Revenue per region matches source", "level": "system", "requirements": ["FR-7"], "design": ["D-7"] },
    { "id": "TP-revenue-02", "title": "Users confirm regional totals", "level": "verification", "requirements": ["FR-7"] }
  ]
}
```

- `project.type` is one of `new-build`, `maintenance`, `migration`. The `direct` type writes no
  trace file. Before a trace file exists, `raid-mode` records any type as one line in
  `AGENTS.md` (`references/project-type.md`); `project.type` wins once it is written.
- `steps[].status` is `done`, `open` or `skipped`. A skip carries `reason` and `date`.
- `status` on an item is `draft` or `approved`. An approval names a role, never a person.
- `tests[].level` is `unit`, `system`, `integration` or `verification` (the V-model:
  unit against code, system against design, integration against architecture,
  verification against requirements).
- `requirements[].source` is optional; a migration uses it to point at the legacy object.
- Every section is optional. A file with only `tests` is valid.

## Versions

- `schema_version` is `major.minor`. Read a file whose major you know, ignore fields you
  do not know, and warn once on an unknown major and read nothing else from it.
- A requirement carries `version`. When it goes up, every design and test that links it
  with an older `requirement_versions` entry is treated as `needs_review` until it is
  updated. Readers report that as information.

## Reading rules

- **Report gaps as information, never as an error.** A requirement with no TP id, a TP id
  with no requirement, a design without approval: list them, do not fail or block.
- **The file and the artifacts must agree.** An id in one and not the other is a gap to
  report, not something to fix silently in either file.
