# Kits plan

A kit is an add-on: SQL loaded at open that brings its own vocabulary,
the things one asks for, its functions and its tests. The core is the
language, the catalog, the lineage, views, tests and `next`; it names
no add-on and runs without each of them. What a kit stores is tracked
by the core's one dependency mechanism. What the kits are today:
`docs/extending/kits.md` and `kits/README.md`.

This plan holds what is open on how kits are cut, versioned and
bundled. The options are evaluated with the project lead before any
row is built.

| Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|
| The options for bundling a kit: which the project lead wants compared, and against what | High: it decides the rows below | this plan | First | |
| A kit's version and config file (name, version, what it requires); the catalog's `kits` row holds the version in place of a hash of the code | Medium | the extension's kit loading, `crates/duck` | After the options | |
| A kit update on a workspace that has values: today a kit cannot change a property that has values | Medium | the extension | With the version | #248 |
| A kit's code in git as exported SQL, as a pointer beside the lake. The code stays in the lake, so a reader of the lake alone still has `next` | Low | an export read | After the version | |
| The `plan` and `outlook` kits come back on stored results, from the tag `before-cut`: a scenario and a plan as assets of a kind the kit declares, through the extension's seam (`glossql_kind_assets`, `glossql_kind_edges`, `glossql_kind_places`) | High: both were built on structures that are gone | the two kits, the console's pages for them | After the version | #246, #174 |
| Which kits are core and which are add-ons, and what a deployment loads | Medium | `kits/`, the server's open | With the options | |

## Measured

Kit code kept outside the lake was spiked: the catalog reload after a
write drops by about 60% (58 to 25 ms on Formula 1), plan time does
not change, a second reader of the lake loses `next`, and a change in
kit code goes unseen without a version bump. The code stays in the
lake.

## Next issue

None drafted: the first row is a session with the project lead.
