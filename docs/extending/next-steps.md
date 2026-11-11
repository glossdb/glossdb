# Next steps

`next` is the work list of a dataset: what is open, by step of the
data intelligence layer. It is read from the states the catalog
already holds, so nothing is stored about it. It is context: the
agent, or the person reading it, decides what to do.

## The steps

| Step | A row is open when |
|---|---|
| `connect` | the dataset has no table; a person approved a change to a load query and it is not declared yet |
| `describe` | a property the kits require is missing on a table, column, relationship or metric that a metric reads; a description is outdated; a value is in conflict |
| `test` | a test on a metric is red, orange, yellow or has not run |
| `decide` | a person decided an assumption and the definition does not carry it yet; a question waits for a person |
| `serve` | no view is defined (a metric, a single value or a table); a metric cannot be served as a series |

The same list serves two situations. While the layer is built, rows
are `missing` or `not_run`. Once it runs, a load can open rows again:
a description is `stale` when the type of its column or its derivation
in the load query changed, a test turns red, a value leaves its
expected range (preview, where a model service is named).

The list is narrowed to what the metrics read. A table no metric
reads opens no row under `describe`.

## Reading it

```sql
SELECT priority, step, asset, state, who, open, cause, statement FROM next
```

One row per asset and state, in this order:

- `priority`: 1 a number is wrong or withheld (a red test, a
  conflict); 2 something changed or was decided (an outdated
  description, a decision to apply); 3 not there yet (missing, not
  run); 9 waiting for a person.
- `ord` and `step`: the step and its order.
- `asset`: the dataset, table, relationship or metric.
- `state`: `missing`, `stale`, `conflict`, a test's state, `decided`,
  `waiting`, `blocked`.
- `who`: `agent`, or `person` for a question in the review queue.
- `open`: the finding in one sentence.
- `for_metric`: the metrics that read the asset.
- `cause`: on an outdated description and on a test that is not
  green, what the newest load changed: its row count against the load
  before, and the columns whose profile moved (distinct values, share
  empty, lowest, highest).
- `statement`: the statement that opens the work, filled from the
  catalog, with `<…>` where only the author can fill in
  ([views and table functions](../reference/reads.md#next)).

Over MCP, every tool result on a dataset ends with the count of open
rows per step and the first row of the list:

```text
next: describe 7 · test 1 · waiting for a person 1
first: test hr.headcount (red): validity_test: headcount reads dept_emp (from_date, to_date) without bounding both validity dates, so a row counts once per version (next://hr/test)
```

Rows that wait for a person are counted apart and are not the
agent's. Each link is a resource, `next://<dataset>/<step>`, which
serves the step's rows with cause and statement as markdown;
`next://<dataset>` serves every step
([MCP interface](../reference/mcp.md)).

## The tests behind a metric

The metrics kit ships four tests on every metric, over the tables its
definition scans: `fan_out_test`, join fan-out; `orphan_test`,
referential integrity on the declared joins; `validity_test`, an
effective-dated table read without both of its dates;
`measure_additivity_test`, whether the value column says how it adds
up. The server runs them after a call that defines a metric,
annotates its columns or loads a table it scans. It also runs the
measurements they read: a profile of every column the metric reads
and the relationship check of the dataset. `metric_tests()` lists
every test on each metric and on what it reads, a team's own tests
included ([views and table functions](../reference/reads.md#metric_tests)).

A result that predates a change to what it read keeps its state, and
the server runs it again at the next call that touches the metric.

## A test brings its advice

A test's check returns two fields beside its rate:

- `finding`: one sentence on what is wrong and what it does to the
  number;
- `fix`: the statement that settles it: a fix to the definition or
  the load, or, where the number is right as it is, a tolerance a
  person can overrule.

`next` serves both as they are. A kit that adds a test on a metric
adds its rows to `next` with it and changes nothing else.

```glossql
DECLARE ASPECT currency_check WITH $${
  "type": "object", "x-subject": "metric",
  "properties": {"breach_rate": {"type": ["number", "null"]},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION currency_check FOR GLOBAL AS $$
  SELECT 1.0 AS breach_rate,
         'the value sums amounts in more than one currency' AS finding,
         main.metric_redefine(split_part($subject, '.', 1), split_part($subject, '.', 2)) AS fix
$$ RETURNS currency_check;

DECLARE TEST currency_test ON currency_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;
```

`x-subject: metric` marks a test the server runs on every metric.
`metric_redefine(dataset, metric)` returns the statement that records
the metric's current definition again, to edit and send.

## What a kit adds

- **A required property** (`DECLARE ASPECT` with a condition for when
  it is required) opens a `describe` row where it is missing on an
  asset a metric reads.
- **A test on a metric** opens a `test` row while it is not green,
  with its own finding and fix.

Test both in the kit's suite, as the shipped kits do: check the step,
the asset and the state of the row, and the statement it hands over.
