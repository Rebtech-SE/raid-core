# AI-Slop Checklist

The single source of truth for what counts as AI-generated writing in reviewed
output. This file is the operational rubric. The lint script
(`scripts/ai_slop_lint.py`) parses its machine-readable word lists directly
from this file, so edit the lists **here** and the linter stays in sync
automatically.

Two kinds of rules live here:

- **Mechanical** — exact strings the linter catches deterministically. Listed
  in the marked blocks below. Fix every one; there are no false positives worth
  keeping.
- **Judgment** — patterns a human (or a reviewing agent) has to read for. The
  linter can't see these. Read this file before declaring copy done.

Run the linter as the cheap first gate, then read the judgment section yourself:

```bash
python3 skills/unslop/scripts/ai_slop_lint.py path/to/draft.md
# or pipe a draft straight in:
pbpaste | python3 skills/unslop/scripts/ai_slop_lint.py -
```

Exit code is non-zero when anything is flagged.

---

## Mechanical rules (the linter enforces these)

### Banned vocabulary

Never use these words. They are the most common AI writing tells. If you reach
for one, find the concrete word that actually says what you mean.

<!-- lint:banned-vocab -->
delve, intricate, tapestry, pivotal, underscore, landscape, foster, testament,
enhance, crucial, vital, significant, profound, steadfast, breathtaking,
captivate, watershed, solidify, multifaceted, nuanced, robust, leverage,
utilize, facilitate, paradigm, synergy, holistic, comprehensive, streamline,
innovative, cutting-edge, game-changing, revolutionary, seamless, intuitive,
best-in-class, empower, transformative, supercharge, ever-evolving, realm,
beacon, meticulous, paramount, game changer, enduring, garner,
interplay, showcasing, vibrant
<!-- /lint:banned-vocab -->

### Conjunctive filler

Cut these or replace with a real transition.

<!-- lint:filler -->
moreover, furthermore, additionally
<!-- /lint:filler -->

### Banned openers

Don't start a piece, section, or paragraph with these. Includes throat-clearing
openers — warm-up phrases that delay the actual point.

<!-- lint:openers -->
welcome to, introducing, here's the thing, let me be clear, i'll be honest,
the uncomfortable truth, what nobody tells you, what most people get wrong
<!-- /lint:openers -->

### Often-empty phrases

Filler that pads a sentence without adding information. Matched anywhere in a
line, not just at the start. Cut the phrase; usually the sentence is stronger
without it (`in order to` → `to`).

<!-- lint:phrases -->
it's worth noting, it's important to note, at the end of the day, at its core,
in today's world, in the age of, in the world of, the reality is, the truth is,
going forward, let's dive in
<!-- /lint:phrases -->

### Em dashes and double hyphens

Never use em dashes (—) in any output. Don't substitute the literal double
hyphen (`--`) either. Restructure with commas, periods, or parentheses, or
split into two sentences. (A normal hyphen inside a compound word like
`best-in-class` or `two-tap` is fine — the linter ignores those.)

### Emoji piling

One emoji per section, max, and only if it earns its place. Two or more emoji on
the same line reads as AI exuberance. The linter flags lines with 2+ emoji.

---

## Judgment rules (read these yourself — the linter can't)

These are the tells that need a reader, not a regex. Check them by hand before
declaring copy done.

### Structural tells

- **Rule of three.** "X, Y, and Z" lists everywhere. Use 2 or 4 — whatever the
  content actually has. One rule-of-three list in a piece is fine; a cadence of
  them is the tell.
- **Negative parallelism.** "It's not about X, it's about Y." Once per piece,
  max.
- **False ranges.** "From X to Y" or "Whether X or Y" used to sound inclusive
  while saying nothing. Be specific instead.
- **Reflexive summaries.** Restating every point at the end. Trust the reader.
- **Negative listing.** "Not a X. Not a Y. A Z." A cousin of negative
  parallelism, done as a stacked list. Once per piece at most; usually just
  state what it *is*.
- **Colon reveals.** "The detail that makes it work: a separate agent grades
  it." The colon-as-drumroll. Rewrite as a plain sentence.
- **Rhetorical setups.** "What if I told you…", "Think about it:", "Plot
  twist:". Manufactured suspense. Cut and make the claim directly.
- **Dramatic fragmentation.** "That's it. That's the whole thing." Punchy
  fragments stacked for effect. One is a beat; three is a tic.

### Tone tells

- **Inflated symbolism.** Framing mundane things as epic narratives.
- **Editorializing.** Telling the reader how to feel — "This is exciting,"
  "Interestingly." Present the thing; let them react.
- **Superficial -ing commentary.** Vague gerund phrases that add nothing:
  "Creating a more engaging experience."
- **Promotional tone about the copy itself.** Just write it; don't sell it.
- **Faux-insight setups.** "Here's what nobody tells you," "the part everyone
  misses," "what most people get wrong." Pretends to reveal a secret. Just say
  the thing; let the reader decide if it's news.
- **Weasel attribution.** "Experts agree," "studies show," "widely regarded
  as," "many argue." Authority with no source. Name the source or drop the claim.
- **Fake-strong verbs.** "The app serves as a centralized hub." Verb sounds
  active but says nothing. Replace with the concrete action ("logs, sorts, and
  exports your sets").
- **Synonym cycling.** Rotating through synonyms for the same thing to avoid
  repetition ("the app… the tool… the platform… the solution"). Pick one word
  and repeat it.

### Ending tells

- **Fake-profound kickers.** The closing "deep" line that restates the point as
  a metaphor or aphorism: "The future isn't coming. It's already here." /
  "And that changes everything." Delete it. End on a concrete point, a takeaway,
  or the next action — never on a manufactured mic-drop.

### Formatting tells

- **Emoji in headings**, and decorative mid-sentence **bold** used for emphasis
  rather than meaning.
- **Headers over one- or two-line sections.** If a section is a sentence, it
  doesn't need a header.
- **Bullets for prose.** Lists for things that aren't a list. If items read as
  sentences, write sentences.
- **Colon-capitalization.** Lowercase the word after a colon unless grammar, a
  proper noun, a title, or code requires a capital.

### Often-empty adverbs (judgment, not a hard ban)

Words like `just`, `simply`, `actually`, `literally`, `honestly`, `truly`,
`fundamentally`, `importantly`, `crucially`, `inherently`, `inevitably` are
usually filler ("this is *just* a simpler way" → "this is a simpler way").
Not linted, because a few are legitimate in casual/spoken copy and the false-
positive rate would be high — read for them by hand and cut the ones that add
nothing.

### Context-dependent words and phrases (judgment, not a hard ban)

Strong AI tells that also have legitimate literal uses, so they're read for by
hand rather than linted:

- **`harness`, `elevate`, `embark`.** Usually puffery ("harness the power of…",
  "elevate your workflow"), but fine when literal ("harness" the gym equipment,
  "embark" on a trip). Cut when they're inflating; keep when they're the plain word.
- **`in order to` → `to`.** Almost always removable padding.
- **`when it comes to`.** Usually cuttable ("when it comes to logging, it's fast"
  → "logging is fast"). Common enough that linting it is noisy.

### Abstract metaphor nouns (judgment, not a hard ban)

Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness
(as metaphor), surface (as in "API surface"), bedrock, scaffolding (as
metaphor), modality, gold-plating, ratchet (as metaphor), evacuate (for moving
code), endgame, north star, flywheel. These read as technical but usually have
a plainer concrete word: "substrate" becomes "base", "wedge in" becomes "add",
"vector" becomes "way" or "method", "gold-plating" becomes "more than the job
needs", "ratchet" becomes the mechanism's real name, "evacuate" becomes "move
out", "endgame" becomes "the last phase". Several have literal uses (a real
wedge, an actual surface area) — swap only when the metaphor is doing the work.

### The read-aloud test

Read the draft out loud. AI slop is smooth, even, and frictionless — every
sentence the same length, every clause balanced. Real copy has uneven rhythm:
a three-word line next to a long one, a fragment, a hard stop. If it sounds
like it was written to be inoffensive, it was. Rewrite for friction.
