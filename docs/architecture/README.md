# Architecture

How the server is built.

- [`kernel.md`](kernel.md) — the business information kernel: the
  core, the kits, drivers and services, and what is planned.
- [`store.md`](store.md) — one record in the lake's catalog: how reads
  and writes behave, what stands and what is stale.
- [`substrate.md`](substrate.md) — building on DuckDB and the gloss
  extension: what each owns and the rules that come with it.
- [`storage.md`](storage.md) — the lake's physical layout and its
  catalog.

## The crates

The server is a Cargo workspace. `parser` reads the language; the
corpus is its acceptance suite, and SPEC.md and `grammar.ebnf` hold
it and the extension's grammar to one definition. `glossary` is the
actor types the doors stamp a call with. `duck` is the engine: the
facade the doors use over the gloss extension and a DuckLake, the
record's own reads (`kits/core.sql`) and the door's (`kits/door.sql`).
`apps` serves the pages; `serverd` is the binary with its doors. The
language's kits — the vocabulary, the quality screens, the metrics,
the futures — are SQL in the extension's repository, loaded at open.
