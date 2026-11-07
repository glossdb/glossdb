# Grounding — read before writing a metric's SQL: the registries, the row-grain shape, ratios and stocks, the rival, serve or stop

## Define the metrics

One QUERY aspect per concept, on the dataset. The aspect blob is thin
— declarations are never replaced by a newer version, so anything the
company might revise belongs in the `definitions` annotation, where a correction
supersedes with actor and timestamp. A field lives in exactly one
place, never both.

```glossql
DECLARE ASPECT throughput WITH $${"title": "Throughput", "x-kind": "measure"}$$ AS QUERY;
```

**One registry ships with the kit, the handbook — annotate into it,
never redeclare.** `definitions` is FACT on the dataset, keyed by the
concept's own name. An entry holds what the company revises: meaning,
unit, owner, source, and for a derived metric its formula.

The `formula` is the metric's **definition** over sibling concepts, a
window-generic expression with the window `w` as its one free variable.
`[w]` reads the window as a flow, `[end of w]` as a stock, `[w-1]` is
the previous one. It covers every window because it names none, and it
is the decided definition: the stored SQL is one evaluation of it, not
a replacement for it. Operands name sibling concepts, plus
window-derived constants like `days[w]`. Nothing validates them; a
misspelled sibling is silent, so read your own operand names back
against `SELECT name FROM aspects WHERE kind = 'query'`. A base
concept defined as an extract has no formula.

Whatever sits in a `WITH` blob cannot be corrected, contested or
outranked once anything is annotated on the aspect. The blob keeps only
the `title` display label and the `x-kind` tooling flag. A unit
written in both copies goes out of date in one. `x-kind` lives in the
`DECLARE ASPECT` blob and nowhere else; the schema of the metric
definition's body refuses it.

```glossql
GLOSS definitions ON ops AS $${"definitions": {
  "throughput": {"meaning": "work completed and accepted; counted at completion date",
                 "unit": "hours", "owner": "Operations", "source": "KPI handbook v3 §2"},
  "backlog_days": {"meaning": "open work expressed in days of current throughput",
                   "unit": "days", "owner": "Operations", "source": "KPI handbook v3 §2",
                   "formula": "backlog[end of w] / throughput[w] * days[w]"},
  "net_completions": {"meaning": "completions net of reopens", "unit": "count",
                      "formula": "completions[w] - reopens[w]"},
  "throughput_growth": {"meaning": "throughput against the previous window", "unit": "ratio",
                        "formula": "(throughput[w] - throughput[w-1]) / throughput[w-1]"}
}}$$;
```

The registry is a single annotation, so a write replaces the whole map.
Read what is there before adding to it — a second concept annotated
blind drops the first one's entry:

```sql
SELECT g.aspect, g.body FROM glossary g
JOIN current_dataset d ON d.dataset = g.dataset
WHERE g.aspect = 'definitions' AND g.actor_kind = 'agent'
ORDER BY g.written_at DESC
```

The join is required: `glossary` serves the whole workspace, and
reading another dataset's registry before rewriting this one drops
every entry this dataset holds.

**A flow's definition carries no grain** — no GROUP BY, no window. It is
the semantic core: scoping, signs, grain-preserving joins composed
inline, served as a row-grain relation with the time axis and the
judged dimensions as columns.

**A stock is the exception.** The running level already aggregates the
events, so the frame must collapse to its own grain — one row per
period, or one per entity and period with the entity served as a
column. Served at event grain, every row on a date carries the same
correct level, and the series read — which sums the rows current at
the bucket's last instant, because that is how a multi-account
balance totals — multiplies the level by the day's event count. The
number is exact on every row and wrong in every sum. An interval
table is a stock with two event columns, `+1` at the start date and
`-1` at the end date, unioned into one served date. Annotate `behavior`
stock on the value column with its grounds — a value without it does
not combine at all, and a value annotated flow sums. Both shapes
written down:

```glossql
GLOSS payables_outstanding ON fin AS $${
  "sql": "WITH daily AS (SELECT entry_date, sum(amount) AS delta FROM journal_lines GROUP BY entry_date) SELECT entry_date AS date, sum(delta) OVER (ORDER BY entry_date) AS value FROM daily"
}$$;
GLOSS role ON payables_outstanding.date AS $${"value": "timestamp"}$$;
GLOSS role ON payables_outstanding.value AS $${"value": "measure"}$$;
GLOSS behavior ON payables_outstanding.value AS $${"value": "stock", "grounds": "the running balance at the day's end"}$$;
```

```glossql
GLOSS headcount ON hr AS $${
  "sql": "WITH events AS (SELECT from_date AS date, 1 AS delta FROM stints UNION ALL SELECT to_date AS date, -1 AS delta FROM stints WHERE to_date IS NOT NULL), daily AS (SELECT date, sum(delta) AS delta FROM events GROUP BY date) SELECT date, CAST(sum(delta) OVER (ORDER BY date) AS DOUBLE) AS value FROM daily"
}$$;
GLOSS role ON headcount.date AS $${"value": "timestamp"}$$;
GLOSS role ON headcount.value AS $${"value": "measure"}$$;
GLOSS behavior ON headcount.value AS $${"value": "stock", "grounds": "open stints at the day's end"}$$;
```

A flow, written down, with its judgment disclosed:

```glossql
GLOSS throughput ON ops AS $${
  "sql": "-- completed work: hours per closed order, at completion date, with its judged axes\nSELECT w.completed_at AS date, w.duration_min / 60.0 AS value, w.region, s.service_line FROM work_orders w JOIN sites s ON w.site_id = s.id WHERE w.status = 'closed'",
  "assumptions": [
    {"dimension": "scope", "key": "closed-only", "assumption": "closed orders only; cancelled and reopened excluded", "basis": "status values + judgment", "confidence": 0.7},
    {"dimension": "behavior", "key": "throughput-is-a-flow", "assumption": "a flow: sums valid over any partition", "basis": "minutes per visit, one row per visit", "confidence": 1.0}
  ]
}$$;
```

**Say the mechanics inside the SQL as comments**; the assumptions
array carries judgment. A comment inside the query cannot drift from
the query the way a separate description can.

**A basis that names a computation is a claim to verify, and prose is
not the tie.** "Ties to GL 4* net" names a route you can run. An
assumption that carries it while the SQL computes something else
drifts silently: every review confirms the words, and no review
decision on the words repairs the numbers. Run the named route against the served
frame before recording the basis, and keep the claim machine-checked
after the session — disclose the route as `alternative_sql` so
divergence measures it on every read, or promote it to a permanent
check (`references/validate.md`). A route that exists only in your
head is judgment: write that as the basis and hold the confidence
below 1.0.

**A composed ratio serves only the axes its composition carries.** The
series slices on the dimension columns an extract *serves*, so a
ratio that groups to `(date, value)` can never be sliced — a set of
metrics defined entirely that way serves headline numbers nobody can
cut.

**The axes are the served columns you annotate.** A served column
slices the metric when it carries `role` dimension; a `dimension`
annotation ranks it, `primary` first, `none` closes it. A distinct count sliced by a
column double-counts across members, and a ratio sliced by its own
discriminator reads one and zero: serve those two shapes with no
dimension column. The write's row names the served columns with no
role and the annotation each needs.

A ratio is never drilled from its output rows. Drilling backlog days
by region means **re-scoping its components per the `formula` in its
handbook entry**
— each operand evaluated at the new scope, then the formula applied
per member. The stored SQL below is that recomposition written down
for one choice of axis; the formula is what it was written down from:

```glossql
GLOSS backlog_days ON ops AS $${"sql": "-- backlog days by region as well as in total.\nWITH bl AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS bal FROM backlog GROUP BY date_trunc('month', date), region), th AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS th FROM throughput GROUP BY date_trunc('month', date), region) SELECT CAST(bl.m AS DATE) AS date, bl.bal / nullif(th.th, 0) * 30.0 AS value, bl.region FROM bl JOIN th ON bl.m = th.m AND bl.region = th.region"}$$;
```

Two things this is not: it is not a roll-up (each member's ratio is
computed from its own numerator and denominator, never averaged), and
it is not free — an axis you carry must exist on both sides, so pick
the axes the question actually needs rather than every one available.

**A ratio must serve its halves beside `value`, and name them.** Annotate
`behavior` ratio on the value column with `numerator` and
`denominator` naming the served halves: they are how the series and
the bands walk total it — `sum(num)/sum(den)` at every grain, which
is right for the headline and for every member. A value annotated flow
is **summed** — a dozen member ratios added into one wrong headline,
an order of magnitude off its true value. Nothing infers this from
the SQL — serve the columns and annotate the claim.

```glossql
GLOSS backlog_days ON ops AS $${"sql": "WITH bl AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS bal FROM backlog GROUP BY 1, 2), th AS (SELECT date_trunc('month', date) AS m, region, sum(value) AS th FROM throughput GROUP BY 1, 2) SELECT CAST(bl.m AS DATE) AS date, bl.bal / nullif(th.th, 0) * date_part('day', bl.m + INTERVAL '1' MONTH - INTERVAL '1' DAY) AS value, bl.bal AS num, th.th * (1.0 / date_part('day', bl.m + INTERVAL '1' MONTH - INTERVAL '1' DAY)) AS den, bl.region FROM bl JOIN th ON th.m = bl.m AND th.region = bl.region"}$$;
```

**A distinct count is the same class without halves.** The series sums
same-period rows, and distinct customers per (doc type, sales org) do
not sum to distinct customers per month — a distinct count served with
dimension columns reports a wrong total, and nothing infers this from
the SQL. Serve it at the scope the metric is asked at, with no
dimension columns, and say so in a keyed assumption; per-member
distinct counts are separate metrics or a drill recomputed from the
entity rows.

`value` stays each row's own ratio — that is what `backlog_days`
serves and what a drill shows. `num` and `den` are the same division's
halves, scaled so their quotient is the metric in its own unit: here
the day factor sits in the denominator, so `sum(num)/sum(den)` is days.

**`sign` and `grain` are settled before you store the definition, at
1.0.** A sign convention is the source's `conventions` annotation and a grain is what
your frame serves — statistics and declarations are your work,
never a question for the review. Below-1.0 confidence is for judgment
dimensions: definition, scope, convention. The inverse holds: a
defensible default does not raise a judgment dimension to 1.0. What
"on time" means, which accounts count, whether partly paid rows
belong — record the default you chose at the confidence it deserves,
and the review serves it for confirmation. Judgment recorded at 1.0
silences the review on exactly what it exists to ask.

**Behaviour is claimed, never defaulted.** The series combines a
metric's rows by the `behavior` on its value column — flow, stock or
ratio — and refuses to combine them while there is none; the write's
answer says so, and `owed` lists the annotation until it is stored. The claim
is yours, with its grounds: the column's meaning and the table's
grain, never a name. The test (`WITNESS`) scores disagreement between actors and
measurements, and `metric_axes().behavior_state` says where the claim
is — `current`, `contested`, `none` where nobody annotated it.

**After defining, run `detect_grounding_collisions`.** Two concepts
defined as the same extract make every ratio between them compute
1.0, silently. A reported pair is either a deliberate synonym — say so
— or a definition error.

**Name the strongest alternative, as SQL that runs.** Definitional risk is invisible
from inside your own judgment; it shows only against an alternative.
An assumption may carry one:

```json
{"dimension": "definition", "key": "cycle-time-basis",
 "assumption": "cycle_time runs from dispatch to completion",
 "alternative": "from order creation to completion",
 "alternative_sql": "SELECT w.completed_at AS date, ... FROM ...",
 "basis": "operations convention", "confidence": 0.7}
```

Run the alternative yourself at the grain the question lives at and record
what you found in the basis; a second route the source data carries is a
check to promote (`references/validate.md`). Start where the families
diverge hardest.

**Search the source data for a second path.** The strongest alternative
is often not an alternative definition but a second route to the same number the data
already carries — a published statement beside the journals, a control
account beside its subledger, any declared relationship that offers
another aggregation path. Look for one per served metric; a found
path is stored as an assumption with `alternative_sql` at the confidence
your judgment gives the discrepancy, and "no second path exists" is
itself a finding worth recording. A contradiction the source data carries
and nobody measured is a question nobody will ever be asked. A
derived metric inherits no alternative from its components: when the
source data carries a statement line for the subtotal itself, that
line is the alternative — component ties do not replace it.

**Four defaults where the brief is silent.** Define on the row-level
path; a pre-aggregated or denormalized column beside it is the second
path, never the basis. A ratio of sums takes each row whole: a null in
either half drops the row from both. Metrics on one set of rows share its
anchor — the same date column, the same year — unless the brief says
otherwise. The impossible goes and the implausible stays: exclude what
violates an identity, keep what is merely an outlier, and disclose
both. A null key does not unmake a row: a count takes every row
unless the brief names the entity counted, and the null share is a
disclosure beside the number, never an exclusion.

## Serve or stop

The dirt you measured at load reaches the metric here. Two cases,
and the measure decides which.

**Serve with disclosure** when the dirt is bounded: you can say how
many rows it touches and which way it moves the number. Define the
metric and carry the finding as a keyed assumption below 1.0 —
dimension `scope` for rows in or out, `convention` for a recode — with
the count in the `basis`. The number is served, the flaw is visible in
the console's open count, and the review asks the person.

**Stop** when the dirt is not bounded: the evidence rows are missing
rather than wrong, a join key cannot be trusted, the column the metric
needs was never loaded. Do not serve a number from a proxy. Record the stop
as the metric definition — `stopped` in place of `sql`, the finding as its
text: what is missing, where, how much, and what closes it (an
upstream fix, a review decision, a recipe change). The assumptions come
with it as with any definition, so the review still asks the judgment
behind it. Say the
same in chat, and write the `definitions` entry: a stopped metric is a
finding, not a failure, and the user learns something about their data
they did not know.

```glossql
GLOSS utilization ON ops AS $${
  "stopped": "capacity never landed: the roster export carries no hours column, so hours worked / capacity cannot be served; closes when the roster export adds capacity_hours, or a ruling names contract hours as capacity",
  "assumptions": [
    {"dimension": "definition", "key": "capacity-source", "assumption": "capacity is the roster's planned hours, not contract hours", "basis": "operations convention", "confidence": 0.6}
  ]
}$$;
```

The write answers with the summary row, `applicable` false and your
own text as the `reason` — that is the check that it was stored. The
query endpoint refuses with the same text, `metric_surfaces` serves it
as `stopped`, and the console says so beside the name. A person's
definition with `sql` outranks it, which is how a stop is lifted.

A plan, a schedule, a calendar is never evidence that its events
happened. Count what happened; check the plan's coverage as a validation.
