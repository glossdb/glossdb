# Harmonising systems of record (preview)

Read before you map several source systems onto one target table.

The job: each market or entity runs its own system of record, with
its own column names, codes and units. The person wants one table in
one format. You load each system as it is, define the target as a
table view with one branch per system, and state its data contract.
After each load the server tests the target against the contract,
lists the codes the mapping does not handle, and reconciles the rows
per system. The examples follow three ERPs: SAP in Denmark, Dynamics
365 in Switzerland, a local system in Poland, and the group's
identity and unit tables.

## 1. Load each system

One source per system, one load query per table, typing only
(`load.md`). State on each table what its source sends:

```glossql
DECLARE SOURCE sap SET (type: csv, location: '/data/sap');
DECLARE RECIPE stock_sap ON supply FROM sap AS $$
  SELECT trim("MATNR") AS matnr, trim("WERKS") AS site,
         try_cast(trim("LABST") AS DOUBLE) AS unrestricted, trim("MEINS") AS uom
  FROM read_csv('mard.csv', all_varchar = true, nullstr = null_markers(), store_rejects = true)$$;
GLOSS delivery ON stock_sap AS $${"value": "full", "basis": "the stock export is the whole table each night"}$$;
```

A source that sends its complete state, or one you are not sure of,
is loaded without a key. A source that sends only new and changed
rows is loaded with `SET (key: …)`. The table and what each costs:
`load.md`. The server then holds each load against what you stated.

## 2. Name the system where one source holds two

A table's system is the source it is loaded from. Where one source
holds two systems (one folder with the old and the new filing
system's files), state the system on each table, the mapping tables
included:

```glossql
GLOSS system_of_record ON ferc.steam_xbrl AS $${"value": "ferc_xbrl", "basis": "the XBRL filings, report years from 2021"}$$;
```

## 3. Load the mapping and code tables, declare the relationships

The identity table (market and local code to the group's number) and
the unit table come from the group's own source. Load them as they
are. A mapping table that is sent whole is a full load; keyed, a
code the group retires stays in the table.

```glossql
DECLARE SOURCE model SET (type: csv, location: '/data/model');
DECLARE RECIPE model_identities ON supply FROM model AS $$
  SELECT trim(market) AS market, trim(local_code) AS local_code,
         try_cast(trim(global_material) AS BIGINT) AS global_material
  FROM read_csv('identities.csv', all_varchar = true, nullstr = null_markers(), store_rejects = true)$$;
DECLARE RELATIONSHIP stock_mono.indeks -> model_identities.local_code;
```

Declare one relationship per join a branch makes between two loaded
tables: `next` lists each join with none, with the statement. The
server checks each against the data (`relationship_coherence`) and
names the codes that find no mapping row, with their rows, in the
view's `orphan_test`. A relationship on the
local code alone holds where the systems' codes do not collide; say
so in its `meaning`.

## 4. Define the target, one branch per system

A table view (`x-kind: relation`) with one `SELECT` per system,
joined by `UNION ALL`. Each branch names its system, reads its
system's table first, joins the mapping tables, and names every code
it maps:

```glossql
DECLARE PROPERTY onhand WITH $${"title": "Stock on hand", "x-kind": "relation"}$$ AS VIEW;
GLOSS onhand ON supply AS $${"sql": "SELECT 'sap' AS source_system, i.global_material AS part, s.site, CASE s.uom WHEN 'PAL' THEN s.unrestricted * u.cases_per_pallet WHEN 'CS' THEN s.unrestricted END AS cases FROM stock_sap s JOIN model_identities i ON i.market = 'DK' AND i.local_code = s.matnr JOIN model_parts u ON u.global_material = i.global_material UNION ALL SELECT 'd365', i.global_material, d.site_id, CASE d.unit_id WHEN 'Pl' THEN (d.physical - d.reserved) * u.cases_per_pallet WHEN 'Cs' THEN d.physical - d.reserved END FROM stock_d365 d JOIN model_identities i ON i.market = 'CH' AND i.local_code = d.item_id JOIN model_parts u ON u.global_material = i.global_material UNION ALL SELECT 'mono', i.global_material, m.warehouse, CASE m.unit WHEN 'pal' THEN m.quantity * u.cases_per_pallet WHEN 'kart' THEN m.quantity END FROM stock_mono m JOIN model_identities i ON i.market = 'PL' AND i.local_code = m.indeks JOIN model_parts u ON u.global_material = i.global_material WHERE m.status = 'D'"}$$;
```

- **Name each code, with no `ELSE`.** A code the `CASE` does not name
  is then NULL, and the server lists it. An `ELSE` hides it.
- **Name the system as a literal, once per branch.** `'sap' AS
  source_system`: the reconciliation counts the target's rows per
  system by it. The mapping knows each table's system without it.
- **Read the system's table first, and copy what you can.** The
  reconciliation holds the first table of each branch against the
  target, row by row at the target's grain. It compares each key
  column the branch copies from that table, as it is or cast, and
  each column it looks up through a join from that table (a mapping
  table). Rows the branch's `WHERE` leaves out are counted as
  excluded, not missing. A key the branch computes (`'SAP/' ||
  o.vbeln`) is left out of the comparison; where nothing is left, the
  rows are only counted, and `notes` says so. A view that groups is
  compared the same way.
- **One row per key.** Where a system sends a key twice, keep one in
  a subquery over its table, before the joins, and state the choice
  as an assumption (step 7):
  `FROM (SELECT * FROM stock_sap QUALIFY row_number() OVER (PARTITION
  BY matnr, site ORDER BY unrestricted DESC) = 1) s`. Where the rows
  add up (two storage bins), the target's grain is the systems'
  grain: sum in a second view that reads the target. A `grain` stated
  in a loaded table's `entity` is tested at each load (`grain_test`).

## 5. State the contract

The key is the `grain` of the view's `entity`. Each column carries a
`contract`: its type as DuckDB names it, whether a value is
required, and the allowed values where the list is fixed.

```glossql
GLOSS entity ON supply.onhand AS $${"value": "the stock of one part at one site", "role": "fact", "grain": ["part", "site"]}$$;
GLOSS contract ON supply.onhand.part AS $${"type": "BIGINT", "required": true}$$;
GLOSS contract ON supply.onhand.site AS $${"type": "VARCHAR", "required": true, "values": ["CH10", "DK01", "DK02", "PL01"]}$$;
GLOSS contract ON supply.onhand.cases AS $${"type": "DOUBLE", "required": true}$$;
GLOSS role ON supply.onhand.cases AS $${"value": "measure"}$$;
```

From the first `contract`, the server runs `contract_test` (key,
required values, allowed values, types), `code_test` (every code
reaches a named branch of the `CASE`) and `reconciliation_test`
(every source row arrives) after each write. `next` asks for a
contract on each other column. A column with role `measure` is summed
per system in the reconciliation, per period where the `entity` names
a `time_axis`.
Where the systems share no key, build it per branch from each
system's own key columns (`'f1_steam_' || o.report_year || '_' ||
o.respondent_id`) and make that column the grain.

## 6. Read the mapping

```sql
SELECT target_column, branch, system, source_table, source_column, condition, lookup, expression, literals FROM column_mapping(for_view := 'onhand') ORDER BY target_column, branch
```

One row per target column, branch and source column: the `system`,
the source column, the `expression` that maps it, and in `literals`
the codes it names. `condition` is what the branch's filters and
literal join conditions require of that table (`market = 'PL'`).
`lookup` is the join that looks a mapping table up: the system's own
code first (`=(supply.stock_mono.indeks, supply.model_identities.local_code)`).
`complete` is false where the lineage could not follow a step. For a
person, one line per target column and branch:

```sql
SELECT target_column, branch, string_agg(DISTINCT system || ': ' || source_table || '.' || source_column, ', ') AS reads, max(array_to_string(literals, ' ')) AS codes FROM column_mapping(for_view := 'onhand') GROUP BY ALL ORDER BY ALL
```

## 7. Close what `next` lists

Read the `must` rows first; the full list with its statements is
long:

```sql
SELECT kind, asset, state, open, statement FROM next WHERE level = 'must'
```

A `must` here is served data that is wrong:

| `next` says | Close it by |
|---|---|
| `code_test`: a column gets codes its expression does not name, per system, with rows (`'Pal' 1 row`) | naming the code in the `CASE` (`WHEN 'Pal' THEN …`) and defining the view again |
| `orphan_test`: keys that find no parent, with their rows (`X9: 1 row`) | the code in the mapping table at its source, then `IMPORT model_identities;`. Adding the row is the mapping owner's work: ask the person |
| `contract_test`: the key repeats, a required value is empty, a value is not allowed | the cause, in the load query or the definition. An empty value is often an unnamed code: close `code_test` first |
| `reconciliation_test`: source rows that do not arrive, per system and period, with their keys (`north 2 of 6 rows, keys N-3, N-6`) | running the statement in the fix that lists those rows at the source, finding why each is left out (most often a join with no partner: the code in the mapping table, as for `orphan_test`), and fixing the definition or the mapping table. Rows the view's `WHERE` leaves out (a blocked status) are not counted as missing |
| a keyed load missed keys, and the source is stated `full` | the load query declared again without the key |

A `should` is the layer incomplete: a column with no `contract`,
`meaning` or `role`, a join with no declared relationship
(`relationship_test` yellow), an assumption waiting for a person. Where the fix
is a judgment, not a fact, state it as an assumption beside `sql` in
the definition, with a `key`, the `alternative` and a confidence
below 1. Two examples: the same SAP line sent twice is kept once
(`{"dimension": "scope", "key": "sap-line-sent-twice", "assumption":
"…", "alternative": "the two lines are two storage bins, and both
count", "confidence": 0.6}`); Switzerland's brand wins over Denmark's
for a part both sell. A person decides it in the review. Where a
person accepts rows as they are, each test's fix gives the annotation
that records the rate with their reason. A test with nothing to check
(`code_test` on a target that maps no codes through a `CASE`) stays
yellow and is no row of `next`.

## 8. Read the reconciliation

The server computes it after each load. Read it per system:

```sql
SELECT r->>'system' AS system, r->>'period' AS period, r->'source_rows' AS source_rows, r->'target_rows' AS target_rows, r->'missing_keys' AS missing_keys, r->'measures' AS measures FROM results, unnest(from_json(value->'rows', '["JSON"]')) t(r) WHERE function = 'reconciliation' AND subject = 'supply.onhand' ORDER BY system, period
```

Per system (and per period, where the view has a `time_axis`): the
rows of the system's table the view's condition keeps
(`source_rows`) and leaves out (`excluded_rows`), the rows the target
serves from it, the source rows it does not serve, named by the
source's own columns (`compared_on` says which target columns were
compared), and per measure the
`source` and the `target` sum, to hold against the system's own
report. A period with source rows and no target rows is a period the
target is short of. Tell the person, per system: rows in, rows out,
and each missing key with its reason from the source row, such as
"Poland: 4 rows at the source, 1 left out as blocked, 2 in the
target; X9 has no identity". `notes` names what the result cannot
compare, and why.
