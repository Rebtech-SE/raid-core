---
name: mannered-prose
description: >-
  Use when writing or reviewing anything a person will read -- a client-facing artifact, a
  report, a review, a summary, a PR body, a stage reply -- and whenever the user asks for
  plainer, less writerly, less performed prose or says something reads as trying too hard.
  Replaces metaphor and flourish with direct statement. Also a standing constraint on your
  own output when a skill or workflow routes its writing through it.
---

# Mannered Prose

Anthropic's definition, quoted as published:

> Mannered prose substitutes metaphor and flourish for direct statement. Instead
> of "a parameter worth varying," the mannered writer produces "a dial worth
> turning." Instead of "this point still matters," they write "this point earns
> its keep." The phrases exist to display the writer, not to convey the idea, and
> readers can tell. That is why mannered prose irritates: it makes the reader work
> harder so the writer can perform. It is also imprecise. Metaphors drag in
> connotations the writer did not choose and cannot control. The fix is to say
> what you mean. When a literal phrase is available, use it.

## The test

One question per suspect phrase: **is a literal phrase available?**

If yes, the metaphor is decoration and costs the reader time. Replace it.

If no, the idea has no plain name, and the comparison is doing explanatory work
the literal version cannot do, keep it. This is the part that is easy to get
wrong in the other direction. Stripping every figure of speech produces flat,
lifeless text, which is a different failure, not a fix. The target is the
metaphor that *stands in for* a plain phrase, not the metaphor that earns its
place by explaining something.

Two things follow from the "imprecise" half of the definition, and they are the
reason this is a correctness problem rather than a matter of taste:

- A metaphor imports connotations you did not pick. "A dial worth turning"
  suggests a smooth continuous range; if the parameter is a small set of discrete
  options, the phrase has quietly told the reader something false.
- Mannered phrasing hides vagueness. When the literal rewrite is hard to write,
  that difficulty is usually the finding: the underlying thought is not yet
  specific. Write the literal version anyway and let it expose the gap.

## Applying it

**To your own output**, before sending: reread for phrases that perform. The
common shapes are a mechanical noun turned into a physical action, an abstract
point given a body ("earns its keep", "does the heavy lifting", "carries its
weight"), and a claim dressed as a scene. Replace each with what you meant.

**To supplied text**: return the rewrite, with the changed phrases listed
alongside what they became, so the writer can see the pattern rather than only
the result. Preserve their meaning, their examples, and their voice, this pass
changes phrasing, never claims. Where a literal replacement would lose real
meaning, leave the metaphor and say why.

When the full definition is more than the moment needs, the short instruction
Anthropic gives is enough on its own:

> Please remove all mannered prose.

## Boundary

`unslop` is the broad rubric for AI writing tells, stock phrases, formulaic
structure, hedging, false range, and much else, and it rewrites end to end.
This skill is one narrow failure, and it applies to prose that is otherwise
human and good. Reach for it during writing, as a constraint on the sentences
being produced; reach for `unslop` afterwards, as a full pass over a finished
draft. Running both is fine, and neither replaces the other.

## Source

Anthropic, *Prompting Claude Fable 5.1*, "Writing density":
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>

The quoted paragraph and the short instruction are Anthropic's text. Everything
else here is local guidance for applying them. The paragraph works on models
from other labs too, so treat it as writing guidance rather than a Claude
workaround.
