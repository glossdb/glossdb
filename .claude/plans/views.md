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
| 1 | A check that reads its subject's rows records the subject, not the dataset: today each new view makes the reconciliation, the contract check and the key check due (measured: about 19 s per kept view on ferc-steam, 3 s on the two others). Then why the reconciliation takes 19 s on 35,000 rows | High: the dependency mechanism | the extension's read tracker (`glossql_runner.cpp`, `DataRead`) | Now |
| 2 | The extension: a definition declares its property, the kind in the body, `AS VIEW` dropped; the corpus and `grammar.ebnf` with it | High: every statement an agent writes and every fixture | `grammar.ebnf`, `SPEC.md` §5 to §7, the store, the lineage kit's places, the corpus | After 1 |
| 3 | The kits: kinds read from the body, the plain view, `rule` and its test, `tags`, the search read; `next` and `view_tests()` on kinds. What a rule view replaces in the tests reference is deleted | High | `kits/views`, `kits/goals`, `kits/core`, the extension's `kpi` kit, the console's frames | With 2 |
| 4 | One pass over every text an agent reads, in the order it meets them: the MCP instructions, the entry skill, what `next` hands out, the references, the docs, the spec. One rule, one count of statements per form; every catalog read spelled `main.<relation>` (done in what `next` and the MCP text hand out) | Medium | `crates/serverd/src/mcp.rs`, `skills/`, `docs/`, `SPEC.md` | After 3 |
| 5 | A glossval round: do agents keep their queries, and what do the kept rules catch | | `../glossval` (run only) | After 4 |
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

## Next issue

Step 1.
