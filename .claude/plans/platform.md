# Platform plan

How the data intelligence layer works with a stack that is already
there: a dbt project, a semantic model, a lake, a database, a
repository with CI. The layer goes in and out in the formats those
tools use. Build order is risk order.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| Spike: a dbt project that builds its models into the DuckLake glossdb attaches; glossdb reads the tables in place and the project's metadata as files | High: nothing is built, and freshness must come from that lake's own metadata | a scratch workspace, DuckDB's dbt integration, the server's open | First; it decides the three rows below | drafted below |
| Read a lake or catalog in place (DuckLake, Iceberg, Delta), without a copy | High: today a load copies, and `stale` is read from glossdb's own load history | the server's open, the stale rule, `SPEC.md` §3's `via` | After the spike | #221 |
| dbt import: models as tables, descriptions as `meaning`, dbt tests as tests, column lineage as lineage | Medium | an import kit: SQL over the project's metadata files | After the spike | #221 |
| dbt export: a metric and a test written in dbt's form | Low: a read beside `semantic_model()` | the views kit | After the import | |
| Ossie import: a semantic model written elsewhere becomes column annotations, relationships and metric definitions | Medium: a metric expression may be in another SQL dialect | the views kit | When a customer names a semantic layer | #221 |
| A database attached read-only (`postgres`, `mysql`, `sqlite`) and read by a load query | Low: the extensions exist and the image carries `postgres` | `SPEC.md` §3's `via`, the server's open, a suite case | When a customer names one | |
| The workspace as code: declarations exported to `.glossql` files and loaded back; `TESTS()` in the team's CI | Medium: which annotations are code and which are run-time results is open | an export read, a load of a directory, a CI example | After the dbt rows; the files sit beside a dbt project | #219 |

## Issue for the next row, drafted

### Spike: a dbt project on the lake glossdb attaches

- **What it buys.** We know whether glossdb can sit beside a dbt
  project on one lake: the tables read without a copy, the project's
  descriptions, tests and lineage read as files.
- **What is there.** A load query copies into the lake. dbt's
  metadata files and its DuckLake target are described in the link
  above. #221 lists the three directions.
- **Done when.** One public dbt project builds into a DuckLake. A
  glossdb workspace on that lake describes one of its tables and
  defines a metric on it without a load. The issue records: how a
  table's freshness is read, what of the project's metadata maps to
  `meaning`, tests and lineage, and what does not map. #221 is split
  into issues from those findings.
