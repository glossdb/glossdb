# Dependency plan

How glossdb decides that something is outdated, and when it computes
it again. Today this is one base rule with exceptions added case by
case. This plan replaces that with one concept, agreed before any
further code. Until then the topic is frozen: no new exception, no
new clause. `DEPENDS ON` is built and provisional.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The project lead chooses from "The choices" below | — | this file | Next | |
| Checks run once per call against one fill of the reads; storing a result does not empty the reads of other datasets or of readers that did not read it | Medium: the read cache's key is the centre of the extension's read path | the extension (`glossql_store.cpp:1636-1906`), `crates/duck/src/lib.rs:1742-1865` | First: it removes most of a write's 6 s without changing what counts as outdated | |
| The extension's own table functions report what they read (`GLOSSARY()`, `dataset_cells`), so a body that reads the catalog through them no longer records "everything" | Medium | the extension (`glossql_runner.cpp:961-1071`) | Second | |
| Catalog dependencies at the grain the matrix names | High: it changes `SPEC.md` §5 and §6 | the extension, the spec, the kits | Third | |
| A content version for a table, so a reload of the same rows outdates nothing | Low: DuckLake's change feed gives it | the extension (`PartsSQL`) | With the third | |
| A property that carries a test's expectation is required only where it is annotated. Today `GLOSSARY()` reports it as missing on every other asset of its kind; the kits ignore that, six console frames do not (`vocabulary`, `aspect_head`, `aspect_values`, `column_values`, `measured`, `unmeasured`) | Medium: it changes what "required" means in `SPEC.md` §5 | the extension (`GLOSSARY()`), the console frames | With the third | |
| The 13 places where spec, docs or comments contradict the code are corrected with each step | Low | both repositories | With each step | |

## The matrix: what is outdated by what, today

Rows are what can be outdated; columns are what changed. "all" means
every result of that kind in the workspace or dataset.

| | Load of a table it read | Load of another table | Annotation it read | Annotation elsewhere | Another function's result | Declaration |
|---|---|---|---|---|---|---|
| Annotation | only if the column was retyped, dropped or derived differently | no | — | no | no | no |
| Result of a function over data only (profiles) | yes | no | — | no | no | its own, newer |
| Result of a built-in check (reads the catalog) | yes | **yes** (all tables of the dataset) | yes | **yes** (any write to that catalog table, any dataset) | yes, per function, **any dataset** | its own, newer |
| Preview result (with `DEPENDS ON`) | yes | **yes** (all tables of the dataset) | yes | no | no | its own, newer |
| Test result | follows the results it scores | | | | | |
| The kept reads (glossary, tests, view rows) | **all emptied by any write, any dataset** | | | | | |

The bold cells are wrong against the spec's own sentence, "a write
the body never reads is not its staleness". A reload of identical
rows counts as a load in every cell.

## What is there

- **Data** is versioned per table by the lake's snapshots.
- **The catalog** is versioned per whole relation, with no dataset
  filter. Other functions' results are versioned per function, with
  no dataset or subject.
- **Why "all tables" appears.** A body's reads are taken from its
  plan. The extension's own table functions (`GLOSSARY()`,
  `dataset_cells`) appear in the plan as opaque scans, so the body is
  recorded as reading everything. All four view checks and all four
  preview functions are in this state. It is our own functions that
  hide the reads, not the engine.
- **What the engine can tell.** The bound plan names tables and
  columns through views and macros. After the optimizer it also gives
  the constant filters on each scan, for example `subject = '…' AND
  aspect = 'meaning'` on the glossary. It cannot tell rows selected
  through a join. `json_serialize_sql` gives the text's parse tree
  only: no views, no macros.
- **When things run.** After a call that annotates, defines or loads,
  the server runs the built-in checks for every metric that scans the
  touched table: 12 results for three metrics. Once per call, not per
  statement. Test results and `next` are computed at read.
- **The exceptions on top of the base rule:** nine in the extension
  and five in the server, each added for one case within two weeks.

## Measured

Release build, Formula 1 workspace (9 tables, 5 views, 3 metrics).
The build mode of the server does not change these numbers.

| Call | Time |
|---|---|
| Any call (of which the closing read of `next`: 0.47 s) | 0.47 s |
| A read of `next` | 0.92 s |
| An annotation on a table no view scans | 1.3 s |
| An annotation on a table a view scans | 6.0 s |
| A reload of one table, same file | 5.5 to 7.8 s |
| 104 annotations in one call | 7.6 s |

Where the 6.0 s go: 0.8 s the write and the first check; 3.9 s the
other 11 checks; 1.3 s the closing `next`. Each stored result moves
the one store version, so the next check fills the glossary read
again: about 12 fills of 0.4 s. The time is planning (binding and
optimizing), not execution. A warm read of the glossary is 0.011 s.

## Prior art

- **Build systems** ("Build systems à la carte"): a system is a
  scheduler and a rule for validity. Ours is a verifying trace with
  version numbers. With content hashes it gains early cutoff: a
  rebuilt input with the same value stops there.
- **Salsa:** one revision counter per class of input ("durability"),
  so a change in one class does not make results over another class
  check again. Our store version is one counter for everything.
- **dbt, Dagster:** declared dependencies; a code version and a data
  version per asset; an observed version for outside data, which is
  the place for the model service's version.
- **Bazel:** a step can read only what it declared. Here: a body
  reads the catalog only through reads that report themselves.
- **DuckLake's change feed** gives the rows a snapshot changed. Three
  reloads of the same file showed every row as updated and no row
  different.

## The choices

1. **Where dependencies come from.** Discovered from the plan, with
   our own table functions reporting what they read (recommended:
   nothing for an author to write, and it removes "everything").
   Declared by the author (`DEPENDS ON`) stays only if a case remains
   that discovery cannot see; otherwise it is removed.
2. **The grain for the catalog.** Per dataset and property
   (recommended: the optimizer's filters give it, and it removes
   every bold cell but the ones about data), or per asset and
   property (finest; needs a rule for filters that are not
   constants).
3. **When checks run.** Once per call, after all writes, against one
   fill (recommended: keeps "what is stated is tested" true at the
   end of every call). Or at the next read of `next` or of the tests.
4. **Identical reloads.** Compare content through the change feed
   (recommended), or keep counting every load.

## Next issue (draft)

**One fill per call.** What it buys: an annotation on a scanned
table costs about 2 s in place of 6 s, with no change to what counts
as outdated. What is there: the read cache keyed by one store
version (`glossql_store.cpp:1636-1906`); `built_in_tests`
(`crates/duck/src/lib.rs:1762-1865`); the measurements above. Done
when: storing a result leaves the kept glossary read in place for
readers that did not read that result; the checks of one call run
against one fill; the six calls above are measured again and in this
file; both suites pass.
