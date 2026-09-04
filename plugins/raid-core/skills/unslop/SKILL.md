---
name: unslop
description: >-
  Cut AI tells from any writing and add human voice. Runs as a write-through
  style pass on everything you draft, and doubles as the audit gate: use when
  asked to check for AI slop, remove AI tells, make writing sound human, or
  review a draft for robotic language.
---

# Unslop

Edit text to remove AI patterns and add human voice.

## Boundary

- Auditing or cleaning existing text: this skill handles it end to end.
- Generating marketing or product copy is a different job. This skill may serve
  as the final quality gate on generated copy, but it does not invent
  positioning, argument, or campaign.
- For short write-through passes on conversational output, apply the process
  inline, without the file and linter steps.

## Process

1. Scan for the patterns below.
2. Rewrite. Preserve meaning, match intended tone.
3. Add soul (see next section).
4. Run the mechanical gate (below) when the draft is a file or pasted text.
5. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

## Adding soul

Removing patterns is half the job. Sterile, voiceless writing is just as obvious.

- **Have opinions.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. Mix it up.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive."
- **Use "I" when it fits.** First person isn't unprofessional.
- **Let some mess in.** Perfect structure looks machine-made.
- **Be specific.** Not "this is concerning" but "there's something unsettling about agents churning away at 3am."

## Mechanical gate

When auditing a draft, run the bundled linter first. It catches the
deterministic tells — banned vocabulary, conjunctive filler, banned openers,
empty phrases, em dashes, emoji piling. Its word lists are parsed from
`references/ai-slop-checklist.md`; edit the lists there, not in the script.

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
python3 "$SKILL_DIR/scripts/ai_slop_lint.py" path/to/draft.md
# or pipe text through stdin
pbpaste | python3 "$SKILL_DIR/scripts/ai_slop_lint.py" -
```

Fix every hit unless the term is a required proper noun or an exact quotation;
state any justified exception. A clean result is necessary but not sufficient —
the judgment rules below still decide whether it sounds human.

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
36. **Dramatic fragmentation.** "That's it. That's the whole thing." Punchy fragments stacked for effect. One is a beat; three is a tic.
37. **Negative listing.** "Not a X. Not a Y. A Z." Stacked denial before the reveal. Once per piece at most; usually just state what it is.
38. **Editorializing.** Telling the reader how to feel: "This is exciting", "Interestingly". Present the thing; let them react.

### Formatting

39. **Headers over tiny sections.** If a section is a sentence, it doesn't need a header.
40. **Bullets for prose.** Lists for things that aren't a list. If items read as sentences, write sentences.
41. **Colon capitalization.** Lowercase the word after a colon unless grammar, a proper noun, a title, or code requires a capital.

### Judgment, not hard rules

These have legitimate uses, so read for them by hand instead of blanket-banning.

- **Empty-phrase padding.** "It's worth noting", "at the end of the day", "at its core", "in today's world", "the reality is", "going forward", "let's dive in". Cut; the linter bans them outright.
- **Empty adverbs.** "just", "simply", "actually", "literally", "honestly", "truly", "fundamentally". A few are fine in casual copy; cut the ones adding nothing.
- **Context-dependent words.** "harness", "elevate", "embark", "when it comes to". Cut when inflating ("harness the power of…"); keep when literal.
- **Read-aloud test.** AI slop is smooth, even, and frictionless — every sentence the same length, every clause balanced. Real copy has uneven rhythm: a three-word line next to a long one, a fragment, a hard stop. If it sounds like it was written to be inoffensive, it was.

## Output (when auditing)

1. **Verdict:** one sentence naming the dominant problem, or "already clean".
2. **Findings:** meaningful issues only — the smallest useful fragment plus the tell name.
3. **Revised draft:** the full cleaned version when changes are needed.
4. **Mechanical gate:** `clean`, or the remaining justified exceptions.

Lead with the revised draft when the ask is a rewrite rather than an audit, and
skip the checklist recital when the user only needs the cleaned copy.
