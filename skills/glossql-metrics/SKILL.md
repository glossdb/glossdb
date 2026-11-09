---
name: glossql-metrics
description: Take a glossql workspace from loaded tables to metrics someone can trust — relationships, metric definitions, the tests on each metric, the questions a person must decide. Use for any substantive work in a workspace: loading a source, declaring relationships, defining a metric, writing a test or a page.
---

# From tables to metrics someone trusts

The `glossql` skill teaches the statements. This page is the work, in
order. Do what the person asked; this is how each part is done well.

**You are done when the `next:` line shows every metric under `done:`
and nothing under `review` waits on you.** Questions waiting for a
person do not hold you back.

## 1. Look at the data

List the tables and columns (`information_schema.columns`), read a few
rows, profile what you will use (`SELECT column_profile() FROM
orders.amount`). Load only what the question needs
(`references/land.md`).

## 2. Find the joins

```glossql
SELECT detect_relationships() FROM ops;
```

Read the candidates, check the ones you will use against the data, and
declare those: `DECLARE RELATIONSHIP orders.customer_id ->
customers.id;`. Then `SELECT relationship_coherence() FROM ops;` so
orphaned keys are measured. A table whose rows are valid from one date
to another (prices, titles, assignments: one key, many versions) is
effective-dated. Say so once:

```glossql
GLOSS validity ON titles AS $${"valid_from": "from_date", "valid_to": "to_date"}$$;
```

Details: `references/structure.md`.

## 3. Define each metric in one statement

A metric is SQL with one row per period and slice. Say which column is
the time, which the measure and how it adds up, and which columns
slice it:

```glossql
DECLARE ASPECT headcount WITH $${"title": "Headcount"}$$ AS VIEW;
GLOSS headcount ON hr AS $${
  "sql": "SELECT p.period, de.dept_no, count(*) AS value FROM periods p JOIN dept_emp de ON de.from_date <= p.period AND de.to_date > p.period GROUP BY 1, 2",
  "time": "period",
  "measure": {"column": "value", "additivity": "semi-additive", "unit": "people"},
  "dimensions": ["dept_no"],
  "assumptions": [{"dimension": "definition", "key": "as-of", "assumption": "headcount counts people with an open assignment at month end", "basis": "dept_emp from_date and to_date", "confidence": 0.8}]
}$$;
```

- **Additivity.** `additive` sums over time and members (revenue,
  orders). `semi-additive` is a level: it sums over members, never
  over time (headcount, a balance, stock on hand); serve one row per
  entity per period. `ratio` names its `numerator` and `denominator`
  columns and is re-divided. A distinct count or a median adds up from
  nothing: serve it without dimension columns.
- **Assumptions.** Every judgment call you made goes in `assumptions`
  with a stable `key` and a `confidence` below 1: which rows count,
  which date, which status. That is how a person sees and decides it.
  Never guess silently, and never ask a person for something the data
  can tell you (`skill://glossql/references/settled.md`).
- **No number is better than a wrong one.** Where the data cannot
  serve the metric, record `{"stopped": "<what is missing>"}` in place
  of `sql`.
- The statement answers with the metric's summary row. Read it:
  `applicable` false comes with the `reason`.

A single value with no date is declared with `"x-kind": "scalar"`;
SQL that other definitions build on with `"x-kind": "relation"`.
Shapes written down, ratios and levels included: `references/ground.md`.

## 4. Read the tests and fix what is red

The server runs these on every metric after you define it, annotate
it, or load a table it reads:

| Test | Red when |
|---|---|
| `fan_out_test` | the join repeats rows: two tables share a key that repeats on both sides |
| `validity_test` | an effective-dated table is read without bounding both of its dates |
| `orphan_test` | rows on a declared relationship find no parent |
| `measure_additivity_test` | the measure does not say how it adds up |

The `next:` line after every call names the worst one per metric:

```text
next: staff_by_title → staff_by_title reads titles (from_date, to_date) without its validity dates (next://hr/staff_by_title) · done: headcount, review
```

Read `SELECT say, why, statement FROM next WHERE surface =
'staff_by_title'` and send the statement it gives, edited: fix the
definition or the load. Where the number is right as it is, record a
tolerance with the reason; a person can overrule it. Every test with
its evidence: `SELECT * FROM metric_tests()`.

A check of your own (a total that must tie out, a rate that must stay
under a bound) is a test too: `references/validate.md`.

## 5. Questions and decisions

Assumptions below full confidence become questions for a person. Their
answers arrive as review decisions; `next:` shows `review → …` when
one waits. Apply it by recording the definition again with the decided
assumption at confidence 1.0 (`skill://glossql/references/review.md`).

## More

| Page | When |
|---|---|
| `references/land.md` | loading: what to load, typing, dirty rows |
| `references/structure.md` | what each table is, relationships, hierarchies |
| `references/vocabulary.md` | annotating a source column: meaning, role, unit |
| `references/ground.md` | metric definitions in depth |
| `references/read-sql.md` | querying a metric: `metric_series()`, levels and ratios, engine specifics |
| `references/validate.md` | writing your own test |
| `references/time-grains.md` | time grains, and the preview features: expected ranges, forecasts, plans, scenarios |
| `references/doors.md`, `skill://glossql-apps/SKILL.md` | a function of your own, a page over the metrics |
| `references/close.md` | the summary you hand back |
