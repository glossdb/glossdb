# Reads

Each read is SQL over the catalog and the lake. The same reads answer
the MCP interface, the query endpoint and the console.

- A table function's named arguments use `:=`.
- The catalog tables and the views marked *workspace* carry `dataset`
  on each row; join `current_dataset` to narrow them. The others
  answer for the dataset in use and are refused on a call bound to
  none.
- `DESCRIBE SELECT * FROM <read>` returns a read's columns with types.

## The catalog tables

The views serve the current rows. Each row carries `begin_snapshot`,
the lake snapshot its write took. `<name>_history` serves every row a
write replaced or removed, with its `end_snapshot`.

| Table | Columns |
|---|---|
| `datasets` | `name`, `settings`, `declared_at`, `declared_by` |
| `sources` | `name`, `settings`, `declared_at`, `declared_by` |
| `recipes` | `dataset`, `table_name`, `source`, `settings`, `sql`, `declared_at`, `declared_by` (the load queries) |
| `imports` | `dataset`, `table_name`, `mode`, `rows`, `dropped_rows_count`, `lineage`, `snapshot_id`, `imported_at` (the loads) |
| `relationships` | `dataset`, `left_side`, `op`, `right_side`, `declared_at`, `declared_by` |
| `aspects` | `name`, `kind`, `grains`, `condition`, `schema`, `declared_at`, `declared_by` (the properties and view names) |
| `glossary` | `dataset`, `subject`, `aspect`, `actor_kind`, `actor_id`, `body`, `written_at` (the annotations) |
| `functions` | `name`, `scope`, `script`, `returns`, `declared_at`, `declared_by` |
| `measurements` | `dataset`, `function`, `subject`, `aspect`, `value`, `computed_at` |
| `inputs` | `begin_snapshot`, `input`, `version` (what each stored result read, at the version read; joins `measurements` on `begin_snapshot`) |
| `tests` | `name`, `aspect`, `actors`, `detector`, `threshold`, `declared_at`, `declared_by` |
| `kits` | `name`, `location`, `statements`, `loaded_at`, `hash` |

`SHOW TABLES` lists the dataset's tables and views beside these.

## The language's reads

| Read | Returns |
|---|---|
| `GLOSSARY(<asset>)` | one row per asset and property: `subject`, `aspect`, `value`, `test_state`, `score`, `state` (`current`, `stale`, `missing`, `conflict`) |
| `GLOSSARY(<asset>, all => true)` | each value side by side: `subject`, `aspect`, `kind`, `test`, `actor`, `body`, `written_at`, `current` |
| `TESTS(<asset>)` | `subject`, `aspect`, `test`, `state`, `score`, `computed_at`, `current`, `error` |

With no argument both cover the dataset in use. `<asset>::<property>`
narrows either to one property.

## Views of the catalog

| View | Scope | Columns |
|---|---|---|
| `current_dataset` | | `dataset`; no row on a call bound to none |
| `workspace_status` | workspace | `area`, `how` (the statement that extends it), `existing`, `open`, `waiting` |
| `open_questions` | workspace | `dataset`, `subject`, `aspect`, `idx`, `dimension`, `key`, `assumption`, `basis`, `alternative`, `conf`, `sibling`, `sibling_stance`, `sibling_note` |
| `agent_assumptions` | workspace | `dataset`, `subject`, `aspect`, `idx`, `dimension`, `key`, `assumption`, `basis`, `alternative`, `conf`, `body` |
| `review_decisions` | workspace | `dataset`, `subject`, `idx`, `aspect`, `key`, `stance`, `dimension`, `assumption`, `note`, `written_at`, `folded_in` |
| `view_definitions` | dataset | `name`, `title`, `kind`, `unit`, `meaning`, `formula`, `defined`, `stopped` |
| `next` | dataset | see below |
| `app_parts` | workspace | `dataset`, `app`, `path`, `text`, `actor_kind` |
| `app_releases` | workspace | `dataset`, `app`, `at`, `note`, `actor_kind`, `released_at` |

- `open_questions` is the review queue: a keyed assumption below full
  confidence in a view definition, with no decision on its key.
  `sibling` is a decision on the same key under another view.
- `review_decisions`: `stance` is `confirmed`, `corrected` or
  `unclear`; `folded_in` is true once the definition carries the
  decision.
- `view_definitions`: one row per view defined here, served or
  stopped. `kind` is the declaration's `x-kind`: `relation`, `scalar`,
  `plan`, or `measure` for a metric. `meaning` is the `meaning`
  annotation on the view, `unit` the `unit` of a metric's or a single
  value's value column. `formula` is the view's formula in the
  dataset's `definitions` annotation, NULL where there is none.
- `workspace_status`: `area` is `sources`, `tables`, `relationships`,
  `properties`, `annotations`, `functions`, `views`, `tests`,
  `scenarios`, `plans`, `review` or `apps`. For `tests`, `open`
  counts a test of your own on each asset that carries its
  expectation and has no result yet, and a descriptive property with
  a test (`meaning`, `role`, `entity`) on each asset a metric reads
  that has no value. `tested_properties()` lists the properties of
  the first kind by `name`.

### next

The open work of the dataset in use, one row per asset, state and
level, ordered by `level`, then `ord`. A test has one row per asset it
is not green on, and each assumption that waits for a person has a
row. A test of your own is listed on the assets that carry its
expectation.

| Column | Holds |
|---|---|
| `level` | `must`: served data is wrong or cannot be served. `should`: the layer is incomplete for what is served. `could`: what sits beside it |
| `ord` | the order inside one level, what blocks other work first: a source, a table or a view (1), a person's decision to apply (2), a test (3), an annotation (4), a stored result to compute again (5), a question for a person (6) |
| `kind` | the kind of work: `integrate` (a source to connect, a table to load, a view to define), `describe`, `test`, `review` (a question for a person, or a person's decision to apply) |
| `asset` | the dataset, table, column, relationship or view |
| `state` | `missing`, `stale`, `conflict`, a test's state, `decided`, `waiting`, `blocked`; for a load, `keys missing` or `unchanged` (`load_modes()`) |
| `who` | `agent` or `person` |
| `open` | the finding |
| `for_view` | the views that read the asset |
| `cause` | what the newest load changed: row counts, and the columns whose profile moved |
| `statement` | the statement that opens the work; `<…>` marks what the author fills |

What each level holds:

- `must`: no table is loaded; no view is defined; a metric serves no
  series; a test is red; two values of one property conflict; a
  person approved a load query, decided a review question or wrote a
  formula, and the definition does not carry it yet; a keyed load
  missed keys of a table whose source is stated to send its complete
  state.
- `should`: a load does not fit what the source likely sends
  (`load_modes()`); an annotation is missing or outdated on an asset a view
  reads or serves; a test on it is not run, yellow, orange or failed;
  an assumption waits for a person; a stored result about the dataset
  or about a plan is out of date, and the server does not compute it
  (`results_due()` does not list it).
- `could`: an annotation is missing or outdated on a table, a column,
  a relationship or the dataset that no view reads.

Work on a dataset is complete when no `must` row is open. The `should`
rows make the layer complete. The `could` rows are read on request:

```sql
SELECT level, kind, asset, state, who, open FROM next WHERE level <> 'could';
SELECT kind, asset, state, open, statement FROM next WHERE level = 'could';
```

A kit adds rows through its tests and its stored results alone: a red
test is a `must` with the test's own `finding` and `fix`, a stored
result out of date is a `should` with the statement that computes it
again. A column property whose schema says `"x-asked": "per table"` is
asked on each column of a table or view once one of its columns
carries it.

### load_modes()

The newest load of each table of the dataset in use, held against the
load before it and against the `delivery` annotation on the table
(`full`: the source sends its complete state; `incremental`: only new
and changed rows). A table needs two stored loads.

| Column | Holds |
|---|---|
| `table_name`, `mode`, `delivery` | the table; `replace` or `merge`; what the source sends, NULL where nobody stated it |
| `rows`, `rows_before`, `source_rows`, `changed_rows`, `identical` | the table's rows after this load and the one before; the rows the load query returned; the rows a merge wrote; whether a replace of 100,000 rows or more holds the same rows as the load before |
| `keys_carried`, `keys_missed` | for a merge: the keys the table held that the file carried, and the keys the table holds that the file did not carry |
| `key` | the key a load without one could merge by: the load query's, the table's `entity` grain, else a column whose stored profile is filled and unique |
| `state`, `level` | `keys missing`: a merge whose file carried at least 90% of the keys the table held and missed some; `must` where `delivery` is `full`, else `should`. `unchanged`: a replace that is `identical`, where `delivery` is not `full`; `should`. NULL otherwise |
| `open`, `statement` | the finding and the statement that fixes it, as `next` lists them |

```sql
SELECT table_name, mode, rows, source_rows, identical, state, level FROM load_modes();
```

## The views kit

### view_summary()

One row per view of the dataset in use.

| Column | Holds |
|---|---|
| `view`, `kind` | the name; `relation`, `scalar`, `plan`, or NULL for a metric |
| `plan_of`, `covers` | a plan's metric, and the grain its rows are booked against |
| `stopped` | the stop reason |
| `applicable`, `reason` | whether a metric's series is served; else what to change. A table and a single value have no series: `applicable` is NULL, and `reason` is filled only where the view is stopped or its definition serves no view |
| `period_column`, `value_column`, `numerator`, `denominator` | the columns the series reads; `period_column` is NULL for a table and a single value |
| `grain_detected`, `floor`, `window_periods` | the grain `temporal()` measured on the period column; the finest grain served; how many periods a read serves at that grain. NULL for a table and a single value |
| `additivity`, `additivity_state` | the value column's additivity; `none` where nobody stated it, `conflict` where it is withheld |
| `dims`, `dimensions_without_rank` | the slicing columns, primary first; dimension columns without a `dimension` annotation |
| `columns_without_role`, `missing` | served columns without a `role`; the annotation each needs. Both are empty for a single value |
| `measurements_to_run` | measurements the row reads that nobody ran |
| `profile_current` | the period column's temporal profile is current |

```sql
SELECT view, kind, applicable, reason, floor, additivity, dims FROM view_summary();
```

### metric_series()

```
metric_series(grain := NULL, world := 'actual', plan := NULL, scenario := NULL, unclaimed := 'refuse')
```

The cells of each served metric: `metric`, `world`, `dimension` (`''`
for the total), `member`, `period`, `value`, `num`, `den`,
`additivity`.

- `grain`: `minute`, `hour`, `day`, `week`, `month`, `quarter`,
  `year`. NULL serves each metric at its floor. A metric coarser than
  the grain asked serves no rows.
- `world`: `actual`; `forecast`, `plan` (with `plan`) and `scenario`
  (with `scenario`) are preview.
- `unclaimed := 'skip'` leaves out a metric whose additivity is not
  stated, where the default refuses and names the annotation.
- A metric marked `non-additive` is served where it has one row per
  period.

### The other reads

| Read | Columns |
|---|---|
| `fact_values()` | `view`, `value`, `reason`: each single value |
| `column_mapping(for_view := NULL)` | `view`, `target_column`, `branch`, `system`, `source_table`, `source_column`, `alias`, `condition`, `expression`, `literals`, `complete`: where each column of a view comes from, read off its SQL. One row per target column, per branch of the union the view's rows come from (1 where it has none) and per source column. `system` is the source table's `system_of_record` where the table states one, else the source it is loaded from. `alias` names each read of a table the view reads more than once, as the expression does (`supply.hierarchy[dk].brand`). `condition` is what the view's joins and filters require of that read alone (`=(supply.hierarchy[dk].market, 'DK')`). `literals` are the codes the expression tests or returns, as written. A column computed from no source column has one row with no source. `complete` is false where the lineage could not follow a step or reads two reads of one table alike; a view that does not plan has one row with no target column |
| `view_tests()` | `view`, `test`, `aspect`, `declared_by`, `subject`, `state`, `current`, `score`, `evidence`, `run`: each test on each view and on what it reads, and on a result about the dataset or a plan, worst first |
| `semantic_model()` | `document`: the dataset as one Apache Ossie document (spec 0.3.0.dev0) |
| `lineage_events()` | `event`: OpenLineage run events (spec 2-0-2), one per load and one per view |
| `pages()` | `uri`, `title`, `body`: each page the MCP interface serves |
| `null_markers()` | a list: the strings a CSV export writes for no value |
| `fmt_number(x)`, `fmt_change(p)` | a number and a change in percent as the console prints them |

`view_tests()`: `declared_by` is `kit:<name>` for a shipped test.
`current` is false once what the result read has changed; the state
is kept until the test runs again. `run` is the function that returns
the test's property, over the subject; it is empty where no function
measures the property, as for a test that compares annotations
(`role_test`). A test on a result about the dataset as a whole, or
about a plan, is a row too: `view` is empty for the dataset and the
plan's name for a plan, `evidence` is the stored result with its
`finding` and `fix`, and `run` is empty, since an actor computes that
result and the server does not.

## The harmonise kit (preview)

Several systems of record mapped onto one target table view. Where
each target column comes from, per branch of the view's union and per
system, is `column_mapping()` above: the system is the source the
source table is loaded from, so the view names no system. Where one
source holds two systems, state the system on each loaded table:

```glossql
GLOSS system_of_record ON ferc.steam_xbrl AS $${"value": "ferc_xbrl", "basis": "the XBRL filings, report years from 2021"}$$;
```

`source_systems()` over a table or a table view lists the sources it
is loaded from, each with whether its `conventions` are written down,
and `without_conventions`, how many are not. An actor runs it; the
server does not.

**The contract on a target view.** A data contract is stated where the
target is defined:

| Part | Where |
|---|---|
| the key, one column or several | `grain` of the view's `entity` |
| the meaning | `meaning` on the view and on each column |
| the type (as DuckDB names it), whether a value is required, the allowed values | `contract` on each column: `{"type": "BIGINT", "required": true, "values": ["CH10", "DK01"]}` |
| the code table | a relationship from the view's column: `DECLARE RELATIONSHIP <view>.<column> -> <code table>.<code>` |

Once one column of a view carries a `contract`, `next` asks for one on
each other column (`should`), and the server runs two tests on the
view after each write. Each is red above a tolerance a person accepts
with `GLOSS <check> ON <view> AS $${"tolerance": …, "basis": …}$$`:

| Test | Its check returns | Red when |
|---|---|---|
| `contract_test` | `breaches`: per column, `rule` (`key`, `required`, `values`, `codes`, `type`, `missing`), `count` of rows and up to three `examples`; `rows` | the key repeats or is empty, a required value is empty, a value is not allowed, a code has no row in its code table, a column is served as another type. `breach_rate` is the share of rows of the largest breach |
| `code_test` | `codes`: per target column and source column, the `system`, the `literals` the expression names, `told`, `contracted`, `rows`, and `unnamed`, each value the literals do not name with its rows | a value the expression does not name reaches a column with a contract: it falls to the `ELSE` or to NULL. Name every code. Values are counted over the rows the view's condition on the source table keeps (comparisons with literals joined by `and`). Where a column is tested by a range, a pattern or a function of it, or the condition has another form (a window, an `or`), `told` is false; where no column is told, the check is not applicable and the test is yellow, not green |

A server opened without the kit serves the same `next`, the same
tests and the same `column_mapping()` for a dataset with no contract.

```sql
SELECT source_systems() FROM onhand;
SELECT test, state, evidence->>'finding' FROM view_tests() WHERE test IN ('contract_test', 'code_test');
```

## The outlook and plan kits (preview)

Stored results, read back as SQL ([outlook](../usage/outlook.md)).
They are functions an actor may run: `metric_ranges()` over the
dataset, `metric_forecast()` and `metric_scenario()` over a metric
(the outlook kit, with a model service), `metric_plan()` over a plan
(the plan kit, without one). The server runs none of them after a
write, and `next` asks for none. Once one is stored, `next` lists it
as any stored result: a red test on it as `must`, the result out of
date as `should`. A server opened without either kit serves the same
`next` for a dataset with no stored result of theirs, and these reads
serve no rows.

| Read | Columns |
|---|---|
| `range_points()` | `metric`, `applicable`, `reason`, `code`, `backtested`, `held_80`, `held_90`, `score`, `state`, `period`, `actual`, `p05`, `p10`, `p50`, `p90`, `p95`, `pit`, `displacement`, `withheld`, `coverage_80`, `coverage_90`, `newest`, `point_seq`, `served_by`, `computed_at`, `error` |
| `forecast_points()` | `metric`, `applicable`, `reason`, `code`, `error`, `additivity`, `grain`, `origin`, `served_by`, `computed_at`, `current`, `point_seq`, `step`, `span`, `to_go`, `period`, `p05`, `p10`, `p50`, `p90`, `p95`, `coverage_80`, `coverage_80_se`, `coverage_90`, `coverage_90_se`, `coverage_points` |
| `scenarios()` | `scenario`, `body`, `annotated`, `applicable`, `reason`, `levers`, `fix` |
| `scenario_points(<name> or NULL)` | `scenario`, `metric`, `grain`, `origin`, `applicable`, `reason`, `code`, `levers`, `step`, `period`, `low`, `value`, `high`, `baseline`, `effect`, `history_value`, `history_low`, `history_high`, `sign`, `basis`, `explains`, `error`, `served_by`, `computed_at` |
| `scenario_levers(<name> or NULL)` | `scenario`, `metric`, `applicable`, `reason`, `sign`, `lever`, `planned_from`, `history_shift`, `history_low`, `history_high`, `computed_at` |
| `plan_points()` | `plan`, `metric`, `grain`, `period`, `label`, `value`, `actual`, `variance`, `low`, `expected`, `high`, `planned`, `covers`, `coverage_80`, `origin` |

- `range_points()`: one row per metric and backtested month.
  `backtested` is how many months were predicted from the months
  before them; `newest` marks the month `score` and `state` are for,
  the model service's result. `code` is the service's code for a
  metric it could not backtest, such as `origins_short`. A backtest
  that failed is one row with its `error`.
- `forecast_points()`: one row per metric and point, from the forecast
  stored on each metric. A row with `span` is a total over that many
  periods, running to the end of `to_go` (`month`, `quarter`,
  `year`). `coverage_80` and `coverage_90` are the service's measured
  share of actual values inside such a range on held-out data, with
  their standard errors. A run that failed is one row with its
  `error`.
- `plan_points()`: `planned` is `complete`, `not_covered`, `inside`,
  `below`, `above`, `partial`, `open` or `ahead`. `not_covered`: the
  period has begun and the metric's series does not cover it, so the
  row has no `actual` and no `variance`. `low`, `expected`, `high`,
  `coverage_80` and `origin` come from the forecast stored on the
  metric, and are empty without one.
- `scenario_points()`: `baseline` is the same estimate with every
  lever as planned; `effect` is the service's difference of the two.
  `code` is the service's code for a scenario it could not answer,
  such as `nothing_changed`.
- `world_series(<grain>)`: `metric`, `series`, `world`, `period`,
  `value`, `additivity`, `low`, `high`, `held`: each plan and each
  stored forecast beside a metric's actual series, as the console's
  chart draws them.
