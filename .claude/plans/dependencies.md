# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. What is built works as a build system does and is stated
in the language's `SPEC.md` §6 and `docs/extending/kits.md`: a
function's body says what it reads, a stored result keeps one input
per read with a digest of what the read returned, a result is current
while each read returns the same, `results_due()` lists what the
views want that is missing or out of date, the server computes it
after a write, and `next` lists what only an actor can do.

What is open is the grain. A change is known for a whole set, and a
result holds a whole set, so one change puts more out of date than it
touched.

## Open, in risk order

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| A result's subject is the finest thing it is about. The scenario estimate is one result per metric with every scenario inside, the expected ranges one per dataset with every metric inside; declaring a scenario puts every stored estimate out of date, and an actor cannot ask for one scenario. A scenario becomes a subject as a plan is; the server loops over subjects | Medium: a scenario is an annotation on the dataset today, so the lineage gets a node and an edge | `kits/outlook/kit.sql`, the extension's lineage kit | Next | #246 |
| An input per element of a read, not one digest for the set: the stored input says which column, relationship or scenario differs, and a result of several rows is out of date per row | High: the design is not written; a body is SQL, and which row used which element is known only where the function runs per element | the extension (`inputs`, `glossql_outdated()`), `SPEC.md` §6 | After a design page, tried on the shipped functions | |
| A digest per asset built from its own statements and from what it contains and reads, as a version tree is. A write changes the digests on the path up from what it touched; the out-of-date check follows that path (today it is computed whole on each write, 0.06 s of 0.24 s). A result stored under the digest of what it read is found again when a change is undone, and a failed result does not replace a good one for another input | High: the lineage is not a strict tree (a view reads tables, a relationship has two ends) | the extension's catalog and runner | With the row above, on the same page | |
| Data is a table's version, not its content: any load puts every result that read the table out of date; a replace load of identical rows computes once more (comparing costs 60 to 160% of the load) | Low until a workspace loads often | the extension | Not planned | |
| An interrupt during a computation and the Postgres catalog's lost-race path are not run by a test | Low | the extension (`glossql_runner.cpp`) | With a Postgres catalog in CI | #247 |

## Measured

Server: 121 tests pass. Extension at `3fa3d78`: its SQL
suite passes, lint clean; its changes since `96b34b7` were reviewed
line by line by two reviewers, the findings fixed with a test each.
glossval's series capture equals each metric's own SQL. On the Formula
1 data (9 tables, 4 metrics, 1 table view), one MCP call each: an
annotation or a relationship no view's checks read 0.24 s, 0 results
(1.00 to 3.2 s, 4 to 12, before the read functions); `role` on a
served column 0.46 s, 1; a table view over three tables 1.73 s, 10.
Per write: `results_due()` 0.15 s, `next` 0.05 s, the write 0.008 s.

**The outlook and plan kits against glossthesi `976842b`**, over MCP
on the MTA subway data (48 months sent; two metrics with dimensions,
a 4-month metric, a plan, three scenarios). Each function, read, code
and refusal holds as used; a load puts each stored result out of date
in `next` and calls no service; an unrelated annotation leaves them
current. Per call: ranges 0.7 to 1.4 s, forecast 0.7 s, scenario 2.3
to 3.5 s, plan 1.0 s. Fixed on the way: a temporal profile out of
date after a load kept every result out of date; a short metric read
`history_short` with one month; no `coverage_datasets`; a failed
scenario run not served; a service that does not answer not classed
`service_failed` (the extension).

Each metric in its own request against a dataset's two in one,
one-step backtest at 24 origins on 48 months, measured. Quantile loss
as % of the mean actual; share inside 10-90 and 5-95; alone / together:

| Dataset | Metric | Loss % | Inside 10-90 | Inside 5-95 |
|---|---|---|---|---|
| MTA subway | trains run | 0.74 / 0.70 | 0.75 / 0.75 | 0.92 / 0.92 |
| MTA subway | trains scheduled | 0.70 / 0.71 | 0.79 / 0.83 | 0.96 / 0.96 |
| BIRD bank | transactions | 1.63 / 1.64 | 0.88 / 0.88 | 0.88 / 0.88 |
| BIRD bank | amount | 1.40 / 1.46 | 0.92 / 0.96 | 0.96 / 0.96 |
| rel-stack | votes | 1.39 / 1.38 | 0.79 / 0.79 | 0.92 / 0.96 |
| rel-stack | edits | 1.29 / 1.31 | 0.83 / 0.83 | 0.96 / 1.00 |

Per metric costs nothing measurable: at most 0.06 points of loss, 1 in 24 inside a range.

## Next issue (draft)

**The design page for the grain** (rows 2 and 3). What it buys: a
change puts out of date what read it and nothing beside, and the
check after a write costs by what the write touched. What is there:
`inputs` (one row per read, `docs/specification/tables/inputs.md` in
the extension), `lineage()`, `glossql_outdated()`, the three cases
that showed the grain (`relationship_coherence`, since split per
relationship; #246; the temporal profile after a load). Done when:
one page states the digest of an asset, what a read stores, and when
a row of a result is out of date; it is tried on `metric_scenario`,
`metric_ranges` and `orphan_check` in a scratch workspace with the
same answers as today and the three cases named per element; the
`SPEC.md` §6 diff is shown to the project lead.
