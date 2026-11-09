# The plan

One table. Work happens on the branch `harness-work` in both
repositories until the table's open rows are done. Other roads, parked:
`gate.md` (access per actor), `sources.md` (workbooks, documents,
databases), `clients.md` and `chat.md` (the trial).

| # | What | State |
|---|---|---|
| 1 | `next` is the test report: per metric its worst test and the statement that fixes it, then review | done |
| 2 | The server runs the built-in tests after a definition, an annotation, a load or a measurement | done |
| 3 | The tests read stored evidence, not the data | done |
| 4 | Forecast goals as steps on the metric (outside its expected range, plan outside the forecast) plus one `outlook` goal for runs due | done |
| 5 | Glossary states `conflict` and `missing`; a test not yet run is `not_run`; `status:` line; "annotate" in served text | done |
| 6 | Effective-dated tables: `validity` on a table, `validity_test` on every metric that reads one | done |
| 7 | A metric definition carries its time column, measure with additivity and dimensions inline; the server writes the column annotations | done |
| 8 | Console: Quality opens on the tests per metric | done |
| 9 | Skills: the one-statement definition and effective-dated tables taught; the rest of the pages still to shorten | partly |
| 10 | glossval: finish line updated (uncommitted in glossval); still to do: rerun the eight seats against the stored bare runs, then the Monday test | open |
| 11 | Remaining coined words: `behavior` → additivity, `entity` → grain, `ladder` → time grains, `band` → severity, `metric_axes()`, `workspace_next`, kit, actor | open, after 10 |
| 12 | Keywords `GLOSS`, `ASPECT`, `RECIPE`: corpus forks, the lead's call | open |
| 13 | Semantic model export as Apache Ossie; lineage export as OpenLineage | open, after 7 |
| 14 | Results page and websites | open, after 10 |

## Measured

On `hr` (two metrics, 331,603 and 443,308 rows), per MCP call: any
statement 0.4 s, of which `next` is 0.33 s; a definition with its
tests 2.5 s; an annotation on a scanned table 1.8 s.

CI: the server 4 to 6 minutes; the extension 6 minutes per platform, a
pull request builds linux_amd64 alone. The server's CI waits for the
extension's build of the pinned commit before building it itself.

## Rules learned

- A red test alone is a failed test, never a conflict.
- A check that reads other functions' results re-runs when those change.
- A test with nothing to check is green with the reason, never a chore.
- A workspace made before a catalog column was added is rebuilt.
