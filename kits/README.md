# The server's kits

A kit is SQL the server loads at each start. It adds properties,
measurements, tests and reads on the glossql language, and no
grammar. The language's `SPEC.md` and `grammar.ebnf` live with the
extension.

The load order is `core`, the extension's `kpi` and `quality`,
`views`, `outlook`, `goals`. A kit the lake already recorded with the
same text runs nothing.

| Kit | Adds | Suite |
|---|---|---|
| `core` | the properties `review_decision`, `recipe_change` and `app`, `app_page`, `app_frame`, `app_spec`, `app_release`; the views `current_dataset`, `agent_assumptions`, `review_decisions`, `open_questions`, `app_parts`, `app_releases`, `view_definitions`, `workspace_status`; `fmt_number()`, `fmt_change()`, `null_markers()` | `core/kit.test` |
| `views` | `time_grains` and `validity`; `view_summary()`, `metric_series()`, `fact_values()`, `view_sources()`, `view_tests()`, `semantic_model()`, `lineage_events()`; the tests `fan_out_test`, `orphan_test`, `measure_additivity_test`, `validity_test` on each metric | `views/kit.test` |
| `outlook` (preview) | `metric_ranges`, `metric_forecast`, `metric_scenario`, `metric_plan` and their tests; `lever`; the reads `range_points()`, `forecast_points()`, `scenario_points()`, `plan_points()` and the forecast, plan and scenario worlds of `metric_series()`. Needs a model service | `outlook/kit.test`; `corpus/` |
| `goals` | `open_items` and `next`, the open work of a dataset by step | `goals/kit.test` |

Each suite is in DuckDB's sqllogictest form and runs with `cargo test
-p glossdb-duck` (`crates/duck/src/sqllogic.rs`). A refusal is
asserted by its code, the word after `----`
(`docs/reference/interfaces.md`). What an agent learns about the
kits is in the skills under `skills/`, served over MCP.

How to write and load a kit: `docs/extending/kits.md`. Each read and
its columns: `docs/reference/reads.md`.
