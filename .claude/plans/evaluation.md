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
| The reconciliation counts rows that arrive as missing. On `erp-supply` `onhand` it counts 1,978 of 2,938 mono stock rows missing where 67 are: the shortfall of the count, on a view whose grain is coarser than the source table's. `reconciliation_test` is red for it | Medium: a red test that is wrong teaches the agent to accept tolerances | `kits/harmonise` (reconciliation) | Next | |
| The reconciliation lists no missing key where the target computes its key (every `erp-supply` target maps its key through the identity table): it counts the right rows per system (104, 32, 2 and 73, as planted) and names none of them | Low | `kits/harmonise` | | |
| The FERC contract states the new system's `record_id` with a rule the reference does not use (glossval's `gen_ferc.py`): 4,434 of 5,221 keys of 2021 to 2025 under the contract's rule, 5,208 under the reference's. It is why a new year scores 83 to 86% of cells; no served column empties after a load (#243 answered) | Medium: every FERC score so far | glossval | In glossval, before the next round | |
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

**The reconciliation counts a source row missing only when it does not
arrive.** What it buys: `reconciliation_test` is red only for rows the
view loses, so an agent does not learn to accept a tolerance for rows
that arrived. What is there: the `erp-supply` run
`runs/erp-supply/20261118T151119Z` in glossval (its `onhand` view:
mono 1,978 of 2,938 counted missing, 67 planted), the reconciliation's
`missing_rows` (the shortfall of the count or the unserved keys,
whichever is more). Done when: on that workspace the reconciliation of
`onhand` counts the planted 67 mono rows, or says why it cannot
compare counts on a view of coarser grain, and the other targets'
counts are unchanged.
