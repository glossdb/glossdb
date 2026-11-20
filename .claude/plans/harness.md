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

`snapshot-version` is merged in both repositories. The glossval round
on it (`evaluation.md`) says what comes next: `next` asks for checks
before descriptions, and a value is checked against its unit (the
first two rows below). The kits plan follows in the next streamlining
session, with what glossval says can be simpler.

## Open outside the missions

| Kind of work | Element | When | Issue |
|---|---|---|---|
| Describe | A kept query: the spec and the skills present a view (`DECLARE ASPECT … AS VIEW`, `GLOSS … {"sql", "assumptions"}`) as any query worth keeping with its reason, a metric being one use; a function or a test on it makes it a check. Precondition: a plain view is asked for no descriptions and no served-view tests (`kits.md` step 2; measured: two kept queries took `next` from 6 to 22 rows) | Next, tried with glossval | |
| Describe | The queries an agent runs are logged and indexed by the columns they read; `next` offers them for keeping and lists kept ones for reuse. Open: when and how the agent is asked. Measured on 38 builds: 81% of a view's decisions have an earlier query on their source column, but one query meets a median of 4 decisions | Not ready: the moment of the nudge is not based on a measurement yet | |
| Test | `next` asks for checks before descriptions, and the three levels do not steer an agent. On hold until the two rows above are shaped | On hold | |
| Test | A value is checked against a bound someone states: a `range` on a column, a rule across columns as a view of the violating rows. Measured: the capacity rule separates the wrong ferc-steam build (median 205 to 230) from the right one (0.22); a baseline taken from the build does not | With the rows above | |
| Integrate | The mappings of free text and the transformations with no recorded assumption (harmonise kit): covered by kept queries where a profile stands behind the decision; what is left is shaped after them | After the rows above | |
| Integrate | The harmonisation kit (preview): the faults no test covers; a target that aggregates | After the smoke test | #244, #245 |
| Integrate | The reconciliation counts rows that arrive as missing on a view of coarser grain than its source, and names no key where the target computes its key | Next (`evaluation.md`) | |
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
