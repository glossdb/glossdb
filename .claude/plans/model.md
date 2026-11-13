# The model: what a result depends on

One page to agree on before more code. Once agreed it replaces the
design sentences of `dependencies.md` and goes into `SPEC.md` §6. The
function table is verified against each function's body.

## 1. Assets are the nodes

| Asset | Example | Has |
|---|---|---|
| dataset | `f1` | tables, views, relationships |
| table | `f1.results` | columns; rows, with DuckLake's version |
| view | `f1.race_points` | columns; a definition (SQL) |
| column | `f1.results.points` | |
| relationship | `f1.results.raceId -> f1.races.raceId` | two columns |

## 2. Statements hang on one asset

- An **annotation**: asset, property, actor, value. Written.
- A **result**: asset, function, value or error. Computed.

A statement is stored on the asset it is about. One result breaks
this today: `relationship_coherence` is one result on the dataset
for all relationships. It becomes one per relationship.

## 3. Edges, each with a kind

| Kind | From → to | Comes from |
|---|---|---|
| `contains` | dataset → table, view, relationship; table or view → column | the lake's catalog |
| `reads` | view → the tables and columns it scans and joins on; view → view | the view's SQL, resolved |
| `relates` | relationship → its two columns | `DECLARE RELATIONSHIP` |
| `plans` | plan → the metric it plans | the plan's declaration |

The edges are one relation the catalog serves (`from`, `to`, `kind`).
This relation is the lineage a person or an agent reads. Finer, later:
`reads` per output column of a view, from the SQL as JSON.

## 4. A function's body says what it reads

A function has an output, the property it returns (`RETURNS`). Its
inputs are not declared a second time: the body is SQL, and SQL reads
what it needs. That was the ruling of August, when `ACCEPTS` was
retired ("a body composes its context inline"), and it stands.

What went wrong since is where the inputs were taken from: the bound
query plan, in which macros are expanded and constants are gone. They
are taken from the body as written instead. DuckDB serves any SQL as
JSON (`json_serialize_sql`); the reads of a body are the table
functions and relations in that tree (tried on five shipped bodies:
0.03 s, every read listed). The engine derives the list when the
function is declared and stores it with the function, as JSON anyone
can read.

For the list to be exact, a body reads statements through a small
set of read functions whose arguments are the **what** and the
**where**, as constants:

| What | |
|---|---|
| data | the rows of a table or the cells of a view |
| a property | the annotations of that property |
| a function | the results of that function |
| the definition | a view's SQL and what it reads |

| Where, from the function's subject | |
|---|---|
| itself | the subject |
| its columns | what it contains |
| its sources | the tables and columns a view reads |
| the columns it joins on | the two sides of each join in a view |
| its relationships | the relationships between its sources, or that touch it |
| its metric | the metric a plan plans |
| the dataset | everything in the subject's dataset |

The engine hands a running function the rows those reads name and no
others; a body that reaches the catalog any other way is refused at
its declaration. So what a function can see and what its result
depends on are the same list.

No rule about how far a function may reach is needed, and there is
no grammar to add.

## 5. When a result is current

A result is current while each declared input is as it was read:

- data: the table has the DuckLake version it had (for a view, each
  table it reads);
- annotations and results: they hold the same values, and those
  results are current;
- the definition, and the function's and the property's own
  declarations: as they were declared;
- the edges that say where (a view's sources, a relationship's
  columns): the same.

Otherwise it is outdated: served and marked. It becomes current by
being computed again, or by the change being undone. "Why is this
outdated" names the declared input that differs.

## 6. Who brings it current

- A result a view needs: the server, after a write (`results_due()`).
- What only an actor can state (an annotation, a decision, a preview
  measurement): `next` lists it.

## 7. The shipped functions, with what each reads

| Function | On | Reads |
|---|---|---|
| `column_profile`, `temporal` | column | data of itself |
| `detect_hierarchies`, `detect_derivations` | table | data of itself |
| `detect_relationships` | dataset | data of the dataset's tables |
| `relationship_coherence` | relationship (today: dataset) | data of itself: the key and date columns of its two tables |
| `detect_definition_collisions` | dataset | data, definitions, `role` and `additivity` of the dataset's views |
| `additivity_check` | view | definition of itself; `role` and `additivity` on its columns |
| `fan_out_check`, `validity_check` | view | definition of itself; `validity` on its sources; `column_profile` on the columns it joins on |
| `orphan_check` | view | definition of itself; `relationship_coherence` on its relationships |
| `metric_ranges`, `metric_forecast`, `metric_scenario` (preview) | dataset | data and definitions of the dataset's metrics; `time_grains`, `lever` and the scenarios on the dataset; `temporal` on the dataset |
| `metric_plan` (preview) | plan | data of itself; data of its metric; `metric_forecast` on the dataset |

The detectors (`value_entropy`, `rate_tolerance`, `range_breach`,
`plan_gap`) read the property of the test they run for, on itself.

| `additivity_evidence` | column | data, `role` and the relationships of the dataset |
| `outlier_profile` | column | data of itself |

`additivity_evidence` decides stock or flow for a measure from
another table: movements summed from an event table that
relationships align with the measure's table, directly, through a
shared key, or through a document or master table. That path is
found in the data, so its honest place is the dataset. No view needs
its result, so nothing computes it by itself; an agent runs it before
annotating additivity.

## 8. What goes overboard

| What | Why |
|---|---|
| `forecast_exists`, `scenario_exists` | the preview tests work out their state without them |
| `fan_out_check` and `validity_check` as two | they split one question; one function |
| The inputs digest the outlook kit computes and stores by hand | section 5 replaces it |
| Inputs derived from a body's bound query plan; the lineage computed in C++ with its three widenings | section 4 replaces them |

## 9. Tried on real functions

A spike (scratch, no repository changed) wrote three read functions,
`annotations(property, where)`, `results(function, where)` and
`definition(where)`, and `additivity_check`, `orphan_check` and
`fan_out_check` with them alone:

- the same row as today's bodies on 13 views, 39 of 39, red cases
  included; one difference, where the model is right: a relationship
  declared after the coherence check ran is "not applicable, no
  result", where today it reads green;
- the JSON of each body lists exactly its reads, macros followed;
- the inputs of one metric changed for `role` on its own column and
  for a profile computed again with another value, and for nothing
  else tried.

What stays beside the reads: a result that read an outdated result
is outdated. A macro with fixed reads inside is shared logic as
before. While every function is ours, a test of our suite holds each
body to the read functions; the refusal at declaration comes when a
customer writes functions. `definition` is DuckDB's own binding of
the view against the catalog, as the extension does it today.
