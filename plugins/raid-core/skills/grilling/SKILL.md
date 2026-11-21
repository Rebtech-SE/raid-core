---
name: grilling
description: >-
  Use when the user wants to stress-test a plan, decision, or idea, or uses any
  "grill" trigger phrase ("grill me", "grill this", "grilling"). Interviews the
  user in rounds down a design tree until shared understanding. The bare form:
  decisions settle in the conversation. `grill-with-docs` adds the durable
  record (ADRs, GLOSSARY.md) via `domain-modeling`.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask *now* without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a *later* round, not this one.

Look up facts in the repo, platform or tools before asking a question that depends on them. Ask the user for decisions and wait for the answer.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
