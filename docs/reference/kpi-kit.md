# The KPI kit

The semantic vocabulary a workspace starts with, the first kit the
engine runs at open, before the quality kit whose screens condition on
`role`, the metrics kit whose reads read the words on a view's
columns, and the futures kit. The kit ships the questions — what a
column means, how a number behaves, its unit, which axes slice, what a
table is, where definitions live, how a correction travels. The
answers — the company's own metrics, validations, scenarios, plans —
stay authored in the flows. The kit is statements, so adapting it is
an edit.

An unwritten witnessed claim is owed: the backlog and the question
round derive from what stands unwritten. `WHEN` narrows what a column
owes to what its role makes meaningful — a role-less column owes only
`role`, and the backlog counts what is real instead of columns ×
vocabulary. A metric's view is a table of its dataset, so its columns
carry these words too: how its value combines over periods and
members is the `behavior` on its value column. Statistics are the
agent's measurement backlog, never a human question; the round asks
judgment only.

## Aspects

| Aspect | Kind · grain | Holds |
| --- | --- | --- |
| `meaning` | FACT ON TABLE, COLUMN, RELATIONSHIP | `value` (prose), optional `term` |
| `role` | FACT ON COLUMN | `key` / `measure` / `dimension` / `timestamp` / `attribute` |
| `behavior` | FACT ON COLUMN WHEN `role = 'measure'` | `stock` / `flow` / `ratio` / `none`, with `grounds`; a ratio names its halves, `numerator` and `denominator`. A flow sums, a stock keeps its last level, a ratio re-divides its summed halves; `none` does not combine |
| `unit` | FACT ON COLUMN WHEN `role = 'measure'` | the unit, optional `source_column` |
| `dimension` | FACT ON COLUMN WHEN `role = 'dimension'` | `primary` / `supporting` / `none`, with `grounds` |
| `entity` | FACT ON TABLE | what the table is: `value`, `role` (fact/dimension), `grain`, `time_axis`, `identity_columns` |
| `conventions` | FACT ON SOURCE | fiscal calendar, sign conventions, what an export's nulls mean — read and superseded workspace-wide |
| `definitions` | FACT ON DATASET | registry keyed by concept name: the handbook content — meaning, unit, owner, source — everything the company might revise, living where supersession applies. The aspect blob keeps only `title` and `x-kind`; a field lives in exactly one place, never both |

The other kits add their words beside these: `ladder` on a time
column, the metrics kit's (the floor a series is served at and the
rung per grain, owed where `role = 'timestamp'`, witness `ladder_w`);
`lever` on a column, the futures kit's (`value` true: a column
someone sets, the input a scenario moves, `grounds` saying who;
witness-free). The record's own words — `recipe_change`, `ruling`,
the app parts, `app_release` — are the engine's, declared at every
open before any kit.

Names machinery reads, shipped by this kit: `recipe_change` (the
brief counts pending approvals by that name), `title` / `x-kind` in
QUERY-aspect blobs and `unit` / `meaning` in `definitions` entries
(the console's metric faces and `metric_surfaces`), and `none` as the
judged negative in enum aspects — "examined, does not apply" is a
different fact from an unassessed row, and the one that lets the
backlog walk to zero.

## Witnesses

| Witness | On | Voices | Detector |
| --- | --- | --- | --- |
| `meaning_w` | `meaning` | AGENT, HUMAN | — |
| `entity_w` | `entity` | AGENT, HUMAN | — |
| `role_w` | `role` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `behavior_w` | `behavior` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `unit_w` | `unit` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `dimension_w` | `dimension` | AGENT, HUMAN | — |

A witness gates who may speak and makes the unwritten claim owed;
detectors adjudicate the written slots — band and score, never a
verdict of their own. The witnesses declare last in the kit: a witness
names an aspect and a detector that must already stand. The futures
kit binds its own: `bands_w`, `forecast_w`, `scenario_w`, `plan_w`
([functions](functions.md)).
