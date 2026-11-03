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

Steps 1 to 5 are the port, built in order; step 6 is the house in
order after it, its rows independent and listed in risk order.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Steps 1–4: the doors on `duckdb-neo`; the vocabulary, quality, metrics and futures kits; the routes and the docket on the engine | Built; the gates passed (below) | `crates/duck`, `../gloss/kits`, `apps`, `serverd` | | |
| Step 5: the cut-over — DuckDB the only engine, the session crates deleted, the image and the release carrying the extension, the docs and skills on the engine | Built on the laptop (below) | `.github/`, the image, `docs/`, `skills/`, the crates deleted | | |
| Step 6a: the runner's green — CI and a tag build on the pushed extension; the deployment shape run once against a Postgres catalog and an object store; glossval's slot image on the engine | Low to medium: the extension's hour on a runner; the secret DuckDB's httpfs reads | `.github/`, the Dockerfile, `crates/duck` (the secret at open), glossval's `evals/serverd.Dockerfile` | Next | |
| Step 6b: the renames — this repository `glossdb`, the extension's `glossql`; SPEC.md, `grammar.ebnf` and the corpus move to the language's repository; the binary, the image, the tap, the env names follow the lead's call | Medium: every consumer names the repositories — the tap formula's URL, the image name glossdeploy pins, the clone in CI and the Dockerfile, the sibling paths in glossval, the memory directory keyed by the checkout's path | both repositories, `.github/`, glossdeploy, glossval, `CLAUDE.md`, the skills | After 6a | |
| Step 6c: DataFusion out of the tree — the stream type and the error a plain Arrow stream, the parquet and csv writers their own crates, the SQL parser `sqlparser`; then the parser crate shrinks to the call shape or the extension serves it | Medium: 341 of 546 crates leave (measured by `cargo tree`); the parser's 2k lines sit on `datafusion-sql` | `crates/duck` (`call_shape`, the stream), `apps` (`ipc`, `export`), `serverd` (`wire`), `parser`, `deny.toml` | After 6b | |
| Step 6d: the validation detector — no kit ships `rate_tolerance`; the checks arm and `validate.md` name a detector the extension refuses as undeclared | Low: 27 lines of SQL in the quality kit, a `.test` case, the skill page | `../gloss/kits/quality`, `door.sql`, `skills/glossql-metrics/references/validate.md` | With 6a | |
| Step 6e: the duckdb-rs features — `bundled` with `json` and `parquet` in place of the prebuilt library; the probing features off | Low: a Cargo line. Measured on the laptop: a clean release build of `duck` with `bundled` takes 4 min 23 s, about 3 min of it DuckDB's C++ on 8 jobs, cached in `target/` after; the extension loads into the static host and the engine's suite passes; ducklake and httpfs stay loadable files. Open: the Linux link needs the host's symbols exported (`--export-dynamic`), estimated one linker line, checked in 6a's image build | the workspace `Cargo.toml`, `build.rs`, the Dockerfile, the release script | With 6a | |
| Step 6f: the plans and the issues on the engine — the other plan files rewritten or deleted, the open issues closed or rescoped (the draft below); `glossary` folded into `duck`; the cube and the session out of 41 code comments | Low | `.claude/plans/`, the issues, `crates/glossary`, comments | With 6b | |

## What stands

- **The DuckDB engine** (`crates/duck`: 3.4k lines of Rust, 2.5k of
  SQL under `crates/`, the engine's own tests). `Plane::open` loads
  the extension and `ducklake`, attaches the lake as `ws`, declares
  `core.sql`, the kits in order and `door.sql`, and composes one
  `next` view from every `routes_<kit>()` macro. A channel is one
  connection: the grammar on, the actor as session variables, the
  dataset in use. `execute` splits statements and answers outcomes;
  `query_page` cuts one row past the cap and never cuts a record
  read; the brief's counts are one read; `rulings::land` folds a
  ruling into the standing body.
- **The extension** (`../gloss`, branch `kit-quality`, pinned by
  `crates/duck/gloss.ref`): the kpi, quality, metrics and futures
  kits with their `.test` suites; a QUERY aspect's claims are the
  view's columns' (fixture 28); `behavior` takes `ratio`; the record
  read planned once and cached under the store's version. The futures
  kit calls the model service through `gloss_service`; the plan is
  judged as a measurement; a lever is a view column, no replay.
- **The gate, measured.** serverd 53 and 14 unit tests, apps 35, the
  engine's 6, the parser's 48; clippy, fmt, deny and machete clean.
  A call's `next` costs about 120 ms on a laptop, `owed` 60 ms, a
  gloss read 20 ms on a fresh connection. Both eval lanes grade three
  seats on DuckDB equal to the session's rows.
- **The cut (step 5).** The session, catalog, import and scripts
  crates are gone (67k lines); `glossary` keeps the actor types. The
  build and the image obtain the extension at the pinned commit: CI
  builds it once per pin into the actions cache, the Dockerfile in a
  stage of its own (`-DGLOSS_LAKE=OFF`, the lake extensions installed
  from DuckDB's repository), the macOS tarball from the sibling
  checkout. The binary carries a run path to `lib` beside its `bin`;
  the engine finds the extension, the kits and the lake extensions in
  `share/glossql` beside it, else where `GLOSS_EXTENSION`,
  `GLOSS_KITS` and `GLOSS_EXTENSION_DIR` say, else the dev checkout.
  Measured on the laptop: the image built with Apple's `container`
  (the extension stage about 7 min, the Rust stage about 4 min; a
  context under the system temp directory reaches the builder VM
  empty, so it is staged under the repository), the doors answer, a
  dataset declares through the MCP door with the kits standing. The
  docs and skills harness binds every single read through `EXPLAIN`
  on a fresh workspace; the vendored guide is DuckDB's. SPEC.md names
  the series read where it named the cube; the misfit door (fixture
  20) stays a ruled form, not built.
- **What the port left out, by name.** `behavior_evidence` (the
  behaviour is a gloss on the view's value column, the cadence the
  ladder's), `dimension_relevance` (the axes are the `role` and
  `dimension` glosses), the scenario's replay through the groundings
  (the lever's effect is the service's estimate), the misfit door,
  `source_files()` (a `PROBE` over `glob`), the ADBC relational
  source (a database DuckDB attaches; not exercised on the engine
  yet), the per-point service names (one `GLOSSQL_SERVICE_URL`), the
  cube cache, the live suites against a Postgres catalog.

## The next row, drafted

**Step 6a: the runner's green.** What it buys: the standing invariant
checked by a machine again, and a release that carries the engine.
What stands: `ci.yml` builds the extension from `crates/duck/gloss.ref`
into the actions cache and runs the suites on it; the Dockerfile
builds the extension in its own stage; `release-macos.sh` refuses
unless `../gloss` is at the pin. What is open: the extension's branch
is not pushed, so a runner cannot check the commit out; the
deployment shape (`Config::deployment`) has no secret for the object
store, which DuckDB's httpfs reads from `CREATE SECRET`; glossval's
slot image (`evals/serverd.Dockerfile`) builds the binary alone and
needs the same stage; glossdeploy names four variables the server no
longer reads (`GLOSSQL_ALLOWED_HOSTS`, `_ORGANIZATION`, `_TABICL_URL`,
`_TABICL_AUDIENCE`), which move at the next deploy. Done when: CI
green, a tag builds and pushes the image, one run of the image against
a Postgres catalog and a bucket lands a table, the eval's slot image
serves a lane.

**The issues, for 6f.** Close as built or gone: #19 (the landing path),
#21 (the cube's stack), #23 (the collapse per witness), #33 (the
pre-pass), #55 (a DataFusion planner bug), #58 (the file reader),
#80 (the docs after the data plane change; the dev rig is gone and
the app door's two writes are stated). Rescope to the engine, the
text rewritten over the kit's files: #5 (the strike holds on the
extension; aspect re-declare), #41 (a measure that does not compose
from members, on `metric_series`), #42 (metric retirement, on
`metric_surfaces`), #60 (an infrastructure error's text, on the
facade's errors), #92 (consumer reads: a DuckLake client with the
extension loaded), #101 (an Iceberg source: a `type` in §3 and
DuckDB's `iceberg` extension), #174 (the recommendations read over
the futures kit's reads). Keep as they are: #20 (the docket as a
`ui://` resource), #24 (`key` in the grounding schema, now the kit's
contract), #56 (Tera 2). The plans: `kits.md` is built and goes;
`lineage.md` and `sources.md` are rewritten on the extension's
lineage and DuckDB's readers; `kernel.md`, `clients.md` and `chat.md`
lose their session paths; `modules-design.md`, the port's design,
goes once this file states what stands.
