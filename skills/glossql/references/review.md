# Review: assumptions, review decisions, conflicts

Read before you state your first assumption, and when `next` shows a
`review` row.

## Assumptions

An assumption is a judgment call in a view's definition: which rows
count, which date, how a value is written. It sits in the
definition's `assumptions` list:

```json
{"dimension": "scope", "key": "delivered-only",
 "assumption": "only deliveries with status delivered count",
 "alternative": "returned deliveries count too",
 "basis": "the status values", "confidence": 0.7}
```

- **`key`** is a short name you choose. Questions and decisions match
  on the view and the key; the wording is for the person and is not
  compared. An assumption without a key is not asked. Keep the key
  when you reword; a new key is a new question. One assumption under two
  keys is asked twice.
- **`confidence`** is tied to the evidence. 1.0: a person decided it,
  or a named measurement or test shows it. About 0.9: independent
  evidence agrees. About 0.7: one source, or your reading of names
  and values. 0.5 and below: a default you took to go on. Everything
  below 1.0 with a key is asked, lowest first.
- **`dimension`** names the kind of call: `scope`, `definition`,
  `convention`. An assumption with the dimension `additivity`, `sign`
  or `grain` is not asked: the data settles those. Measure, and
  record it at 1.0 with the measurement as the basis.
- **`alternative`** names the strongest other reading, so the person
  sees the choice.

Do not ask a person for something the data can tell you: run the
function (`skill://glossql-modeling/SKILL.md` has the list). What is
left for a person is judgment: definitions, conventions, business
meaning, a choice between two readings.

## The review queue

```sql
SELECT o.aspect, o.dimension, o.key, o.assumption, o.basis, o.conf
FROM open_questions o JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf
```

`open_questions`, `review_decisions` and `agent_assumptions` cover
the whole workspace; the join narrows them to the dataset of the
call. A person answers in the console. Where the person is in chat
with you, ask the open questions there, with the alternative and your
reason, and tell the person to record the answer in the console.
The work goes on while a question waits; `next` counts it under
`waiting for a person`.

## Applying a decision

A person's answer is a review decision: `confirmed`, `corrected` or
`unclear`, with a note. It is the person's own annotation and
outranks yours. `next` lists it as a `review` row with the view's
current definition as the statement.

- **Confirmed**: record the definition again with that assumption at
  confidence 1.0 and `"basis": "decided-by-person"`.
- **Corrected**: change the SQL and the assumption as the note says,
  then record it the same way.
- **Unclear**: the person could not tell what was asked. Rewrite the
  assumption in plain words under a new key and record the
  definition; the old question goes with the old key.

A decision counts as applied (`folded_in`) when the view's current
definition carries the key at confidence 1.0. Tests on the view run
again after the new definition. A test that turns red after a
decision stays red for the person to see; do not change the
definition to make it green.

Two more rows carry a person's decision, one of kind `review` and
one of kind `integrate`:

- **A person's formula is newer than the definition.** A person wrote
  a `formula` for the view in the business glossary. Change the SQL
  to match and record the definition, or state the difference as an
  assumption.
- **A change to a load query is approved.** A person approved new
  SQL for a table (`recipe_change`). Declare the load query with it.

## A value in conflict

`state = 'conflict'` in `GLOSSARY()` means two authors' values for
one property of one asset differ by more than its test allows, or a
measured rate is above the tolerance. The value is withheld. Read
every value with `SELECT actor, body, current FROM
GLOSSARY(deliveries.status, all => true)` and go back to the data.
Annotate again only if the evidence changed your mind: your new
annotation replaces your old one, and agreeing values end the
conflict. Where the evidence still supports your value, leave the
conflict open; a person ends it with their own annotation.
