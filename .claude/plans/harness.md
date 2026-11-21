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
| What an agent keeps: views and their kinds, tags, rules; the texts that teach it | `views.md` |
| A result is current or computed again, by one mechanism | `dependencies.md` |
| Kits: the cut between glossql, the kits and the server, the packaging, and the one list of clean-up steps | `kits.md` |
| glossdb works with the platform that is there: dbt, semantic models, lakes, the workspace as code | `platform.md` |
| Access per user | `gate.md` |
| What glossval measures | `evaluation.md` |

## State

`snapshot-version` is merged in both repositories. The glossval round
on it (`evaluation.md`) shows agents write their checks as ad hoc SQL
and hardly use the kits' tests. `views.md` holds the design that
follows from it and is the work in hand, on the branch `views-layer`.
The kits plan is shaped together with it.

A test on 143 tables of six source systems showed the stored lineage of
stacked views growing past 500 MB a view, so the server computed
nothing after a load. On the branch `core-layer` a view's lineage
holds the columns each output column is computed from, the tables
scanned and the join pairs, and no text of its expressions. The code
check and the reconciliation, which parsed that text, are gone; their
needs come back as stated inputs (a crosswalk table, control totals as
two queries) in the harmonise kit, which moves to `../glosskits`.
Measured on that case at 0.05, 0.5 and 5 GB a load: all lineage
together 0.97 MB, a reload with everything recomputed in 103, 121 and
260 s, a plain read in 0.25 s, no memory failure.

## Open outside the missions

| Kind of work | Element | When | Issue |
|---|---|---|---|
| Integrate | The mappings of free text and the transformations with no recorded assumption (harmonise kit): covered by kept queries where a profile stands behind the decision; what is left is shaped after `views.md` | After `views.md` | |
| Integrate | The rejected lines of a CSV load are readable | | #255 |
| Integrate | Spreadsheets, documents and search as sources | When a customer brings the data | |
| Describe | Citations to documents on tables, columns, relationships and metrics | With documents | #220 |
| Test | A recompute rule: a measure that does not sum from its members is recomputed, not summed | | #41 |
| Review | A review decision made inside the chat | With the hosted trial | #20 |
| Review | Governance: who owns an asset and who may use it, beyond accepting a count of rows | After the clean-up and further glossval tests | |
| Review | A simulated collaboration: an agent and the project lead work through a complex dataset together | After governance | |
| None of the four | glossval tests of other shapes than the five cases: many tables, several systems, a reload | With the glossval session | |
| None of the four | The hosted trial: the platform is `../glossdeploy`'s. The server needs a check of the token's organization, extra allowed hosts, and an upload page in the console | When the trial is scheduled | |

Housekeeping: #241 (a CSV load with `null_padding`), #60 (an
infrastructure error's text reaches the client), #56 (Tera 2 for the
app pages).

## Loose ends

| What | Where | When |
|---|---|---|
| The spec says data-changing SQL is refused; the server allows it. It follows access control | `gate.md` | with `gate.md` |
| A property that carries a test's expectation is required only where it is annotated | the extension (`SPEC.md` §5), six console frames | open |
