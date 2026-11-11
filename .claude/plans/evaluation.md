# Evaluation plan

glossval measures the data intelligence layer as data middleware: raw
sources go in, cleaned tables in a given format come out of the lake.
An agent gets the raw files and a contract (table, key, columns, types,
meanings, code tables) and builds the table in glossdb. The score is a
diff against a reference that an independent party cleaned. The reader
of a built lake uses DuckDB with the `ducklake` and glossql extensions;
DuckLake's own schema is not changed. The accuracy of one answer
inside glossdb stays one angle and is no longer the headline.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The contract seat runs through the harness: source mounted, nothing loaded, the contract put into the task, the built table exported from the lake and scored | Medium: `run.py` seeds tables and reads the old `next` columns; both change | glossval `run.py`, `next_state.py`, `scenarios/eia-generators/` | Next | |
| A harder slice of the same source: every month since 2015-07 against PUDL's changelog table itself. The workbooks' layout changes over the years and the target keeps one row per change | Medium: about 1.2 GB of workbooks; the first slice is too easy to separate arms (below) | glossval `gen_eia.py`, a second contract | After the first runs | |
| The running state on real loads: build on the first months, then load the later months one by one. Scored: does the table stay right, and does `next` name what changed | Low | the seat's months split in two, `next_state.py` | With the harder slice | |
| Conventions the reference follows and the contract does not state (generator ids without leading zeros, `NA` as no value): stated in the contract, or left to the builder | Low: a decision, 1% of keys depend on it | `gen_eia.py` | The project lead decides | |
| The arms of a build: the agent in glossdb, and the same agent with DuckDB only, same contract, same reference | Low | glossval `bare_run.py` | The project lead decides | |
| The tools that read the old `next` columns are adapted or deleted: `plan_lane.py`, `ab_seats.py`, `chat_agent.py`, `joint_report.py`, `score.py`, `truth_stack.py`, `truth_trial.py`, `mining/next_table.py`, `graph/graph.py` | Low once `run.py` and `next_state.py` are done | glossval | With the first row, the rest before the pull requests | |
| The read stage: a second agent reads the built lake and answers questions; against the same agent on the raw files; a third arm without the glossary | Low | glossval `bare_run.py`, `bare/duck_mcp.py` | After the build stage | |
| More real pairs: mapping across systems against a published crosswalk (EPA's plant ids to EIA's, in PUDL's archive); finance from `../glosstest`, labelled generated | Medium: not checked yet | new seats | After the EIA seat reports | |
| The existing seats rerun, the Monday test, then the results page | Low | glossval, the websites | Last | |

## What is there

- The seat `eia-generators` in glossval. Raw: EIA Form 860M, nine
  monthly workbooks of 2026, every sheet as CSV with each cell as text
  and the title rows and footnotes kept (78 MB). Reference: the table
  PUDL v2026.11.0 publishes from the same archive, one row per
  generator and month, 338,246 rows, 33 columns. Contract: generated
  from PUDL's own descriptor. Built by `tools/gen_eia.py`.
- The scorer `tools/contract_score.py`: key recall and precision, the
  share of values equal per column, the share of all reference cells
  right, the share of rows right in every column. No judge.
- Measured: the reference against itself scores 100%. A first pass by
  hand (column mapping, types, dates, status codes) scores 95.7% of
  cells and 99.0% of keys. What it misses: the sector labels do not
  match the code table's, ids carry leading zeros, `NA` stands for no
  value, a month `0` in a date.
- So this slice has little room between a careful and a careless
  build. It proves the set-up; the harder slice carries the result.
- The run harness does not run the seat yet: it loads tables before
  the agent starts and reads the old `next`.

## What the scores are

- **Build.** Cells right, keys right, rows right in every column,
  against the reference. Cost and turns beside it.
- **Running.** After a later month is loaded: the same scores on the
  new month, and whether `next` named what changed.
- **Read.** Share of answers right on the built lake against the raw
  files, same reader, same questions.

A result on generated data is labelled generated. The headline
numbers come from real data with a reference we did not write.

## Next issue (draft)

**The contract seat runs through the harness.** What it buys: the
first number on glossdb as data middleware, on real data with an
independent reference. What is there: `scenarios/eia-generators/`
(scenario, task, contract), `tools/gen_eia.py`,
`tools/contract_score.py`; `tools/run.py` seeds tables and stops on
the old `next` columns. Done when: `run.py eia-generators` starts a
server with the source mounted and nothing loaded, the agent builds
`eia.generators_monthly`, the run stops when `next` has no open row
for the agent, the table is exported and `contract_score.py` writes
its score into the run folder.
