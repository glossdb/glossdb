# The modules plan

One binary in one image: MCP, the app, the query door, import and
export in one process. The engine is ruled: DuckDB with DuckLake, and
the glossql extension (`../gloss`) owns the language, the store and the
kits; this repository owns the doors. The seams and their rules are
`docs/architecture/` and the glossql-substrate skill; this file is
the plan. The frame is `kernel.md`.

The rules:

- **Each step is measured at a gate**: a suite, a lane of the eval,
  a number through the door. The old path was deleted at the cut,
  never refactored.
- **Engine types stop at the facade**: a door sees batches, a schema,
  a wrapped stream, string parameters; `crate::engine` is the one
  name for the engine.
- **Kits are DuckDB SQL**, a `.test` suite beside each: the
  language's (kpi, quality, spatial) with the extension, the server's
  (metrics, futures) in `kits/` here; the record's own words and the
  doors' derived reads live in `crates/duck/kits/core.sql` and
  `door.sql`.
- **The doors stay closed** (`kernel.md`, "Not now").

## The table

Steps 1 to 5 are the port, built in order; step 6 is the house in
order after it, its rows independent and listed in risk order.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Steps 1–4: the doors on `duckdb-neo`; the vocabulary, quality, metrics and futures kits; the routes and the docket on the engine | Built; the gates passed (below) | `crates/duck`, `../gloss/kits`, `apps`, `serverd` | | |
| Step 5: the cut-over — DuckDB the only engine, the session crates deleted, the image and the release carrying the extension, the docs and skills on the engine | Built on the laptop (below) | `.github/`, the image, `docs/`, `skills/`, the crates deleted | | |
| Step 6a: the runner's green — CI and a tag build on the pushed extension; the deployment shape run once against a Postgres catalog and a bucket; glossval's lanes on the engine | Low to medium: the extension's hour on a runner. Built: the warehouse's credential (a key pair, or the platform's own account for a `gs://` bucket, minted before the lake opens and anew before it expires); glossval's slot is the server's own image | `.github/`, the Dockerfile, glossval's Rust crate (it names the deleted crates) | Next | |
| Step 6b: the renames — this repository `glossdb`, the extension `glossql` | Built here and in the extension: the packages, the binary, the image, the tap, the share directory, the server's `GLOSSDB_*` and the extension's `GLOSSQL_*` names, the extension's artifact, functions and variables. Open: the two GitHub renames, this repository first since it frees the name; the laptop's directory names, after which the dev default in `crates/duck/src/lib.rs`, the `../gloss` mentions and the memory directory follow; glossdeploy's image and env names and glossval's sibling paths at their next deploy | both repositories, glossdeploy, glossval | After 6a | |
| Step 6i: the language's record with its parser — SPEC.md, `grammar.ebnf` and the corpus in the extension's repository, held to the grammar by its own suite; the door serves the two documents from the extension's share; the two fixtures behind the server's kits stay here with `kits/README.md` | Built: 25 fixtures and the two documents moved; the extension's corpus test judges every block through `json_serialize_sql` (measured: 75 admitted and 15 SPEC blocks parse, 4 gaps fail) | | | |
| Step 6c: DataFusion and the parser crate out — the facade's own batch stream, the export door on the engine's `COPY … TO`, the call shape from the statements' text, the docs, skills and SPEC harness on the engine's parser | Built: 546 crates to 388 (measured by `cargo tree`); `crates/parser` deleted, `corpus/` beside SPEC.md | | | |
| Step 6d: the validation detector — `rate_tolerance` in the quality kit, bands the authored tolerance against the check voice per subject; the checks arm names it | Built: the kit's test runs the three bands (yellow, green, red); the pin moved | | | |
| Step 6e: DuckDB compiled in — `bundled` with `json` and `parquet`, the probing features off; no library file in the image or the tarball, no run path | Built. Measured on the laptop: the C++ about 3 min once per profile, cached in `target/`; the extension binds through the C API table and resolves no host symbol (its 287 undefined symbols are libc++'s), so Linux needs no linker flag; the Linux image built and run on the laptop (below) | | | |
| Step 6f: the house on the engine — the plans rewritten or deleted, `glossary` folded into `duck`, the code comments on the engine, the issues closed or rescoped (#5, #41, #42, #60, #92, #101 and #174 carry their rescope as a comment; their bodies follow) | Built | | | |
| Step 6h: the kits with their wrappers — the extension ships the language and its examples (kpi, quality, spatial); the metrics and futures kits are the server's and live in `kits/` here with their suites | Built: 1,938 lines of SQL and 980 of tests moved; the suites run under `cargo test` on the engine's own runner (`crates/duck/src/sqllogic.rs`, the four directives they use); one `share/glossdb/kits` in the image and the tarball carries both roots; SPEC's paragraph on the worlds (§9, lines 633–654) is the lead's cut | | | |
| Step 6g: the substrate allowlist — the docs and skills say DDL, DML and COPY are closed at the doors, and nothing closes them: the extension's conformance leaves the allowlist to the wrapper, and the facade runs every statement | Low to medium: the rule is the lead's (which door, which statements); a text rule in the facade's `execute`, estimated a day with its suite | `crates/duck` (`execute`), the door suites, `docs/concepts/statements.md`, `skills/glossql/references/sql-here.md` | After 6a | |

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
  `crates/duck/glossql.ref`): the language, the store, the kpi, quality
  and spatial kits with their `.test` suites; the language's record,
  SPEC.md, `grammar.ebnf` and the corpus, with the suite that holds it
  to the grammar; a QUERY aspect's claims are the view's columns'
  (fixture 28); `behavior` takes `ratio`; the record read planned once
  and cached under the store's version.
- **The server's kits** (`kits/`): metrics and futures with their
  suites, run by the engine crate's suite on the facade's own runner.
  The futures kit calls the model service through `glossql_service`;
  the plan is judged as a measurement; a lever is a view column, no
  replay.
- **The gate, measured.** serverd 54 door tests and 16 unit tests,
  apps 35, the engine's 8; clippy, fmt, deny and machete clean.
  A call's `next` costs about 120 ms on a laptop, `owed` 60 ms, a
  gloss read 20 ms on a fresh connection. Both eval lanes grade three
  seats on DuckDB equal to the session's rows.
- **The cut (step 5).** The session, catalog, import and scripts
  crates are gone (67k lines); `glossary` keeps the actor types. The
  build and the image obtain the extension at the pinned commit: CI
  builds it once per pin into the actions cache, the Dockerfile in a
  stage of its own (`-DGLOSSQL_LAKE=OFF`, the lake extensions installed
  from DuckDB's repository), the macOS tarball from the sibling
  checkout. DuckDB is compiled into every binary; the engine finds
  the extension, the kits and the lake extensions in `share/glossdb`
  beside it, else where `GLOSSQL_EXTENSION`, `GLOSSQL_KITS` and
  `GLOSSQL_EXTENSION_DIR` say, else the dev checkout. DataFusion and
  the server's own parser are gone with 6c: the doors drive the
  facade's batch stream, the export door is the engine's `COPY`, the
  call shape (the `USE`, a write, a review) is read off the text, and
  the harness parses every example and SPEC.md through the engine's
  parser, which is the door's.
  Measured on the laptop: the image with DuckDB compiled in built
  with Apple's `container` in about 8 min on 8 CPUs and 12 GB, the
  Rust stage after the extension stage (two DuckDB compiles at once
  exhaust the memory; the size goes on the build command, which
  recreates the builder to it; a context under the system temp
  directory reaches the builder VM empty, so it is staged under the
  repository); the doors answer, a dataset declares through the MCP
  door with the four kits standing. The
  docs and skills harness binds every single read through `EXPLAIN`
  on a fresh workspace; the vendored guide is DuckDB's. The worlds on
  the series read are `kits/README.md`'s, with fixtures 19 and 27.
- **What the port left out, by name.** `behavior_evidence` (the
  behaviour is a gloss on the view's value column, the cadence the
  ladder's), `dimension_relevance` (the axes are the `role` and
  `dimension` glosses), the scenario's replay through the groundings
  (the lever's effect is the service's estimate),
  `source_files()` (a `PROBE` over `glob`), the ADBC relational
  source (a database DuckDB attaches; not exercised on the engine
  yet), the per-point service names (one `GLOSSDB_SERVICE_URL`), the
  cube cache, the live suites against a Postgres catalog.

## The next row, drafted

**Step 6a: the runner's green.** What it buys: the standing invariant
checked by a machine other than the laptop, and the deployment shape
known to open. What stands: CI builds the extension from the pin into
its cache and runs the workspace suite with `GLOSSQL_EXTENSION` and
`GLOSSQL_KITS`; the image builds on the laptop in about 8 min; the
bucket's credential is built; glossval's slot is the server's image.
Done when: CI is green on the pushed pin, a tag build pushes the
image, the server opens once against a Postgres catalog and a bucket,
and glossval's two lanes grade on the image.

**The issues, after 6f.** Open: #20 (the docket as a `ui://`
resource), #24 (`key` in the grounding schema, now the kit's
contract), #56 (Tera 2), and the seven rescoped to the engine by a
comment, whose bodies are rewritten next: #5 (aspect re-declare under
glosses, refused as §3 says), #41 (a measure that does not compose
from members, on `metric_series`), #42 (metric retirement, on
`metric_surfaces`), #60 (an infrastructure error's text, on the
facade's errors), #92 (consumer reads: a DuckLake client with the
extension loaded), #101 (an Iceberg source: a `type` in §3 and
DuckDB's `iceberg` extension), #174 (the recommendations read over the
futures kit's reads). #27 is a language question for SPEC.md §9.
