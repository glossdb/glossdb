# The server's kits

The language is the extension's: `SPEC.md`, `grammar.ebnf` and the
corpus live in its repository, and the MCP interface serves the two documents
as `doc://SPEC.md` and `doc://grammar.ebnf`. The kits here add
vocabulary and reads on that language, never grammar; a form they
would need goes through the extension's corpus first. Each kit is SQL
loaded at open, in order: core, the extension's kpi and quality
kits, views, outlook, goals. A kit whose text the lake recorded
is current at open and runs nothing. Each has a `kit.test` suite beside
it, run by the engine crate's suite on its own runner
(`crates/duck/src/sqllogic.rs`); views and outlook carry a
`SKILL.md` that teaches them.

| Kit | Adds | Tested by |
|---|---|---|
| `core` | the workspace's own vocabulary, the review decisions, a recipe's approval and the apps as glosses, and the catalog's own reads: `open_questions`, `review_decisions`, `current_dataset` | `core/kit.test` |
| `views` | the actual world: every applicable metric's cells at its floor or a coarser grain, read as `metric_series()` and described by `view_summary()`; the time_grains over the view's time column; three tests on every metric over the tables it scans (join fan-out, referential integrity, additivity), `view_tests()`, every test per metric, worst first, and one goal per metric in `next`, its test report | `views/kit.test`; fixtures 26 and 28 of the extension's corpus |
| `outlook` | the forecast, scenario and plan worlds on the same read, answered by the model service: the walk's ranges, the forecast, the scenario's estimate, the plan's judgement | `outlook/kit.test`; `corpus/` here, fixtures 19 and 27 |
| `goals` | what waits for an action in the bound dataset, `open_items`, and the review goal of `next` | `goals/kit.test` |

## The worlds on the series read

A scenario is a world on the series read (fixture 19): a FACT aspect
per scenario, `x-kind: scenario`, carrying a factor per period on
declared levers — a lever a FACT aspect on a column of a metric's
view — read as `metric_series(world := 'scenario', scenario :=
'<name>')` beside the actual and the forecast worlds; the estimate
ahead is machinery, never statement syntax. A plan is a world on the same read
(fixture 27): one VIEW aspect per plan, `x-kind: plan`, tied to its
metric by `x-plan-of` in the declaration, its body the definition
— a plan's numbers are a loaded table, read by SQL
as the actual's are — read as `metric_series(world := 'plan', plan :=
'<name>')` under the metric it names, at the plan's own grain; an
edition of a plan is an aspect of its own, and a plan aspect serves
no cell of the actual world. `metric_series()` serves the cells —
every applicable metric at its floor or a coarser grain, computed at
read from the metric's view and the claims on its columns, never
recorded, except the forecast, scenario and plan worlds, which read
the catalog's measurements and the plan's view — as long rows: metric names become data so a static frame (the built-in
console app) slices any metric with plain value filters; `view_summary()`
beside it says what the catalog says of each metric's columns.
