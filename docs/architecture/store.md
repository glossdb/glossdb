# The store

Every relation the language declares — glosses, functions, aspects,
witnesses, sources, recipes, relationships, measurements, imports —
is a table in the lake's catalog, beside the lake's own metadata, and
the engine serves each as a view, `ws.glossql.<relation>`
([storage](storage.md)). The record the language keeps sits beside
the rows that name the data.

## One store

Rows carry a sequence the store assigns at insert, so the store never
mints its own ordering twice. Writes are inserts; each statement's
rows land as it runs. Nothing updates in place.

**Supersession is a read, never an update.** The current slot for a
subject is the latest row per (subject, aspect, actor kind), computed
at read time. A correction never destroys history: the superseded row
remains, with its actor and time, and the read rule decides what
"current" means.

## The pin

A measurement carries the pin of what it read: the data's snapshot,
and the legs of the record the function read. It stands, and serves,
while those are unchanged; it is stale once one moved, and the read
says so. A gloss on a column ages the same way against the column's
own history. Old rows are the drift record, not garbage; reads never
write; re-measuring over unchanged inputs answers the same fact.

The store's version is the lake's snapshot and every relation's
highest sequence, and any write moves it. The record read —
`GLOSSARY()`, `ATTEST()`, the collapsed slots with their bands — is
planned once per dataset and kept in the engine's object cache under
that version, shared by every connection; a dataset's views are kept
the same way, so a read over the metrics scans what stands instead of
computing every view from its tables on each call. The first read
after a write computes once; a read never writes.

## Streaming

Reads stream as Arrow, one batch in memory at a time. The Arrow door
never caps — the client drains the stream, and hanging up cancels the
work. The MCP door's row cap is a limit on the read: one row past the
cap is asked for, and the result says `truncated`.

## Invalidation and disclosure

Definition changes are coarse, explicit, and refused rather than
migrated; dependencies are declared, never sniffed; staleness is
marked at read. Machinery never suppresses judgment: `stale` is served
and marked, `contested` is withheld with its band and score,
`unassessed` is a visible row.
