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

## State

The two branches `data-intelligence` are up as pull requests, measured
by glossval at their heads (`evaluation.md`): the extension's first,
then the server's pin moves to the extension's `main`. Next, in this
order: a served column that empties is named (#243); the grain of a
result and its inputs (`dependencies.md`, #246); the results page and
the websites; then the backlog.

## The backlog, by kind of work

| Kind of work | Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|---|
| Integrate | Harmonisation kit (built, preview): the faults no test covers; the reconciliation on an aggregated target. A key that is unique only inside one system waits for a real case (the extension's `corpus/29-identities-by-market.md`) | Medium | `kits/harmonise` | After #243 | #244, #245 |
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
| A kit cannot change a property that has values, so an existing workspace cannot take a kit update | the extension | #248 |
| The spec says data-changing SQL is refused; the server allows it. It follows access control | `gate.md` | with `gate.md` |
| The demo workspace is rebuilt on the new names | the demo server | before the pull requests |
| A property that carries a test's expectation is required only where it is annotated | the extension (`SPEC.md` §5), six console frames | open |

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
