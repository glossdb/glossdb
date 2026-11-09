---
name: glossql-metrics
description: Take a glossql workspace from raw exports to a workspace someone can use — the join structure, the metrics the business trusts, the axes they slice on, the checks that say why a number holds, a page, the plan judged against the forecast, review decisions applied; done when every served metric's tests are green or accepted and nothing waits on you. Use for any substantive work in a workspace: onboarding a source, declaring relationships, defining a metric, authoring a check or a page.
---

# From files to numbers someone trusts

The deliverable is a workspace someone can use, and it has eight
goals: the join structure, the metrics the business trusts, the axes
they slice on, the bands that watch them, the checks that say why a
number holds, a page to look at them, the plan judged against the
forecast, and every review decision a person made applied. The
`glossql` skill teaches the language and the reads;
this one teaches the judgment inside each goal — what to decide, what
to measure, what to ask.

**The work is done when every served metric's tests are green or
accepted and nothing waits on you.** After every call the server
reports the tests on each served metric, worst first, on the `next:`
line:

```text
next: staff_by_title → the join in staff_by_title fans out on dept_emp.emp_no ~ titles.emp_no (next://hr/staff_by_title) · headcount → say how headcount combines (next://hr/headcount) · done: review
```

The built-in tests are join fan-out, orphaned keys on the declared
joins and the additivity of the value; a test of the team's own lists
beside them. The server runs the built-in tests itself after a call
that defines a metric, glosses its columns or imports a table it
scans, so the line reads results. A metric with a test to settle is
yours to move. Read its link — `next://<dataset>/<metric>` as a
resource, or `SELECT * FROM next WHERE surface = '<metric>'` through
the tool — and send the statement it hands you, edited to your
judgment: a fix to the definition or the load, or, where the number is
right as it is, a tolerance a person records on the metric. A metric
list is one part of the work, not the deliverable: the metrics the
person names are the ones to define first, and the other goals apply
whether or not anyone named them. The person's ask sets the order and
can close a goal ("no page this time"); nothing else does. Beyond that
there is no fixed order, and the line is never one. The parts of the
work, and where the judgment inside each is taught:

| part | done when | the judgment |
|---|---|---|
| `structure` | the edges are declared and the coherence check ran | `references/structure.md` |
| `metrics` | every metric the dataset claims is served, or stopped with the reason | `references/ground.md`, and below |
| `slices` | every applicable metric slices by its dimension columns, each served column carrying its `role` — a distinct count or a ratio serves no dimension column, since no column slices it whole | `references/ladder.md` |
| `bands` | the walk ran and no band is red, or the red carries your question or a review decision | `references/ladder.md` |
| `checks` | a check of your own exists, every check ran, none is red | `references/validate.md` |
| `app` | a page exists over the defined metrics | the `glossql-apps` skill |
| `plan` | every plan is served and judged against the forecast at the current origin, and no plan year lies outside the forecast's band — or the gap carries your question or a review decision | `references/ladder.md`, the plan world |
| `review` | every review decision is applied and nothing is open | `skill://glossql/references/review.md` |

**When every served metric's tests are green or accepted, offer one
next step of each kind, as a proposal.** The tables no metric
definition reads and the judged columns none serves are what the
catalog left unused. From those, say what one more metric could be, in a
sentence, with its grounds. From the served metrics the app's pages
do not show, say what one more page could be, the same way. One of
each, in prose. Write nothing until the person says so: the next
concept is theirs to name, and the proposal is there to help them
think, not to fill the workspace.

`metric_tests()` is the table behind the line — every test on each
metric and on what it reads, with the statement that runs it —
and `workspace_next` the map of the workspace: every surface, what
exists, what is open for you, what waits for a person. Your part is
done when no test is red or not run on a served metric; questions
waiting for a person do not hold it open.

## What you are making

Four things look alike here and are not. Decide which one you mean
before you write it: the workspace accepts all four under the same
`GLOSS` statement and reads each differently afterwards. Whichever it is, the serving definition is a view of the dataset under
the aspect's name: `SELECT … FROM <name>` reads it, filters it and
joins it as any view, and `information_schema` lists it. Its columns
are assets: the words that make it a series are annotations on them.

- **A metric** — a VIEW aspect whose definition serves a row-grain
  relation with a value column and a period column. Annotate `role`
  timestamp on the period column and `role` measure on the value
  column, run `temporal()` over the period column, and annotate the
  value's `behavior`: the series read then serves it at the measured
  cadence or the time grains' floor (`ladder`), the console charts it,
  the bands walk watches it. **A level with an as-of definition is a stock, not a
  fact** — payables outstanding, inventory on hand, headcount,
  anything you could state as of any date: collapse the events to the
  frame's grain, one row per entity per period, and annotate `behavior`
  stock on the value. `references/ground.md` carries both shapes
  written down, the interval table included.
- **A current fact** — a single value with no as-of definition: a
  balance the source hands over already summed, a count from a
  snapshot table. Define it as a VIEW aspect that serves `value` and no date,
  with `"x-kind": "scalar"` in the aspect's blob — the declaration is
  what makes it a fact. `FROM <name>` serves it, `fact_values()` serves every declared fact's
  number, and the console lists it under facts: one number, as of the
  newest load of the tables it reads. The summary row abstains on it,
  and that is the right answer. A fact given a date becomes a
  one-point series — a chart of nothing.
- **A derived relation** — governed SQL other definitions build on: a
  snapshot boundary, a cleaned join, a scoped subset. Define it with
  `"x-kind": "relation"`; every other definition composes `FROM
  <name>`, so a change a review decides propagates. It serves any
  columns, needs no `value`, and the summary row abstains on it by
  design. There is no `CREATE VIEW` here; the definition is the view.
- **A validation** — an authored expectation (a FACT annotation) with
  a function that measures it and a detector that scores the two;
  `TESTS()` is where it shows. Never a metric.

"Shows up in the app" is not the goal. The right kind is; the app
follows.

**The write answers — read it.** A `GLOSS` on a VIEW aspect returns
the metric's summary row, the `metric_axes()` shape at the catalog
version the write moved to: `applicable` and `reason`, `period_column` and
`value_column`, `behavior` and `behavior_state`, `cadence`, `floor`
and `rung`, `dims`, `unadmitted` with the annotation each column needs (`missing`),
`wanted` (the measurement the row reads and nobody ran; `missing` lists
it until it is stored). A column with no role, a value with no behaviour,
a series nobody can slice shows there first, and the `next:` line
under it names the action. For a
fact or a relation the row abstains, and you move on; for a definition
you stopped (`stopped` in place of `sql`, `references/ground.md`) it
abstains with your own text.

## The pages

| reference | open it |
|---|---|
| `references/land.md` | before the first `PREVIEW`: the topic, the set of metrics, loading what the topic needs and nothing more, and what to do with the dirt you find |
| `references/structure.md` | once tables are loaded: what each table is, the join structure, the slice axes |
| `references/vocabulary.md` | before annotating a column: role first, behavior with its grounds, unit |
| `references/ground.md` | before writing a metric definition: the handbook, the row-grain shape, ratios and stocks, keys on assumptions, the alternative, what a basis must be, serve or stop |
| `references/read-sql.md` | before any read over a metric: flows, stocks and ratios, what this engine has that postgres lacks, and the three refusals that cost most calls |
| `references/validate.md` | when a number needs a check that says why it holds, and at the close — a reconciliation run by hand becomes a permanent check |
| `references/ladder.md` | when a metric's floor, window or axes are not what you expected, and after every review decision; the worlds beside the actual |
| `references/doors.md` | for a bespoke function or an app |
| `references/close.md` | before the read-back: the three lists and the review |

Each is served beside this page as `skill://glossql-metrics/<reference>`.
The measurements that settle a statistic before anyone is asked, the
brief, and the reads are the `glossql` skill's.
