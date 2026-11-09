# Review decisions and open questions — read when the status line counts a decision, a question or a conflict

Every assumption in your metric definitions with a confidence below 1
is a question for a person. Their answer is stored as a review
decision: confirmed or corrected, naming the assumption by its `key`.
It is the person's own annotation on the asset; your definition stays
yours.

- Questions come from your current definition. Raising a confidence
  with a measurement as its basis closes the question.
- A person's decline holds until the workspace changes. Your next
  write opens the question again.
- A client without question forms shows nothing. Ask the open
  questions in chat yourself, as multiple choice with your reasons,
  and run the statement the answer names.

The review queue is a view:

```sql
SELECT o.aspect, o.dimension, o.key, o.assumption, o.conf
FROM open_questions o JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf ASC;
```

These are the rows the forms and the console show. The join limits
them to the bound dataset; without it you read every dataset in the
workspace. `review_decisions` lists what the person has decided.

## Keys

Every assumption carries a `key`: a short slug you choose
(`business-days-only`, `completed-only`). Decisions and questions
match on `(aspect, key)` only. The wording is for the person and is
never compared.

- **An assumption without a key is never asked.**
- **One claim under two keys is two questions.** Nothing detects it.
  Use one key for one decision. Better: declare the shared concept as
  its own metric and build both metrics on it.
- **Dropping a key drops its question.** Do it only when the
  definition no longer rests on the claim.
- **One key decided two ways on two metrics is yours to reconcile.**
  The form shows the earlier decision when it asks; `review_decisions`
  shows both. Decide whether the metrics really differ and record that
  in their definitions. If you need it settled, ask again.

## Apply what was decided, in the same session

**A decision not yet applied** (the status line counts these). Record
the metric definition again with the decided assumption under the same
key, at confidence 1.0 with `basis: "decided-by-person"`, or changed
as the decision's note says. It counts as applied once your current
definition carries that key at 1.0. Keep the key; reword freely.

- A decision with the stance `unclear` means the person could not tell
  what you asked. Rewrite the assumption plainly under a new key (the
  note says what confused them) and record it again. The old key's
  question goes away with the key.
- A note that names another metric ("differs from … by design") is the
  person's judgment across both. Carry it into the assumption text.

**Then measure again.** Every definition you wrote changes what the
measurements were computed on, so their results are out of date;
`open_items` counts them as `re-measure` rows. The `next:` line gives
the order: apply the decisions, run `temporal()` once, run the
expected-ranges step once.

- Read the results on the metrics you touched: `TESTS()` on their
  checks, and `metric_summary().alternative_divergence` where an
  assumption names an alternative.
- A test that turned red after a decision is a conflict for the
  console. Leave it open so the person decides again with the
  measurement in front of them. Never change the definition to quiet
  it. A decision outranks your judgment, not the measurements.

**A person's formula answer newer than the metric's definition.**
Record the SQL again to match it, or carry the difference as an
assumption. Until then the view serves the old SQL and the console
shows the answer as waiting on you.

**An approved `recipe_change`** (a person's annotation with `{table,
sql, reason}`). Run the `DECLARE RECIPE` it approves.

**A person's value over yours.** Read it and rebuild what you hold on
top of it. Theirs governs.

## Confidence

One scale, tied to the evidence:

- **1.0**: decided by a person, or verified by a named measurement or
  test. Nothing else.
- **About 0.9**: independent evidence agrees: a measurement, a
  conventions annotation and the data's shape. A well-argued
  convention stops here.
- **About 0.7**: one source: a single measurement, or your reading of
  names and values.
- **0.5 and below**: a default you took in order to proceed.

Nothing branches on confidence. The review orders by it, lowest
first, and everything below 1.0 can be asked. Too high hides a
question from the person; too low wastes their time.

When a result is ambiguous, say so at the top of your summary: the
readings you saw, the one you took, and why. "Two readings hold; I
took A because B breaks the grain check."

## A value in conflict

`state = 'conflict'` means two authors' values differ on one aspect of
one asset by more than the test allows. The value is withheld.

1. Read both values: `GLOSSARY(subject, all => true)`.
2. Go back to the data.
3. Annotate again only if the evidence changed your mind. Your new
   annotation replaces your old one, and agreeing values end the
   conflict.

If the evidence still supports you, leave the conflict. A person ends
it in their own annotation. Never change an annotation only to end a
conflict. `DELETE FROM glossary WHERE …` removes a value for good;
a new annotation keeps the history.
