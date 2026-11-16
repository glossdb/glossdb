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
| 1 | The mapping read: per target column and branch, the source table and columns, the expression, the literals. From the lineage per column (`glossql_views_lineage`), which now renders CASE and COALESCE as they are. `view_sources()` returns a passed-through column with no field: looked at first | Medium: unions name columns by position; one table joined under three aliases loses which alias | a new `kits/harmonise`, `kits/views/kit.sql` (`view_sources()`), the extension's lineage if the branch or alias is missing there | Built: `column_mapping()` in the views kit replaces `view_sources()` | |
| 2 | The source system of a loaded table, readable by a function through a place of the lineage (a table's load and its source) | Low | the extension's lineage kit (`lineage()`, a place), `kits/harmonise` | Built: the edge `loaded from`, the place `its source systems` | |
| 3 | The contract on a target view's columns: key, type, meaning, allowed values; a test that the view's rows keep it (key unique, values allowed) | Low: the forms exist (a FACT property, a function, `rate_tolerance`) | `kits/harmonise`, the modeling skill | Built: `contract` per column, `contract_check`, `contract_test` | |
| 4 | Reconciliation per system and period, with its test | Medium: "dropped and why" must come from the view's joins and filters, which the lineage does not carry today (row filters, literals in a join) | `kits/harmonise`, the extension's lineage (filters) | Built: `reconciliation` on a view with a contract, computed by the server after each load; `branch_rows()` in the extension; no test of its own (it cannot be red where it can follow a view) | |
| 5 | Codes that are unique only inside a system (a Swiss and a Polish item with the same local code): a relationship that holds under a condition. Open question in `SPEC.md` §9 (the polymorphic reference). Through the corpus: two forms on the demo's identity sheet and one real switching case, a constant inside the key (`t.('CH', code) -> m.(market, code)`) and a condition on the relationship (`WHEN`, which today reads a sibling annotation on a property declaration, so the word would shift), shown to the project lead | Medium: a grammar change; every reader of a relationship follows the condition | the extension (`corpus/`, `grammar.ebnf`, `SPEC.md`, the checks) | Corpus test done (`corpus/29-identities-by-market.md` in the extension): no artifact has a code that collides across systems, and none has a switching target. Not built; taken up when a case appears. If built: a constant inside the key for the scoped key, `WHERE` rather than `WHEN` for a condition | |
| 6 | Value codes mapped in a view (`status = 'D'`, units written three ways): a test that every value in the data is handled by the expression, listing the ones that fall through | Low: the literals come from row 1 | `kits/harmonise` | Built: `code_check`, `code_test`; counts the rows a branch keeps | |
| 7 | Full load or append/update load, stated and tested. An agent states per load whether the source sends its complete state or only changes (an assumption a person confirms). A full load (no key) is right where rows can disappear unflagged, and when unsure; a keyed load where only new or changed rows arrive. Tested at each load: a keyed load whose file covers most keys of the table and misses some is a finding with the fix to load without the key; a large full load that changes almost nothing is a should row naming a key | Low | `kits/core` or `kits/harmonise`, `load_changes()` in `kits/goals/kit.sql`, the load skill, `docs/usage/load.md` | Built: `delivery` on a table, `load_modes()`; a full load of 100,000 rows or more keeps a sum of row hashes (5% of the load) | |
| 8 | The skill: how an agent harmonises with the kit, on both cases | Low | `skills/` | Built: `skills/glossql-modeling/references/harmonise.md`, walked from an empty workspace to `must 0` in 9 calls | |
| 9 | The demo rebuilt on the kit: its statements run on this server, its Mapping and Reconciliation pages read the kit's reads | Medium: the demo is behind the server (`cube`, `metric_bands`, `ruling` no longer exist) | `../glossdemo`, the project lead's repository | After 8; the lead says when | |

## Found while building

- A branch of a union reads more than one system: the identity and
  unit tables come from the group's own source. The system is per
  source table. Reconciliation (row 4) needs a rule for the table
  that drives a branch: the one whose rows the branch keeps.
- FERC's two filing systems are loaded from one source. A table's
  system is its load's source unless an annotation on the table
  states another.
- A function body gets a view's systems as a set. Row 4 needs each
  read table's source in `definition()`.

- The unmapped code shows as an orphan rate only; the reconciliation
  names the codes.
- Each kit that adds rows to `next` adds planning time to every
  write: 0.44 s before the kit, 0.49 s with it, on a dataset that
  does not use it (`dependencies.md`, the write-time row).

- The reconciliation does not follow an aggregated target (GROUP
  BY), DISTINCT, LIMIT, joins other than inner, left and right, or a
  query around the union: such a view reads "not applicable" with the
  step. Unmatched keys are counted over the whole table, not per
  period. The sum at the source appears only where a measure comes
  from the driving table alone.

- Found by the walk and fixed: a join with no declared relationship
  is a should with its statement; a loaded table's stated grain is
  tested at each load (`grain_check`); a join on several columns is
  judged as one key; the mapping read shows the column a value is
  looked up by (`lookup`); a test with nothing to check is no row.

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
