# Views plan: what an agent keeps

The design agreed with the project lead after the glossval round on
`snapshot-version`, and the steps towards it. Work is on the branch
`views-layer` in both repositories.

## Why

The language's forms come from metrics on an engine without views: a
declared concept, an annotation per way to compute it, a function for
what a view could not hold. Measured on 38 builds: agents wrote 1,080
ad hoc reads of loaded data and kept about 3 tests per build; 4% of
their reads called a kit's function; a check of one's own takes five
statements around a query the agent had already written. The texts
explain the three forms in the metric's terms and do not say when to
use which.

## The rule

**Everything an agent keeps is a view, and its kind says what it is
for.** A function is a kit's machinery.

| Kind | What it is |
|---|---|
| none | a plain view: a query worth keeping, with its reason. Asked for no descriptions and no served-view tests |
| `table`, `value`, `metric` | what the dataset serves |
| `rule` | a query whose rows are the violations. It must return none; the kit's test runs on it with no further statement. A person accepts a count of rows, not a rate |

## The metadata, one home each

| What | Home | Replaces |
|---|---|---|
| The definition | one statement, `GLOSS name ON dataset AS {"sql": …}`, which declares the property where it is missing; the view is created and annotated in one go | `DECLARE ASPECT … AS VIEW` before it |
| The kind | `kind` in the body; a new definition may change it | `x-kind` in the declaration, with three spellings |
| The description | the `meaning` annotation; `meaning` in the body is shorthand for it, so one statement keeps a query with its reason | `title` and `description` in the declaration |
| Keywords | the property `tags`, a list, annotated on a table, a column or a view; `tags` in the body is shorthand. An actor's new list replaces its own, so `next` hands out the list with the word added; a person's and an agent's lists are read as their union. `next` shows it, a search read finds by it | `x-indicators`, read by nothing |
| The assumptions, the stop | the body, as today | |
| A metric's `time`, `measure`, `dimensions` | shorthand in the body, written as annotations; the spec says so | the spec's "never keyed in the body" |
| Words | "view definition"; a "result" is what a function stores; "measurement" is a kit's computed property | "metric definition", three meanings of "measurement" |

Grammar and names, approved by the project lead: the keyword `ASPECT`
becomes `PROPERTY` with the relation `properties` and the column
`property` (done); the relation `measurements` becomes `results`
(done); `DECLARE PROPERTY … AS VIEW` is dropped.

DuckDB's own `CREATE VIEW` in a dataset is left until access control
(`gate.md`): taking it up as a plain view needs the statement hook
that work builds.

## Steps

| # | Element | Risk | What it touches | When |
|---|---|---|---|---|
| 5 | Point agents at the checks only they can write (magnitude, units, continuity across sources), since the kit's contract test already covers key, required, codes and format | Medium: touches the levels and checks-before-descriptions, which are on hold | `next`, the MCP text, the entry skill | The project lead decides the shape |
| 6 | The queries an agent runs are logged, indexed by the columns they read, and served by the search read beside the kept views. Open: when the agent is asked to keep one; read access follows `gate.md` | Medium | the server, the extension's lineage of a SQL text | After 5 says what is still hidden |

## Measured

- Keeping two real queries as views today: two statements each, 20 to
  70 ms; `next` went from 6 to 22 rows, since each view is treated as
  served.
- 81% of the decisions in the finished views (a cast, a `CASE`, a
  filter, a lookup) have an earlier query on their source column; one
  query meets a median of 4 decisions. The columns are a hint, the
  written link is the tag and the meaning.
- The capacity rule as a view of violating rows separates the wrong
  ferc-steam build (median 205 to 230) from the right one (0.22). A
  baseline taken from the build does not: the wrong build keeps the
  wrong number.
- A rule check on a view ran in 0.15 to 0.55 s.

- The spike on three builds: with the kind read from the body, ten
  kept plain views leave `next` as it was (ferc 5, eia 6, erp 43 rows;
  today 94, 88, 146). `find(term)` over name, meaning, tags and the
  columns a view reads takes 22 to 27 ms. Of 15 hand-written checks 4
  became rule views as written, 7 with a small rewrite, 4 written as
  rates had to be restructured. The kits' diff: core +26/-2, views
  +130/-29, goals +19/-12.
- A table of the user's named `results` hides the catalog's `results`
  for a bare read while its dataset is in use.

- A check that reads its subject's rows recorded its whole dataset,
  so each view defined and each other table loaded made it due. It
  records the subject and what it reads now. The reconciliation took
  19.5 s on ferc-steam (35,333 rows) because it matched a four-column
  join one equality at a time; on the whole key it takes 0.95 s with
  the same result.

- Built and walked through MCP: a plain view kept in one statement
  with its meaning and tags (0.49 s), a rule view in one statement,
  red with its count and sample rows after the write and again after a
  load (0.6 s), `find('unit')` in 0.2 s. On the ferc-steam workspace
  five kept views leave `next` as it was and compute only their
  lineage (0.5 s a write).

- The glossval round on this branch (15 builds): cells right after the
  review as before (99.0 to 100%). 77 rule views, each with a meaning;
  no `DECLARE TEST`, no function. 56 of 59 rules on the contract cases
  restate the contract and stayed green; none checks magnitude. Rule
  views were red on 0 of 89 wrong columns. In erp-supply, 13 rules of
  the agents' own; one caught the planted brand conflict in 2 of 3
  runs. 3 of 1,237 ad hoc reads became a view. `find()` was called 17
  times, to read back a view's SQL.
- Stacked views made one gbif workspace run out of memory at 5.7 GiB:
  `place_sources` listed 26,043 scanned columns where 347 are
  distinct. Listed once each, all 37 checks compute in 9 s.

## Open beside the steps

| What | When |
|---|---|
| A kept view is not compared between loads: a profile that grows a row (a new unit, a new code) is not a row of `next`. A function or a test on the view would say it | After the glossval round shows what agents keep |
| `find()` matches a view on a column it reads only through another view: the stored lineage of a view over a view names every column the inner view reads | Before the query log, which uses the same index |
| An agent with only the MCP instructions and the entry skill does not learn the five statements of a test with a tolerance or how to write a function (a count and a link are given), nor that a person's definition outranks its own | The glossval round says whether that costs anything |
| The stored lineage of a stacked view is large (10.7 MB for one rule view, 3.5 MB of it one derivation repeated per scanned column): each reference to an inner column repeats its whole derivation | A proposal to the project lead; it changes the lineage's stored shape |
| The console lists kept views nowhere of their own | With the text pass or after |
| A rule view's scanned columns get a column profile computed, as a served view's do | Measure the cost first |
| `next` says "no view is served" as a must on a dataset that holds only kept views | Shaped with the levels, which are on hold |

## Next issue

Step 5, once its shape is decided.
