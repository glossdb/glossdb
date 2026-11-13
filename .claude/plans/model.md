# The model: what a result depends on

One page to agree on before more code. It replaces the design
sentences of `dependencies.md` once agreed, and then goes into
`SPEC.md` §6. Marked *(to verify)* where I have not read the code.

## 1. Assets are the nodes

| Asset | Example | Has |
|---|---|---|
| dataset | `f1` | tables, views, relationships |
| table | `f1.results` | columns; rows, with DuckLake's version |
| view | `f1.race_points` | columns; a definition (SQL) |
| column | `f1.results.points` | |
| relationship | `f1.results.raceId -> f1.races.raceId` | two columns |

## 2. Statements hang on one asset

- An **annotation**: asset, property, actor, value. Written by an
  agent or a person.
- A **result**: asset, function, value or error. Computed.

**A statement is stored on the asset it is about.** Two results break
this today and are the cause of a patch: `relationship_coherence` is
one result on the dataset for all relationships, and
`metric_forecast` one on the dataset for all metrics. In the model
each is one result per relationship and per metric.

## 3. Edges, each with a kind

| Kind | From → to | Comes from |
|---|---|---|
| `contains` | dataset → table, view, relationship; table or view → column | the lake's catalog |
| `reads` | view → column it scans or joins on; view → view it reads | the view's SQL, resolved (`glossql_views_scans`, `glossql_views_joins`) |
| `relates` | relationship → its two columns | `DECLARE RELATIONSHIP` |
| `plans` | plan → the metric it plans | the plan's declaration |

Later, finer: `reads` from one output column of a view to the input
columns of its expression, from the SQL as JSON
(`json_serialize_sql`).

The edges are one relation the catalog serves: `from`, `to`, `kind`.
Lineage, as a person or an agent reads it, is this relation.

## 4. The reach of an asset

What a result on asset X may read, and so depends on:

1. X, what X contains, and what contains X up to its table or view
   (a column reaches its table; not the dataset's other tables).
2. From there, along `reads` and `plans`, as far as they go.
3. The relationships that touch a column reached so far, and the
   column and table at their other end. One step, not further.
4. A result on the dataset reaches everything in the dataset.

While a function runs it sees the annotations and results of its
reach and nothing else. So the rule cannot be broken by a function's
SQL; a read outside the reach returns no rows.

## 5. When a result is current

A result on X is current while all four hold:

- **Data**: each table it scanned has the DuckLake version it had.
- **Statements**: the annotations and results it read in its reach
  hold the same values, and those results are current themselves.
- **Rules**: its function, its property and the definitions of the
  views in its reach are as they were declared.
- **Reach**: the edges that gave its reach are the same.

Otherwise it is outdated: served and marked. Nothing flips a mark;
the result is computed again, or the change is undone.

"Why is this outdated" has one answer form: the statement, table,
rule or edge that differs, and the path from X to it.

## 6. Who brings it current

- A result a view needs: the server, after a write
  (`results_due()`).
- A statement only an actor can make (an annotation, a decision, a
  preview measurement): `next` lists it.

## 7. Each shipped function in the model

| Function | On | Reads in its reach |
|---|---|---|
| `column_profile`, `outlier_profile`, `temporal` | column | the table's rows |
| `additivity_evidence` | column | `role` on the tables one relationship away *(one step: to verify)* |
| `detect_derivations`, `detect_hierarchies` | table | the table's rows and columns |
| `relationship_coherence` | relationship (today: dataset) | the rows of its two tables |
| `detect_relationships`, `detect_definition_collisions` | dataset | everything |
| `additivity_check` | view | the view's definition; `role`, `additivity`, `dimension`, `time_grains`, `temporal_profile` on the columns it reads; for a plan, its metric |
| `fan_out_check` | view | `column_profile` of the columns it reads and joins on |
| `orphan_check` | view | `relationship_coherence` of the relationships between the columns it joins on |
| `validity_check` | view | *(to verify)* |
| `metric_ranges`, `metric_forecast`, `metric_scenario` (preview) | metric (today: dataset) | the metric's series; the scenario its levers |
| `metric_plan` (preview) | plan | its metric's forecast and series |

## 8. What goes overboard

- The three widenings in the extension's `ClosureOf`: results on the
  dataset in every view's reach, the relationship component taken
  whole, the dataset as fallback for a relationship.
- The reach computed in C++: it becomes a recursive query over the
  edges.
- One result on the dataset for all relationships, and for all
  metrics' forecasts.

## 9. One question left open

**How a result knows which properties it read.** Rule 5 says "the
annotations it read". Today the extension takes the properties from
the function's SQL where a read names one as a constant
(`glossql_glossary(…, 'role')`); a read that names none counts every
property in the reach (measured: `meaning` on a scanned table
computes two results where none is right).

- **A. Keep reading it from the SQL** and make each kit read name
  its property. No grammar. A kit author who writes a read without a
  property gets a correct but coarse dependency.
- **B. The function declares the properties it reads**, and sees only
  those. Exact and visible in the catalog. It is grammar, so it goes
  through the corpus and the project lead.

I would take A now and keep B for when a customer writes functions.
