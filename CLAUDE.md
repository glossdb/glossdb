# glossdb — workspace rules

glossdb is the data harness for people and agents. Agents build a
company's data intelligence layer in the lake, beside the data.
glossdb tests what they state against the data at each load, and a
person can review and decide. It is the server around the glossql
language, shipped as a brew tap and an image on GHCR, both cut at the
workspace version.

## Positioning

- **Data intelligence** is what a company knows about its data: what
  it means, how its sources map, whether it can be trusted, and who
  decides. It is the layer under BI and AI. Answers, data apps and
  forecasts sit on top of it.
- **Two properties.** The glossary is stored in the lake, so a
  description belongs to a version of the data. Statements about the
  data are tested against the data.
- **The reader** builds and runs that layer: data engineers and data
  leaders at companies such as Carlsberg and Ikea. Harmonising
  systems of record is the first use case we name. glossdb works
  beside dbt, semantic layers, catalogs and lakes, in their formats.
- **The industry's words.** Everything a person or an agent reads
  uses the words they already use: data intelligence, business
  glossary, semantic model, metric, dimension, test, lineage, data
  contract, referential integrity, additivity. A term the industry
  uses is adopted. A word we invented, in served text, a page or a
  plan, is a defect to fix, not a term to document. Words: the terms
  table in the glossql-prose skill.
- **Voice.** Describe glossdb from our own side. No comparison with
  other vendors. No absolute statements (never, always, "in an
  hour"). No claim without a measurement behind it.
- **The project lead sets the positioning.** A deck, a link or a
  statement from them is the brief: take it up, build on it, and say
  once, with the reason, where you see it differently.

## The map

- **The language** is the extension's (`../gloss`, pinned by
  `crates/duck/glossql.ref`): `SPEC.md`, the only normative language
  prose; `grammar.ebnf`, the source of truth for syntax; `corpus/`,
  transcriptions of real artifacts, the language's acceptance tests
  (` ```glossql ` must parse, ` ```glossql-gap ` must fail). Open
  questions live in SPEC.md §9 and close by a corpus test. The MCP
  interface serves both documents as `doc://SPEC.md` and
  `doc://grammar.ebnf`.
- `crates/` — the server, a Cargo workspace: `duck` (the engine: the
  extension on DuckDB, compiled into every binary) · `apps` (the
  console and data apps) · `serverd` (the binary and its interfaces).
  Packages are `glossdb-*`. Details: the crate headers.
- `kits/` — the server's kits, SQL loaded at open around the
  extension's kits, each with a `kit.test` suite beside it. Core:
  `core`, `views`, `goals`. Add-on: `harmonise`. The `plan` and
  `outlook` kits are offloaded at the tag `before-cut` and come back
  on the stored structure.
  `kits/README.md` says what each adds: vocabulary and reads, never
  grammar.
- **Results and next steps**: `results_due()` in
  `kits/goals/kit.sql` lists the results that are missing or
  outdated; the server computes them after a write
  (`docs/reference/dependencies.md`). The `next` view beside it lists
  what only an actor can do, read from the states the catalog holds;
  a test brings its own finding and fix. The lines every result
  closes with:
  `crates/serverd/src/window.rs`.
- `skills/` — the product skills served to agents over MCP.
  `.claude/skills/` — the skills for building the server: substrate,
  prose, release.
- `docs/` — what the system is and what is planned, for agents and
  people, written for an enterprise evaluator, always current.
- `vendor/` — DuckDB's SQL guide for the locked release, served as
  `doc://vendor/duckdb/sql/…`; `vendor/duckdb/refresh.sh` at every
  pin move.
- `.github/` — `ci.yml` runs the standing invariant on every push and
  pull request; `release.yml` builds the image on a `v*` tag. The
  release order: the glossql-release skill.

## The architecture

- **A core and add-ons.** The core is the language, the catalog, the
  lineage, views, tests and `next`. A kit is an add-on: it brings its
  own vocabulary, the things one asks for, its functions and its
  tests. The core names no add-on and runs without each of them. What
  an add-on stores is tracked by the core's one dependency mechanism;
  an add-on gets no mechanism of its own.
- **What is kept is a view.** Everything an agent keeps is a view: a
  named query with its meaning and tags, defined in one statement.
  Its kind says what it is for: none (a kept query), `table`, `value`,
  `metric` (served), `rule` (its rows break a rule). A function is a
  kit's machinery: one stored result per asset. What is open:
  `.claude/plans/views.md`.
- **`next`** has four kinds of work (integrate, describe, test,
  review) and three levels (must, should, could). An add-on's rows
  come in through its tests and its stored results.
- **Dependencies** are demand-driven incremental computation, as in
  Adapton and Salsa's red-green algorithm. The revision is the lake's
  snapshot id, and it is the only version: no digest, counter or
  fingerprint beside it. `docs/reference/dependencies.md` holds the
  model and its reference; `.claude/plans/dependencies.md` holds what
  is open and what must not exist beside the mechanism.
- **The inside follows the outside.** When what is exposed changes (a
  name, a kit that becomes an add-on, the grain of what one asks
  for), the structure behind it changes in the same work. An old
  structure is not kept behind a new surface.
- **Both repositories shrink** over time, by deleting what a change
  replaces. Correct behaviour comes first: lines are not counted per
  change.

## How we work

- **An agreed design is written down, with its reference**, in the
  plan it belongs to. A change that departs from it stops and is put
  to the project lead. Working without check-ins holds for the rows
  inside an agreed design, not for the design.
- **A spike before a structure.** A new structure is tried standalone
  first, outside the code and the suites it would replace, on real
  cases and at three sizes. Its report says where it does not hold.

- **Use the product as the agent does.** Before and after a change to
  anything an agent reads (kits, skills, the MCP text, the `next`
  line), start a server on a scratch workspace, connect through the
  MCP interface and walk the flow: load, describe, define a view,
  read `next`. A stale demo workspace is rebuilt, not reported.
- **Evaluate from the reader's side.** Say in their words what
  glossdb does for them, what breaks and what it costs. Numbers from
  code, tests and glossval are labelled measured or estimated.
- **The feature is the work.** A task on the server ends in a feature
  that works when used as the agent or the person uses it. What it
  replaces is deleted in the same step, with its tests: one read
  answers one question. The suite follows the feature, not the
  reverse.
- **Build on the engine.** A read, a function, a next step is SQL
  in a kit. The extension owns the language and the catalog; the
  server owns the interfaces. Extend DuckDB and the extension at
  their own seams (the glossql-substrate skill).
- **Standing invariant, at merge.** Work that replaces a structure
  may be red on its branch until it is whole, and the tests of what
  it replaces are deleted first. Workspace `cargo test` passes: every fenced
  example under `docs/`, `skills/` and `.claude/skills/` parses and
  every single read binds, the interface suites hold, the corpus
  behaves as tagged, and the kits' suites pass. A change that breaks
  it does not land.
- **Tests assert code, not wording.** A test asserts status, rows,
  values, columns, paths, that a statement an agent is handed runs,
  and that a refusal happens, by its code. It compares no sentence,
  label or hint. A test's name and body say what it protects, in
  plain words. A test that blocks a text change is changed or
  deleted on the way.
- **One layer per behaviour.** A flow a kit owns is tested in its
  `kit.test`. A Rust test covers what the server adds: results
  computed after a write, the interfaces, access, the console's
  frames. Fixtures are the shipped kits.
- **Lint before pushing**: `cargo fmt`, `cargo clippy`, `cargo test`
  here; `make lint` in the extension.

## Issues, code, docs, plans

- **Issues** (`glossdb/glossdb`) are the work log. One issue is one
  actionable unit: what it buys, what is there (`file:line`,
  fixtures), done-when. Public and factual: no session narrative, no
  actor names, nothing private, no other vendor's product as a
  reference point. Labels: `bug` · `ruling-candidate` · `upstream` ·
  `debt` · `docs`. Language questions go to SPEC.md §9, not to
  issues.
- **Code and comments** are the truth for what is implemented. A
  comment states a constraint the code cannot show, not history.
- **Docs** state what the system is and what is planned, not what was
  rejected or reversed. No dated decision stamps; git is the history.
- **Plans** live in `.claude/plans/`; `harness.md` is the frame and
  names the others. A plan holds what is open on a long-term mission:
  what is built is in `docs/`, a small valid item is an issue, and an
  idea with no customer and no measurement is not kept. A plan is a
  table first (element, risk, what it
  touches, when, issue), in risk order, under 150 lines. It drafts an
  issue only for its next row. When the direction moves, the plan is
  rewritten, not patched. The project lead picks the next issue.

## The language

- **One document.** The extension's SPEC.md is the only normative
  prose. The kits here add vocabulary and reads, not grammar; a form
  they need goes through the extension's corpus.
- **Corpus before prose.** An idea enters SPEC.md after a corpus
  test: competing statement forms for the same real artifact, checked
  against the grammar and real table shapes, the forks shown to the
  project lead. The chosen fork is a SPEC.md diff that shrinks or
  holds the spec.
- **One owner.** The project lead approves every change to
  `grammar.ebnf` before it is made. SPEC.md follows an agreed design
  and is edited with the work; the report names what changed in it.
  The grammar does not drift through implementation convenience.
