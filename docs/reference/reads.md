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
| `properties` | `name`, `kind`, `grains`, `condition`, `schema`, `declared_at`, `declared_by` (the properties and view names) |
| `glossary` | `dataset`, `subject`, `property`, `actor_kind`, `actor_id`, `body`, `written_at` (the annotations) |
| `functions` | `name`, `scope`, `script`, `returns`, `reads` (what the body reads, by kind and place), `declared_at`, `declared_by` |
| `results` | `id`, `dataset`, `function`, `subject`, `property`, `value`, `computed_at`, `error`, `read_at`, `changed_at` (the stored results: a measurement, a test's result, a view's lineage; the lake snapshot the result read at, and the one its value last changed at) |
| `inputs` | `result`, `asset`, `what` (each node a stored result read: an asset and what was read of it; `result` is the result's `id`) |
| `edges` | `result`, `from`, `to`, `kind` (a view's lineage: one edge from the view to each table, column and view it reads) |
| `tests` | `name`, `property`, `actors`, `detector`, `threshold`, `declared_at`, `declared_by` |
| `kits` | `name`, `location`, `statements`, `loaded_at`, `hash` |

`SHOW TABLES` lists the dataset's tables and views beside these. How
`results`, `inputs` and `edges` decide whether a result is
current: [how results stay current](dependencies.md).

## The language's reads

| Read | Returns |
|---|---|
| `GLOSSARY(<asset>)` | one row per asset and property: `subject`, `property`, `value`, `test_state`, `score`, `state` (`current`, `stale`, `possibly`, `missing`, `conflict`) |
| `GLOSSARY(<asset>, all => true)` | each value side by side: `subject`, `property`, `kind`, `test`, `actor`, `body`, `written_at`, `current` |
| `TESTS(<asset>)` | `subject`, `property`, `test`, `state`, `score`, `computed_at`, `current`, `error` |

With no argument both cover the dataset in use. `<asset>::<property>`
narrows either to one property.

## Views of the catalog

| View | Scope | Columns |
|---|---|---|
| `current_dataset` | | `dataset`; no row on a call bound to none |
| `open_questions` | workspace | `dataset`, `subject`, `property`, `idx`, `dimension`, `key`, `assumption`, `basis`, `alternative`, `conf`, `sibling`, `sibling_stance`, `sibling_note` |
| `agent_assumptions` | workspace | `dataset`, `subject`, `property`, `idx`, `dimension`, `key`, `assumption`, `basis`, `alternative`, `conf`, `body` |
| `review_decisions` | workspace | `dataset`, `subject`, `idx`, `property`, `key`, `stance`, `dimension`, `assumption`, `note`, `written_at`, `folded_in` |
| `view_definitions` | dataset | `name`, `kind`, `unit`, `meaning`, `defined`, `stopped` |
| `next` | dataset | see below |
| `app_parts` | workspace | `dataset`, `app`, `path`, `text`, `actor_kind` |
| `app_releases` | workspace | `dataset`, `app`, `at`, `note`, `actor_kind`, `released_at` |

- `open_questions` is the review queue: a keyed assumption below full
  confidence in a view definition, with no decision on its key.
  `sibling` is a decision on the same key under another view.
- `review_decisions`: `stance` is `confirmed`, `corrected` or
  `unclear`; `folded_in` is true once the definition carries the
  decision.
- `view_definitions`: one row per view defined here, kept, served or
  stopped. `kind` is the definition's: `table`, `value`, `metric`,
  `rule`, NULL for a plain view. `meaning` is the `meaning`
  annotation on the view, `unit` the `unit` of a metric's or a single
  value's value column.
- `tested_properties()` lists by `name` the properties that exist to
  be tested: an expectation a function measures and a test scores.
  `next` asks for one only on the assets that carry it.

### next

The open work of the dataset in use, one row per asset, state and
level, ordered by `level`, then `ord`. It lists the states the catalog
holds: annotations, test results, a person's decisions. It judges
nothing itself: a judgement is a test, computed by the server after a
write, and `next` lists its result. A test has one row per asset it
is not green on, and each assumption that waits for a person has a
row. A test of your own is listed on the assets that carry its
expectation. A row for outdated annotations names the read that says
what the newest load changed, `load_changes()`, in a comment above its
statement.

| Column | Holds |
|---|---|
| `level` | `must`: served data is wrong or cannot be served. `should`: the layer is incomplete for what is served. `could`: what sits beside it |
| `ord` | the order inside one level, what blocks other work first: a source, a table or a view (1), a person's decision to apply (2), a test (3), an annotation (4), a stored result to compute again (5), a question for a person (6) |
| `kind` | the kind of work: `integrate` (a source to connect, a table to load, a view to define), `describe`, `test`, `review` (a question for a person, or a person's decision to apply) |
| `asset` | the dataset, table, column, relationship or view |
| `state` | `missing`, `stale`, `conflict`, a test's state, `decided`, `waiting`; for a load, `keys missing` or `unchanged` (`load_modes()`) |
| `who` | `agent` or `person` |
| `open` | the finding |
| `for_view` | the views that read the asset |
| `statement` | the statement that opens the work; `<…>` marks what the author fills. A comment line above a statement says why the row is open, or which choice it is and when to take it; one a person decides is commented out |

What each level holds:

- `must`: no table is loaded; no view is served; a test is red (a
  metric that serves no series is `series_test` red); two values of one property conflict; a
  person approved a load query or decided a review question, and the
  definition does not carry it yet; a keyed load
  missed keys of a table whose source is stated to send its complete
  state.
- `should`: a load does not fit what the source likely sends
  (`load_modes()`); an annotation is missing or outdated on an asset a view
  reads or serves; a test on it is not run, out of date, orange or
  failed, or yellow with a fix (a join a view makes between two loaded
  tables with no declared relationship is `relationship_test` yellow:
  its fix declares it, from the side that repeats the key where a
  profile or a stated grain says which side holds it once) (a yellow test whose current result has
  no fix has nothing to check and is no row);
  an assumption waits for a person; a stored result about the dataset
  is out of date, and the server does not compute it
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

### load_changes()

Per table of the dataset in use loaded more than once, what its
newest load changed against the load before.

| Column | Holds |
|---|---|
| `table_name` | `<dataset>.<table>` |
| `cause` | the row counts of the two loads, and each column whose stored profile moved: distinct values, the share empty, the lowest and the highest value |

```sql
SELECT table_name, cause FROM load_changes();
```

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

One row per view the dataset in use serves (`table`, `value`,
`metric`); a plain view and a rule are kept, not served.

| Column | Holds |
|---|---|
| `view`, `kind` | the name; `table`, `value` or `metric` |
| `stopped` | the stop reason |
| `applicable`, `reason` | whether a metric's series is served; else what to change. A table and a single value have no series: `applicable` is NULL, and `reason` is filled only where the view is stopped or its definition serves no view |
| `period_column`, `value_column`, `numerator`, `denominator` | the columns the series reads; `period_column` is NULL for a table and a single value |
| `grain_detected`, `floor`, `window_periods` | the grain `temporal()` measured on the period column; the finest grain served; how many periods a read serves at that grain. NULL for a table and a single value |
| `additivity`, `additivity_state` | the value column's additivity; `none` where nobody stated it, `conflict` where it is withheld |
| `dims`, `dimensions_without_rank` | the slicing columns, primary first; dimension columns without a `dimension` annotation |
| `columns_without_role`, `missing` | served columns without a `role`; the annotation each needs. Both are empty for a single value |
| `measurements_to_run` | measurements the row reads that nobody ran or that are out of date; the server runs them after a write |
| `profile_current` | the period column's temporal profile is current |

```sql
SELECT view, kind, applicable, reason, floor, additivity, dims FROM view_summary();
```

### metric_series()

```
metric_series(view := NULL, grain := NULL, unclaimed := 'refuse')
```

The cells of each served metric: `metric`, `world` (`actual`), `dimension` (`''`
for the total), `member`, `period`, `value`, `num`, `den`,
`additivity`.

- `view`: one metric by its name. The read then reads that view's rows
  alone, and only that metric's missing additivity refuses it. NULL
  serves every metric.
- `grain`: `minute`, `hour`, `day`, `week`, `month`, `quarter`,
  `year`. NULL serves each metric at its floor. A metric coarser than
  the grain asked serves no rows.
- `unclaimed := 'skip'` leaves out a metric whose additivity is not
  stated, where the default refuses and names the annotation.
- A metric marked `non-additive` is served where it has one row per
  period.
- A flow's total fills its empty periods with zero up to the newest
  instant of any metric served at that grain, as the temporal profile
  of its period column measured it.
- The engine sums each view's own typed columns as it reads the rows,
  per period and per member of each dimension. No row is kept. A
  `member` is the dimension's value as text, `NULL` where it has none.

### The other reads

| Read | Columns |
|---|---|
| `view_kinds()` | `view`, `kind`, `stopped`: each view of the dataset, kept or served, with its kind (`table`, `value`, `metric`, `rule`, NULL for a plain view) and, where its definition serves no number, why |
| `find(term)` | `asset`, `what` (`view`, `table`, `column`), `kind`, `meaning`, `tags`, `matched_on`, `reads`, `sql`: each view, loaded table and column whose name, meaning or tags hold the term, and each view that reads a column whose name holds it; `tags` is a person's and the agents' lists as one; a stopped view is not found |
| `tag_statement(asset, words)` | the statement that adds the words to the actor's own `tags` on the asset: an actor's newest list replaces its list before |
| `fact_values()` | `view`, `value`, `reason`: each single value |
| `column_mapping(for_view := NULL)` | `view`, `target_column`, `branch`, `system`, `source_table`, `source_column`, `alias`, `condition`, `lookup`, `expression`, `literals`, `complete`: where each column of a view comes from, read off its SQL. One row per target column, per branch of the union the view's rows come from (1 where it has none) and per source column. `system` is the source table's `system_of_record` where the table states one, else the source it is loaded from. `alias` names each read of a table the view reads more than once, as the expression does (`supply.hierarchy[dk].brand`). `condition` is what the view's joins and filters require of that read alone (`=(supply.hierarchy[dk].market, 'DK')`). `lookup` is the equality of the join that joins that read to the rows before it, the driving side first: the column a mapping table is looked up by (`=(supply.stock_sap.matnr, supply.identities.local_code)`). `literals` are the codes the expression tests or returns, as written. A column computed from no source column has one row with no source. `complete` is false where the lineage could not follow a step or reads two reads of one table alike; a view that does not plan has one row with no target column |
| `view_tests()` | `view`, `test`, `property`, `declared_by`, `subject`, `state`, `current`, `score`, `evidence`, `run`: each test on each view and on what it reads, and on a result about the dataset, worst first |
| `semantic_model()` | `document`: the dataset as one Apache Ossie document (the 0.3.0.dev0 draft, schema at apache/ossie `74a26bef`); units and a semi-additive or non-additive value in `nonportable_extensions` |
| `lineage_events()` | `event`: OpenLineage run events (spec 2-0-2), one per load and one per view |
| `pages()` | `uri`, `title`, `body`: each page the MCP interface serves |
| `null_markers()` | a list: the strings a CSV export writes for no value |
| `fmt_number(x)`, `fmt_change(p)` | a number and a change in percent as the console prints them |

`view_tests()`: `declared_by` is `kit:<name>` for a shipped test.
`current` is false once what the result read has changed; the state
is kept until the test runs again. `run` is the function that returns
the test's property, over the subject; it is empty where no function
measures the property, as for a test that compares annotations
(`role_test`). A test on a result about the dataset as a whole is a
row too: `view` is empty, `evidence` is the stored result with its
`finding` and `fix`, and `run` is empty, since an actor computes that
result and the server does not.

## The harmonise kit (preview)

Several systems of record mapped onto one target table view. Where
each target column comes from, per branch of the view's union and per
system, is `column_mapping()` above: the system is the source the
source table is loaded from. The reconciliation counts the served
rows per system by a column that names it in each branch. Where one
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
each other column (`should`), and the server runs three tests on the
view after each write. Each is red above a tolerance a person accepts
with `GLOSS <check> ON <view> AS $${"tolerance": …, "basis": …}$$`:

| Test | Its check returns | Red when |
|---|---|---|
| `contract_test` | `breaches`: per column, `rule` (`key`, `required`, `values`, `codes`, `type`, `missing`), `count` of rows and up to three `examples`; `rows` | the key repeats or is empty, a required value is empty, a value is not allowed, a code has no row in its code table, a column is served as another type. `breach_rate` is the share of rows of the largest breach |
| `code_test` | `codes`: per target column and source column, the `system`, the `literals` the expression names, `told`, `contracted`, `rows`, and `unnamed`, each value the literals do not name with its rows | a value the expression does not name reaches a column with a contract: it falls to the `ELSE` or to NULL. Name every code. Values are counted over the rows the view's condition on the source table keeps (comparisons with literals joined by `and`). Where a column is tested by a range, a pattern or a function of it, or the condition has another form (a window, an `or`), `told` is false; where no column is told, the check is not applicable and the test is yellow, not green |
| `reconciliation_test` | `comparison`; `rows`: per system and period, `compared_on`, the `source_rows` the view's condition keeps, the `excluded_rows` it leaves out, the `target_rows`, `missing_rows`, the first ten `missing_keys` and `missing_key_count`, and `measures` (per column with role `measure`, the `source` and the `target` sum); `notes` | a source row the view's condition keeps does not arrive. `breach_rate` is the share of compared source rows that do not arrive. Row counts are shown and not compared: a view that groups, or a join that matches one row to many, serves another number of rows than it reads |

**The reconciliation.** The source of each branch of the union is the
table it reads that is joined to nothing before it (the lineage's
mapping: a read with no `lookup`); its system is its
`system_of_record`, else its load's source. A served row belongs to a
system by `system_column`: a column that each branch serves as a
different literal (`'sap' AS source_system`). A view of one branch
needs none; a view of several without one is not applicable, and the
fix says to add it. The period is the view's `time_axis` (its
`entity`), else its column with role `timestamp`, a date truncated to
its `time_grains` floor, a month where none is stated. The key is the
`grain` of the view's `entity`.

The comparison is at the view's grain. A source row the view's
condition on its table keeps (comparisons with literals joined by
`and`) gets the columns of `compared_on` as the view computes them:
each key column the branch copies from the source table, as it is or
cast, and each column it looks up through a join from the source
table (a mapping or identity table), with that table's condition. A
row whose join finds no partner gets no value there. The row arrives
where the view serves a row of its system with the same values. Rows
the condition leaves out are `excluded_rows`, not missing. Where a
branch compares nothing (its key is computed and it looks nothing
up), or its condition has another form (an `or`, a window), its rows
are counted and `missing_rows` is NULL; `notes` says which and why.
A period or a measure the branch computes is named in `notes` too:
the rows are counted over every period, or the measure has no
`source` sum. A missing row is named by the source table's own
columns the compared values come from (`ZESTPIL6, BR01, 2025-10-01`
for a local code, a warehouse and a date). The fix lists those rows
at the source.

A server opened without the kit serves the same `next`, the same
tests and the same `column_mapping()` for a dataset with no contract.

```sql
SELECT source_systems() FROM onhand;
SELECT test, state, evidence->>'finding' FROM view_tests() WHERE test IN ('contract_test', 'code_test', 'reconciliation_test');
SELECT reconciliation() FROM onhand;
SELECT r->>'system' AS system, r->>'period' AS period, r->'source_rows' AS source_rows, r->'target_rows' AS target_rows, r->'missing_keys' AS missing_keys
FROM results, unnest(from_json(value->'rows', '["JSON"]')) t(r) WHERE function = 'reconciliation';
```

`orphan_test` names the keys that find no parent on each relationship
the view joins over, the three with the most rows, from the
relationship's `relationship_coherence`. The keys are values from the
data, each cut to its first 100 characters; a key of two columns is a
JSON list.

`completeness_test` has one result per column a view serves. Where
the column's share of empty values rose past the tolerance, its
evidence holds `before`, `now`, `emptied_by` (`load` or `definition`)
and, for a load, `sources`: the table columns that emptied too. Its
`cause` names them, or says the definition empties the column. The
share before is read from the values the column's `column_profile`
held, oldest first: the last share within the tolerance. `SELECT completeness_check() FROM
<dataset>.<view>` computes the check on each column of the view.

