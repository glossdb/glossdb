# What settles a question — the function to run before anyone is asked

A question the shipped functions can settle is your work. The round
and your chat relays carry judgment only: definitions, conventions,
business meaning, choices between readings. Before any question
leaves the workspace, walk this map and run what answers it:

| the question | what settles it |
|---|---|
| what values a column holds — range, nulls, distincts, top values | `column_profile()` |
| outliers on a numeric column | `outlier_profile()` |
| a date column's grain, span, gaps | `temporal()` — on a table's column and on a metric's period column alike; the cadence is the floor the series is served at |
| **stock or flow — may it be summed** | your reading of the column's meaning and the table's grain, glossed as `behavior` on the column with its `grounds`; the witness bands disagreement, and a series over the column refuses to combine rows until a claim stands |
| **a sign convention** (source-signed vs natural) | the `conventions` gloss on the source, read before the first probe |
| which columns join, and how well | `detect_relationships()`, then your anti-join judging; standing health is `relationship_coherence()` |
| whether a column derives from siblings (a = b × c) | `detect_derivations()` |
| which axes are worth slicing | the served columns that carry `role` dimension; a `dimension` gloss ranks them, `primary` first, `none` closes one |
| hierarchies inside dimensions | `detect_hierarchies()` |
| two metrics accidentally identical | `detect_grounding_collisions()` |
| whether a metric's month is surprising | `metric_bands()`, the service's verdict carried by `bands_w` |
| the app's series and slices | `metric_series(grain := …)`: each metric's cells at its floor or a coarser grain, from its view at read; `metric_axes()` says what the record says of its columns, and what each still owes |
| whether an authored expectation holds | a check function's voice and the detector you bind, read via `ATTEST()` |

A measurement is called in the SELECT list with its subject in FROM,
never as a table function: `SELECT detect_relationships() FROM ops`
for a dataset-grain one, `SELECT column_profile() FROM orders.amount`
for a column, `SELECT detect_hierarchies() FROM orders` for a table.
`SELECT * FROM detect_relationships()` is refused.

What remains askable after the map is walked is what the round
serves: an assumption whose basis is your judgment, held below full
confidence. The round enforces the boundary: it never serves an
assumption whose `dimension` is `behavior`, `sign`, or `grain` —
those are the functions' and the glosses' work, so record them at 1.0
citing the measurement or the gloss. When a measurement abstains, the
abstention names why: close the claim on your strongest remaining
ground — a mirror table, a reference system, the data's own shape —
and cite it; relay it as a judgment question only if it stays
load-bearing, never as a raw "which is it?".

The round is one of two registers. **Prose shapes the work; forms
rule the record.** Anything that decides what the work is — the
dataset's topic, which metrics to build, whether to widen the import
— is conversation: stop, present the facts, propose in prose,
interpret the human's prose. Forms carry only standing assumptions to
confirm or correct; they cannot replace conversation, because there
is nothing standing to confirm yet.
