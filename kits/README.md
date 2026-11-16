# The server's kits

A kit is SQL the server loads at each start. It adds properties,
measurements, tests and reads on the glossql language, and no
grammar. The language's `SPEC.md` and `grammar.ebnf` live with the
extension.

The load order is `core`, the extension's `lineage`, `kpi` and `quality`,
`views`, `plan`, `harmonise`, `outlook`, `goals`. A kit the lake already recorded with the
same text runs nothing.

| Kit | Adds | Suite |
|---|---|---|
| `core` | the properties `review_decision`, `recipe_change`, `delivery` and `app`, `app_page`, `app_frame`, `app_spec`, `app_release`; the views `current_dataset`, `agent_assumptions`, `review_decisions`, `open_questions`, `app_parts`, `app_releases`, `view_definitions`, `workspace_status`; `tested_properties()`, `fmt_number()`, `fmt_change()`, `null_markers()` | `core/kit.test` |
| `views` | `time_grains` and `validity`; `view_summary()`, `metric_series()`, `fact_values()`, `column_mapping()`, `view_tests()`, `semantic_model()`, `lineage_events()`; the tests `join_test` and `orphan_test` on each view, `measure_additivity_test` on each metric; the reads the plan and outlook kits replace (`world_series()`, `range_points()`, `plan_points()` and the worlds of `metric_series()`), empty until they are loaded | `views/kit.test` |
| `plan` (preview) | the function an actor may run, `metric_plan`, and its test `plan_test`; the reads `plan_points()` and `plan_series()`, and the plan world of `metric_series()`. Needs no model service; holds a plan's open periods against the forecast stored on its metric where there is one. The server runs without it | `plan/kit.test`; `corpus/27-plan-budget.md` |
| `harmonise` (preview) | several systems of record mapped onto one target table view: `system_of_record` on a loaded table where one source holds two systems; the function an actor may run, `source_systems`, the source systems a table or a table view is loaded from, each with whether its `conventions` are written down; `contract` on a target's columns (type, required, allowed values; the key is the `entity` grain), and on a view that carries one the tests `contract_test` and `code_test`, which the server runs after a write, and there too the result `reconciliation`, per system and period the rows each branch of a target view reads, leaves out and why, and serves (read through the extension's `branch_rows()`). Where each target column comes from, per branch and system, is `column_mapping()` of the views kit. The server runs without it | `harmonise/kit.test`: three ERPs with one market each, two filing systems split by time and loaded from one source |
| `outlook` (preview) | the functions an actor may run, `metric_ranges` on a dataset, `metric_forecast` and `metric_scenario` on a metric, and the test `range_test`, which a person accepts with a tolerance; `lever`; the reads `range_points()`, `forecast_points()`, `scenarios()`, `scenario_points()`, `scenario_levers()`, `forecast_series()` and the forecast and scenario worlds of `metric_series()`. It builds each request from the lake, stores the model service's answer and serves its verdicts as they are. Needs a model service. The server runs without it | `outlook/kit.test`; `corpus/19-whatif-scenario.md` |
| `goals` | `results_due()`, the results the server computes after a write: the tests on each view and what their checks read; `load_changes()`, what the newest load of each table changed; `load_modes()`, the newest load held against what its source sends (`delivery`, declared by the core kit); `next`, the open work of a dataset, each row with its level (must, should, could) and its kind of work, a kit's rows coming from its tests and stored results alone | `goals/kit.test` |

Each suite is in DuckDB's sqllogictest form and runs with `cargo test
-p glossdb-duck` (`crates/duck/src/sqllogic.rs`). A refusal is
asserted by its code, the word after `----`
(`docs/reference/interfaces.md`). What an agent learns about the
kits is in the skills under `skills/`, served over MCP.

How to write and load a kit: `docs/extending/kits.md`. Each read and
its columns: `docs/reference/reads.md`.
