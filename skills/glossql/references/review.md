# Rulings and what they owe you — read when the brief counts a ruling, a question, or a contest

A person's answer is stored as a **review decision** (`ruling` in the
catalog): the judgment alone — confirmed or corrected, naming the
claim by its `key` — in the person's `ruling` annotation on the asset,
never a copy of your body. A decision keeps its question closed; your
metric definition stays yours. Questions derive from *your current
body*, so raising a confidence with a measurement basis closes its
question on its own. A person's decline holds only while the workspace
does not change — your next write re-opens it for the next review. A
client without question forms gets nothing — relay the open questions
in chat yourself, multiple choice with your grounds, and run the
statement the answer names.

The review queue is a read, and you can see it yourself:

```sql
SELECT o.aspect, o.dimension, o.key, o.assumption, o.conf
FROM open_questions o JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf ASC;
```

`open_questions` is the derivation itself, not a summary of it — the
same rows the forms serve and the console renders. Filter it like any
table (`WHERE o.aspect = 'cycle_time'`); order it where you read it,
since a read carries no ordering of its own. The join is what scopes
it to the dataset you bound — drop it and you are reading every
dataset in the workspace. `review_decisions` is what the person has
decided; both build on it.

**One key decided two ways is yours to reconcile.** The review names
the sibling decision on the form when it asks about a key the person
already decided under another aspect; `review_decisions` shows both
afterwards. Nothing pairs or resolves them: decide whether the aspects
genuinely differ, and record the reconciliation in the metric
definitions themselves. Applying both literally is how a decided
component ends up contradicting the metric that composes it — and if
you need the question settled again, ask again.

**Every disclosed assumption carries a `key`** — a short slug you
write at disclosure (`business-days-only`, `completed-only`). The key
is the claim's identity and the only thing the catalog joins on:
review decisions, question closure, and the decisions still to apply
all match `(aspect, key)`. Assumption prose is what the person reads,
never what the system compares — wording is never matched against
wording anywhere in this system. What that costs you:

- **An assumption without a key is never asked.** It cannot be kept
  closed, so the review would re-ask it forever; it is skipped
  instead. The catalog shows it; no person is ever served it.
- **The same claim under two different keys reads as two claims.**
  Nothing detects it. If you disclose one decision on two aspects,
  use one key for it — or better, declare the shared concept as its
  own metric and compose both from it, so the decision lives in one
  place.
- **Dropping a key from your body clears what it owes.** The claim is
  no longer disclosed, so nothing is held below full confidence. Drop
  a key only when you truly no longer rest on the claim.

Then close what waits on an action, in the same session:

- **A review decision not yet applied** (the brief counts these):
  record the decided metric definition again — the decided assumption
  **under the same key**, at confidence 1.0 with `basis:
  "decided-by-person"`, or redefined per the correction note in the
  decision. It clears the moment your current body carries that key
  at full confidence; until then the decision keeps the question
  closed for you both. Keep the key and rewrite the prose as freely as
  the correction requires — the join is on the key alone. Each write
  moves the pin: the series reads the newest claims at its next read,
  `metric_axes().judged_current` says whether the profile is current
  at the data's version, and the walk is stored at the pin it runs at.
  The `review`, `slices` and `bands` goals on the `next:` line carry
  the order — the decisions applied, then the profile once, then the
  walk once. **That closing re-measure is the audit of the batch, not
  hygiene**: a review decision outranks your judgment, never the
  measurements — and the batch moved the pin, so every check function's
  value is stale until it runs again (`open_items` counts them as
  `re-measure` rows). Re-run them, then read the results back on the
  metrics the batch touched: `TESTS()` on their check aspects,
  `metric_axes().alternative_divergence` where an alternative reading
  is disclosed. A test that applying a decision turned red is a
  conflict for the console — leave it open so the person decides again
  with the measurement in front of them, and never redefine to quiet
  it. Applying decisions is not finished until their checks have run.
  Read the decision notes as you apply them: a note naming a sibling
  aspect ("differs from … by design", or a slip decided again) is the
  person's cross-aspect judgment — carry it into the metric
  definition's assumption text. A decision whose stance is
  **`unclear` is a refusal of the question, not of the claim**: the
  person could not tell what you were asking. Applying it means
  rewording — rewrite the assumption plainly (its note says what
  confused them) **under a new key** and record it again; the clearer
  wording derives its own question, and dropping the old key clears
  what it needed.
- **A person's formula answer newer than the metric's stored
  annotation**: the two are one definition in two forms — record the
  materialization again to match (or carry the difference as a
  disclosed assumption). Until you do, the metric's view serves the
  old SQL and the app shows the answer as waiting on you.
- **An approved `recipe_change`** (a person's annotation carrying
  `{table, sql, reason}`): run the `DECLARE RECIPE` it approves — the
  approval is data, the action is yours.
- **A contested value**: redefine and judge again as the conflict
  section below says.
- **A person's values over your own**: read each back and rebuild what
  you still hold on top of the person's decision — their word governs.

## Confidence means the number

Wherever a value carries `confidence` (metric definitions' assumptions
are the main carrier), one scale governs, anchored to the evidence
behind the number:

- **1.0** — decided by a person, or verified by a named measurement or
  check. Nothing else.
- **~0.9** — independent evidence converges: a measurement plus a
  conventions annotation plus the data's own shape. A well-argued
  convention choice tops out here.
- **~0.7** — one source: a single measurement, or your reading of
  names and values.
- **0.5 and below** — a default you adopted to proceed. Exactly what
  the review exists to surface.

Confidence is evidence, never a gate: nothing routes on it
mechanically — the review orders by it (lowest first) and every
assumption below 1.0 stays askable. An inflated number empties the
person's queue falsely; a deflated one wastes their attention.

State ambiguity plainly. The reader is a capable engineer: when a
result is ambiguous, name the readings you saw, which you took, and
why — in the report's front matter, not softened or buried. An
honest "two readings hold, I took A because B breaks the grain
check" is worth more than fluent certainty.

## When a value is contested

`state = 'contested'` means the authors' values differ on one asset's
aspect and the detector's score crossed the test's
threshold — the value is withheld, never decided for you. Read the
raw values (`GLOSSARY(subject, all => true)`), go back to the data,
and annotate again only if the evidence moved you: your new annotation
supersedes your old one, and agreeing values turn the band green. If
the evidence still says you were right, leave it contested — a person
closes it by conceding in their own annotation. (Striking a value with
`DELETE FROM glossary WHERE …` removes it from the catalog for good;
concede in your own annotation instead, which keeps the history.)
Never change an annotation just to end a conflict.
