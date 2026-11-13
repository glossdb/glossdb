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

## 4. A function declares what it reads

A function has an output, the property it returns (`RETURNS`, as
today), and an input signature, which the language had until August
(`ACCEPTS`) and lost when a body became SQL. Each input is a **what**
and a **where**:

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
| its relationships | the relationships between its sources, or that touch it |
| its metric | the metric a plan plans |
| the dataset | everything in the subject's dataset |

The engine hands a running function the rows its signature names and
no others; a body that reads anything else is refused. So what a
function can see and what its result depends on are the same list,
and it is in the catalog for anyone to read.

No rule about how far a function may reach is needed, and nothing is
derived from the body's query plan.

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

## 7. The shipped functions, with their signature

| Function | On | Reads |
|---|---|---|
| `column_profile`, `temporal` | column | data of itself |
| `detect_hierarchies`, `detect_derivations` | table | data of itself |
| `detect_relationships` | dataset | data of the dataset's tables |
| `relationship_coherence` | relationship (today: dataset) | data of itself: the key and date columns of its two tables |
| `detect_definition_collisions` | dataset | data, definitions, `role` and `additivity` of the dataset's views |
| `additivity_check` | view | definition of itself; `role`, `additivity`, `dimension`, `time_grains` on its columns; `temporal` on its columns |
| `fan_out_check`, `validity_check` | view | definition of itself; `validity` on its sources; `column_profile` on its sources |
| `orphan_check` | view | definition of itself; `relationship_coherence` on its relationships |
| `metric_ranges`, `metric_forecast`, `metric_scenario` (preview) | dataset | data and definitions of the dataset's metrics; `time_grains`, `lever` and the scenarios on the dataset; `temporal` on the dataset |
| `metric_plan` (preview) | plan | data of itself; data of its metric; `metric_forecast` on the dataset |

The detectors (`value_entropy`, `rate_tolerance`, `range_breach`,
`plan_gap`) read the property of the test they run for, on itself.

Every function that stays fits the six places. The one that does not
is retired below.

## 8. What goes overboard

| What | Why |
|---|---|
| `additivity_evidence` | no test, read or frame uses its result; it follows relationships up to three steps and reads `role` on the whole dataset; it is the only function the six places cannot express |
| `forecast_exists`, `scenario_exists` | the preview tests work out their state without them |
| `fan_out_check` and `validity_check` as two | they split one question; one function |
| The inputs digest the outlook kit computes and stores by hand | section 5 replaces it |
| Inputs derived from a body's query plan; the lineage computed in C++ with its three widenings | section 4 replaces them |
| `outlier_profile` | only two console frames read it; to decide |

## 9. For the project lead

- **The form of the signature is grammar.** It goes through the
  corpus: two or three spellings of the same real functions, shown
  as forks. This page fixes only its content: what, and where.
- **`its sources` is coarser than one check needs**: `fan_out_check`
  reads the profile of the join columns only. A seventh place, the
  columns it joins on, would make it exact. I would start with six.
- **The preview measurements stay on the dataset** for now: one
  service call scores all metrics together. Per metric is the outlook
  issue.
