# The server's kits

A kit is SQL the server loads at each start. It adds properties,
measurements, tests and reads on the glossql language, and no
grammar. The language's `SPEC.md` and `grammar.ebnf` live with the
extension.

The load order is `core`, the extension's `lineage`, `kpi` and `quality`,
`views`, `harmonise`, `goals`. A kit the lake already recorded with the
same text runs nothing. The plan and outlook kits (forecasts, expected
ranges, plans, scenarios) are not shipped; they are at the tag
`before-cut`.
The answer to which step of a view left a row out (`branch_rows()` in the
extension) is not shipped either; it is at the same tag.

| Kit | Adds | Suite |
|---|---|---|
| `core` | the properties `review_decision`, `recipe_change`, `delivery` and `app`, `app_page`, `app_frame`, `app_spec`, `app_release`; the views `current_dataset`, `agent_assumptions`, `review_decisions`, `open_questions`, `app_parts`, `app_releases`, `view_definitions`; `tested_properties()`, `fmt_number()`, `fmt_change()`, `null_markers()` | `core/kit.test` |
| `views` | `time_grains` and `validity`; `view_summary()`, `view_kinds()`, `metric_series()`, `fact_values()`, `column_mapping()`, `view_tests()`, `semantic_model()`, `lineage_events()`; the tests `join_test` and `orphan_test` on each view, `completeness_test` on each column of each view, `measure_additivity_test` on each metric, `grain_test` on each loaded table whose `entity` states a grain (`key_repeats()`, which the harmonise kit's contract key reads too) | `views/kit.test` |
| `harmonise` (preview) | several systems of record mapped onto one target table view: `system_of_record` on a loaded table where one source holds two systems; the function an actor may run, `source_systems`, the source systems a table or a table view is loaded from, each with whether its `conventions` are written down; `contract` on a target's columns (type, required, allowed values; the key is the `entity` grain), and on a view that carries one the tests `contract_test`, `code_test` and `reconciliation_test`, which the server runs after a write: the last holds, per system and period, the rows and the sum of each measure at the source against what the view serves, and lists the keys the view does not serve. Where each target column comes from, per branch and system, is `column_mapping()` of the views kit. The server runs without it | `harmonise/kit.test`: three ERPs with one market each, two filing systems split by time and loaded from one source |
| `goals` | `results_due()`, the results the server computes after a write: the tests on each view and what their checks read; `results_moved_since()`, the results a round of them left out of date, which the server computes in another round; `load_changes()`, what the newest load of each table changed; `load_modes()`, the newest load held against what its source sends (`delivery`, declared by the core kit); `next`, the open work of a dataset, each row with its level (must, should, could) and its kind of work, a kit's rows coming from its tests and stored results alone | `goals/kit.test` |

Each suite is in DuckDB's sqllogictest form and runs with `cargo test
-p glossdb-duck` (`crates/duck/src/sqllogic.rs`). A refusal is
asserted by its code, the word after `----`
(`docs/reference/interfaces.md`). What an agent learns about the
kits is in the skills under `skills/`, served over MCP.

How to write and load a kit: `docs/extending/kits.md`. Each read and
its columns: `docs/reference/reads.md`.
