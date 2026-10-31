# The modules plan

One binary in one image: MCP, the app, the query door, import and
export in one process. The engine is ruled: DuckDB with DuckLake, and
the gloss extension (`../gloss`) owns the language, the store and the
kits; this repository owns the doors. The design, with the diagrams,
the seams and the port's steps, is `modules-design.md` (§7); this
file is the plan. The frame is `kernel.md`; the content tree is
`kits.md`.

The rules:

- **The new path beside the old.** Each step builds on DuckDB behind
  the `duck` feature of `serverd` and `apps` and is measured at a
  gate; the session crates are not touched before the cut-over, and
  then deleted, never refactored.
- **Engine types stop at the facade**: a door sees batches, a schema,
  a wrapped stream, string parameters; `crate::engine` is the one
  name for whichever engine the build carries.
- **Kits are DuckDB SQL** and live with the extension, their `.test`
  suites beside them; the record's own words and the doors' derived
  reads live in `crates/duck/kits/core.sql`.
- **A test the DuckDB build cannot run yet is marked**
  `cfg(not(feature = "duck"))` with its reason on the line above; the
  mark leaves with the step that serves it.
- **The doors stay closed** (`kernel.md`, "Not now").

## The table

Build order is the port's order: each step needs the one before it,
and the risk sits in the middle.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Step 1: the three doors on `duckdb-neo` over the extension's record and lake — channels, statements, reads, the row cap, the brief, the question round, rulings, glossed apps | Built; the gate passed (below) | `crates/duck`; `serverd` and `apps` under `duck`; the door suites | | |
| Step 2: the vocabulary and quality kits as SQL with `.test` suites | Built, on `../gloss` branch `kit-quality` (`kits/quality/kit.sql` over `dataset_cells`) | the extension | | |
| Step 3: the metrics kit — the grounding schema, the metric reads, the shipped reads (`next`, `workspace_next`, `owed`, `app_releases`, `metric_surfaces`), the metrics and slices goals, the docket's frames | High: the `period`/`value` convention against the judged axes is the lead's ruling; the routes carry 893 lines of tests | `../gloss/kits`, `core.sql`; `crates/session/reads/*.sql` and `cube.rs` as the source to port | Next; ten to fourteen days | drafted below |
| Step 4: the futures kit with the service calls from the host; the scenario's replay deferred | Medium: forecast and bands through the service; the plan as a declared table | `../gloss/kits`; `crates/scripts` (the service client carried over) | After step 3; ten to sixteen days | |
| Step 5: the cut-over — the image and the release carry DuckDB and the extension; `duck` the only build; session, catalog, import's DataFusion half, the kernels and their tests deleted; docs and skills | Medium: the release machinery (`glossql-release`); CI fetching the extension | `.github/`, the image, `docs/`, `skills/`, the crates deleted | After step 4; six to nine days | |

## What stands

- **The DuckDB engine** (`crates/duck`: 1,287 lines of Rust, 139 of
  SQL, 235 of tests). `Plane::open` loads the extension and
  `ducklake`, attaches the lake as `ws`, declares `core.sql` and the
  kits. A channel is one connection: the grammar on, the actor as
  session variables, the dataset in use, a search path of the
  dataset's schema, the store's, and the instance's in-memory
  database that holds the door pages as `pages()`. `execute` splits
  statements and answers outcomes; `query_page` cuts one row past the
  cap and never cuts a record read; a named parameter binds only where
  the statement spells it; the brief's counts are one read;
  `rulings::land` folds a ruling into the standing body. Both engines
  compile; `duck` is off by default, so CI is unchanged.
- **Core** (`crates/duck/kits/core.sql`): the record's aspects
  (`recipe_change`, `ruling`, the app parts) and the derived reads
  `current_dataset`, `agent_assumptions`, `ruling_entries`,
  `open_questions`, replaced at every open.
- **The gate, measured.** On DuckDB: serverd 46 of 46, apps 11 of 11,
  the engine's own 3. On the session engine: serverd 66, apps 38, all
  green. Marked session-only with a reason: serverd 21 (the next
  routes 8, bootstrap 3, the judge 2, six door tests — the next line,
  the affordance map, the metric reads, the kit's witnesses — one docs
  and one skills read), apps 27 (25 that seed the cube and the judged
  axes in the session's SQL, the landing's refused cells,
  `app_releases`).
- **The extension** (`../gloss`, branch `kit-quality`, four commits):
  the quality kit and the temporal profile; `AS QUERY ON DATASET`
  lands as no grain, as the docs and skills spell it. Its suite: 11
  files green.
- **Conventions the port fixed.** The extension keeps a subject
  dataset-qualified (`fin.t.a`) and the session as spelled; the app
  door gives the prefix back. `written_at` is a TIMESTAMP, rendered
  by the door's one formatter. DataFusion 55 types `VARCHAR` as
  `Utf8View`, so a door decodes a cell by value, never by a downcast.
  `at` and `lambda` are reserved words in DuckDB. A kit's `$subject`
  is spelled bare; optional typed keys are `["type", "null"]`.

## Decisions that are the lead's

- How the build, CI and the image obtain the extension: today a path
  into `../gloss/build` (`GLOSS_EXTENSION`, `GLOSS_KITS`, or the
  default beside the checkout); a release of `../gloss` per platform,
  or a CI build of it, for the image and for CI to run the `duck`
  suites.
- The `period`/`value` convention of the metric reads against the
  judged axes: step 3's first question.
- Whether relative subjects (`FROM work_orders.duration_min` under a
  `USE`) are the extension's to resolve; today it takes the
  dataset-qualified form, and the docs spell the relative one.

## The next row, drafted

**Step 3: the metrics kit.** What it buys: the metrics and slices
goals on DuckDB, so the next read, the question round's forms and the
docket's metric pages answer from one SQL record, and the cube's Rust
(`cube.rs`, 4,000 lines) has nothing left to serve. What stands: the
grounding schema (SPEC §5.2) and the four metric reads in
`crates/session/src/cube.rs` (`metric_series_batch` at 4117–4227,
`metric_axes`, `fact_values`, `metric_sources`); the series read as
32 lines of SQL in `../gloss-neo-spike/kit/series.sql`; the nine
shipped reads in `crates/session/reads/` with `next.sql` the routes;
the docket's 52 frames in `crates/apps/builtin/docket/frames/`; the
tests marked session-only above. Done when: the metrics kit declares
the grounding schema and the reads as macros with a `.test` suite
holding the server's fixtures; the shipped reads stand in `core.sql`
or the kit; the `next` suite and the six door tests run under `duck`
with their marks gone; the docket's metric pages render under `duck`
with the 25 marks gone; one glossval run compares.
