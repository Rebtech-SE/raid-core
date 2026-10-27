---
name: unslop
description: >-
  Use when writing or reviewing anything a person will read (a client-facing
  artifact, a report, a ticket, a PR body, a stage reply), when asked for
  plainer or less performed prose, when asked to deslopify a response, or to
  check a draft for AI slop. Removes AI writing tells, mannered prose, and stock
  phrasing, with a bundled lint gate. Also a standing write-through constraint
  on user-facing output.
---

# Unslop

Edit text to remove AI patterns and performed phrasing, and add human voice.

## Modes

Pick the mode from the request. All three use the same rubric below.

- **Write-through.** A standing constraint on your own user-facing output
  (reports, reviews, summaries, tickets, PR bodies, chat replies). Apply the
  rubric while writing and reread once before sending. No audit output, and no
  mechanical gate unless the output is a file.
- **Cleanup or audit.** Supplied text. Follow the process below and return the
  output described at the end.
- **Deslopify.** The user says "deslopify", or asks for a response to be
  rewritten so anyone can follow it. See the section below.

## Boundary

- Generating marketing or product copy is a different job. This skill may serve
  as the final quality gate on generated copy, but it does not invent
  positioning, argument, or campaign.
- This pass changes phrasing, never claims. Preserve the writer's meaning,
  examples, and voice.

## Process

1. Scan for the patterns below, including mannered prose.
2. Rewrite. Preserve meaning, match intended tone. Read
   `references/before-after.md` when a fix is not obvious; it pairs each
   common tell with a rewrite.
3. Add soul (see below).
4. Run the mechanical gate (below) when the draft is a file or pasted text.
5. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

`references/ai-slop-checklist.md` is the long-form rubric with the full banned
word lists, for workflows that run an explicit slop gate.

## Mechanical gate

When auditing a draft, run the bundled linter first. It catches the
deterministic tells: banned vocabulary, conjunctive filler, banned openers,
empty phrases, em dashes, emoji piling. Its word lists are parsed from
`references/ai-slop-checklist.md`; edit the lists there, not in the script.

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
python3 "$SKILL_DIR/scripts/ai_slop_lint.py" path/to/draft.md
# or pipe text through stdin
pbpaste | python3 "$SKILL_DIR/scripts/ai_slop_lint.py" -
```

Fix every hit unless the term is a required proper noun or an exact quotation;
state any justified exception. A clean result is necessary but not sufficient.
The judgment rules below still decide whether it sounds human.

## Mannered prose

Anthropic's definition, quoted as published:

> Mannered prose substitutes metaphor and flourish for direct statement. Instead
> of "a parameter worth varying," the mannered writer produces "a dial worth
> turning." Instead of "this point still matters," they write "this point earns
> its keep." The phrases exist to display the writer, not to convey the idea, and
> readers can tell. That is why mannered prose irritates: it makes the reader work
> harder so the writer can perform. It is also imprecise. Metaphors drag in
> connotations the writer did not choose and cannot control. The fix is to say
> what you mean. When a literal phrase is available, use it.

The test, one question per suspect phrase: **is a literal phrase available?**
If yes, the figure is decoration; replace it. If no, the idea has no plain name
and the comparison is doing explanatory work, so keep it. Stripping every figure
of speech produces flat text, which is a different failure, not a fix.

Two consequences make this a correctness problem rather than taste:

- A metaphor imports connotations you did not pick. "A dial worth turning"
  suggests a continuous range; if the parameter has three discrete values, the
  phrase told the reader something false.
- Mannered phrasing hides vagueness. When the literal rewrite is hard to write,
  the underlying thought is not yet specific. Write the literal version anyway
  and let it expose the gap.

Common shapes: a mechanical noun turned into a physical action, an abstract
point given a body ("earns its keep", "does the heavy lifting", "carries its
weight"), and a claim dressed as a scene. When the full definition is more than
the moment needs, Anthropic's short instruction is enough: "Please remove all
mannered prose."

Source: Anthropic, *Prompting Claude Fable 5.1*, "Writing density":
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>

## Deslopify

Rewrite the previous response, or the text given with the request, for a sharp
reader who has no project context: an executive, or an engineer from another
team. Return only the rewrite.

1. Open with the conclusion or the decision needed.
2. Give the background in a sentence or two: what the problem was and what was
   happening before.
3. Explain what changed or how it works, in order. Walk a sequence step by step.
4. Keep the technical details the reader needs. Use the established name for
   each thing, not a term coined during the work, and define anything a
   newcomer would not know. Drop internal ids, branch names, and file paths
   unless the reader must act on them.
5. Apply the rest of this rubric.

## Adding soul

Removing patterns is half the job. Sterile, voiceless writing is just as obvious.

- **Have opinions.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. Mix it up.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive."
- **Use "I" when it fits.** First person isn't unprofessional.
- **Let some mess in.** Perfect structure looks machine-made.
- **Be specific.** Not "this is concerning" but "there's something unsettling about agents churning away at 3am."

## Patterns to detect and fix

### Content

1. **Puffery.** "pivotal moment", "testament to", "evolving landscape", "setting the stage for", "indelible mark", "deeply rooted". Cut puffery, state what happened.
2. **Name-dropping.** Listing media outlets without context. Pick one, say what was said.
3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete or expand with real sources.
4. **Promotional language.** "nestled", "vibrant", "breathtaking", "groundbreaking", "renowned", "stunning", "must-visit". Use neutral descriptions.
5. **Vague attributions.** "Experts believe", "Industry reports suggest", "Some critics argue". Name the source or delete.
6. **Formulaic challenges.** "Despite challenges... continues to thrive." Replace with specific facts.

### Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore, vibrant. Replace with plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Just say "is" or "has".
9. **"Not just X, but Y."** State the point directly instead.
10. **Rule of three.** Forcing ideas into groups of three. Use the natural number.
11. **Synonym cycling.** Protagonist, main character, central figure, hero all in one paragraph. Pick one, repeat it.
12. **False ranges.** "from X to Y" where X and Y aren't on a meaningful scale. List topics directly.

### Style

13. **Em dash overuse.** Avoid em dashes entirely. Use periods or commas only (no parentheses, no en dashes, no hyphen-as-dash substitutes). Em dashes are an AI tell, and reaching for parentheses instead just trades one tell for another. If a thought needs separation, end the sentence or use a comma.
14. **Colon overuse.** Colons are fine before a list or example. Not as mid-sentence connectors. "If you're coming from traditional automation: instead of registering event handlers, you describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own without comparison framing. "Describing when the scheduler should fire works best as plain English." Same meaning, no crutch punctuation.
15. **Boldface overuse.** Don't bold every proper noun or acronym.
16. **Inline-header lists.** The tell is a bold label and colon that restates the line: "**Performance:** Performance improved...". Convert those to prose. A bold lead-in that ends in a period, names the item, and is followed by genuinely new detail ("**Schema in TypeScript.** Tables live in one file.") is fine, not a tell.
17. **Title case headings.** Use sentence case.
18. **Decorative emojis.** Remove from headings and bullets.
19. **Curly quotes.** Replace with straight quotes.

### Communication artifacts

20. **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Of course!", "Certainly!", "Found the smoking gun!" Remove.
21. **Cutoff disclaimers.** "While specific details are limited..." Find sources or remove.
22. **Sycophantic tone.** "Great question! You're absolutely right!" Respond directly.

### Filler

23. **Filler phrases.** "In order to" becomes "To". "Due to the fact that" becomes "Because". "It is important to note that" gets deleted.
24. **Excessive hedging.** "could potentially possibly be argued that it might" becomes "may".
25. **Generic conclusions.** "The future looks bright." State specific plans or facts.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. These read as technical but usually have a plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the last phase". Pick the concrete word.

### Plain speech

27. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read", "types that follow your schema" name a feeling. The fix names the mechanism or a number: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build". Ask what the sentence tells the reader to do or know, then write that. If you can't restate it as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break it in two or drop clauses. One idea per sentence.
29. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor: "queries are validated" becomes "the compiler validates queries", "the file is parsed by the loader" becomes "the loader parses the file". Passive is fine only when the actor is unknown or genuinely doesn't matter.
30. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
31. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.

### Openings and endings

32. **Throat-clearing openers.** "Here's the thing", "Let me be clear", "I'll be honest", "What nobody tells you", "What most people get wrong", "Welcome to", "Introducing". They delay the point. Start with the point.
33. **Reflexive summaries.** Restating every point at the end. Trust the reader.
34. **Fake-profound kickers.** The closing aphorism that restates the point as a metaphor: "The future isn't coming. It's already here." / "And that changes everything." End on a concrete point, a takeaway, or the next action.

### Rhetoric

35. **Rhetorical setups.** "What if I told you…", "Think about it:", "Plot twist:". Manufactured suspense. Cut and make the claim directly.
36. **Dramatic fragmentation and staccato sentences.** "That's it. That's the whole thing." Punchy fragments stacked for effect. One is a beat; three is a tic. The staccato form is two or three clipped, parallel fragments: "More reliable. Less expensive." / "Sleep better. Live longer." / "Thinner. Lighter. Faster." It is the default voice of AI landing pages and ads, so in headlines, taglines, and feature copy treat even one pair as a hit. Join the ideas in one sentence: "More reliable. Less expensive." becomes "It is more reliable and costs less." Name the mechanism or number behind them only when the source gives it; otherwise ask the writer for it rather than inventing one.
37. **Negative listing.** "Not a X. Not a Y. A Z." Stacked denial before the reveal. Once per piece at most; usually just state what it is.
38. **Editorializing.** Telling the reader how to feel: "This is exciting", "Interestingly". Present the thing; let them react.

### Formatting

39. **Headers over tiny sections.** If a section is a sentence, it doesn't need a header.
40. **Bullets for prose.** Lists for things that aren't a list. If items read as sentences, write sentences.
41. **Colon capitalization.** Lowercase the word after a colon unless grammar, a proper noun, a title, or code requires a capital.

### Clarity

42. **Fake agency.** An object that "decides", "transforms", or "becomes" when a person or process is the real actor. "The logs become searchable records" becomes "you can search the logs once the job finishes". Plain factual verbs for tools are fine: "the API returns JSON".
43. **Vague demonstratives.** A sentence, and above all a paragraph, that opens with a bare "This", "That", or "These" whose referent the reader has to look back for. Name the thing: "That context carries over" becomes "The agent keeps your saved rules on the next turn".
44. **Count openers.** "Two cautions." "Three things to know." Announcing the number before the content. State the first point.
45. **Invented hyphen compounds.** Adjectives coined by gluing words together to sound compact: "reveal-style colon", "agent-shaped workflow". If a dictionary or the field doesn't use it, write the phrase out. Established compounds ("well-known", "read-only") are fine.
46. **Missing context in chat.** A report that names the change but not the problem: "The exporter now waits on the reset header." Say what was wrong first, in one sentence, then what changed and how you know it works. Keep the setup short.

### Judgment, not hard rules

These have legitimate uses, so read for them by hand instead of blanket-banning.

- **Empty-phrase padding.** "It's worth noting", "at the end of the day", "at its core", "in today's world", "the reality is", "going forward", "let's dive in". Cut; the linter bans them outright.
- **Empty adverbs.** "just", "simply", "actually", "literally", "honestly", "truly", "fundamentally". A few are fine in casual copy; cut the ones adding nothing.
- **Context-dependent words.** "harness", "elevate", "embark", "when it comes to". Cut when inflating ("harness the power of…"); keep when literal.
- **Read-aloud test.** AI slop is smooth, even, and frictionless, every sentence the same length, every clause balanced. Real copy has uneven rhythm: a three-word line next to a long one, a fragment, a hard stop. If it sounds like it was written to be inoffensive, it was.

## Output (when auditing)

1. **Verdict:** one sentence naming the dominant problem, or "already clean".
2. **Findings:** meaningful issues only, the smallest useful fragment plus the tell name and what it became, so the writer sees the pattern. Where you kept a metaphor because no literal phrase exists, say so.
3. **Revised draft:** the full cleaned version when changes are needed.
4. **Mechanical gate:** `clean`, or the remaining justified exceptions.

Lead with the revised draft when the ask is a rewrite rather than an audit, and
skip the checklist recital when the user only needs the cleaned copy.
