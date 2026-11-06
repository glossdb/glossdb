# The docs plan

How the two repositories say what glossdb and glossql are, and how the
console shows it. glossdb is a harness framework for data agents;
glossql is the language for writing data harnesses. Agents hallucinate
on company data because of information asymmetry: the meaning is not
in the rows. The harness closes the gap by making the agent establish
what must be known (the semantic layer, the ontology, the quality
record) and by serving it back. glossql.org and glossdb.com are built
from the two repositories. Build order is risk order: what keeps a
reader from the story comes first.

## The table

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The READMEs' first screens | Built on `readme-harness` in both repositories | `README.md` here and in the extension | Merge is the lead's | |
| glossdb's docs around the story: what it is, how the harness works, what ships, other harnesses, actors and grants, getting started, the console, running it, reference; `onboarding/` and `system/` folded in; the futures pages under a Preview heading; a terms page | Low: the pages exist and the suite parses their examples; every page is also an agent's `doc://` resource, so a moved page changes what a connected agent reads | `docs/`, `crates/serverd/build.rs`, `crates/serverd/tests/suite/docs.rs` | Next | drafted below |
| The console's defects: lineage's metric end behind an unmarked scroll and labelled `read.<metric>()`; raw numbers (`21205673.3`, a 0.1% ratio shown as `0.0`); "glossql." in the bar; a one-line dataset summary above the review queue | Low | `crates/apps/builtin/docket/` (frames, pages), `crates/apps/assets/` | Beside the docs rows | |
| The console's name: Docket becomes Console, the app's title and its path | Low to medium: the path rides the links in the `next` line, the skills and the docs | `crates/apps/builtin/docket/`, `skills/`, `docs/`, the apps suite | With the defects | |
| glossql's docs, laid out like DuckLake's: overview, getting started, concepts (usage, not normative), the catalog (one page per table, held to `STORE_RELATIONS`), functions, kits, building a door, specification and conformance; a terms page | Medium: the concept, store, storage, KPI-kit and quality-method pages move from here; a moved page must stay on the MCP door, served from the extension's share as `SPEC.md` is; the extension's suite parses their examples | the extension's `docs/` and `test/sql/`; `docs/` here; the share the server reads at boot | After the glossdb docs | |
| The console's navigation: a tree (dataset → sources → tables → columns; metrics; views); the same sub-tabs on every object's page (what is said, what is measured, checks, uses and used by, history); a breadcrumb; plain section names with the reads' names behind a toggle; the harness scorecard on the landing page (known against owed per aspect, the goals: `chat.md`'s goals tile) | Medium: a new page set over reads that exist | `crates/apps/builtin/docket/`, `crates/apps/src/` | After the docs rows | |
| The console's two new views: Model (entities, keys, joins, measures, dimensions, time grains: the ontology and the semantic layer in one picture) and History (loads, glosses and review decisions over time) | Medium: new frames over recorded rows, a graph | `crates/apps/` | After the navigation | |

## What stands

- **The READMEs.** Here: the one-liner, why agents get data wrong, how
  it works in five points, what ships (glossql's and glossdb's
  features; forecasts and plans as preview; grants as planned), other
  harnesses, actors and grants, then getting started, interfaces,
  building, layout, status. The extension: the one-liner, declare what
  must be known, record what is, read it, the kits, then the whole
  session, status, the mapping onto DuckDB, the doors, building. The
  extension's new examples run on its build.
- **glossdb's docs.** 40 pages, 4,326 lines (measured). About 1,200
  lines explain what the extension owns: eight of the ten `concepts/`
  pages, `architecture/store.md` and `storage.md`,
  `reference/kpi-kit.md`, and the four quality-method pages.
  `onboarding/README.md` and `system/README.md` restate what stands in
  the project's words. The futures pages (`methods/bands.md`,
  `forecast.md`, `scenario.md`, `plan.md`; 574 lines) carry no preview
  mark. Every page is embedded in the binary and served as a `doc://`
  resource (`crates/serverd/src/skills.rs:127`); the suite parses and
  binds every fenced example (`crates/serverd/tests/suite/docs.rs`).
- **The extension's docs.** For a person: README, SPEC.md,
  CONFORMANCE.md, `kits/README.md`. The catalog's eleven tables exist
  only in `STORE_RELATIONS` (`src/glossql_store.cpp:294`); the
  functions (`glossql_kit`, `glossql_lineage`, `glossql_columns`,
  `dataset_cells`, `subject_column`, `json_schema_check`,
  `glossql_service`) only in README and CONFORMANCE prose.
  `docs/UPDATING.md` is the extension template's.
- **The console** (walked on a demo workspace). Depth where it was
  built: the table page and the metric page. Sections labelled with the
  reads' names; the catalog page is one 6,500-pixel page that opens with
  the vocabulary; sources, joins, checks and loads have no page; the
  metric page has no title and no way back; a dataset with nothing open
  lands on three zeros. The known-against-owed table that opens the
  catalog page is the harness's scorecard.

## Terms

Our words stay; each is explained once beside the industry's.

| Ours | The industry's |
|---|---|
| aspect | property of the harness schema |
| an aspect's grain | what it applies to |
| `FACT` / `MEASUREMENT` / `QUERY` | asserted / computed / metric definition |
| gloss | assertion |
| subject | asset |
| witness (after Dawid–Skene's observers) | check |
| `unassessed` / `contested` / `stale` | missing / conflict / stale |
| owed | required, open; coverage as the KPI |
| pin, reads | provenance |
| the record | the catalog: append-only, versioned with the data |
| recipe, landing, `PROBE` | load query, load, dry run |
| grounding | metric definition |
| `behavior`: flow / stock / ratio | additivity: additive / semi-additive / non-additive |
| `entity`, `definitions`, ladder | entity (the table's grain and key), business glossary, time grains |
| door | interface |
| `next`, routes | goals, next steps |
| open questions, ruling | review queue, review decision |
| the docket | the console |

"Ontology" names what agents establish (entities, relationships,
terms); the declared level is the harness schema.

## Issue, drafted

### glossdb's docs tell the harness story

- **What it buys.** The pages a reader reaches from the README say what
  the README says: a harness framework for data agents, what ships, how
  to run it, in the same terms; the console has a page for people.
- **What stands.** The README's first screen (`readme-harness`).
  `docs/README.md` indexes start, concepts, reference, methods,
  architecture, system, onboarding and quality; `onboarding/README.md`
  and `system/README.md` restate what stands; the futures pages carry
  no preview mark; every page is a `doc://` resource
  (`crates/serverd/src/skills.rs:127`) and its examples are held by
  `crates/serverd/tests/suite/docs.rs`.
- **Done when.** `docs/README.md` opens with what glossdb is, how the
  harness works, what ships, other harnesses, actors and grants,
  getting started, the console, running it and reference, the language
  linked to the extension; `onboarding/` and `system/` are folded in and
  gone; the futures pages sit under Preview; `docs/terms.md` carries the
  terms table; the suite passes.

## For the other repos

- **The extension**: its docs row above, on a branch of its own.
- **glossval**: a naive agent against a harness-driven one on the same
  tasks, numbers right and questions answered, once the story stands.
- **The websites**: glossql.org from the extension's docs, glossdb.com
  from the story; `../dataraum-website` has the docs sync and the sample
  checks, and its copy predates the engine.
