# Dependency plan

How glossdb knows that a stored result is still valid, and who brings
it current. The model, its reference and what is built are in the docs
(`docs/reference/dependencies.md`): demand-driven incremental
computation on the lake's snapshot id as the only version. This plan
holds what is open on it.

What must not exist beside the mechanism: a second version of anything
(a digest of what a read returned, a counter, a fingerprint as a key);
a lineage or a check computed whole after a write; a result that holds
what one asks for alone; a copy kept per snapshot or across
statements. A change that needs one of these stops and is put to the
project lead.

## Open

| Element | Risk | What it touches | Issue |
|---|---|---|---|
| A view's lineage is stored as one JSON value and unnested on each read. To be rows | Medium | the extension's lineage kit, `next`, the harmonise kit | #249 |
| The result's summary and the statement splitting in the server repeat what the kits and the engine answer | Medium | `crates/serverd`, `crates/duck` | #250 |
| Three parse-tree walks beside the bound-plan walk. Spike first | Medium | the extension | #251 |
| The glossary state read slows as snapshots grow (25 ms to 43 ms at ten times the history) | Low | the extension's store | #252 |
| The key check after a load reads every column of the table | Low | `kits/views`, the extension's seam of `series_aggregate` | #253 |
| An interrupt during a computation; the Postgres catalog's lost-race path | Low | the extension | #247 |

## Left out, by the project lead

- **Removing a function or a macro.** Direction: a removal is soft, and
  the results computed with it are retired.
- **Compaction and expiry.** Direction: only what no result references
  and no audit needs, or an archive, monthly or quarterly.
- **Call time.** An MCP call is 0.14 to 0.22 s on every size measured,
  most of it planning `next`. No further cheap step is known.

## How this plan is worked

The tests of what a step changes are deleted first, as a commit of
their own, so nothing is built towards them. Done-when is the flow
walked on a running server through MCP: load, describe, define a view,
read `next`, run the handed statements. New tests come last and few. A
new structure is spiked standalone first. `SPEC.md` is edited with the
work; `grammar.ebnf` needs the project lead's approval first.

## Next issue

The project lead picks from the table above.
