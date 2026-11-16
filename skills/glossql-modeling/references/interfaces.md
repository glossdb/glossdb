# The other interfaces: console, query endpoint, exports

Read when someone asks how to look at the layer or use it from
another tool.

The MCP interface is where you work. The same server has interfaces
for people and for other tools. A dataset's name is the first segment
of each path.

| Interface | Path | For |
|---|---|---|
| MCP, workspace | `/mcp` | an agent; begin a call with `USE <dataset>;` |
| MCP, one dataset | `/<dataset>/mcp` | an agent; every call opens on the dataset |
| console | `/<dataset>/app/console` | a person: the views and their tests, the loads, the review queue and its decisions |
| data apps | `/<dataset>/app/<name>` | a person: pages you write over the views (`skill://glossql-apps/SKILL.md`) |
| query endpoint | `/<dataset>/query` | another tool: SQL over the dataset's tables and views, answered as Arrow IPC |
| download | `/<dataset>/app/export/<name>.csv` or `.parquet` | a table or a view of the dataset as a file; Parquet keeps the types |

The review decisions a person records in the console reach you
through `next` (`skill://glossql/references/review.md`).

## Handing the layer to another tool

The views are views in the lake: a tool that opens the lake reads
`FROM <view>` like any table. Two reads export what the catalog
knows, in open formats:

```sql
SELECT document FROM semantic_model()
```

`semantic_model()` is the dataset as one Apache Ossie document: the
tables and metrics with their fields, time columns, dimensions,
metric expressions and relationships.

```sql
SELECT event FROM lineage_events()
```

`lineage_events()` is the dataset's lineage as OpenLineage run
events: one per load and one per view, with column lineage. Inside
the workspace, `column_mapping()` gives the same lineage as rows:

```sql
SELECT view, target_column, system, source_table, source_column FROM column_mapping()
```
