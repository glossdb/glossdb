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
  questions live in SPEC.md §9 and close by a corpus verdict. The MCP
  interface serves both documents as `doc://SPEC.md` and
  `doc://grammar.ebnf`.
- `crates/` — the server, a Cargo workspace: `duck` (the engine: the
  extension on DuckDB, compiled into every binary) · `apps` (the
  console and data apps) · `serverd` (the binary and its interfaces).
  Packages are `glossdb-*`. Details: the crate headers.
- `kits/` — the server's kits: core, views, outlook, goals. SQL
  loaded at open around the extension's kpi and quality kits, each
  with a `kit.test` suite beside it. A kit whose words depend on the
  server lives here; `kits/README.md` says what they add: vocabulary
  and reads, never grammar.
- **Next steps**: the `next` view in `kits/goals/kit.sql`, read from
  the states the catalog holds; a test brings its own finding and
  fix. The lines every result closes with:
  `crates/serverd/src/window.rs`.
- `skills/` — the product skills served to agents over MCP.
  `.claude/skills/` — the skills for building the server: substrate,
  prose, release.
- `docs/` — what the system is and what is planned, for agents and
  people, written for an enterprise evaluator, always current.
- `corpus/` — the two transcriptions behind the server's kits (19 and
  27); the serverd suite parses them.
- `vendor/` — DuckDB's SQL guide for the locked release, served as
  `doc://vendor/duckdb/sql/…`; `vendor/duckdb/refresh.sh` at every
  pin move.
- `.github/` — `ci.yml` runs the standing invariant on every push and
  pull request; `release.yml` builds the image on a `v*` tag. The
  release order: the glossql-release skill.

## How we work

- **Use the product as the agent does.** Before and after a change to
  anything an agent reads (kits, skills, the MCP text, the `next`
  line), start a server on a scratch workspace, connect through the
  MCP interface and walk the flow: load, describe, define a metric,
  read `next`. A stale demo workspace is rebuilt, not reported.
- **Evaluate from the reader's side.** Say in their words what
  glossdb does for them, what breaks and what it costs. Numbers from
  code, tests and glossval are labelled measured or estimated.
- **Code is the work.** A task on the server ends in changed code and
  a passing suite.
- **Build on the engine.** A read, a measurement, a next step is SQL
  in a kit. The extension owns the language and the catalog; the
  server owns the interfaces. Extend DuckDB and the extension at
  their own seams (the glossql-substrate skill).
- **Standing invariant.** Workspace `cargo test` passes: every fenced
  example under `docs/`, `skills/` and `.claude/skills/` parses and
  every single read binds, the interface suites hold, the corpus
  behaves as tagged, and the kits' suites pass. A change that breaks
  it does not land.
- **Tests assert code, always; text case by case.** A test compares
  served text where the text is context an agent acts on, a decided
  process or offering, a named entity or an industry term. Other
  text is free to change, synonyms included. A test's name and body
  say what it protects, in plain words. A test that blocks a text
  change without protecting one of these is changed or deleted on
  the way.
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
  names the others. A plan is a table first (element, risk, what it
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
- **One owner.** The project lead reviews every grammar change.
  Propose SPEC.md edits with the reason; the grammar does not drift
  through implementation convenience.
