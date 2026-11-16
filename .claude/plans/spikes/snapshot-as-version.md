# Spike: the snapshot is the version

Does "a result is out of date when a node it read changed after the snapshot it read at" decide
correctly, on a real DuckLake lake, without a digest of what each read returned? Plain DuckDB 2.0.0
(the version `glossql/vendor/duckdb/VERSION` pins) with `ducklake` 417a9117f5, in a uv venv. No
glossql code, catalog or server. The older files in this directory (`setup.sql`, `deps.sql`, …) are
an earlier, unrelated spike; this one is `sv/` and this README.

Run (about 10 minutes, the 500,000 bench is most of it):

```sh
cd sv && uv venv -q .venv && uv pip install -q --python .venv/bin/python duckdb==2.0.0 numpy \
  && mkdir -p run && .venv/bin/python cases.py > cases.out && .venv/bin/python bench.py > bench.out
```

| File | Lines | What |
|---|---|---|
| `sv/schema.sql` | 87 | the catalog tables, when each node changed (`g_changed`), the check (`g_check`) |
| `sv/lake.py` | 105 | a write at the lake's next snapshot id; annotate, define, relate, declare, load, compute with early cutoff |
| `sv/cases.py` | 149 | questions 1 and 5; output `sv/cases.out` |
| `sv/bench.py` | 133 | question 2; output `sv/bench.out` |

Over the 300 lines asked for: the design is `schema.sql` and `lake.py` (192 lines); the rest drives it.

Labels: **[measured]** this spike ran it, output in `cases.out`/`bench.out`; **[code]** read in the code;
**[assumed]** reasoned, not run.

## The schema

All in the lake's metadata database, beside `ducklake_snapshot`. A write opens a transaction, takes
`max(snapshot_id) + 1` and inserts that `ducklake_snapshot` row, as the extension does today
([code] `gloss/src/glossql_runner.cpp:17-21`, `Inner::Write`). A load is DuckLake's own commit.

| Table | Columns | Note |
|---|---|---|
| `g_annotation`, `g_definition`, `g_relationship` | `begin_snapshot, end_snapshot,` + key and body | rows ended, never deleted |
| `g_declaration` | `begin_snapshot, end_snapshot, asset, kind, body` | anything else: a function, an add-on's scenario, an outside service's version as observed |
| `g_result` | `begin_snapshot, end_snapshot, function, subject, value, error, read_at, changed_at` | `read_at`: the snapshot the computation read. `changed_at`: when (value, error) last changed; kept on a recomputation with the same value |
| `g_read` | `result, asset, what` | one row per node read. `what`: `annotation <p>`, `definition`, `declaration`, `data`, `result <f>`, and two sets: `relationships` (those touching the asset), `declarations` (those of a kind) |

`g_changed(asset, what, changed_at)` is one `UNION ALL`: per node, the latest begin or end of its rows;
for a result, its `changed_at`; for a table, the table row and DuckLake's change log
(`tables_inserted_into`, `tables_deleted_from`, `tables_altered`, `inlined_insert`, `inlined_delete`).

The check (`g_check`), one query: a current result is **out of date** when a node it read has
`changed_at > read_at`, naming the node and snapshot; **possibly out of date** when a result it read
is out of date or possibly so (recursive CTE over `g_read`); **not declared** when its function was
declared and is no longer. Nothing else is compared.

## Question 1: is it right? [measured, `sv/cases.out`]

| Case | What happened | Check said | Right? |
|---|---|---|---|
| a1 | annotation on `customers.id`, read by nothing | all current | yes |
| a2 | `orders.amount` unit changed at 16 | `profile(orders.amount)` out of date, `orders.amount annotation unit @16`; its reader `summary` possibly out of date; others current | yes |
| b | `customers` loaded at 18 | `profile(customers)` out of date `main.customers data @18`; results on `orders` current | yes |
| c1 | `orders` loaded at 21, max unchanged, `total` not yet recomputed | `total` out of date; `share` (reads `total`) possibly out of date | yes |
| c2 | `total` recomputed, same value | `total.changed_at` stays 10; `share` current without recomputing | yes |
| c3 | load with a new max, `total` recomputed, new value at 26 | `share` out of date `main.orders result total @26` | yes |
| d1 | relationship on `items`, which the view does not read | current | yes |
| d2 | relationship `orders → customers` declared at 31 | `coherence(sales)` out of date, `main.orders relationships @31`, `main.customers relationships @31`; the added row found by `begin_snapshot > read_at` | yes |
| d3 | view redefined at 34 to read `items` too (which already had a relationship) | `coherence` (walk recorded: the definition and each table's set) out of date `main.sales definition @34`. **`coherence_ends_only` (only the tables' sets recorded) current: wrong** | only if the whole walk is recorded |
| e1 | unit changed at 36, changed back at 37 | `profile` out of date, `summary` possibly | by design; a digest says current |
| e2 | `profile` recomputed, same value | `profile.changed_at` stays 27; `summary` current again, not recomputed | early cutoff recovers the readers |
| e3 | unit written again with the same body at 38 | `profile` out of date | a no-op write costs a recomputation, unless the write is skipped |
| g1 | A takes snapshot 39 in an open transaction; B commits 39 | A's commit: `PRIMARY KEY … duplicate key "39"` | ids order writes; the loser retries |
| g2 | A computes at 39; B annotates (40) and loads `customers` (41); A stores | stored with `read_at` = 39: out of date `main.customers data @41`. **Stored with `read_at` = its commit snapshot (43): current, wrong** | only if the result keeps the snapshot it read at |
| h1 | `fx` fails (`service down`), `uses_fx` reads it; `fx` fails again the same way | `fx.changed_at` kept; `uses_fx` current | yes |
| h2 | `fx` succeeds | `uses_fx` out of date `main.orders result fx @47` | yes |

**d, places.** A read of a place is recorded as every node the walk passed through, plus one set node
per collection it ended in: "the relationships of this view" = `(view, definition)` and, for each
table read, `(table, relationships)`. A set node's `changed_at` is the latest begin **or end** of any
row in the set, so an added and a removed member both show, by snapshot alone, as long as ended rows
are kept. What was added or removed is a query on the rows: `begin_snapshot > read_at OR
end_snapshot > read_at`. Recording only the places the walk ended in is wrong (d3).

**e, changed and changed back.** By snapshot, each result that read the node directly is computed
once more; with a digest, none is. Early cutoff stops it there: readers further down stay or become
current once that one recomputation returns the same value (e2). The same holds for a write of an
unchanged value (e3) unless the writer skips it, which is a comparison at write time, once, not at
every check.

**f, DuckLake's change log** (lake with `DATA_INLINING_ROW_LIMIT 10`):

| Snapshot | Write | `changes` |
|---|---|---|
| 2 | insert 3 rows (inlined) | `inlined_insert` |
| 4 | `ducklake_flush_inlined_data` | `flushed_inlined` |
| 5, 6 | insert 1,000 rows twice | `tables_inserted_into` |
| 8 | `ducklake_merge_adjacent_files` | `merge_adjacent` |
| 10 | `DELETE FROM t` | `tables_deleted_from` |

Flush and compaction take a snapshot under their own key, so a check that counts only the five keys
above does not see them as changes; the merged file keeps `begin_snapshot` 2. Before expiry `t`
changed at 10. After `ducklake_expire_snapshots(older_than => now())` and cleanup, the change log holds
only snapshot 11 and no data file row is left; **`t` reads as changed at 1, its creation. A result that
read `t` at 3, 7 or 9 would be judged current although `t` is now empty: wrong.** After expiry,
"changed after S" can be answered only for S at or after the oldest kept snapshot. Two ways out
[assumed]: treat `read_at` below the oldest kept snapshot as out of date (one round of recomputation
after each expiry), or write the catalog's own row per load (the extension already writes "its row in
the store" after a lake change, [code] `glossql_runner.cpp:20-21`) and never expire it.

**g, two writers.** Snapshot ids order writes through the primary key of `ducklake_snapshot`: the
second commit of the same id fails and retries with the next. The trap is elsewhere: a computation
that reads at S and commits at S+k must store S. Two connections of one process were tested; two
processes on a Postgres or SQLite catalog were not.

**Today's server (8080, `subway`), [measured] read only.** `glossql_outdated()` lists
`metric_forecast` and `metric_scenario` on `trains_recent` (stored at 436 and 438) for
`data(data, itself)` and `results(temporal, its columns)`. By snapshot the answer is the same:
`service` was replaced at 440 (`tables_created`, `tables_inserted_into`), and `temporal` on
`trains_recent.month` was stored at 447 with a value different from the one at 430 (md5 of the value).
Where the answers would differ:
- a node changed and changed back, or written again unchanged: today current, by snapshot out of date
  until recomputed. A data engineer would call today's answer right; snapshot's costs a recomputation
  and is never wrong.
- the kit macros: 236 of the lake's 534 snapshots are macro writes; `main.world_scenario` was
  re-created at 139, 251, 427 and 489, at each open. Today a function's input includes the digest of
  each macro its body follows ([code] `MacroDigests`, `glossql_runner.cpp:1479`; `rn_fmac` in
  `ReadsNowSQL`), so an open changes nothing. **By snapshot, every result whose function follows a kit
  macro would be out of date after every open**, unless an open stops re-creating an identical macro.

## Question 2: does it need a graph in memory? [measured, `sv/bench.out`]

Generated catalogs on a DuckDB file (the metadata database as DuckDB): tables = results / 25, 10
columns per table with 4 annotated properties each, 1.5 views per table; each result reads 3–10
nodes, 1 in 8 of them one of 20 results read by many, 1 in 8 another earlier result. After the last
result, 1 in 200 annotations rewritten and 1 in 100 tables loaded. Median of 3 (SQL) or 5 (memory)
runs on this laptop (Apple silicon, DuckDB using all cores). Both sides return the same counts.

| | 5,000 results | 50,000 | 500,000 |
|---|---|---|---|
| edges / most-read node read by | 32,319 / 218 | 325,049 / 2,104 | 3,249,976 / 20,774 |
| SQL (i) after a write to a hub result: results out of date or possibly | 2.3 ms (473) | 9.3 ms (6,315) | 37 ms (69,962) |
| SQL (i) after a write to a table | 1.9 ms | 9.1 ms | 35 ms |
| SQL (ii) is one result current | 4.4 ms | 13 ms | 46 ms |
| SQL (iii) the whole check | 12 ms | 28 ms | 91 ms |
| memory: build at open / held | 50 ms / 4 MiB | 481 ms / 35 MiB | 6.7 s / 336 MiB |
| memory (i) hub / table | 0.2 ms / 0.001 ms | 2.6 ms / 0.004 ms | 31 ms / 0.005 ms |
| memory (ii) one result | 0.014 ms | 0.006 ms | 0.055 ms |
| memory (iii) whole check | 0.4 ms | 2.1 ms | 28 ms |

- ART indexes on `g_read(asset, what)`, `g_read(result)`, `g_result(subject)` changed nothing (within
  2 ms): DuckDB plans these recursive joins as hash joins over the whole edge table, so each SQL
  question costs about a scan of `g_read` [measured: same times; the reason assumed]. Sorting was
  not tried. Postgres as the catalog was not tried: none is reachable here.
- The memory side is Python with numpy and a dict of node names; a compiled structure would hold
  less and build faster [assumed]. Its build reads every edge and `g_changed`.

**Plainly:** at the plan's target (5,000 results) the whole check in SQL is 12 ms and a single
question 2–4 ms; at 500,000 it is under 0.1 s. A graph in memory answers a single question in
microseconds instead of milliseconds, and pays for itself only where one write is followed by many
such questions (hundreds per write), or past about 500,000 results where a single question nears
50 ms. Its cost in correctness, not measured here [assumed]: it must be updated in the step of each
write and dropped on a rollback (a failed write that already updated it leaves it wrong); a write
by another process (a second server, a load by another tool on the lake) is invisible to it until it
reads the catalog's rows since its last snapshot, which is `g_changed` restricted to `> last seen`,
the same SQL the check already is; and expiry (f) breaks it the same way it breaks the SQL.

## Question 3: the least that has to exist

What the design needs [measured: it is what `sv/` runs]:

- On every catalog row: `begin_snapshot`, `end_snapshot` (today's rows have them [code]); rows ended,
  not deleted, for as long as a result may have read them.
- On a result: `read_at` (the snapshot it read) and `changed_at` (the snapshot its value last changed).
- One edge table: `(result, asset, what)`, one row per node read. No version column.
- One generic `declaration (asset, kind, body)` table for what the core does not model (question 5).
- Two queries: `g_changed` (per node, latest begin/end; a table's from the change log) and `g_check`
  (compare, then walk results that read results). About 50 lines of SQL together.
- The write rule: a recomputation with the same (value, error) keeps `changed_at`.

What in today's design would have no counterpart [code, line counts at extension `2fe24e3`]:

| Today | Where | Lines |
|---|---|---|
| `ReadsNowSQL`: the digest of what each read returns now | `gloss/src/glossql_store.cpp:424-570` | 147 |
| `CheckSQL` with `rc_moved`, `rc_outdated` | `glossql_store.cpp:582-609` | 28 |
| `CheckRowsSQL` | `glossql_store.cpp:616-622` | 7 |
| `InputsNow`: the digests stored with a result | `gloss/src/glossql_runner.cpp:1802-1825` | 24 |
| `MacroDigests`: a macro's body in the digest | `glossql_runner.cpp:1479-1522` | 44 |
| `Keep`, `glossql_cached` incl. the kept check (`CachedCheck`) | `glossql_store.cpp:1981-2073` | 93 |
| `glossql_kept`, the kept reads | `glossql_store.cpp:2120-2203` | 84 |
| `inputs.version` | `docs/specification/tables/inputs.md` | a column |

That is about 430 lines of C++ against about 50 of SQL. `glossql_kept` also caches reads that are
not the check (views' summary, tests); only the check's part goes with this design [code]. Kept, with a
counterpart: `RelationVersionsSQL` (`glossql_store.cpp:377-391`, 15 lines) is `g_data_changed`; the
places of `gloss/kits/lineage/kit.sql` (`place_list` and `place_*`, lines 131-229, about 100) stay,
since a place must still be walked when a result is computed, but each walk must now emit the nodes
it passed (d3). `lineage()` (`kit.sql:64-98`, 35 lines) is not replaced by anything here: the edges
of `g_read` are what results read, not what views read; a lineage that answers "what does this view
read" stays a read of definitions.

## Question 4: where it does not hold

1. **Expiry loses the change log [measured, f2].** After `ducklake_expire_snapshots`, a table emptied
   at 10 reads as last changed at 1; a result read at 3–9 is judged current. Wrong, silently. A
   digest of DuckLake's version has the same blind spot today [code: `RelationVersionsSQL` reads the
   same log], but a digest of rows would not.
2. **A place recorded by its end nodes alone is wrong [measured, d3].** Every node the walk passed
   must be an edge. A place that walks several hops (the dataset's metrics and their columns, a view
   of a view) gives many edges per read where today stores one input per place.
3. **Changed and changed back, or written unchanged, costs a recomputation [measured, e1, e3].** One
   per direct reader; early cutoff stops it from going further (e2). A digest costs none.
4. **Kit macros re-created at every open [measured on 8080].** With macros as nodes, every result
   whose function follows one is out of date after each open, unless the open writes nothing for an
   unchanged macro. That is a comparison of bodies at write time: a content check, once per write,
   which this design still needs.
5. **The snapshot a result stores must be the one it read at [measured, g2].** Stored at its commit,
   a value computed before another writer's load reads as current.
6. **Set nodes are coarse [assumed, from the schema].** `(table, relationships)` changes when any
   relationship touching the table changes, including ones a narrower place ("the columns it joins
   on") would not include; `(kind, declarations)` changes when any scenario's body changes, not only
   when one is added or removed (q5b shows an addition). A false "out of date", never a missed one.
   Making it exact needs a set node per place definition, or a membership query at check time.
7. **Outside the lake there is no snapshot [measured, q5d].** A model service's change is seen only
   when something writes a row for it; between two observations, and for an answer that changes
   with no version change, the check says current. A digest of the answer has the same limit.
8. **Data at table grain.** Any load to a table puts every reader out of date, whatever rows it read
   [assumed]. Today's `data(...)` input is the same grain [code].
9. **The check walks results that read results in SQL.** A long chain is one recursion step per link
   [assumed; the bench's chains are short, see question 2].

## Question 5: an add-on the core knows nothing about [measured, `sv/cases.out`, q5]

No table, column or query of `schema.sql` names a kit. The add-on writes rows of `g_declaration`
(its function, its scenarios, the model service's version it observed) and its results' edges.

| Case | What happened | Check said | Holds? |
|---|---|---|---|
| a | `scenario_forecast` (add-on) and `profile` (core) both declared as `kind = 'function'`; results stored with edges | both current, same check | yes |
| b | `main.scenario_b` declared at 10 | `scenario_forecast(scenario_a)` current; `scenario_count` (reads the set `(scenario, declarations)`) out of date `scenario declarations @10` | yes |
| d | the add-on observes the service again at 1.3; then 1.4 | 1.3: no write (`unless_same`); 1.4 written at 13: both scenario results out of date `model_service declaration @13`; core `profile` current | yes, as far as observed |
| c | the add-on removed at 14: its declarations end | `profile` current; `scenario_forecast` on both scenarios **not declared**; **`scenario_count`, whose function was never declared, out of date** | only if every function is declared |

What the core has to offer an add-on for this:
- a generic declaration row `(asset, kind, body)` with begin/end, and the set node per kind;
- results and edges for any function, with the function itself declared as a row, so that a result
  whose function has ended reads "not declared" and not "out of date" (c);
- read functions that record `(asset, 'declaration')` and `(kind, 'declarations')` edges when an
  add-on's body reads its own declarations, as they record annotations and definitions;
- a way to write an observation of something outside the lake as a declaration, skipped when the
  body is the same.

What cannot be made generic: when an outside service is observed (on each call, on a schedule, on
a version endpoint the service may not have), what counts as its version, and whether its answer is
the same for the same question. The lake's snapshot orders what the add-on wrote down; it cannot
know what it did not. A scenario that sets levers on columns of several metrics is a node with its
own edges as soon as its body (its levers) is a declaration and the function records
`(scenario, declaration)` plus the columns' nodes it reads; how the levers are read stays the add-on's.

## Not tested

- Two processes writing one lake; a Postgres catalog (none reachable here); a SQLite catalog.
- DuckLake's change log at the size of question 2: the bench reads a table's loads from a plain
  table (`g_load`), not from `ducklake_snapshots()`. Today's `RelationVersionsSQL` reads the whole log
  per check; at 100,000s of snapshots that lookup is its own cost.
- Whether DuckLake's reads and the metadata database's reads in one DuckDB transaction see one
  snapshot (assumed: one transaction).
- An in-memory graph in a compiled language; the numbers above are Python with numpy.
- A view of a view several levels deep; dimension members or periods as nodes.
