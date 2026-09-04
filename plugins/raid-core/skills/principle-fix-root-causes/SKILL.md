---
name: principle-fix-root-causes
description: "Use when debugging. Trace each symptom to its root cause and fix it there; reproduce first, ask why until you reach it, and resist the guards that silence a failure without fixing it."
disable-model-invocation: true
---

# Fix Root Causes

When debugging, do not paper over symptoms. Trace every problem to its root cause and fix it there.

**Why:** Symptom fixes accumulate. Each workaround makes the system harder to reason about, and the real bug remains. Root-cause fixes are slower upfront but reduce total debugging time.

**Pattern:**
- Reproduce first (if you can't reproduce it, you can't verify your fix)
- Ask "why" until you hit the root cause
- Resist the urge to add guards (adding a nil check to silence a crash is a symptom fix)
- If a workaround needs a paragraph-long comment to justify it, the code is wrong (fix the code, not the comment)
- Check for the pattern, not just the instance (grep for the same pattern, fix all instances)
- When stuck, instrument. Don't guess (add logging, read the actual error)

**Restart bugs: suspect state before code**

Code doesn't change between runs. State does. When something "fails after restart," suspect stale persistent state first: config files, caches, lock files, serialized state. If clearing a state file restores behavior, prioritize state validation as the fix.

**In data work, the equivalents are the data and the load, not the SQL.** A model that was
right yesterday and wrong today usually means the source changed, the watermark moved, a
late-arriving fact landed, or an incremental run skipped a partition -- not that the
transform logic rotted. Check what came in before you read the SQL again.

The data-specific symptom fixes to resist: a `COALESCE` that hides a broken join, a
`DISTINCT` that hides a fan-out, a `WHERE` that filters out the rows that expose the bug,
and a full refresh that makes an incremental defect disappear without fixing it. Each one
turns a loud failure into a silently wrong number.

`debug-data-issue` is this principle as a procedure -- trace symptom to failing transform
to upstream data, and prove the cause with a failing check before fixing it.
