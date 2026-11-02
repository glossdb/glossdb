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
| Step 3: the metrics kit — the ladder fact on time columns, `behavior` with `ratio`, the reads as macros over the view's own slots, the shipped reads, the routes per kit and the composed `next`, the docket's frames in DuckDB SQL | Built; the gate passed (below); glossval's f1 seat on DuckDB equals the session's score, and the tpcds seat grades the weekly stock at month and per warehouse right, `glossval/notes/duckdb-first-run.md` | `../gloss/kits/metrics`, `core.sql`, `door.sql`, `docket/duck/frames` | | |
| Step 4: the futures kit over the service seam — the walk, the forecast and the plan worlds, the scenario's estimate; the service owns its topic | The four worlds built and measured (below); open: the forecast lane's switch and the other plan seats' setups | `../gloss/kits/futures` over `gloss_service`; glossthesi `/forecast` and `/whatif`; `crates/duck`, `serverd`'s config; the docket's futures frames | In progress; one to two days left, estimated | |
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
  (`current_dataset`, the assumptions, the rulings, the open questions), replaced at every open.
- **The extension** (`../gloss`, branch `kit-quality`): the quality
  kit, the temporal profile, a view and its columns as subjects, the
  metrics kit (the ladder, `metric_axes()`, `metric_series()`, the
  routes), the lineage of views, the record read planned once (seven
  witnesses: 4 s to 0.5 s). A QUERY aspect takes no grain clause; the
  grounding contract is open and the claims are the view's columns'
  (fixture 28); `behavior` takes `ratio` with its halves.
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
  (the DuckDB frames parse in the engine). The extension keeps a
  dataset's record read in the instance's object cache under the
  store's version, shared by every connection, so a call's `next`
  costs about 120 ms on a laptop, `owed` 60 ms and a gloss read 20 ms
  on a fresh connection; the first read after a write computes the
  rows once, about 300 ms. Connections stay per call, as on the session.
- **Conventions the port fixed.** The extension keeps a subject
  dataset-qualified (`fin.t.a`); the app door gives the prefix back.
  `written_at` is a TIMESTAMP, rendered by the door's one formatter. A
  door decodes a cell by value, never by a downcast. A kit's `$subject`
  is spelled bare; optional typed keys are `["type", "null"]`.

## Parked until the switch

- How the build, CI and the image obtain the extension: today a path
  into `../gloss/build` (`GLOSS_EXTENSION`, `GLOSS_KITS`, or the
  default beside the checkout); a release of `../gloss` per platform,
  or a CI build of it, for the image and for CI to run the `duck`
  suites. The binary links `libduckdb.dylib` by `@rpath` and carries
  none: the image ships the library beside the binary, a laptop release
  binary gets an rpath onto libduckdb-sys's `out/`. httpfs is installed
  like ducklake and named explicitly: `gloss_service` needs it for POST
  and TLS. Settled at step 5, with the release machinery.

## The next row, drafted

**Step 4: the futures kit.** What it buys: bands, forecast, plan and
scenario on DuckDB through one seam — `gloss_service(route, body)` in
the extension, JSON each way, the service named once per instance
(`gloss_service_url`, `_token`, `_timeout`; httpfs loaded beside
ducklake) — and the service owning its topic: the walk answers per
metric the held shares, the newest point's displacement and a verdict
banded against a threshold, the withheld rule its own; the calendar
stays the caller's, so the kit sends complete buckets only. What
stands: `gloss_service` and an extraction running its body once
(`../gloss` af97f6a, 182981b), measured on the tpcds workspace: the
walk of six metrics one call of 0.1 s, the extraction 0.67 s, a repeat
served. The three worlds (`../gloss` 9ef6cf2, a5789ab, 3793dcc; glossql
88dc254, 28f39d9): glossthesi's walk verdict (branch `walk-verdict`);
the walk and the forecast as measurements on the dataset; the plan a
QUERY aspect `x-kind: plan` read through its metric (`x-plan-of`), its
judgement a measurement on the plan (`metric_plan`, witness `plan_w`),
under the rule that an arm of `next` reads the record and never the
data; the host naming the service at open and refreshing the ID token;
the bands and plan goals routed, the futures frames served. Measured
through the door on the tpcds copy: `next` 0.28 s with a plan judged
(0.95 s before the rule); a dataset's views kept once per store version
and the cells read bound over the views alone, so the series read is
0.2 s of its own SQL and reads no table. The glossval plan lane grades
the tpcds seat on DuckDB as it graded the session (glossval 7d0a57e:
`--engine=duck`, a setup per metric, the judgement run as the forecast
is). The scenario (`../gloss` 1f2d6c9): a lever is a FACT on a column
of a metric's view, no grounding is replayed; a scenario is the actor's
FACT aspect with a factor per period; the estimate through `/whatif`
lands as `metric_scenario` with `scenario_w`, each lever's own forecast
as the planned input (held at its last value where the forecast is
refused, through the service call's soft form) and times the factor
under the scenario; `scenario_points()`, `scenario_levers()`, the
scenario world on the series read, the plan goal judging the gap under
it; live on Rossmann weekly from the what-if test data: a holiday
scenario estimated with a direction, a promotion scenario answered with
the history's bounds.
Next: the forecast lane's switch and the other plan seats' setups, then
step 5. Done when: every goal routes, the lanes grade, the frames serve
rows.
