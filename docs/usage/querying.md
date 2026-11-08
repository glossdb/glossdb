# Querying and export

Tools read a dataset over plain HTTP, as Arrow; people download any
table or metric as CSV or Parquet from the console.

## The query endpoint

POST the statement text as the body to `/<dataset>/query`. No client
library is needed.

- **One read** answers as an Arrow IPC stream
  (`application/vnd.apache.arrow.stream`), straight from the engine:
  no row cap, one batch in memory at a time, and hanging up cancels the
  work.
- **Anything else** (sequences, declarations, writes) answers in the
  same JSON outcome shape as the MCP interface
  ([connect](../getting-started/connect.md#the-mcp-interface)).
- **A refused statement** answers `422` with `{"error": "…"}`.

```python
import urllib.request
import pyarrow.ipc

req = urllib.request.Request(
    "http://127.0.0.1:8080/fin/query",
    data=b"SELECT metric, period, value FROM metric_series() WHERE dimension = ''",
)
with urllib.request.urlopen(req) as resp:
    table = pyarrow.ipc.open_stream(resp).read_all()
```

The endpoint writes as a person. It reads and writes in a dataset but
does not create datasets; a dataset the workspace does not hold answers
`404`, naming the ones it does.

## Export

Every loaded table and every metric or view downloads as a file:

```
/fin/app/export/orders.csv
/fin/app/export/dso.parquet
```

The console's Export tab lists them all.

## From another DuckDB

The workspace is a plain DuckLake, so any DuckLake client can attach
and read its tables ([storage](../internals/storage.md)).
