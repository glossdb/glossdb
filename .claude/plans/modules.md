# The modules plan

One binary in one image: MCP, the app, the query door, import and
export in one process. The engine is ruled: DuckDB with DuckLake, and
the gloss extension (`../gloss`) owns the language, the store and the
kits; this repository owns the doors. The design, with the diagrams,
the seams and the port's steps, is `modules-design.md` (§7); this
file is the plan. The frame is `kernel.md`; the content tree is
`kits.md`.

The rules:

- **Each step is measured at a gate**: a suite, a lane of the eval,
  a number through the door. The old path was deleted at the cut,
  never refactored.
- **Engine types stop at the facade**: a door sees batches, a schema,
  a wrapped stream, string parameters; `crate::engine` is the one
  name for the engine.
- **Kits are DuckDB SQL** and live with the extension, their `.test`
  suites beside them; the record's own words and the doors' derived
  reads live in `crates/duck/kits/core.sql` and `door.sql`.
- **The doors stay closed** (`kernel.md`, "Not now").

## The table

Build order is the port's order: each step needs the one before it,
and the risk sits in the middle.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Step 1: the three doors on `duckdb-neo` over the extension's record and lake — channels, statements, reads, the row cap, the brief, the question round, rulings, glossed apps | Built; the gate passed (below) | `crates/duck`; `serverd` and `apps` under `duck`; the door suites | | |
| Step 2: the vocabulary and quality kits as SQL with `.test` suites | Built, on `../gloss` branch `kit-quality` (`kits/quality/kit.sql` over `dataset_cells`) | the extension | | |
| Step 3: the metrics kit — the ladder fact on time columns, `behavior` with `ratio`, the reads as macros over the view's own slots, the shipped reads, the routes per kit and the composed `next`, the docket's frames in DuckDB SQL | Built; the gate passed (below); glossval's f1 seat on DuckDB equals the session's score, and the tpcds seat grades the weekly stock at month and per warehouse right, `glossval/notes/duckdb-first-run.md` | `../gloss/kits/metrics`, `core.sql`, `door.sql`, `docket/duck/frames` | | |
| Step 4: the futures kit over the service seam — the walk, the forecast and the plan worlds, the scenario's estimate; the service owns its topic | Built; the four worlds measured and graded on three seats (below) | `../gloss/kits/futures` over `gloss_service`; glossthesi `/forecast` and `/whatif`; `crates/duck`, `serverd`'s config; the docket's futures frames | | |
| Step 5: the cut-over — DuckDB the only engine, the session crates deleted, the image and the release carrying the extension, the docs and skills on the engine | Built on the laptop (below); open: CI and the image on a runner need the extension's commit pushed, the deployment's object-store secret, the eval's own image | `.github/`, the image, `docs/`, `skills/`, the crates deleted | | |
| Step 6: the runner's green — CI and a tag build on the pushed extension; the deployment shape run once against a Postgres catalog and an object store; glossval's slot image on the engine | Low to medium: the extension's hour on a runner; the secrets DuckDB's httpfs reads | `.github/`, the Dockerfile, `crates/duck` (the secret at open), glossval's `evals/serverd.Dockerfile` | Next | |

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
  `rulings::land` folds a ruling into the standing body.
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
  DuckDB SQL under `builtin/docket/frames`, the pages shared.
- **The gate, measured.** The workspace suite on the engine: serverd
  51 and its 14 unit tests (the routes suite: a fresh dataset routes
  every goal, a metric walks from its claim to its behaviour, the next
  page carries the forms; the docs and skills harness binding every
  read), apps 35, the engine's own 6, the parser's 48. The extension keeps a
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

- **The cut (step 5).** The `duck` feature is gone and the session,
  catalog, import and scripts crates with it (67k lines); `glossary`
  keeps the actor types; `duck` links the engine, `apps` and
  `serverd` build on it alone. The build and the image obtain the
  extension from its repository at the commit `crates/duck/gloss.ref`
  names: CI builds it once per pin into the actions cache, the
  Dockerfile builds it in a stage of its own (`-DGLOSS_LAKE=OFF`, the
  lake installed from DuckDB's repository into `share/glossql/extensions`),
  the macOS tarball takes it from the sibling checkout at the pin.
  The binary carries a run path to `lib` beside its `bin`; the engine
  finds the extension, the kits and the lake extensions in
  `share/glossql` beside the binary, else where `GLOSS_EXTENSION`,
  `GLOSS_KITS` and `GLOSS_EXTENSION_DIR` say, else the dev checkout.
  The memory ceiling and the spill bound are the engine's settings;
  the cube cache is gone. Measured on the laptop: the image built with
  Apple's `container` (the extension stage ~7 min native, the Rust
  stage ~4 min; a context under the system temp directory reaches the
  builder VM empty — stage it under the repo), the doors answer, a
  dataset declares through the MCP door with the kits standing (29
  aspects, 17 functions, 11 witnesses). The docs and skills harness
  binds every single read through `EXPLAIN` on a fresh workspace; the
  vendored guide is DuckDB's (`vendor/duckdb`, 73 pages at a pinned
  duckdb-web commit). Every docs and skills page states the engine:
  the reads reference from the kits' own words, the methods pages on
  the kits' screens, the behaviour-evidence page retired.


## The next row, drafted

**Step 6: the runner's green.** What it buys: the standing invariant
checked by a machine again, and a release that carries the engine.
What stands: `ci.yml` builds the extension from `crates/duck/gloss.ref`
into the actions cache and runs the suites on it; `release.yml` is
unchanged and the Dockerfile builds the extension in its own stage;
`release-macos.sh` refuses unless `../gloss` is at the pin. What is
open: the extension's branch is not pushed, so a runner cannot check
the commit out — the lead's push comes first; the deployment shape
(`Config::deployment`, a Postgres catalog and an object-store data
path) has no secret for the store — DuckDB's httpfs reads a secret
the plane does not create yet; the deployment's `gs://` warehouse
needs that and nothing else; glossval's slot image
(`evals/serverd.Dockerfile`) still builds the binary alone and needs
the same stage. Done when: CI green on main, a tag builds and pushes
the image, one run of the image against a Postgres catalog and a
bucket lands a table, the eval's slot image serves a lane.

