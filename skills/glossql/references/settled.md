# What settles a question — the function to run before anyone is asked

A question the shipped functions can settle is your work. The review
and your chat relays carry judgment only: definitions, conventions,
business meaning, choices between readings. Before any question
leaves the workspace, walk this map and run what answers it:

| the question | what settles it |
|---|---|
| what values a column holds — range, nulls, distincts, top values | `column_profile()` |
| outliers on a numeric column | `outlier_profile()` |
| a date column's grain, span, gaps | `temporal()` — on a table's column and on a metric's period column alike; the cadence is the floor the series is served at |
| **stock or flow — may it be summed** | `behavior_evidence()` over the declared edges: the level reconciled against a related event table's movements per entity and period, with the anchor that decided; then your reading of the column's meaning and the table's grain, annotated as `behavior` on the column citing the anchor in `grounds`; the test bands disagreement, and a series over the column refuses to combine rows until a claim is in force |
| **a sign convention** (source-signed vs natural) | the `conventions` annotation on the source, read before the first probe |
| which columns join, and how well | `detect_relationships()`, then your anti-join judging; ongoing health is `relationship_coherence()` |
| whether a column derives from siblings (a = b × c) | `detect_derivations()` |
| which axes are worth slicing | the served columns that carry `role` dimension; a `dimension` annotation ranks them, `primary` first, `none` closes one |
| hierarchies inside dimensions | `detect_hierarchies()` |
| two metrics accidentally identical | `detect_grounding_collisions()` |
| whether a metric's month is surprising | `metric_bands()`, the service's verdict carried by `bands_w` |
| the app's series and slices | `metric_series(grain := …)`: each metric's cells at its floor or a coarser grain, from its view at read; `metric_axes()` says what the catalog says of its columns, and what each still needs |
| whether a written expectation holds | a check function's value and the detector you bind, read via `ATTEST()` |

A measurement is called in the SELECT list with its subject in FROM,
never as a table function: `SELECT detect_relationships() FROM ops`
for a dataset-grain one, `SELECT column_profile() FROM orders.amount`
for a column, `SELECT detect_hierarchies() FROM orders` for a table.
`SELECT * FROM detect_relationships()` is refused.

What remains askable after the map is walked is what the review
serves: an assumption whose basis is your judgment, held below full
confidence. The review enforces the boundary: it never serves an
assumption whose `dimension` is `behavior`, `sign`, or `grain` —
those are the functions' and the annotations' work, so record them at
1.0 citing the measurement or the annotation. When a measurement abstains, the
abstention names why: close the claim on your strongest remaining
ground — a mirror table, a reference system, the data's own shape —
and cite it; relay it as a judgment question only if it stays
load-bearing, never as a raw "which is it?".

The review is one of two registers. **Prose shapes the work; forms
settle the catalog.** Anything that decides what the work is — the
dataset's topic, which metrics to build, whether to widen the import
— is conversation: stop, present the facts, propose in prose,
interpret the human's prose. Forms carry only assumptions in force to
confirm or correct; they cannot replace conversation, because there
is nothing in force to confirm yet.
