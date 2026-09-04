### Autonomous run

**You own the exit condition. Define done, then drive to it without stopping.** For "run
until done", "keep going until the backfill completes", "I'm going to bed".

1. **State the exit condition as a checkable predicate before the first iteration** --
   "all 14 silver models build green", "the backfill reconciles to source within 0.1%",
   "the DQ pass rate is above 98%". A vague goal stalls; a predicate lets you stop. If you
   cannot write the predicate as something you could run, you are not ready to start.
2. **Establish the baseline** and record it. You cannot claim improvement against a number
   you never measured.
3. **Each iteration makes the smallest change the evidence justifies**, verifies it against
   the predicate, commits if it advanced, and **discards changes that didn't help**. A
   partition filter that "might help" gets reverted, not left to ride. One variable at a
   time, or you learn nothing from the result.
4. **Sequence into verifiable units** and check each before the next, rather than batching
   the checks at the end (`principle-sequence-verifiable-units` is not shipped; the rule
   lives here: a unit that has not been verified is not done).
5. **Mid-run discoveries are yours.** A broken test, a flaky source, a stale credential, an
   adjacent bug -- fix it and carry on, in its own commit. Do not park reversible work for
   the human. Surface only the gated items from the Autonomy section, a genuine product
   call no experiment can settle, or a real dead end.
6. **Checkpoint every iteration** -- what changed, what the measurement was, whether the
   predicate moved. A run with no trail cannot be audited or resumed. Keep it in the
   session; commit it only when the work is large enough that someone will need it later.
7. **Stop when the predicate is met.** A plateau is not a stop -- pivot the approach and
   keep going. Surface a genuine dead end rather than spinning. **Never relax the predicate
   to declare victory**: moving the bar to reach it is the failure mode this playbook
   exists to prevent.

**Gated items queue, they do not stop the run.** When you hit a customer-production write,
a deploy, or a destructive operation, record what you would do and why, and continue with
everything downstream that does not depend on it. The operator clears the queue in one pass.

**Reply:** the exit condition, iterations run, the baseline and final measurement, what
landed, what was discarded and why, the gated queue, and the final predicate state.
