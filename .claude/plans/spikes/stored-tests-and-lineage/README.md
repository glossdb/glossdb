# Spike 2b: a test's result and a view's lineage as stored results

Plain DuckDB 2.0.0 + `ducklake` 417a9117f5 in a uv venv; no glossql code. Builds on the snapshot-as-version spike's schema and check. Rerun (about 30 s): `./run.sh` → `cases.out` (DuckLake lake), `bench.out`, `parts.out`, `walk.out` (DuckDB file). Design: `schema.sql` (146 lines) and `store.py` (266: writes, due, compute). Reads over stored rows: `reads.sql` (93). Drivers: `kit.py` (four real detectors copied, stand-ins), `cases.py`, `bench.py`, `parts.py`, `walk.py`.
Labels: **[measured]** in an `.out` file · **[code]** read at gloss `4b27a07` / glossql `8cd06df` plus the uncommitted edits on `snapshot-version` (line numbers move while the other agent works) · **[assumed]**.

## 1. Inventory: what is computed on read today

Model: (a) input · (b) derived value, stored with its nodes · (c) read over stored rows, nothing stored.

| What | Where [code] | Kept? | Read by | Reads | Model |
|---|---|---|---|---|---|
| stale mark of an annotation | `glossql_store.cpp:1325-1384` `AnnotationsOverSQL` | in `glossql_cached` per snapshot, per dataset | values, collapsed, raw, detectors | lake columns, views, loads' lineage | (c): begin vs the definition node's change, 6.2 ms per dataset at 500k [measured] |
| values with function marks | `:1397` `ValuesSQL`, `:1302` `CurrentResultsSQL` | same | all three reads, detectors | glossary, measurements, the check | (c); the mark is the check walk (§4) |
| detectors (TESTS) | `:1518-1576` `ResultsSQL` | `glossql_cached('tests')` | TESTS(), collapse, `view_tests` | the property's values, tests, functions | **(b)** per (subject, test) |
| missing rows | `:1579` `MissingSQL` | inside collapsed | GLOSSARY() | columns, relationships, sources | (c) |
| collapsed read | `:1643` `CollapsedSQL` | `glossql_cached('collapsed')` | GLOSSARY(), `annotations()` read function, `view_rows` | values, test results, missing | (c): 6.5 ms a column, 13.5 ms a dataset at 500k without marks [measured] |
| raw read | `:1681` `RawSQL` | `glossql_cached('raw')` | GLOSSARY(all) | values | (c) [assumed: a subset of the collapse's work] |
| the keeping itself | `:1909-2083` `Keep`, `Cached`, `glossql_cached`, fill stack | object cache, key = snapshot | the reads above | — | goes |
| a view's rows | `:2085-2123` `glossql_kept_view` | per snapshot | cells reads (`glossql_runner.cpp:2198-2294`) | the view | goes, no replacement (decided) |
| kit reads kept | `:2125-2210` `glossql_kept` | per snapshot | `view_summary` (views `:341`), `results_due` (goals `:48`), `next` (goals `:322`) | `view_rows`, `view_tests` | goes |
| `view_rows` / `view_summary` | views kit `:135`, `:341` | via `glossql_kept` | `next`, `results_due`, series reads, `column_mapping` | 5 collapsed reads, columns, profiles | (c): stand-in 69.6 ms per dataset at 500k [measured] |
| `view_tests` | views kit `:1110` | via `glossql_kept` | `next`, `results_due` | TESTS(), lineage, measurements | (c): stand-in 96.4 ms [measured] |
| a view's lineage, scans, joins, mapping | `glossql_lineage.cpp:1506-1607` `KeptLineage`, `DatasetLineage`; `:1609`, `:1740` | per catalog version, per dataset | `lineage()`, places, `view_tests`, `next`, `results_due`, `definitions()` | the views' plans | **(b)** per view, edges as rows |
| `lineage(ds)` | lineage kit `:57` | no, per call | console, places, `next` | columns, relationships, view bodies (`json_serialize_sql` per call), scans, joins, kind edges | (c) over stored edges: 2.3 ms at 500k [measured] |
| `places()`, `place_nodes()` | lineage kit `:190`, `:217` | no | `results_due`, read functions | as above | (c): a view's sources 1.2 ms [measured] |
| kit edges: scenario levers, plan's metric | outlook `:555`, plan `:30`, via `glossql_kind_edges` (`glossql_store.cpp:1811`) | no | `lineage()`, places | annotation bodies, aspects | (c): 10,000 scenarios × 5 levers in 2.8 ms [measured]; storable as (b), case G |
| the check | `:1271` `CheckRowsSQL`, `glossql_outdated()` | no (step 2a) | `results_due`, marks | inputs, measurements | the mechanism itself |
| `glossql_columns`, `load_changes`, `server_results` | `:1690-1770`, goals `:111`, `:34` | no | many | the lake catalog, imports | (a) / (c) |

## 2. The proposed schema; the grain of a test result

| Table | Change against step 1 |
|---|---|
| `g_result` (= `measurements`) | adds `id`: one write stores many results (a round of one function), so `begin_snapshot` no longer names a result |
| `g_read` (= `inputs`) | keyed by `id`; unchanged nodes. A test result reads `(subject, annotation p)`, `(subject, result f)` for each `f` returning `p`, the subject's definition node (the stale rule), `(test, declaration)`, `(detector, declaration)` |
| `g_edge (result, src, dst, kind)` | new: the lineage edges a result holds, current while it is. `lineage(ds)` = contains edges from the catalog ∪ edges of current results |
| `g_declaration` | a function's body names `subjects` (SQL: where it is expected) and `after` (whose results it reads); a test names property, detector, threshold. The core reads only these |

`lineage` is a function on a view: reads `(view, definition)` and the definition of each relation its walk passes (a view of a view: both). Due = expected ∖ stored (missing) ∪ out of date (`g_after(since)`, from the nodes the write began or ended) ∪ stored ∖ expected (retired); `possibly` waits.

**Grain: one result per (subject, test), computed in one batch per test per round.** One annotation write puts 1 result out of 153,838 `role_test` results out of date at 500k [measured]. Per (dataset, test) computes as cheaply (the detector whole: 8.4 ms for 15,392 subjects at 500k [measured]) but is one node: every reader of any subject's test result in the dataset is out of date after any annotation of that property, against "a change must not turn off everything". The four real detectors (`value_entropy`, `rate_tolerance`, `range_state`, `plan_gap`) give the same rows whole, per subject and per batch [measured, H].

## 3. Cases [measured, `cases.out`, DuckLake lake]

| Case | The check said (due) | Computed | Right? |
|---|---|---|---|
| start | 21 missing | all, in order lineage → grain_check → grain_test | yes |
| A1 agent changes role on `sales.amount` | `role_test(sales.amount)` | 1, value same | yes |
| A2 a person disagrees | same one | 1; collapse of `main.sales` shows `conflict` on that row only | yes |
| B unit on a column no view reads | `unit_test` missing there | 1; no lineage | yes |
| C1 new view | its lineage missing | 1 | yes |
| C2 `sales` reads items too | lineage of `sales` and `sales_by_region` (view of a view); `grain_check` possibly; the 5 tests on `sales` and its columns (they read its definition) | lineage 2 changed; tests and `grain_check` same value | yes; tests recomputed for the stale rule only |
| D a column added to `orders` (3 views read it) | 3 lineages, `role_test(orders)`, a missing profile; `grain_check` possibly | lineages same value: `changed_at` kept, `grain_check` not recomputed | yes |
| D/E stale mark | annotation on `orders` stale after D; `unit` on `orders.amount` stale after retype | — | yes |
| F load `orders` | 5 profiles, `grain_check(sales)`; `grain_test` possibly | 3 profiles changed, `grain_check` same → `grain_test` current | yes |
| G1-G3 scenarios as a kit's function with edges | each scenario's own result only | 1 each; other scenario current | yes |
| I `role_test` declared again | all 4 role_test results | 4, same values | yes |
| J detector not declared, then declared | errors stored per subject; then out of date via `(detector, declaration)` | 2 + 2 | yes |
| K a load by another tool, no write after | TESTS() serves `grain_test` with `current` false, `possibly` | nothing until the next write through the server | as designed |
| L view removed | lineage retired; its edges leave `g_lineage` | retired 1 | yes |
| H a cross-subject detector (`rank_share`, a window) | per subject ≠ whole | — | **no**: see §5.1 |

The due set from the nodes written equals the whole check's in every case [measured]; the narrowed check equals the whole check after an uncomputed write at all three sizes [measured, bench].

## 4. Timings [measured, `bench.out`, `parts.out`; median of 3; DuckDB file, Apple silicon]

Mix per table: 10 columns × (profile + 3 tests), 1.5 views × (lineage, grain check, grain test, 5 tests on its columns); 4 agent annotations per column, a person's role on 1 in 10.

| | 5,000 | 50,000 | 500,000 |
|---|---|---|---|
| results / edges read / lineage edges | 4,992 / 18,922 / 648 | 49,968 / 189,400 / 6,486 | 499,976 / 1,895,054 / 64,882 |
| annotation with a test: decide / compute+store (results) | 8.7 / 28 ms (1) | 16 / 46 ms (1) | 44 / 103 ms (1) |
| annotation with no test: decide | 8.6 ms (0) | 16 ms (0) | 42 ms (0) |
| a table three views read, column added | 8.7 / 39 ms (10: 3 lineage, same value) | 15 / 52 ms | 45 / 127 ms (13) |
| a new view: decide / compute | 8.4 / 26 ms (1) | 15 / 43 ms | 44 / 118 ms |
| a view defined again | 9.1 / 69 ms (8) | 15 / 84 ms (8) | 47 / 243 ms (8) |
| a test declared again (one dataset) | 9.6 / 110 ms (960) | 15 / 222 ms (2,410) | 44 / 825 ms (9,620) |
| decide = `g_after` + expected∖stored | 5.4 + 3.4 ms | 11.4 + 5.0 ms | 37.2 + 13.9 ms |
| whole due, every dataset / the whole check | 11.9 / 7.9 ms | 20.7 / 16.1 ms | 69.6 / 65.9 ms |
| TESTS() dataset / column, with marks | 7.1 / 5.5 ms | 16.9 / 11.5 ms | 61.6 / 42.2 ms |
| the same without marks | 1.8 / 0.8 ms | 3.6 / 1.3 ms | 5.5 / 2.7 ms |
| GLOSSARY() dataset / column, with marks | 11.0 / 8.2 ms | 18.2 / 13.1 ms | 80.7 / 46.0 ms |
| the same without marks (pick, conflict, stale, missing) | 7.1 / 4.2 ms | 9.0 / 4.6 ms | 13.5 / 6.5 ms |
| stale mark alone, a dataset | 2.2 ms | 3.1 ms | 6.2 ms |
| `view_summary` / `view_tests` stand-ins, a dataset | 14.3 / 11.4 ms | 20.7 / 22.9 ms | 69.6 / 96.4 ms |
| `lineage(ds)` / a view's sources | 0.8 / 0.6 ms | 1.0 / 0.6 ms | 2.3 / 1.2 ms |
| today, stand-in: a dataset's detectors whole + collapse, per write | 21.1 ms | 32.4 ms | 89.6 ms |
| today: every view of a dataset planned whole (1 ms per view, stand-in) | 154 ms | 370 ms | 1,452 ms |

Compute+store includes a second due query (the round that finds nothing), about the decide time; the detector and the store for one result are the rest (≈15 ms at 500k) [derived]. Datasets: 1 / 4 / 10.
**Postgres [assumed, not run]:** the store's tables are read through DuckDB's Postgres scanner; filters push down, joins and the recursive walk run in DuckDB, so each walk step pulls `g_read` across the connection: the marks and `g_after` would grow with the edge table, not shrink. Run as SQL inside Postgres with B-tree indexes on `inputs(result)`, `inputs(asset, what)`, `measurements(subject, function)`, a one-column walk is index lookups (sub-millisecond) and the whole check slower than DuckDB's scans. `QUALIFY` and table macros need rewriting.

## 5. Where it does not hold

1. **A detector that judges a subject against the others.** `rank_share` (a window over subjects) gives other rows per subject than whole [measured, H]. Stored per subject, its result reads only the subject's values, so another subject's write leaves it current and wrong. None of the four real detectors does this [measured]; SPEC §7.2 allows it ("one query over the test's annotations"). A body check finds a window [measured: `json_serialize_sql`]; a scalar subquery over `annotations` would pass it [assumed].
2. **The current marks cost a walk at every read.** TESTS() of one column: 2.7 ms without marks, 42 ms with them at 500k [measured]; the walk is a recursive hash join over the edge table: 12 ms for one column over result edges only, 29 ms over all edges [measured, `walk.out`]. Storing removes the per-write recomputation; it does not make a read with marks cheaper than today's stand-in (89.6 ms per dataset). `next` composes several marked reads and pays the walk in each [assumed].
3. **A view defined again recomputes the tests on its columns** (they read its definition through the stale rule): 8 results each time, same values [measured]. Needed only if a detector reads `current`; none of the four does [code].
4. **A declaration recomputes its results in every dataset.** A test declared again: 9,620 results in one dataset in 825 ms; the 9 other datasets stay due (86,547) until their next write [measured].
5. **Stale by snapshot differs from today's rule.** Today a column retyped and retyped back is not stale (type then = type now, `glossql_store.cpp:1364`) [code]; by snapshot it stays stale until written again. Re-derivation by a load (today compared by `imports.lineage`) needs a definition row written at the load whose derivation differs, a comparison at write time [assumed].
6. **Data loaded by another tool:** nothing is computed until a write through the server; TESTS() serves `possibly` [measured, K]. A read-only attach cannot store: its reads serve stored rows marked, or run the detector at read, the one case that still needs it [assumed].
7. **One snapshot per result does not scale:** 9,620 results would take 9,620 snapshots; the spike stores a round in one, keyed by `id` [measured]. `inputs.md` keys a result by `begin_snapshot` [code].
8. **Deciding is a scan:** 44 ms at 500k for any write, 37 of it `g_after` [measured]; a kit's `subjects` query runs on every write of the dataset [assumed].
9. **The lineage stand-in reads definitions only;** a view that calls a macro or reads another dataset needs those nodes too [assumed].

## 6. What in today's code has no counterpart [code; lines as information]

| Today | Where | Lines |
|---|---|---|
| `glossql_cached`, `Keep`, `Cached`, `CacheKey`, `ReadFill`, the fill stack | `glossql_store.cpp:1909-2083` | ~175 |
| `glossql_kept` and `KeptNow`/`Keeping` | `:2125-2210` | ~86 |
| `glossql_kept_view` (decided) and its use in the cells read | `:2085-2123`; `glossql_runner.cpp:2198-2294` (part) | ~39 + part |
| `KeptValuesSQL`, `StoreValues`, `KeptTestsSQL`, fill shapes | `:1505-1516`, `:1639-1642`, `:2212-2228` | ~33 |
| `KeptLineage`, `CatalogState`, the caching in `DatasetLineage` | `glossql_lineage.cpp:1506-1607` (planning stays) | ~80 |
| `glossql_kept(...)` calls | views kit `:342`; goals `:48`, `:322` | 3 |

About 410 lines of C++ go. Counterpart: `g_edge`, a result `id`, `g_changed_since`/`g_after` (30 lines SQL), due and the batched detector run (≈90 lines Python here), lineage reads over rows.

## 7. Open decisions for the project lead

1. **Detector grain.** Recommend: a detector judges one subject's values; it runs over the due subjects as one batch and its result is stored per (subject, test). SPEC §7.2 ("Detectors run at read", "one query over the test's annotations") changes. A cross-subject detector: refuse at `DECLARE TEST` when the body has a window or reads beyond `annotations`, or store it per (dataset, test) reading the set node. Recommend refuse; no kit needs it today.
2. **Many results in one write.** Recommend a result `id` in `measurements` and `inputs`; one write per function per round.
3. **The marks at read.** Recommend accept 40–60 ms at 500k now and compute the marks once per statement for the composed reads; measure on Postgres before deciding more.
4. **Stale rule by snapshot.** Recommend snapshot (one version), with a definition row at a load whose derivation differs; the retype-and-back case stays stale.
5. **Kit edges from an annotation's body.** They work as a stored result (G) but read in 2.8 ms for 10,000 scenarios. Recommend: store what needs planning (a view's lineage); read edges that are a field of one catalog row.
6. **A workspace-wide declaration.** Recommend each dataset brings its results current at its next write, and `next` lists them as due meanwhile.
7. **Read-only attach.** Recommend serve stored rows marked; no detector at read.
