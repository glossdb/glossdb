# Evaluation plan

glossval measures glossdb as data middleware: source data goes in, a
cleaned table in a given format comes out of the lake. An agent gets
the sources and a contract (table, key, columns, types, meanings, code
tables) and builds the table in glossdb. The score is a diff against a
reference that an independent party built.

Two cases, by what the source is:

- **Typed sources** (Parquet, database tables) are the main case.
  Nothing is cleaned at load. The work is views on top: one table from
  several systems that name and code the same things differently.
- **CSV** is the exception. The load gives DuckDB's CSV reader one
  standard configuration and casts in the load query.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The reconciliation compares at the view's grain and names keys by the source's own columns. Not counted: a row dropped by a second join in a chain; a branch whose key is computed with nothing looked up; a target none of whose columns comes from its source table (`sites` on `erp-supply`) | Low: it undercounts, it does not read red wrongly | `kits/harmonise` | | |
| The FERC contract states the new system's `record_id` with a rule the reference does not use (glossval's `gen_ferc.py`): 4,434 of 5,221 keys of 2021 to 2025 under the contract's rule, 5,208 under the reference's. It is why a new year scores 83 to 86% of cells; no served column empties after a load (#243 answered) | Medium: every FERC score so far | glossval | Fixed in glossval `6edc9ef`; FERC scores before and after are not comparable | |
| The running state on `eia-generators`; a third `erp-supply` run; a "handled" rule for a fault the builder removes at load (`due_date_format`) | Low | glossval | In glossval | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Medium | glossval | After the running state | |
| The rejected lines of a CSV load are readable after the load, not only counted | Low | the extension's runner | | #255 |
| The results page | Low | glossval, the websites | Last | |

Not planned: reading a CSV in place as a view; the same agent with
DuckDB only as a comparison (a story for the docs later).

What the harness, the test cases and the scorers are, and the scores
of each round, are glossval's own (`../glossval/README.md`,
`evals/README.md`, `goldens/README.md`). The last round ran on the
branch `snapshot-version` at glossql `58938e6e` and the extension
`ce94506`: `ferc-steam` 93.7% of cells, `eia-generators` 99.0%,
`erp-supply` (generated) found 2, handled 1, missed 2, not covered 5
with the scorer on the rebuilt reconciliation. The goldens' baseline is
accepted at glossql `f7485aac` with the extension `ce94506`, every
difference a deliberate change (glossval `512fd5e`). On the FERC
running replay no served column loses its fill after a load: the years
already built keep their rows and empty shares column by column, and a
new year scores as the build's own new-system years, for the contract's
key rule above. `next` naming nothing there is right.

## Next issue (draft)

None drafted. The reconciliation's count on `erp-supply` `onhand` is
fixed: the view filters on stock status and does not group, so of the
67 mono rows without an identity 24 are in scope and counted, with
their keys; the 1,954 rows the condition leaves out are shown as
excluded and not judged. A wrong condition is therefore not red: the
result shows how many rows it leaves out. The project lead picks what
follows.
