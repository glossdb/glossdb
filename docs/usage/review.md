# Review and decide

Some statements about the data are judgment: which bookings count,
which date a delivery is measured at. An agent states them as
assumptions in a view definition. A person confirms or corrects each
one. The decision is stored as the person's annotation and outranks
the agent's.

## The review queue

`open_questions` is the review queue. It is a view over the catalog,
not a stored list. An assumption is in it when:

- it is in a view definition and carries a `key`;
- its `confidence` is below 1;
- its `dimension` is not `additivity`, `sign` or `grain`: those are
  measured, not asked;
- no person has decided that key on that view.

```sql
SELECT o.aspect AS view, o.key, o.assumption, o.basis, o.alternative, o.conf
FROM open_questions o JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf;
```

`open_questions` covers the workspace and carries `dataset` on each
row. The join narrows it to the dataset in use.

The `key` is the assumption's identity. Questions and decisions join
on it; wording is not compared. An assumption without a key is not
asked.

## Decide

**In the console.** The Review section of `/<dataset>/app` lists the
questions. Choose **Correct as stated**, or correct it in your own
words.

**In the agent's client.** While questions are open, a tool call that
only reads the catalog carries one form per question, where the
client supports MCP elicitation. A form offers:

- Correct as stated;
- Rather, this reading: the alternative the agent named;
- Same as before: your decision on the same key for another view;
- The question itself is unclear: it is asked again in other words;
- What is right instead: your own words, which outrank the boxes.

Where the client shows no forms, the agent relays the question in
chat.

**With a statement**, over the query endpoint, which writes as a
person:

```glossql
GLOSS review_decision ON logistics AS $${"decisions": [
  {"aspect": "on_time_rate", "key": "promise-date", "stance": "corrected",
   "note": "measure against the first promised date, not the rescheduled one"}
]}$$;
```

`stance` is `confirmed`, `corrected` or `unclear`. The console and the
form add one decision to the list on that asset. A statement replaces
the whole list, so include the earlier entries.

## Apply the decision

A decision leaves the agent one action: record the view definition
again, with the decided assumption at confidence 1.0, or rewritten as
the correction says. `next` lists it as a `review` row, with the
statement to edit:

```sql
SELECT asset, state, who, open, statement FROM next WHERE step = 'review';
```

| `state` | `who` | Meaning |
|---|---|---|
| `waiting` | person | questions open on this view |
| `decided` | agent | a decision the definition does not carry yet |

`review_decisions` shows each decision and whether it is applied:

```sql
SELECT subject, aspect, key, stance, note, folded_in FROM review_decisions;
```

`folded_in` turns true once no assumption below full confidence
carries the decided key on that view. Nothing is marked done by hand.

## Which value is served

Annotations are appended, not updated. A person's value, an agent's
value and each measurement stay side by side. A read serves one value
per asset and property: the person's, else the agent's, else the
measurement's. Only a signed-in person, on the console or the query
endpoint, writes a person's value.

Two more things a person decides:

- **A test result.** Accept a measured rate as a tolerance with a
  reason ([test](test.md#accept-a-result)).
- **A view's meaning or formula.** Annotate `meaning` on the view;
  write a formula into `definitions`
  ([define views](views.md)). A person's formula newer than the
  view's definition shows in `next` as a `review` row.
