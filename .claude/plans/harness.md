# The plan

glossdb builds a company's data intelligence layer. Its five
functions are the frame for what a person looks at: integration,
metadata, quality, governance, lineage. The work on it is of four
kinds: integrate, describe, test, review.

This file is the frame. A plan holds what is open on a long-term
mission. What is built is in `docs/`; a small, valid item is an issue
(`glossdb/glossdb`); an idea with no customer and no measurement is
not kept.

| Mission | Plan |
|---|---|
| A result is current or computed again, by one mechanism | `dependencies.md` |
| Kits: the core and the add-ons, how a kit is versioned and bundled | `kits.md` |
| glossdb works with the platform that is there: dbt, semantic models, lakes, the workspace as code | `platform.md` |
| Access per user | `gate.md` |
| What glossval measures | `evaluation.md` |

## State

The branch `snapshot-version` is pushed in both repositories, the
server pinned at the extension's head of it. A glossval round ran on
it (`evaluation.md`). Next, in this order: the project lead's smoke
test; the pull requests; then what the project lead picks from the
missions and the issues.

## Open outside the missions

| Kind of work | Element | When | Issue |
|---|---|---|---|
| Integrate | The harmonisation kit (preview): the faults no test covers; a target that aggregates | After the smoke test | #244, #245 |
| Integrate | A served column that empties is named: the running state on FERC | With `evaluation.md` | #243 |
| Integrate | The rejected lines of a CSV load are readable | | #255 |
| Integrate | Spreadsheets, documents and search as sources | When a customer brings the data | |
| Describe | Citations to documents on tables, columns, relationships and metrics | With documents | #220 |
| Test | A recompute rule: a measure that does not sum from its members is recomputed, not summed | | #41 |
| Review | A review decision made inside the chat | With the hosted trial | #20 |
| None of the four | The hosted trial: the platform is `../glossdeploy`'s. The server needs a check of the token's organization, extra allowed hosts, and an upload page in the console | When the trial is scheduled | |

Housekeeping: #241 (a CSV load with `null_padding`), #60 (an
infrastructure error's text reaches the client), #56 (Tera 2 for the
app pages).

## Loose ends

| What | Where | When |
|---|---|---|
| The spec says data-changing SQL is refused; the server allows it. It follows access control | `gate.md` | with `gate.md` |
| A property that carries a test's expectation is required only where it is annotated | the extension (`SPEC.md` §5), six console frames | open |
