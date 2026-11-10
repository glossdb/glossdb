# The review queue

The review queue holds the questions only a person can answer: the
assumptions in metric definitions that the agent holds below full
confidence. A person answers in the console or in the agent's client,
and the answer is stored as that person's annotation.

## What becomes a question

An assumption in a metric definition becomes a question when:

- the agent's confidence is below 1;
- it carries a `key` ([keys](#keys));
- its dimension is not one a measurement settles, such as
  stock-or-flow, sign conventions or grain: those are the agent's work;
- no person has already decided that key.

A required property nobody annotated is not a question either: it is
the agent's backlog, and the shipped measurements settle it. The queue
holds judgment only: definitions, conventions, business meaning, a
choice between readings.

The queue is not stored. It is a view, `open_questions`, computed from
the catalog, least confident first. A question disappears once it is
answered or the agent raises its confidence.

```sql
SELECT o.aspect, o.dimension, o.key, o.assumption, o.conf
FROM open_questions o JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf ASC;
```

`open_questions` covers the whole workspace and carries `dataset` on
every row; a table name is unique only within a dataset, so the same
claim in two datasets is two questions. Join `current_dataset`, as
above, for the dataset in use.

## Answer a question

**In the agent's client.** Over MCP, a call that only reads the catalog
carries one form per open question. Each form offers:

- **Correct as stated**;
- **Wrong**, with your correction in your own words;
- **Unclear**: the question is reworded and asked again;
- where you already decided the same key for another metric, that
  decision, offered back so agreeing takes one click.

**In the console.** The Review tab shows the same rows, with the same
choices ([the console](console.md)).

The answer is stored as the decision alone, as the person's own annotation.
`Unclear` defers; it is not a decision. A person's value outranks the
agent's at every read, so the answer takes effect at once.

A person can also answer by annotating directly:

```glossql
GLOSS definitions ON fin AS $${"definitions": {
  "revenue": {"meaning": "Product and Service revenue families only"},
  "gross_profit": {"meaning": "revenue minus COGS"}
}}$$;
```

## Apply a decision

A decision leaves the agent one action: record the metric definition
again, with the decided assumption under the same key at full
confidence and citing the decision, or rewritten as the correction
says. Until then the decision keeps the question closed for both
sides. `review_decisions` shows each decision and whether it has been
applied; the `review` goal on the `next:` line points to the ones
that wait.

## Keys

Every assumption carries a `key`: a short name the agent writes when
it records the assumption. The key is the claim's identity, and the
only thing questions and decisions join on. Wording is never compared.
So:

- an assumption without a key is never asked;
- the same claim under two keys reads as two claims;
- a key dropped from the definition drops its question.

## What else waits

What waits on an action rather than an answer is a different view,
`open_items`: an approved load-query change not yet loaded, a formula answer
newer than the stored result, a conflicting value, a measurement stale or
never run, a decision not yet applied. `open_items` covers the dataset in
use ([views and table functions](../reference/reads.md)).

The forms confirm or correct existing claims. Anything that decides
what the work is happens in conversation first.
