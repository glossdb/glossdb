# The catalog

Every relation the language declares is a table in the lake's catalog,
beside the lake's own metadata: annotations, functions, aspects, tests,
sources, load queries, relationships, measurements, imports. The engine
serves each as a view in the lake's `main` schema, `ws.main.<relation>`,
readable by its bare name from any dataset in use
([storage](storage.md)). What is known about the data sits beside the
rows that describe the data itself.

## Writes

The catalog assigns each row a sequence number at insert, so the
ordering is never minted twice. Writes are inserts; each statement's
rows are stored as it runs. Nothing is updated in place.

**The current value is a read, not an update.** The current value of an
aspect on an asset is the newest row per (asset, aspect, kind of
actor), computed at read time. A correction never destroys history: the
older row remains, with its actor and time, and the read decides what
"current" means.

## Provenance and staleness

A measurement stores the versions of what it read: the data's
snapshot, and the catalog relations the function read (`pin`). It is
current, and is reused, while those are unchanged. It is stale once one
changes, and the read says so. An annotation on a column ages the same
way against the column's own history. Old rows are the history of
drift, not garbage. Reads never write. Measuring again over unchanged
inputs returns the same result.

The catalog's version is the lake's snapshot plus every relation's
highest sequence number, and any write moves it. The catalog reads
(`GLOSSARY()`, `TESTS()`, the newest values with their bands) are
planned once per dataset and kept in the engine's object cache under
that version, shared by every connection. A dataset's views are kept
the same way, so a query over the metrics scans what is stored instead
of computing every view from its tables on each call. The first read
after a write computes once.

## Streaming

Reads stream as Arrow, one batch in memory at a time. The query
endpoint never caps: the client drains the stream, and hanging up
cancels the work. The MCP interface's row cap limits the read: one row
past the cap is asked for, and the result says `truncated`.

## Changes and disclosure

- Definition changes are coarse and explicit, and refused rather than
  migrated.
- Dependencies are declared, never guessed.
- Staleness is marked when read.
- Nothing hides a judgment: `stale` is returned and marked, `contested`
  is withheld with its band and score, and `unassessed` is a visible
  row.
