# The plan

glossdb builds a company's data intelligence layer. Its five
functions are the frame for what a person looks at: integration,
metadata, quality, governance, lineage. The work on it is of four
kinds: integrate, describe, test, review. They are kinds of work, not
stages; lineage results from the four, and a view can be queried once
it is defined. This file is the frame. It lists what is open, first
the data intelligence direction, then the backlog by kind of work. The
plans beside it: `platform.md` (dbt, semantic models, lakes, the
workspace as code), `sources.md` (spreadsheets, documents, search),
`gate.md` (access per user), `clients.md` and `chat.md` (the hosted
trial), `evaluation.md` (what glossval measures), `dependencies.md`
(how a result becomes outdated and when it is computed again).

## First: the data intelligence direction

Finished before anything new is picked. Everything built is on the
branch `data-intelligence` in both repositories, not pushed.

| # | What | State |
|---|---|---|
| 1 | Names: every interface name that was a project word is renamed to the industry's word, in both repositories | built |
| 2 | Text: README, docs, skills, the corpus, the text an agent reads on connecting, written new for every kind of view (a table, a single value, a metric) and checked against the code | built |
| 3 | Tests: no test compares wording; tests that protected nothing and code written for tests are deleted; a refusal carries a code | built |
| 4 | `next`: the work list, most urgent first, each row labelled with its kind of work, derived from the states the catalog holds, with a statement per row; the console's overview shows the same rows | built |
| 5 | The console: overview, model and lineage as two pages, a test's page with its results, every kind of view under Views | built along the earlier step names; the overview moves to the five functions and the four kinds of work, then the wording inside the other pages |
| 6 | What an outside agent found when it built a workspace from the skill alone (20 items) | in work |
| 7 | glossval: its tools follow the renamed reads; its old notes and tools are cut; the contract test cases run (`evaluation.md`) | next |
| 8 | One pull request per repository; the extension's branch first, then the server's pin moves to it | when the project lead says the branches go up |
| 9 | Results page and websites | after 7 |

## The backlog, by kind of work

| Kind of work | Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|---|
| Integrate | Harmonisation kit: the mapping of several systems of record onto one target model, and the reconciliation per load | Medium: the demo's statements are written for one case; the kit must hold for a second | `kits/`, a skill, a suite; the statements in `../glossdemo/statements/` (structure, harmonise, watch) and its Mapping and Reconciliation pages | The first use case | |
| Integrate | Works with your platform: dbt, semantic models, lakes read in place, attached databases | See `platform.md` | | | #221 |
| Integrate | Spreadsheets, documents, search | See `sources.md` | | When a customer brings the data | |
| Describe | The workspace as code: declarations as `.glossql` files, tested in CI | See `platform.md` | | | #219 |
| Describe | Citations to documents on tables, columns, relationships and metrics | Low | an optional kit | With documents | #220 |
| Test | A certification level per metric: the level sets which tests and which review a metric needs before it is served as certified | Low: a property and a read over `view_tests()` | the views kit, `next`, the console's metric page | After the harmonisation kit | |
| Test | A recompute rule: a measure that does not sum from its members is recomputed, not summed | Medium | the views kit | | #41 |
| Review | Access per user | See `gate.md` | | When a workspace has a second user | |
| Review | A recommendations read: findings with their options, chosen in the console (preview) | Low | the outlook kit, a console tile | | #174 |
| Review | A review decision made inside the chat | See `chat.md` | | With the trial | #20 |
| None of the four | The hosted trial | See `clients.md` | | | |

Housekeeping, outside the kinds of work: #214 (the image hangs on opening a
seeded workspace), #60 (an infrastructure error's text reaches the
client), #56 (Tera 2 for the app pages).

## Loose ends of this round

Closed before the pull requests open, or moved to a row above.

| What | Where | When |
|---|---|---|
| How a result becomes outdated and when it is computed again: a caching design on versions the storage guarantees; a proposal, nothing built | `dependencies.md` | after the open items of this round |
| A kit cannot change a property that has values, not even to add a description, so an existing workspace cannot take a kit update | the extension | before a workspace lives longer than a release |
| The spec says data-changing SQL is refused; the server allows it. It follows access control | `gate.md` | with `gate.md` |
| The demo workspace is rebuilt on the new names | the demo server | before the pull requests |
| `../glossthesi` uses the old words in its README | `../glossthesi` | before the pull requests |

## Measured

On `hr` (two metrics, 331,603 and 443,308 rows), per MCP call: any
statement 0.4 s, of which `next` is 0.33 s; a definition with its
tests 2.5 s; an annotation on a scanned table 1.8 s.

CI: the server 4 to 6 minutes; the extension 6 minutes per platform, a
pull request builds linux_amd64 alone. The server's CI waits for the
extension's build of the pinned commit before building it itself.

## Rules learned

- A red test alone is a failed test, not a conflict.
- A check that reads other functions' results re-runs when those change.
- A test with nothing to check is green with the reason, not a chore.
- A workspace made before a catalog column was added is rebuilt.
