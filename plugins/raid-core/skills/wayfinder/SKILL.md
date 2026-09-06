---
name: wayfinder
description: >-
  Use when a piece of data work is too big for one agent session and the way to the end is
  not yet visible -- a platform migration, a new source system, a re-model of a domain.
  Triggers: 'this is too big', 'where do we even start', 'chart this out', 'wayfind this'.
  Plans it as a shared map of decision tickets on the engagement's issue tracker, then
  resolves them one at a time until nothing is left to decide. Planning, not building.
disable-model-invocation: true
---

A loose idea has arrived, too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** on the repo's issue tracker, then works its **decision tickets** (questions whose resolution is a decision, not slices of a build to execute) one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting: it shapes every ticket. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic: engineering work, course content, whatever fits the shape.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the map is done when the way is clear, with nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off. An effort can override this in its **Notes**, carrying execution into the map itself, but absent that, produce decisions, not deliverables.

## Refer by name

Every map and ticket is an issue, so it has a **name**: its title. In everything the human reads (narration, the map's Decisions-so-far), refer to it by that name, never by a bare id, number, or slug. A wall of `#42, #43, #44` is illegible; names read at a glance. The id and URL don't vanish; a name wraps its link, but they ride _inside_ the name, never stand in for it.

## The Map

The map is a single issue on this repo's issue tracker, labelled `wayfinder:map`, the canonical artifact. Its tickets are child issues of the map.

The map is an **index**, not a store. It lists the decisions made and points at the tickets that hold their detail; a decision lives in exactly one place, its ticket, so the map never restates it, only gists it and links.

**Where the map, its child tickets, blocking, and frontier queries physically live is tracker-specific.** Use the tracker recorded as `tracker.provider` in `.raid/config.yaml`, and the command recipes for it in `setup-raid`'s `references/trackers/` (`azure-devops.md`, `jira.md`, `linear.md`, `github.md`). If no tracker has been configured, tell the user to invoke `setup-raid`, then stop; choosing a tracker or silently falling back to local files is the engagement's decision, not yours.

Prefer native tracker relationships because they keep the frontier visible in the
tracker UI. When a configured tracker lacks one of them, or the engagement's
`tracker.mapping.wayfinder` block chooses them (`map_issuetype` for the map's issue
type, `markers: body` where the label vocabulary is controlled), use these portable
body fields instead:

| Concept | Native representation | Portable fallback |
| --- | --- | --- |
| Map | Issue labelled `wayfinder:map` | `Type: wayfinder-map` in the body |
| Child | Sub-issue of the map | `Part of: <map link>` in the body |
| Ticket type | `wayfinder:<type>` label | `Type: <type>` in the body |
| Claim | Assignee | `Claimed by: <actor>` in the body |
| Blocking | Native dependency edge | `Blocked by: <ticket links>` in the body |

Use one representation consistently for the whole map. Never infer that a missing
CLI means the tracker is unavailable; a host-provided tracker interface may cover
the same operations.

### The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed: they are open child issues, found by query.

```markdown
## Destination

<what reaching the end of this map looks like: the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index: one line per closed ticket, enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [<closed ticket title>](link): <one-line gist of the answer>

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
```

### Tickets

Each ticket is a **child issue** of the map; the tracker's issue id is its identity. Its body is the question, sized to one 100K token agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

A ticket of type `task` -- one that produces a build rather than a decision -- uses RAID's
standard ticket-brief shape instead (Goal, Scope, Context, Acceptance, Verify, Forbidden,
Blocked by), so the build loop can claim it without translation. `to-tickets` owns that
shape and its definitions.

Each ticket records one type — `research`, `prototype`, `grilling`, or `task` — as
a `wayfinder:<type>` label where labels are available, otherwise with the fallback
field above (see [Ticket Types](#ticket-types)).

A session **claims** a ticket **first**, before any work, so concurrent sessions
skip it. Prefer assigning it to the dev driving the map; where assignment is not
available, write the fallback claim field. An open ticket without either marker is
unclaimed.

Blocking uses the tracker's **native** dependency relationship when available,
because it renders the frontier _visually_ in the tracker's own UI. Otherwise use
the fallback body field. A ticket is **unblocked** when every ticket blocking it
is closed; the **frontier** is the open, unblocked, unclaimed children, the edge
of the known.

On resolution, the durable answer is recorded in the body or the linked artifact, and the
comment summarises and links it (see [Work through the map](#work-through-the-map)) -- an
answer that lives only in a comment thread is one the next reader has to reconstruct.
Assets created while resolving a ticket are linked from the issue, not pasted in.

## Ticket Types

Every ticket is either **HITL** (human in the loop, worked _with_ a human who speaks for themselves) or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): Read authoritative documentation, third-party APIs, or local resources like knowledge bases to surface a fact a decision waits on. Delegate the ticket as an independent research task when the host supports parallel agents; otherwise leave it for a dedicated session. Use when knowledge outside the current working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to (an outline, a rough take, a stub, or UI/logic code) with `prototype`. Link the prototype as an asset. Use when "how should it look" or "how should it behave" is the key question.
- **Grilling** (HITL): Conversation, and the default case. Run the `grilling` skill (raid-core) as a breadth-first decision interview: ask the whole currently-unblocked question frontier in one round, give a recommended answer for each, wait for the human, then recompute the frontier. Apply `domain-modeling` throughout so resolved vocabulary and durable decisions are captured as they crystallise.
- **Task** (HITL or AFK): Manual work that must happen before a _decision_ can be made: nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that _does_ rather than decides, and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, new URLs, row counts) later tickets depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war**: the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets, one at a time, until the way to the destination is clear and no tickets remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. It's the undiscovered frontier _toward_ the destination: everything here is in scope, just not sharp enough to ticket. Write as loosely or as fully as the view allows; it doubles as a signpost for collaborators reading where the effort is headed.

**Fog or ticket?** The test is whether you can state the question precisely now, _not_ whether you can answer it now.

- **Ticket when** the question is already sharp, even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into ticket-sized pieces: it's coarser than a ticket, and one patch may graduate into several tickets, or none, once the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live ticket, and what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out of scope**: it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section on the map: work you've consciously ruled out of _this_ effort. Scope, not sharpness, lands it here.

Out-of-scope work never graduates (the frontier stops at the destination), so it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a ticket that already exists turns out to sit past the destination (mis-scoped in while charting, or exposed by a resolution), **close it** (a closed ticket is unambiguously off the frontier) and leave one line in the **Out of scope** section: the gist plus why it's out of scope, linking the closed ticket. It stays out of **Decisions so far**, which records the route actually walked; a scope boundary isn't a step on it.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session**, with the exception of research tickets.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run the breadth-first decision interview above while applying `domain-modeling`, to pin down what this map is finding its way to: the spec, decision, or change. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** (the way to the destination is already clear, the whole journey small enough for one session), you don't need a map. Stop and ask the user how they'd like to proceed.
3. **Create the map** using the configured tracker representation: Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
4. **Create the tickets you can specify now** as child issues of the map, then wire blocking edges in a **second pass** (issues need ids before they can reference each other). Wiring sorts them into the frontier and the blocked; everything you can't yet specify stays in the fog: the **Not yet specified** section.
5. **Fire the research tasks.** For each `research` ticket you just created, delegate one independent task when the host supports it. Each task claims and resolves only that ticket, cites its authoritative sources in the resolution comment, and links any larger artifact instead of pasting it into the map. If parallel delegation is unavailable, leave the research tickets open on the frontier for dedicated later sessions.
6. Stop: charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map (URL or number). A ticket is **optional**: without one, you pick the next decision, not the user.

1. Load the **map**: the low-res view, not every ticket body.
2. Choose the ticket. If the user named one, use it. Otherwise take the first frontier ticket in order. **Claim it**: assign it to yourself before any work.
3. Resolve it. **Zoom as needed**: fetch the full body of any related or closed ticket on demand; use whichever shipped skills the `## Notes` block names. If in doubt, use the breadth-first decision interview and apply `domain-modeling`.
4. Record the resolution: post the answer as a **resolution comment**, **close** the issue, and **append a context pointer** to the map's Decisions-so-far.
5. Add newly-surfaced tickets (create-then-wire); graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified** so it lives only as its new ticket. If the answer reveals that a ticket (this one or another) sits beyond the destination, **rule it out of scope** rather than resolving it on the route. If the decision invalidates other parts of the map, update or delete those tickets.

The user may run unblocked tickets in parallel, so expect other sessions to be editing the tracker concurrently.

**When the map is clear**, hand off rather than starting to build inside it: run
`to-tickets` to cut the now-visible work into vertical slices with their blocking edges,
then work them through `raid-mode`. The map's Decisions-so-far is the Context those tickets
point at.
