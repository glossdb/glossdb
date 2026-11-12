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
| `open_items` | dataset | `kind`, `subject`, `what`, `why`, `since` |
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
- `open_items`: `kind` is `recipe-change`, `formula`, `conflict`,
  `re-measure`, `never measured` or `apply-decision`.
- `workspace_status`: `area` is `sources`, `tables`, `relationships`,
  `properties`, `annotations`, `functions`, `views`, `tests`,
  `scenarios`, `plans`, `review` or `apps`. For `tests`, `open`
  counts a test of your own on each asset that carries its
  expectation and has no result yet, and a descriptive property with
  a test (`meaning`, `role`, `entity`) on each asset a metric reads
  that has no value. `tested_properties()` lists the properties of
  the first kind by `name`.

### next

The open work of the dataset in use, one row per asset and state,
ordered by `priority`, then `ord`: the most urgent first, not by kind
of work. A test has one row per asset it is not green on, and each
assumption that waits for a person has a row. A test of your own is
listed on the assets that carry its expectation.

| Column | Holds |
|---|---|
| `priority` | 1 a number is wrong or withheld; 2 something changed or was decided; 3 not there yet; 9 waiting for a person |
| `step` | the kind of work: `integrate` (a source to connect, a table to load, a view to define), `describe`, `test`, `review` (a question for a person, or a person's decision to apply) |
| `ord` | the order of the rows inside one priority: loads (1), `describe` (2), `test` (3), `review` (4), views (5) |
| `asset` | the dataset, table, column, relationship or view |
| `state` | `missing`, `stale`, `conflict`, a test's state, `decided`, `waiting`, `blocked` |
| `who` | `agent` or `person` |
| `open` | the finding |
| `for_view` | the views that read the asset |
| `cause` | what the newest load changed: row counts, and the columns whose profile moved |
| `statement` | the statement that opens the work; `<…>` marks what the author fills |

```sql
SELECT step, asset, state, who, open FROM next;
```

The `describe` rows cover the assets the views read, and each value
in conflict.

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
| `view_sources(for_view := NULL)` | `view`, `field`, `source` (`table.column`), `table_name`, `reason`: column lineage; one more row per table read |
| `view_tests()` | `view`, `test`, `aspect`, `declared_by`, `subject`, `state`, `current`, `score`, `evidence`, `run`: each test on each view and on what it reads, worst first |
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
(`role_test`). The preview tests are rows under
the metric, a plan's test under the metric it plans; their `state`
can be `not_applicable`, their `evidence` holds `applicable`,
`reason`, `finding` and `fix`, and their `run` is empty.
`view_tests_without_preview()` is the same read without them.

## The outlook kit (preview)

Stored results of the model service, read back as SQL
([outlook](../usage/outlook.md)).

| Read | Columns |
|---|---|
| `range_result()` | `served_by`, `grain`, `score`, `state`, `threshold`, `computed_at` |
| `range_points()` | `metric`, `applicable`, `reason`, `additivity`, `backtested`, `held_80`, `held_90`, `period`, `actual`, `p05`, `p10`, `p50`, `p90`, `p95`, `pit`, `withheld`, `displacement`, `newest`, `point_seq`, `computed_at` |
| `forecast_points()` | `seq`, `metric`, `applicable`, `reason`, `additivity`, `grain`, `origin`, `served_by`, `computed_at`, `current`, `point_seq`, `step`, `span`, `to_go`, `period`, `p05`, `p10`, `p50`, `p90`, `p95`, `service_80`, `service_90`, `actual`, `actuals`, `held_80`, `held_90`, `held_from` |
| `forecast_coverage()` | `metric`, `grain`, `step`, `span`, `to_go`, `points`, `inside_80`, `inside_90`, `held_80`, `held_90` |
| `scenarios()` | `scenario`, `annotated`, `applicable`, `reason`, `levers` |
| `scenario_points(<name> or NULL)` | `scenario`, `metric`, `grain`, `origin`, `applicable`, `reason`, `levers`, `pass`, `step`, `period`, `low`, `value`, `high`, `baseline`, `effect`, `history_value`, `history_low`, `history_high`, `held_80`, `held_from`, `sign`, `confidence`, `basis`, `explains`, `error`, `served_by`, `computed_at` |
| `scenario_levers(<name> or NULL)` | `scenario`, `metric`, `applicable`, `reason`, `sign`, `basis`, `lever`, `planned_from`, `history_shift`, `history_low`, `history_high`, `computed_at` |
| `plan_points()` | `plan`, `metric`, `grain`, `period`, `label`, `value`, `actual`, `variance`, `low`, `expected`, `high`, `planned`, `covers`, `held_80`, `held_from`, `origin` |
| `plan_stored()` | the stored comparison: the columns of `plan_points()` without `origin`, with `plan_grain`, `forecast_run`, `forecast_origin`, `computed_at` |

- `forecast_points()`: a row with `span` is a total over that many
  periods, running to the end of `to_go` (`month`, `quarter`, `year`).
  `actuals` is `below`, `low`, `inside`, `high` or `above`.
  `held_from` says whose count `held_80` is: `metric`, `dataset` or
  `service`.
- `plan_points()`: `planned` is `complete`, `not_covered`, `inside`,
  `below`, `above`, `partial`, `open` or `ahead`. `not_covered`: the
  period has begun and the metric's series does not cover it, so the
  row has no `actual` and no `variance`.
- `range_points()`: `backtested` is how many months were predicted
  from the months before them.
- `scenario_points()`: `baseline` is the same estimate with every
  lever as planned; `effect` is `value` minus `baseline`.
- `outlook_measurements()`: `name`, `stored`, `due`: the preview
  functions the dataset needs; `due` is true where none is stored or
  what the function reads changed since its result.
