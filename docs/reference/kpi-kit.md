# The KPI kit

The semantic layer's vocabulary: the properties every workspace starts
with. It ships with the glossql extension and loads at every open,
before the quality kit (whose screens read `role`), the metrics kit
(whose reads read these properties on a view's columns) and the
futures kit. The kit asks the questions — what a column means, how a
number adds up, its unit, which columns slice, what a table is, where
definitions live. The answers — your metrics, tests, scenarios, plans —
are written per dataset. The kit is statements, so changing it is an
edit ([kits](../extending/kits.md)).

A property with a test is required, and a required property nobody
annotated is open work. `WHEN` narrows what a column requires to what
its role makes meaningful: a column without a role requires only
`role`. A metric's view is a table of its dataset, so its columns
carry these properties too: how its value adds up over periods and
members is the `behavior` on its value column. Statistics are the
agent's work and never a question for a person; the review queue asks
for judgment only.

## Properties

| Property | Kind · applies to | Holds |
| --- | --- | --- |
| `meaning` | FACT ON TABLE, COLUMN, RELATIONSHIP | `value` (prose), optional `term` |
| `role` | FACT ON COLUMN | `key` / `measure` / `dimension` / `timestamp` / `attribute` |
| `behavior` | FACT ON COLUMN WHEN `role = 'measure'` | `stock` / `flow` / `ratio` / `none`, with `grounds`; a ratio names its halves, `numerator` and `denominator`. A flow sums, a stock keeps its last level, a ratio divides its summed halves; `none` does not combine |
| `unit` | FACT ON COLUMN WHEN `role = 'measure'` | the unit, optional `source_column` |
| `dimension` | FACT ON COLUMN WHEN `role = 'dimension'` | `primary` / `supporting` / `none`, with `grounds` |
| `entity` | FACT ON TABLE | what the table is: `value`, `role` (fact/dimension), `grain`, `time_axis`, `identity_columns` |
| `conventions` | FACT ON SOURCE | fiscal calendar, sign conventions, what an export's nulls mean; shared by every dataset |
| `definitions` | FACT ON DATASET | the business glossary, keyed by metric name: meaning, unit, owner, source, formula. The metric's own aspect keeps only `title` and `x-kind`; a field lives in exactly one place |

The other kits add theirs beside these: `ladder` on a time column, the
metrics kit's (the finest grain a series is served at and how many
periods per grain, required where `role = 'timestamp'`, test
`ladder_w`); `lever` on a column, the futures kit's (`value` true: a
column someone sets, the input a scenario moves, with `grounds`; no
test). The core kit declares `recipe_change`, `ruling` and the app
properties before any other kit.

Names the server reads, shipped by this kit: `title` and `x-kind` on
VIEW aspects and `unit` and `meaning` in `definitions` entries (the
console's metric pages and `metric_surfaces`), and `none` as the
examined negative in the enum properties. "Examined, does not apply" is
a different fact from an unassessed row, and the one that lets the
open work reach zero.

## Tests

| Test | On | Who may annotate | Detector |
| --- | --- | --- | --- |
| `meaning_w` | `meaning` | AGENT, HUMAN | — |
| `entity_w` | `entity` | AGENT, HUMAN | — |
| `role_w` | `role` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `behavior_w` | `behavior` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `unit_w` | `unit` | AGENT, HUMAN | `slot_entropy`, threshold 0.7 |
| `dimension_w` | `dimension` | AGENT, HUMAN | — |

A test (`DECLARE TEST`) says who may annotate a property and
makes it required; its detector scores the values written, a band and
a score. The tests come last in the kit, since a test names a property
and a detector that must already exist. The futures kit adds its own:
`bands_w`, `forecast_w`, `scenario_w`, `plan_w` ([functions](functions.md)).
