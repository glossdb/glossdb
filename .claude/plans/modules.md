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
| Step 3: the metrics kit — the ladder fact on time columns, `behavior` with `ratio`, the reads as macros over the view's own slots, the shipped reads, the routes per kit and the composed `next`, the docket's frames in DuckDB SQL | Built; the gate passed (below); the glossval run is open | `../gloss/kits/metrics`, `core.sql`, `door.sql`, `docket/duck/frames` | | |
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
- **The extension** (`../gloss`, branch `kit-quality`): the quality
  kit, the temporal profile, a view and its columns as subjects
  (`test/sql/gloss_views.test`), the metrics kit
  (`kits/metrics/kit.sql`, `test/sql/gloss_kit_metrics.test`: the
  ladder, `metric_axes()`, `metric_series(grain, unclaimed)`,
  `fact_values()`, `metric_sources(for_metric)`, `routes_metrics()`),
  `gloss_views_lineage(dataset)`, and the record read planned once
  (seven witnesses: 4 s to 0.5 s). Its suite: 12 files green. A QUERY
  aspect takes no grain clause; the grounding contract is open and the
  claims are the view's columns' (fixture 28); `behavior` takes `ratio`
  with its halves; the KPI kit declares no grounding schema.
- **Step 3's server half.** `door.sql` (after the kits): `owed` and the
  core routes; `core.sql`: `app_parts`, `app_releases`,
  `metric_surfaces`, `workspace_next`. The engine composes one `next`
  view at open from every `routes_<kit>()` macro's CTE and arm text
  over the relations it reads once (`ds`, `axes`, `owed`, `reds`,
  `bodies`, `applicable`); a grounding's write answers with the
  metric's fact row; an extraction runs unwrapped; re-measure runs the
  stale and the wanted measurements. The docket's 52 frames stand in
  DuckDB SQL under `builtin/docket/duck/frames`, the pages shared; the
  futures frames (breaches, corridor, check points, movers, plan) serve
  no row until step 4.
- **The gate, measured.** On DuckDB: serverd 55 of 55 (the routes
  suite: a fresh dataset routes every goal, a metric walks from its
  claim to its behaviour, the next page carries the forms), apps 34 of
  34, the engine's own 3; on the session engine: serverd 66, apps 38,
  the whole workspace green. Still marked session-only, with reasons:
  serverd — the next suite (its harness is the session's; the routes
  suite is its DuckDB counterpart), bootstrap, the judge, the docs and
  skills reads (their examples spell the session engine's reads, step
  5), the points test (step 4); apps — the corridor and the plan
  (step 4), the landing's refused cells (step 5), the frame parse test
  (the DuckDB frames parse in the engine). `next` reads the record once
  per relation, about 2 s on a laptop; the record read's planning is
  the extension's next performance lever.
- **Conventions the port fixed.** The extension keeps a subject
  dataset-qualified (`fin.t.a`) and the session as spelled; the app
  door gives the prefix back. `written_at` is a TIMESTAMP, rendered
  by the door's one formatter. DataFusion 55 types `VARCHAR` as
  `Utf8View`, so a door decodes a cell by value, never by a downcast.
  `at` and `lambda` are reserved words in DuckDB. A kit's `$subject`
  is spelled bare; optional typed keys are `["type", "null"]`.

## Parked until the switch

- How the build, CI and the image obtain the extension: today a path
  into `../gloss/build` (`GLOSS_EXTENSION`, `GLOSS_KITS`, or the
  default beside the checkout); a release of `../gloss` per platform,
  or a CI build of it, for the image and for CI to run the `duck`
  suites. Settled at step 5, with the release machinery.

## The next row, drafted

**Step 4: the futures kit.** What it buys: the bands, forecast, plan
and scenario worlds on DuckDB through the service calls from the host,
the plan as a declared table, the scenario's replay deferred; the
docket's corridor, breaches, check points, movers and plan frames
serve again. What stands: `crates/scripts` (the service client), the
session's `metric_bands`, `metric_forecast`, `band_points`,
`forecast_points`, `plan_points`, `scenario_points` as the source to
port; the worlds' framing is a discussion with the lead first. Done
when: the futures kit declares its aspects and functions; the service
points are declared on the engine; `metric_series(world := …)` serves
the worlds; the bands and plan goals route; the marked step 4 tests run
under `duck`; the futures frames serve rows.
