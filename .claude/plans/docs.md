# The positioning plan

glossdb is a harness framework for data agents. glossql is the language
for writing data harnesses. The software works, and glossval measured it
against agents without the harness. What holds it back is the words:
the docs, skills, comments, console and some keywords speak a private
vocabulary that buyers can't repeat. This plan changes the words, not
the behaviour. Order: first the things that make every later page come
out in the old words.

## The table

| Step | Risk | What it touches | Issue |
|---|---|---|---|
| 1. House rules: the prose skill's list of protected terms is replaced by the terms table below; CLAUDE.md and the build skills use the plain words | Low. Without it every agent session writes the old words again | `.claude/skills/glossql-prose/`, `CLAUDE.md`, `.claude/skills/` | done on `readme-harness` |
| 2. One terms page and one analogy page (the coding harness table below), in both repositories | Low | `docs/terms.md`, `docs/harness.md`, the extension's `docs/` | done on `readme-harness` |
| 3. The READMEs in the shape DuckLake and SurrealDB use: category sentence, the coding-harness analogy, features in industry words, a quick look, status per feature (stable, preview, planned). Out: "proof-of-concept", "working draft", the research file, "not built on purpose", the corpus and the DuckDB mapping table (to the docs) | Low | `README.md` here and in the extension | |
| 4. A results page: the same tasks with and without the harness, in plain numbers; glossval runs them again, the lead approves them | Low | `docs/results.md`, linked from both READMEs | |
| 5. What agents read: the MCP server instructions, the tool description, the four skills, the `next:` lines, error and refusal text. Hosts show this text to users | Medium: the door suites assert some strings | `crates/serverd/src/`, `skills/`, `kits/door/` | |
| 6. The console: Docket becomes Console (title and path); plain section names, the reads' names behind a toggle; formatted numbers; the lineage defects | Low to medium: the path rides links, skills and docs | `crates/apps/builtin/docket/`, `crates/apps/assets/`, the apps suite | |
| 7. An evaluator's page: what it is, where it runs, what data leaves, sign-in, deployment, support | Low | `docs/start/evaluate.md` | |
| 8. glossdb's docs by reader: overview, getting started, concepts, guides, the console, running it, reference; `onboarding/` and `system/` folded in; preview pages marked | Low: every page is also a `doc://` resource; the suite parses examples | `docs/`, `crates/serverd/build.rs`, `crates/serverd/tests/suite/docs.rs` | |
| 9. glossql's docs in DuckLake's shape: overview, specification (one page per catalog table, held to `STORE_RELATIONS`), the extension (install, usage, functions, kits, building an interface), conformance | Medium: pages move from here and stay served from the extension's share | the extension's `docs/`, `test/sql/`; `docs/` here | |
| 10. Keyword forks: each rename below as competing forms on a real fixture, the lead's verdict, then a SPEC.md diff | Medium: grammar, corpus, every example in both repositories | `../gloss` grammar, SPEC.md, corpus; the docs suite here | |
| 11. Code comments and identifiers, by area as it is touched | Low | crates, kits | |
| 12. The console's navigation and its Model and History views | Medium: new pages over existing reads | `crates/apps/` | |
| 13. The websites from the two docs trees | Low | `../dataraum-website` | |

## The analogy

Coding agents work inside a harness: types, compiler, linters, tests,
CI, review. Data never had one; its meaning exists only in production.
glossdb builds that harness inside the database, on the live data and
its versions.

| Coding harness | Data harness | glossql today |
|---|---|---|
| type system | the harness schema: what must be known per dataset, table, column, metric | aspect |
| type annotations, docstrings | annotations: what a row is, a column's unit, a measure's additivity | gloss |
| compiler error | validation on write against a JSON Schema | admission |
| linter | quality screens: keys, joins, hierarchies, stock or flow | quality kit |
| unit test | a measurement or a check on the data | function, witness |
| test coverage | coverage of required annotations | owed, unassessed |
| CI on every commit | recomputed on every load; stale when the data changes | pin, stale |
| git history | snapshots of data and catalog together | DuckLake, the record |
| code review | the review queue: a person decides | open questions, ruling |
| rule packs (lint configs, test plugins) | kits | kit |
| the failing test that says what to fix next | next steps after every call | `next`, routes |
| IDE | the console | docket |

One line: glossdb gives data agents what compilers, tests and CI give
coding agents.

## Terms

Plain words in prose, UI and agent text now. Keywords only through step 10.

| Today | Plain | Where it stays |
|---|---|---|
| door | interface, endpoint | nowhere |
| docket | console | nowhere |
| ruling | review decision | nowhere |
| open questions | review queue | the read's name |
| owed | required, missing; coverage | the read's name |
| grounding | metric definition | nowhere |
| landing, land | load | nowhere |
| the record | the catalog | nowhere |
| slot, voice | (subject, aspect) value; source of an annotation | nowhere |
| pin, reads | provenance | the column names |
| band | confidence | the column name |
| ladder | time grains | nowhere |
| stands | is current | nowhere |
| subject | asset (table, column, dataset) | the grammar |
| gloss | annotation (the verb: annotate) | the keyword: the product's name |
| `GLOSSARY()` | the glossary | the keyword |
| aspect | property of the harness schema | the keyword (prior art in metadata catalogs) |

Keywords for step 10. Kept: `GLOSS`, `GLOSSARY()`, `ASPECT`.

| Keyword | New | State |
|---|---|---|
| `PROBE` | `PREVIEW` | agreed |
| `WITNESS` | `TEST` | agreed; `BY` and `DETECTOR` open |
| `ATTEST()` → `CHECKS()` | `TESTS()` | agreed |
| kind `QUERY` | `VIEW` | agreed |
| `x-kind: fact` | `scalar` | agreed |
| `RECIPE` | `PIPELINE`, kept | open |

## How DuckLake and SurrealDB say it

- One sentence, category first: "a lakehouse format built on SQL";
  "a multi-model database written in Rust".
- Features in words a buyer already uses: snapshots, time travel,
  schema evolution, ACID transactions, access control, live queries.
  No coined term on the first screen.
- New things named by what they do: SurrealQL's `DEFINE TABLE`,
  `DEFINE FIELD`, `DEFINE ACCESS`, `LIVE SELECT`.
- Docs by reader: overview, specification, the extension
  (installation, usage, maintenance, advanced features, migrations,
  guides, unsupported features); SurrealDB adds security and
  "in production".
- Status per feature, never for the whole project.

## Issue, drafted

### The READMEs open like a product

- **What it buys.** An evaluator reads one screen and can say what
  glossdb is, what it does for their agents, and what is stable.
- **What is there.** Both READMEs open with the one-liner. glossdb's
  closes with "a working proof-of-concept" and "a working draft"; the
  extension's carries the research file, "not built on purpose", the
  corpus and the 20-row DuckDB mapping table.
- **Done when.** Each opens with the category sentence, the coding-
  harness analogy in three lines, features in industry words, a quick
  look, and a status table per feature (stable, preview, planned);
  the mapping table and the corpus move to the extension's docs; the
  extension's examples run on its build; the suite passes.
