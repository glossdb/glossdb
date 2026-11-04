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

The server is a Cargo workspace. `duck` is the engine: the facade the
doors use over the glossql extension and a DuckLake, the record's own
reads (`kits/core.sql`) and the door's (`kits/door.sql`), and the
actor types the doors stamp a call with. `apps` serves the pages;
`serverd` is the binary with its doors. The language is the
extension's: SPEC.md, `grammar.ebnf` and the corpus live in its
repository, and the door serves the two documents from its share. The
kits are SQL loaded at open: the vocabulary and the quality screens
from the extension's repository, the metrics and the futures from
`kits/` here; `kits/README.md` says what they add.
