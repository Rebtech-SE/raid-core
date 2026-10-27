# Before and after

One rewrite per common tell. The numbers match the patterns in `SKILL.md`.
These show the direction of a fix, not a template: the right rewrite depends on
what the writer actually meant, and sometimes the fix is to cut the sentence.

## Mannered prose

Before: Batch size is a dial worth turning.
After: Try batch sizes of 16, 32, and 64.

Before: The retry logic does the heavy lifting here.
After: Most of the failures are recovered by the retry logic.

Before: Kept as is: "the queue acts as a shock absorber for traffic spikes."
Why: no shorter literal phrase says that bursts are smoothed out over time, so
the comparison explains something. Keep it.

## Content and language

1. Puffery
Before: The launch marked a pivotal moment for the team.
After: The launch doubled weekly signups.

8. Fancy ways to say "is"
Before: The config file serves as the single source of truth.
After: The config file is the only place these values are set.

9. "Not just X, but Y"
Before: It's not just a parser, it's a full toolchain.
After: It parses and formats the file.

12. False ranges
Before: Covers everything from logging to deployment.
After: Covers logging, CI, and deployment.

## Style and formatting

13. Em dashes
Before: The build is fast — it finishes in about ten seconds.
After: The build is fast. It finishes in about ten seconds.

14. Colon as connector
Before: Read the schema first: the feature depends on it.
After: Read the schema first, because the feature depends on it.

16. Inline-header list
Before: **Performance:** Performance improved by 40%.
After: Pages load 40% faster.

## Communication and filler

20. Chatbot phrases
Before: Great question! Here's what I found. Let me know if this helps!
After: The test fails because the fixture uses last year's date.

24. Hedging
Before: The change could potentially cause some issues in certain cases.
After: The change breaks imports when the path has a space in it.

## Plain speech

26. Abstract metaphor nouns
Before: The deal gives us a wedge into the enterprise vector.
After: The deal gets us a first enterprise customer.

27. Feeling instead of mechanism
Before: Types that follow your schema.
After: Renaming a column fails the build until every query is updated.

29. Passive voice
Before: Queries are validated before they are sent.
After: The compiler checks each query before sending it.

## Openings and endings

34. Fake-profound kicker
Before: The future isn't coming. It's already here.
After: The new API ships to all users on Monday.

36. Dramatic fragmentation
Before: One file. One command. Done.
After: Setup is one file and one command.

36. Staccato sentences
Before: More reliable. Less expensive.
After: It is more reliable and costs less.

## Clarity

42. Fake agency
Before: The logs become searchable records once the job finishes.
After: You can search the logs once the job finishes.

43. Vague demonstrative
Before: This changes how the cache behaves.
After: The new expiry setting makes the cache drop entries after an hour.

44. Count opener
Before: Two cautions. First, the doc can drift. Second, it can grow too long.
After: The doc can drift out of date, and it grows long if every item gets a
paragraph.

45. Invented hyphen compound
Before: We added a reveal-style colon to the heading.
After: We added a colon before the part of the heading that shows the result.

46. Missing context in chat
Before: The exporter now waits on the reset header, and the tests pass.
After: The log exporter was re-reading whole hours after a rate limit, so it
wrote some events twice. It now waits until the time in the reset header, and
the six acceptance tests pass.

## Deslopify

Before: Fixed it. `syncWorker` was racing `flushQueue` on the shared cursor, so
I moved the lock up into `runCycle` and the flake on CI is gone.
After: The nightly sync sometimes skipped records, and that is now fixed. Two
parts of the sync job were updating the same position marker at the same time,
so one could overwrite the other's progress. The job now holds a lock for the
whole cycle, so only one part moves the marker at a time. The test that failed
intermittently has passed on every run since.
