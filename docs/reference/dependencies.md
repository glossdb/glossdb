# How results stay current

glossdb stores what its functions compute: a function's result, a
test's result, a view's lineage. Each stored result knows what it read. When
something it read changes, the result is out of date, and the server
computes it again after the write. A result that nothing changed under
is served again, not computed again.

## The model

This is demand-driven incremental computation, as in Adapton (Hammer
et al., PLDI 2014) and the red-green algorithm of Salsa. In the terms
of "Build Systems à la Carte" (Mokhov, Mitchell, Peyton Jones, ICFP
2018), it verifies traces with early cutoff, over a dependency graph
that is kept.

| The model's term | In glossdb |
|---|---|
| Revision | the lake's snapshot id. It is the only version: no digest, counter or fingerprint is stored beside it |
| Input | a row of the catalog (an annotation on an asset, a view's definition, a relationship, a declaration) and a table's data. A row changed at the snapshot it begins or ends at; a table's data at the snapshot of its last load |
| Derived value | a stored result of a function on an asset, a row of `results`. It carries the snapshot it read at (`read_at`) and the snapshot its value last changed at (`changed_at`) |
| Dependency | one row of `inputs` per node the function read when it ran, recorded by the reads in the function's body |
| Check | a result is current while nothing it read changed after `read_at`. The check runs on demand, along the result's inputs |
| Early cutoff | a result computed again with the same value keeps its `changed_at`, so the results that read it stay current |
| The graph | the `inputs` and `edges` rows in the catalog, read by SQL |

A kit's functions are tracked by the same mechanism. The core names no
kit.

## What puts a result out of date

| Result | Out of date when |
|---|---|
| a function's result (`SELECT column_profile() FROM orders.amount`) | a node it read changed: the data of a table it read, an annotation or another function's result it read, the function's own declaration, a macro its body calls |
| a result that reads a view over the stored results (a rule view that compares each column's profile with the previous load's) | a measurement of the dataset was stored with another value: a result of a function whose property is a MEASUREMENT. A FACT's result, such as the rule's own check, a test's result and a view's lineage leave it current |
| a test's result, per asset and test | the asset's values of the tested property, the asset's definition, or the declarations of the test and its detector changed |
| a view's lineage (function `lineage` on the view) | the view's definition, the definition of a table or view its SQL names, through the views it reads, or a macro it calls changed |
| an annotation | it is an input, not a result. It reads `stale` once its table's load query was declared with other SQL; once a load retyped or dropped its column, or computed it from other source columns or source types than the load before; or once the view it is on was defined again ([describe](../usage/describe.md#states)) |

A result that read another result waits for it. Once that result is
computed again, the same value leaves the reader current, and another
value puts it out of date. While it waits, a read of its value is
marked `possibly` in `GLOSSARY()`.

## Who brings a result current, and when

After each write, the server lists the results the dataset needs that
are missing or out of date, `results_due()`, and computes them in
order: each view's lineage first, then the results each test's check
reads, then the checks, then the tests. It asks again with what that
round changed and stops when nothing is left. A write that stores what
the catalog already holds, such as the same annotation again, writes
nothing and computes nothing.

A result an actor computes, such as a kit's function about the dataset
as a whole, is not computed by the server. Once it is out of date,
`next` lists it as a `should`, with the statement that computes it
again ([reads](reads.md#next)).

## A load with other columns

A load whose columns differ from the table's alters the table in
place. An annotation on a column the load retyped or dropped reads
`stale`; a column added leaves the other annotations current.

## A load query with other SQL

Each load stores per column the source columns it is computed from
and their types as the source delivered them (`imports.lineage`).
Under the same load query, a column whose source columns or types
differ from the load before's changes its definition, and its
annotations read `stale`. A load query declared with SQL text that
differs from the one before it changes the definition of the table
and of every column: every annotation on them reads `stale`, and is
confirmed by writing it again. Both compare values the catalog
stores; the lake's snapshot id stays the only version. The results that read the table's data are out of date: the
server computes those it brings current after the load, and `next`
lists the others.

## Nothing kept beside the catalog

The lake keeps every snapshot of the catalog and the data together.
glossdb keeps no copy per snapshot beside it: a result's `read_at`,
its `changed_at` and its `inputs` rows are enough to say whether it is
current.

## See it

The stored results, with the snapshots they read at and changed at:

```sql
SELECT function, subject, read_at, changed_at, error FROM main.results;
```

What each result read, by the result's `id`:

```sql
SELECT result, asset, what FROM main.inputs;
```

A view's lineage as edges, from the view to each table, column and
view it reads:

```sql
SELECT result, "from", "to", kind FROM main.edges;
```

Each stored result out of date, with the node that changed. `reason`
is `changed`, or `possibly` where a result it read is out of date and
not computed again yet:

```sql
SELECT dataset, function, subject, asset, what, reason FROM glossql_outdated();
```

What the server computes after the next write, with the statement for
each:

```sql
SELECT ord, function, subject, run FROM results_due();
```

Inside a function's body, the reads `annotations()`, `results()` and
`definition()` record what they return as `inputs`. The node kinds
and the reads that record them are in the extension's specification
(`doc://SPEC.md`, §6).
