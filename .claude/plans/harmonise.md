# Harmonisation plan

Several systems of record are mapped onto one target model, and the
mapping is tested at each load. The kit adds vocabulary and reads on
what is there: table views, relationships, the lineage, `next`. It is
held to two cases: the demo (three ERPs, one market each) and FERC
Form 1 (two filing systems split by time, a key built per system,
refilings of earlier years).

The design, agreed with the project lead:

1. **The target is a table view with a contract on its columns**: key,
   type, meaning, allowed values, as annotations on the view.
2. **The mapping is read from the view's SQL**, not stated a second
   time: per target column and per branch of a union, the source
   table, the source columns, the expression and the code literals it
   tests.
3. **The source system is a property of a loaded table**, taken from
   its load's source. The mapping read and the reconciliation group by
   it; a view needs no literal for it.
4. **Reconciliation is one function on the target view**, per source
   system and per period in the data (a cycle, a report year, a
   month; one row per system where the data has no period): rows
   read, rows that reached the target, rows dropped and why, and the
   sums of the columns annotated as measures. A refiling changes the
   row of the period it refiles. Its test is red when rows vanish
   unexplained.
5. **In `next`**: a red reconciliation or an unmapped code is a must;
   a target column without a contract is a should.

## Rows, in the order they are built

| # | Element | Risk | What it touches | When | Issue |
|---|---|---|---|---|---|
| 1 | The mapping read: per target column and branch, the source table and columns, the expression, the literals. From the lineage per column (`glossql_views_lineage`), which now renders CASE and COALESCE as they are. `view_sources()` returns a passed-through column with no field: looked at first | Medium: unions name columns by position; one table joined under three aliases loses which alias | a new `kits/harmonise`, `kits/views/kit.sql` (`view_sources()`), the extension's lineage if the branch or alias is missing there | Now | |
| 2 | The source system of a loaded table, readable by a function through a place of the lineage (a table's load and its source) | Low | the extension's lineage kit (`lineage()`, a place), `kits/harmonise` | Now | |
| 3 | The contract on a target view's columns: key, type, meaning, allowed values; a test that the view's rows keep it (key unique, values allowed) | Low: the forms exist (a FACT property, a function, `rate_tolerance`) | `kits/harmonise`, the modeling skill | After 1 and 2 | |
| 4 | Reconciliation per system and period, with its test | Medium: "dropped and why" must come from the view's joins and filters, which the lineage does not carry today (row filters, literals in a join) | `kits/harmonise`, the extension's lineage (filters) | After 3 | |
| 5 | Codes that are unique only inside a system (a Swiss and a Polish item with the same local code): a relationship that holds under a condition. Open question in `SPEC.md` §9 (the polymorphic reference). Through the corpus: competing forms on the demo's identity sheet, shown to the project lead | Medium: a grammar change; every reader of a relationship follows the condition | the extension (`corpus/`, `grammar.ebnf`, `SPEC.md`, the checks) | Beside 1 to 4; the lead reviews | |
| 6 | Value codes mapped in a view (`status = 'D'`, units written three ways): a test that every value in the data is handled by the expression, listing the ones that fall through | Low: the literals come from row 1 | `kits/harmonise` | After 1 | |
| 7 | The skill: how an agent harmonises with the kit, on both cases | Low | `skills/` | After 4 | |
| 8 | The demo rebuilt on the kit: its statements run on this server, its Mapping and Reconciliation pages read the kit's reads | Medium: the demo is behind the server (`cube`, `metric_bands`, `ruling` no longer exist) | `../glossdemo`, the project lead's repository | After 7; the lead says when | |

## What is there

- Relationship detection and the check per relationship
  (`detect_relationships`, `relationship_coherence`).
- On a table view: `join_check` (a join that repeats rows, an
  effective-dated table) and `orphan_check` (rows with no parent),
  computed by the server after a write.
- `load_changes()`: what the newest load changed in a table.
- Assumptions with an alternative, and a person's review decision.
- `meaning` with a `term`.

## Fixtures

Small tables in the kit's suite, shaped like the two cases; no
corpus is committed. The demo's shape: three source systems, one
product, stock and orders table each, an identity table keyed by
market and local code, a unit conversion table. FERC's shape: one
table per filing system, a period column, a mapping table per
system, a year filed twice.

## Done when

On both fixtures, with no literal naming a system in any kit read:
the mapping read lists every target column with its sources per
system; a code with no mapping row makes a test red and `next` lists
it as a must with the codes; a row dropped by a join shows in the
reconciliation under its system and period; a refiled year changes
that year's row alone.

## Next issue (draft)

**The mapping read and the source system.** What it buys: a person
or an agent reads, for a harmonised table, which column of which
system each target column comes from, without anybody writing it
down twice. What is there: `glossql_views_lineage` (the derivation
per column), `view_sources()` (`kits/views/kit.sql`), `recipes` and
`sources` in the catalog, `lineage()` and the places in the
extension's lineage kit. Done when: on both fixtures the read
returns one row per target column, branch and source column with the
system, the expression and the literals; a function body can read a
table's system through a place; `view_sources()` returns every
column with its field.
