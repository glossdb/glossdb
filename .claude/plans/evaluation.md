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
| A served column that empties. On the `eia-generators` replay `next` names both emptied columns as a `must` (`completeness_test` red: 80.7% empty, 0.0% before, the definition empties it). On the FERC running replay three later years load and `next` shows no row come or gone, as before; whether a column empties there, or the new years only score lower (83 to 86% of cells against 97 to 98% so far), is not established | Medium: it is what the layer adds over a built table | the FERC running replay, `completeness_check`, `load_changes()` | Next | #243 |
| The running state on `eia-generators`; a third `erp-supply` run; the harmonisation scorer on the rebuilt reconciliation, with a "handled" rule for a fault the builder removes at load | Low | glossval | In glossval | |
| The read stage: a second agent reads the built lake with DuckDB, `ducklake` and glossql and answers questions; against the same agent on the sources | Medium | glossval | After the running state | |
| The rejected lines of a CSV load are readable after the load, not only counted | Low | the extension's runner | | #255 |
| The results page | Low | glossval, the websites | Last | |

Not planned: reading a CSV in place as a view; the same agent with
DuckDB only as a comparison (a story for the docs later).

What the harness, the test cases and the scorers are, and the scores
of each round, are glossval's own (`../glossval/README.md`,
`evals/README.md`, `goldens/README.md`). The last round ran on the
branch `snapshot-version` at glossql `58938e6e` and the extension
`ce94506`: `ferc-steam` 93.7% of cells, `eia-generators` 99.0%, the
goldens differing only where the branch changed behaviour on purpose.
Open in glossval after it: the harmonisation scorer reads the
reconciliation's earlier shape, and the goldens' baseline is not
accepted yet.

## Next issue (draft)

**The running state on FERC names what a later year changed.** What it
buys: after a period is loaded, `next` says which served columns moved
and in which period, or the replay shows that none did. What is there:
the replay `--replay=runs/ferc-steam/20261116T112642Z --running=2` in
glossval, `completeness_check` per served column, `load_changes()`.
Done when: the replay's three periods are read column by column
against the build before each load, and either `next` names each
column whose filled share dropped with its period, or the plan states
that no column emptied and the lower score of a new year has another
cause.
