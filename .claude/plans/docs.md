# The positioning plan

glossdb is a harness framework for data agents; glossql is the language
for writing data harnesses. The software works. What holds it back is
the words: data engineers at Carlsberg and Ikea read coined terms where
they expect the ones they use every day. The fix is to use their words
in the product, not to document a mapping. Done so far: the READMEs in
the shape DuckLake and SurrealDB use, the docs by reader in both
repositories, the console's name and navigation, the keyword renames
TEST, TESTS(), PREVIEW and VIEW, the names review decision, load query,
load, catalog, interface, and the built-in tests named join fan-out,
referential integrity and additivity.

## The table

| Step | Risk | What it touches | Issue |
|---|---|---|---|
| 1. The remaining coined words replaced by the industry's in everything served and shown: the glossary states, the kpi kit's property names, the reads' names, the two closing lines; each a rename outright, no alias | Medium: the states and property names are in the extension, the kits, the console, the skills, the docs and glossval's scorer | both repositories, glossval | drafted below |
| 2. The keywords the lead kept on 2026-11-06, `GLOSS`, `ASPECT`, `RECIPE`, `IMPORT`, reconsidered one by one as corpus forks, since every served sentence carries them | Medium: grammar; the corpus decides | `../gloss` grammar, SPEC.md, corpus; every example here | the lead's call |
| 3. A results page: the same tasks with and without the harness, one session and across sessions, in plain numbers; glossval runs them, the lead approves | Low | `docs/results.md`, both READMEs | after the Monday test |
| 4. The websites from the two docs trees | Low | `../dataraum-website` | after 3 |

## The words still ours

| Today | The industry's | Where |
|---|---|---|
| `contested` | conflict | glossary state: extension, kits, console, skills, docs |
| `unassessed` | missing | glossary state |
| `stale` | stale (kept: the industry's word) | |
| `behavior`: flow, stock, ratio | additivity: additive, semi-additive, non-additive | kpi kit property, metrics kit, console, skills |
| `entity` | grain | kpi kit property |
| `definitions` | business glossary | kpi kit property |
| `ladder` | time grains | metrics kit property |
| `band` | severity | tests, console |
| `metric_axes()`, `metric_series()` | metric summary, metric values | metrics kit reads |
| `workspace_next` | workspace status | core kit read |
| `situation:` | status: | the closing line |
| kit | package | docs, skills |
| actor | principal | docs, the catalog's `declared_by` |
| gloss, aspect | annotation, property | keywords, step 2 |

## Issue, drafted (step 1)

### The product speaks the industry's words

- **What it buys.** A data engineer reads the console, a tool result
  and a skill without a glossary: conflict, missing, additivity, grain,
  business glossary, time grains, severity, status.
- **What is there.** The states are the extension's collapsed read
  (`src/glossql_store.cpp`) and its tests; the properties are the kpi
  kit's declarations (`../gloss/kits/kpi/kit.sql`) read by the metrics
  kit, the console's frames and the skills; glossval's scorer reads
  `behavior` and `entity` by name.
- **Done when.** Each word above is replaced outright in both
  repositories and glossval, with no alias; the suites, the docs
  examples and the console pass; a grep for the old word in served
  text finds nothing.
