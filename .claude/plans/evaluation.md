# Evaluation plan

glossval measures the data intelligence layer, not one answer. An
agent builds the layer in a DuckLake. A second agent reads that lake
with plain DuckDB. We score what was built, and what the reader gets
right on it against the same reader on the raw data. Data analysis
(the accuracy of one answer inside glossdb) stays one angle and is no
longer the headline.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| What a reader on plain DuckDB sees in a glossdb lake: descriptions as comments on tables, columns and views; the catalog's reads independent of the name the lake is attached under | High: the result of the whole evaluation depends on it; comments in DuckLake are not tried yet | the extension's store, `kits/core/kit.sql`, a suite that opens a lake without the extension | Next | |
| The two-stage run. Build: an agent builds tables, views and metrics over MCP; scored against the scenario's truth. Read: a second agent with plain DuckDB and no memory of the build answers questions the builder was not asked; scored against the same truth at other slices and grains | Medium: the harness has one stage today; the reader's arm exists as the bare arm | glossval `run.py`, `bare_run.py`, `bare/duck_mcp.py`, `score.py`, the scorecard schema | After the first row | |
| The arms of the read stage: the raw lake, the built lake, and the built lake per way of presenting it (views only, views with comments, the glossary as a table, the semantic model export) | Low once the stage runs | glossval `ab_seats.py`, `ab_report.py` | With the stage | |
| Data. Real data first: the corpora glossval holds (salt, avito, hm, f1, stack, trial, baton-rouge, eia-860m, mta-subway, biocase). Finance from `../glosstest` (`month-end-close`, `multi-system-recon`, `erp-migration`), named as generated in every result. No new generator | Medium: truth on real data is authored by us; a held-out question needs a truth value | glossval `evals/scenarios/`, `fetch_corpora.py` | With the stage | |
| A seat for the running state: after the build a load changes a table; scored on whether `next` names the change and its cause | Low | a scenario with two loads, `next_state.py` | After the stage | |
| The tools that read the old `next` columns are adapted or deleted: `next_state.py`, `run.py`, `plan_lane.py`, `ab_seats.py`, `chat_agent.py`, `joint_report.py`, `score.py`, `truth_stack.py`, `truth_trial.py`, `mining/next_table.py`, `graph/graph.py` | Medium: no seat runs until `run.py` and `next_state.py` are done | glossval | With the stage | |
| The finish line for the builder: no open row for the agent in `next`; rows waiting for a person do not count | Low | glossval `next_state.py`, the metrics skill says the same | With the stage | |
| The eight seats rerun, the Monday test, then the results page | Low | glossval, the websites | Last | |

## What is there

- A glossdb lake opens in plain DuckDB with the `ducklake` extension.
  Measured on the employees lake: the tables read, the metric views
  read and return rows, `metric_surfaces` and `relationships` read.
- The glossary's rows read only when the lake is attached under the
  name `ws`; under another name the view fails. `next` and every read
  built on the extension's functions fail without the extension.
- No description reaches the reader as a comment: `duckdb_columns()`
  and `duckdb_views()` show none. A reader finds a meaning only by
  knowing to query `main.glossary`.
- glossval has 21 scenarios; one has gold truth, one redundancy, two
  generated, the rest authored. The last A/B (same agent in glossdb
  against plain DuckDB, employees data): 92%/97% right against
  90%/94%. Both arms are near the ceiling, so the comparison shows
  little.
- `../glosstest` generates finance data with an answer key: a closed
  ledger, three source systems with different schemas, an ERP
  migration, planted defects at four strengths.

## What the scores are

- **Build.** Share of metric values right against truth; values wrong
  without a disclosed assumption; planted defects named by a test or
  an open row; relationships right.
- **Read.** Share of held-out answers right, built lake against raw
  lake, same reader, same questions; the reader's cost in both.
- **Running.** After a changed load: is the change an open row, and
  does the cause name the table and column.

A result on generated data is labelled generated. The headline
numbers come from real data.

## Next issue (draft)

**A glossdb lake read with plain DuckDB.** What it buys: the layer an
agent built is usable by any tool that opens the DuckLake, and the
evaluation's read stage has something to read. What is there: tables
and metric views read; the glossary view is bound to the attach name
`ws`; no comments are written. Done when: a suite opens a lake built
by the server with DuckDB and the `ducklake` extension only, under
another attach name, and finds each table's, column's and metric's
meaning and unit as a comment, and reads the glossary's rows.
