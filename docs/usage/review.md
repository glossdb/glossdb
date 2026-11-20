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
SELECT o.property AS view, o.key, o.assumption, o.basis, o.alternative, o.conf
FROM main.open_questions o JOIN main.current_dataset d ON d.dataset = o.dataset
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

**In the agent's chat.** The agent relays the question, with the
alternative it named and its reason. The person records the answer in
the console. What arrives over MCP is stored as the agent's, so an
agent cannot record a person's decision; the console stores it as the
signed-in person's.

**With a statement**, over the query endpoint, which writes as a
person:

```glossql
GLOSS review_decision ON logistics AS $${"decisions": [
  {"property": "on_time_rate", "key": "promise-date", "stance": "corrected",
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
SELECT level, asset, state, who, open, statement FROM main.next WHERE kind = 'review';
```

| `level` | `state` | `who` | Meaning |
|---|---|---|---|
| `should` | `waiting` | person | questions open on this view |
| `must` | `decided` | agent | a decision the definition does not carry yet |

`review_decisions` shows each decision and whether it is applied:

```sql
SELECT subject, property, key, stance, note, folded_in FROM main.review_decisions;
```

`folded_in` turns true once no assumption below full confidence
carries the decided key on that view. Nothing is marked done by hand.

## Which value is served

Annotations are appended, not updated. A person's value, an agent's
value and each function's result stay side by side. A read serves one
value per asset and property: the person's, else the agent's, else the
function's. Only a signed-in person, on the console or the query
endpoint, writes a person's value.

What else a person decides:

- **A view.** A person's view definition, written over the query
  endpoint, outranks the agent's under the same name: a person's
  `sql` serves over an agent's `stopped`, and a person's `stopped`
  stops an agent's `sql`. A person approves a view as it is by
  recording the agent's definition as their own.
- **A view's meaning.** Annotate `meaning` on the view
  ([define views](views.md)).
- **A test result.** Accept a measured rate as a tolerance with a
  reason ([test](test.md#accept-a-result)).
- **A rule's count.** Only a person accepts the rows a rule view
  returns, with `accepted` and the reason on `rule_check`
  ([test](test.md)).
