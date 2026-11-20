-- The harmonise kit (preview): several systems of record mapped onto one
-- target table. The target is a table view (kind table), each of its
-- branches reading one system's loaded tables. Where each target column
-- comes from is read off the view's SQL by column_mapping() (the views
-- kit), each source table's system being its `system_of_record` where the
-- table states one, else the source its load query reads (the lineage's
-- 'loaded from' edge). The target carries a contract on its columns; the
-- server checks the rows against it after a write wherever it is stated,
-- and runs without the kit. Loaded after the views kit.
--
--   FROM glossql_kit('kits/views/kit.sql');
--   FROM glossql_kit('kits/harmonise/kit.sql');

--===------------------------------------------------------------------===--
-- system_of_record, on a loaded table: the system its rows come from,
-- where that is not the source its load query reads (one source that
-- loads two filing systems). column_mapping() groups by it.
--===------------------------------------------------------------------===--

DECLARE PROPERTY system_of_record WITH $${
  "description": "Preview. The system of record a loaded table's rows come from, where it is not the source the table is loaded from.",
  "type": "object", "required": ["value"],
  "properties": {"value": {"type": "string"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

--===------------------------------------------------------------------===--
-- source_systems, a function an actor runs on a table or a table view:
-- the source systems it is loaded from, each with whether its conventions
-- (units, codes, dates, as the kpi kit's `conventions ON SOURCE` holds
-- them) are written down. Read through the place 'its source systems', so
-- the result is out of date once a system's conventions change or the
-- view reads another system. The place is the sources the tables are
-- loaded from, which carry the conventions; a system_of_record names no
-- source and carries none.
--===------------------------------------------------------------------===--

DECLARE PROPERTY source_systems WITH $${
  "description": "Preview. The source systems a table or a table view is loaded from, and whether the conventions of each are written down.",
  "type": "object",
  "properties": {
    "systems": {"type": ["array", "null"], "items": {"type": "object"}},
    "without_conventions": {"type": "integer"}
  }
}$$ AS MEASUREMENT ON TABLE;

DECLARE FUNCTION source_systems FOR GLOBAL AS $$
  SELECT list({'system': asset, 'conventions': state} ORDER BY asset) AS systems,
         count(*) FILTER (WHERE state = 'missing') AS without_conventions
  FROM annotations('conventions', 'its source systems')
$$ RETURNS source_systems;

--===------------------------------------------------------------------===--
-- The contract on a target's columns, a data contract stated where the
-- target is defined:
--   the key       the `entity` grain on the view (one column or several):
--                 unique and filled
--   the meaning   `meaning` on the view and on each column
--   contract      on each column: its type (as DuckDB names it: VARCHAR,
--                 BIGINT, DOUBLE, DATE), whether a value is required, the
--                 allowed values as a list
--   a code table  a relationship from the view's column to the code
--                 table's key (DECLARE RELATIONSHIP <view>.<column> ->
--                 <table>.<code>)
-- Once one column carries a contract, `next` asks for it on each other
-- column of the view (x-asked: per table), and the server runs
-- contract_check and code_check on the view after each write
-- (x-set-by: contract).
--===------------------------------------------------------------------===--

DECLARE PROPERTY contract WITH $${
  "description": "Preview. A target column's part of the data contract: its type, whether a value is required, the allowed values.",
  "type": "object", "x-asked": "per table",
  "examples": [{"type": "<VARCHAR|BIGINT|DOUBLE|DATE|...>", "required": false}],
  "properties": {"type": {"type": "string"}, "required": {"type": "boolean"},
                 "values": {"type": "array", "items": {"type": ["string", "number", "boolean"]}},
                 "basis": {"type": "string"}}
}$$ AS FACT ON COLUMN;

-- contract_type(t): a type as the contract may spell it, as DuckDB names
-- it; contract_type_holds(served, stated): the served type is the stated
-- one, a stated DECIMAL holding any precision
CREATE OR REPLACE MACRO main.contract_type(t) AS
  CASE upper(trim(t)) WHEN 'STRING' THEN 'VARCHAR' WHEN 'TEXT' THEN 'VARCHAR' WHEN 'INT' THEN 'INTEGER'
       WHEN 'INT4' THEN 'INTEGER' WHEN 'INT8' THEN 'BIGINT' WHEN 'LONG' THEN 'BIGINT' WHEN 'FLOAT8' THEN 'DOUBLE'
       WHEN 'DOUBLE PRECISION' THEN 'DOUBLE' WHEN 'BOOL' THEN 'BOOLEAN' ELSE upper(trim(t)) END;

CREATE OR REPLACE MACRO main.contract_type_holds(served, stated) AS
  main.contract_type(served) = main.contract_type(stated)
  OR (NOT contains(stated, '(') AND split_part(upper(served), '(', 1) = main.contract_type(stated));

-- contract_check: the view's rows keep its contract. Per column, the
-- breaches with how many rows and up to three example values: key (the
-- key repeats: the rows past the first per key, the repeated keys, as the
-- views kit's key_repeats() counts them for a loaded table's grain too),
-- required (rows with no value; every key column is required), values
-- (rows whose value is not an allowed one), codes (rows whose value finds
-- no row in the code table, from the relationship's stored coherence; no
-- examples), type (the column is served as another type: every row, the
-- served type as the example), missing (a key column the view does not
-- serve). breach_rate is the share of rows of the breach with the most.
-- Not applicable until each code table relationship has its coherence
-- stored, which the server computes first.
DECLARE PROPERTY contract_check WITH $${
  "description": "Preview. The rows of a target view keep its contract: the key is unique and filled, required values are filled, values are allowed, codes are in their code table, the types hold.",
  "type": "object", "x-subject": "view", "x-set-by": "contract",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]}, "rows": {"type": ["integer", "null"]},
                 "breaches": {"type": ["array", "null"], "items": {"type": "object"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION contract_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  cells AS MATERIALIZED (SELECT "column" AS col, column_type, rn, val FROM dataset_cells($subject, true)),
  n AS (SELECT count(DISTINCT rn) AS rows FROM cells),
  served AS (SELECT DISTINCT col, column_type FROM cells),
  stated AS (
    SELECT substr(asset, length($subject) + 2) AS col, value
    FROM annotations('contract', 'its columns') WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  key AS (
    SELECT from_json(value->'grain', '["VARCHAR"]') AS cols
    FROM annotations('entity', 'itself')
    WHERE value IS NOT NULL AND state IN ('current', 'stale') AND json_array_length(value->'grain') > 0),
  -- the views kit's count of a repeated key, as a loaded table's grain is tested
  repeated AS (SELECT shown, n FROM key_repeats($subject, (SELECT cols FROM key)) WHERE shown IS NOT NULL),
  required AS (
    SELECT col FROM stated WHERE coalesce(value->>'required' = 'true', false)
    UNION SELECT unnest(cols) FROM key),
  disallowed AS (
    SELECT c.col, c.val, count(*) AS n FROM cells c JOIN stated s ON s.col = c.col
    WHERE json_type(s.value->'values') = 'ARRAY' AND c.val IS NOT NULL
      AND NOT list_contains(json_extract_string(s.value, '$.values[*]'), c.val)
    GROUP BY ALL),
  codes AS (
    SELECT regexp_extract(asset, '^[^.]+\.[^.]+\.(.+) -> ', 1) AS col, asset AS relationship, value
    FROM results('relationship_coherence', 'its relationships')
    WHERE starts_with(asset, $subject || '.') AND contains(asset, ' -> ')),
  breaches AS (
    SELECT (SELECT array_to_string(cols, ', ') FROM key) AS col, 'key' AS rule, sum(n - 1)::BIGINT AS count,
           list(shown ORDER BY n DESC, shown)[1:3] AS examples
    FROM repeated HAVING count(*) > 0
    UNION ALL
    SELECT u.kc, 'missing', n.rows, []::VARCHAR[] FROM key, unnest(key.cols) u(kc), n
    WHERE u.kc NOT IN (SELECT col FROM served) AND n.rows > 0
    UNION ALL
    SELECT c.col, 'required', count(*), []::VARCHAR[] FROM cells c
    WHERE c.col IN (SELECT col FROM required) AND c.val IS NULL GROUP BY c.col
    UNION ALL
    SELECT col, 'values', sum(n)::BIGINT, list(val ORDER BY n DESC, val)[1:3] FROM disallowed GROUP BY col
    UNION ALL
    SELECT c.col, 'codes', (c.value->>'orphans')::BIGINT, []::VARCHAR[] FROM codes c
    WHERE coalesce((c.value->>'orphans')::BIGINT, 0) > 0
    UNION ALL
    SELECT s.col, 'type', n.rows, [v.column_type] FROM stated s JOIN served v ON v.col = s.col, n
    WHERE s.value->>'type' IS NOT NULL AND NOT main.contract_type_holds(v.column_type, s.value->>'type')),
  state AS (
    SELECT (SELECT bool_or(c.derivation IS NOT NULL) FROM d, unnest(d.columns) t(c)) IS TRUE AS plans,
           (SELECT string_agg(relationship, ', ' ORDER BY relationship) FROM codes WHERE value IS NULL) AS unchecked,
           (SELECT redefine_statement(view) FROM d) AS redefine,
           (SELECT max(count) FROM breaches) AS worst, n.rows
    FROM n)
  SELECT state.plans AND state.unchecked IS NULL AS applicable,
         CASE WHEN NOT state.plans THEN 'its definition does not plan'
              WHEN state.unchecked IS NOT NULL THEN 'no coherence result is stored for ' || state.unchecked || ': run relationship_coherence() over each' END AS reason,
         CASE WHEN state.plans AND state.unchecked IS NULL THEN least(1.0, coalesce(state.worst, 0) / greatest(state.rows, 1)::DOUBLE) END AS breach_rate,
         state.rows,
         (SELECT list({'column': col, 'rule': rule, 'count': count, 'examples': examples} ORDER BY col, rule) FROM breaches) AS breaches,
         CASE WHEN EXISTS (SELECT 1 FROM breaches)
              THEN split_part($subject, '.', 2) || ' breaks its contract: ' || (SELECT string_agg(col || ' ' || CASE rule
                     WHEN 'key' THEN 'repeats in ' || count || ' more ' || CASE WHEN count = 1 THEN 'row' ELSE 'rows' END || ': ' || array_to_string(examples, ', ')
                     WHEN 'required' THEN 'is empty in ' || count || CASE WHEN count = 1 THEN ' row' ELSE ' rows' END
                     WHEN 'values' THEN 'holds a value outside the allowed ones in ' || count || CASE WHEN count = 1 THEN ' row' ELSE ' rows' END || ' (' || array_to_string(examples, ', ') || ')'
                     WHEN 'codes' THEN 'holds a code with no row in its code table in ' || count || CASE WHEN count = 1 THEN ' row' ELSE ' rows' END
                     WHEN 'type' THEN 'is served as ' || examples[1] || ', not the type the contract states'
                     ELSE 'is not served' END, '; ' ORDER BY col, rule) FROM breaches) END AS finding,
         CASE WHEN EXISTS (SELECT 1 FROM breaches) THEN concat_ws(chr(10),
           '-- fix the load query or the definition so that every row keeps the contract, then record the definition again:',
           state.redefine,
           '-- where a person accepts the rows as they are, record the rate with their reason:',
           '-- ' || main.gloss_statement('contract_check', $subject,
                    '{"tolerance": ' || ceil(least(1.0, coalesce(state.worst, 0) / greatest(state.rows, 1)::DOUBLE) * 1000) / 1000
                    || ', "basis": "<who accepted the rows and why>"}')) END AS fix
  FROM state
$$ RETURNS contract_check;

DECLARE TEST contract_test ON contract_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

--===------------------------------------------------------------------===--
-- A view's condition on one read of a table, as definition() renders it
-- (=(supply.stock.status:VARCHAR, 'D')), applied to the table's cells.
-- condition_applies(c): the condition is comparisons of the table's
-- columns with values (=, IN, <>, <, >, <=, >=) joined by and; another
-- form (an or, a window, a function of a column) cannot be applied.
-- condition_terms(c): each comparison, with the column's path
-- (dataset.table.column, the alias of a table read twice left out), the
-- operator and the values. condition_holds(op, literals, v): a value
-- meets one comparison.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.condition_applies(c) AS
  c IS NULL OR regexp_replace(regexp_replace(c, '(?:=|in|<>|!=|<=|>=|<|>)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\)', '', 'g'),
                                'and\(|[(), ]', '', 'g') = '';

CREATE OR REPLACE MACRO main.condition_terms(c) AS
  list_transform(
    regexp_extract_all(c, '(?:^|[^a-z_<>!~=])((?:=|in|<>|!=|<=|>=|<|>)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\))', 1),
    lambda m: {'path': regexp_replace(regexp_extract(m, '^[^(]+\(([^:]+):', 1), '\[[^\]]*\]', ''),
               'op': regexp_extract(m, '^([^(]+)\(', 1),
               'literals': list_transform(
                  regexp_extract_all(regexp_extract(m, '^[^:]+:[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(, .*)\)$', 1),
                                     '''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*'),
                  lambda l: CASE WHEN starts_with(l, '''') THEN replace(l[2:-2], '''''', '''')
                                 WHEN starts_with(l, 'cast(') THEN trim(trim(regexp_extract(l, '^cast\((.*) as [A-Z]+\)$', 1)), '''')
                                 ELSE l END)});

CREATE OR REPLACE MACRO main.condition_holds(op, literals, v) AS
  coalesce(v IS NOT NULL AND CASE
    WHEN op IN ('=', 'in', '<>', '!=')
    THEN (list_contains(literals, v)
          OR coalesce(list_contains(list_transform(literals, lambda l: try_cast(l AS DOUBLE)), try_cast(v AS DOUBLE)), false))
         = (op IN ('=', 'in'))
    WHEN op = '<' THEN coalesce(try_cast(v AS DOUBLE) < try_cast(literals[1] AS DOUBLE), v < literals[1])
    WHEN op = '<=' THEN coalesce(try_cast(v AS DOUBLE) <= try_cast(literals[1] AS DOUBLE), v <= literals[1])
    WHEN op = '>' THEN coalesce(try_cast(v AS DOUBLE) > try_cast(literals[1] AS DOUBLE), v > literals[1])
    WHEN op = '>=' THEN coalesce(try_cast(v AS DOUBLE) >= try_cast(literals[1] AS DOUBLE), v >= literals[1]) END, false);

--===------------------------------------------------------------------===--
-- code_check: the codes a target's expressions name, against the codes
-- the source columns hold. From each column's derivation (definition()),
-- each source column the expression tests against literals (=, IN, a
-- CASE over the column) with the literals it names; from the data of the
-- tables the view reads, the values of that column the literals do not
-- name, with their rows. Such a value falls to the expression's ELSE or
-- to NULL: name every code, so that a new one shows here. Per target
-- column and source column: the system (its table's system_of_record,
-- else its load's source), the literals, the values not named, and told,
-- false where the column is also tested by a range, a pattern or a
-- function of it (the literals do not tell what it handles), or where
-- the view's condition on its table cannot be applied here. The values
-- are counted over the rows the view's condition on the table keeps
-- (definition()'s conditions: comparisons with literals joined by and);
-- a row a join drops for want of a partner is orphan_test's, as is a
-- code mapped through a join. Red where a value not named
-- reaches a column with a contract: breach_rate is the largest share of a
-- source column's rows whose value is not named. Not applicable where no
-- column tests a code the literals tell.
--===------------------------------------------------------------------===--

DECLARE PROPERTY code_check WITH $${
  "description": "Preview. Every code a source column holds is named by the expression of the target column it reaches.",
  "type": "object", "x-subject": "view", "x-set-by": "contract",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "codes": {"type": ["array", "null"], "items": {"type": "object"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION code_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  cols AS (SELECT c.name AS col, c.derivation FROM d, unnest(d.columns) t(c) WHERE c.derivation IS NOT NULL),
  -- a test against literals, as the lineage renders it: =(column, literal) or in(column, literal, ...)
  tests AS (
    SELECT col, regexp_extract(m, '\(([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1) AS path,
           regexp_extract_all(regexp_extract(m, ':[A-Z][A-Z0-9_ ]*(, .*)\)$', 1),
                              '''(?:[^'']|'''')*''|cast\([^()]* as|-?[0-9][0-9.]*') AS literals
    FROM cols, unnest(list_distinct(regexp_extract_all(derivation,
      '(?:^|[^a-z_<>!~=])(?:=|in)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\)'))) u(m)),
  -- a test the literals do not tell: a range, a pattern, or a function of the column
  untold AS (
    SELECT DISTINCT col, regexp_extract(m, '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1) AS path
    FROM cols, unnest(list_distinct(regexp_extract_all(derivation,
      '(?:^|[^a-z_<>!~=])(?:(?:<>|!=|<=|>=|<|>|~~\*?|!~~\*?|regexp_matches|regexp_full_match|prefix|suffix|starts_with|contains)\(|(?:=|in)\([a-z_]+\()[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:'))) u(m)),
  named AS (
    SELECT col, path, list_sort(list(DISTINCT CASE WHEN starts_with(l, '''') THEN replace(l[2:-2], '''''', '''')
                                         WHEN starts_with(l, 'cast(') THEN trim(trim(l[6:-4]), '''')
                                         ELSE l END)) AS literals
    FROM tests, unnest(literals) u(l) GROUP BY col, path),
  -- what the view requires of each source table's rows (definition()'s conditions): one condition for
  -- every read of the table, made of comparisons of its columns with literals joined by and, is applied;
  -- reads with different conditions, or one with another form (a window, an or), are not
  conds AS (
    SELECT split_part(c.table_name, '.', 2) AS t, count(DISTINCT coalesce(c.condition, '')) AS n, max(c.condition) AS condition
    FROM d, unnest(d.conditions) u(c) GROUP BY 1),
  tellable AS (SELECT t, n = 1 AND main.condition_applies(condition) AS ok FROM conds),
  conjuncts AS (
    SELECT c.t, u.k.path, u.k.op, u.k.literals
    FROM conds c JOIN tellable USING (t), unnest(main.condition_terms(c.condition)) u(k)
    WHERE tellable.ok AND c.condition IS NOT NULL),
  judged AS (
    SELECT n.col, n.path, n.literals,
           NOT EXISTS (SELECT 1 FROM untold u WHERE u.col = n.col AND u.path = n.path)
             AND coalesce((SELECT ok FROM tellable WHERE t = split_part(n.path, '.', 2)), true) AS told FROM named n
    UNION ALL
    SELECT u.col, u.path, []::VARCHAR[], false FROM untold u
    WHERE NOT EXISTS (SELECT 1 FROM named n WHERE n.col = u.col AND n.path = u.path)),
  cells AS MATERIALIZED (
    SELECT "table" AS t, split_part($subject, '.', 1) || '.' || "table" || '.' || "column" AS path, rn, val
    FROM dataset_cells(split_part($subject, '.', 1), 'its sources')),
  -- the rows of a source table the view's condition leaves out
  dropped AS (
    SELECT DISTINCT x.t, x.rn
    FROM (SELECT DISTINCT t, rn FROM cells WHERE t IN (SELECT t FROM conjuncts)) x
    JOIN conjuncts k ON k.t = x.t
    LEFT JOIN cells v ON v.t = x.t AND v.rn = x.rn AND v.path = k.path
    WHERE NOT main.condition_holds(k.op, k.literals, v.val)),
  present AS (
    SELECT j.col, j.path, c.val, count(*) AS n FROM judged j JOIN cells c ON c.path = j.path
    WHERE j.told AND c.val IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dropped x WHERE x.t = c.t AND x.rn = c.rn)
    GROUP BY ALL),
  unnamed AS (
    SELECT p.* FROM present p JOIN judged j ON j.col = p.col AND j.path = p.path
    WHERE NOT list_contains(j.literals, p.val)
      AND NOT coalesce(list_contains(list_transform(j.literals, lambda l: try_cast(l AS DOUBLE)), try_cast(p.val AS DOUBLE)), false)),
  records AS (
    SELECT asset, value->>'value' AS system FROM annotations('system_of_record', 'its sources')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  systems AS (
    SELECT r.table_name, coalesce(o.system, r.source) AS system
    FROM d, unnest(d.reads) t(r) LEFT JOIN records o ON o.asset = r.table_name),
  contracted AS (
    SELECT substr(asset, length($subject) + 2) AS col FROM annotations('contract', 'its columns')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  codes AS (
    SELECT j.col, s.system, split_part(j.path, '.', 2) || '.' || split_part(j.path, '.', 3) AS source, j.literals, j.told,
           j.col IN (SELECT col FROM contracted) AS contracted,
           (SELECT coalesce(sum(p.n), 0) FROM present p WHERE p.col = j.col AND p.path = j.path)::BIGINT AS rows,
           (SELECT coalesce(sum(u.n), 0) FROM unnamed u WHERE u.col = j.col AND u.path = j.path)::BIGINT AS unnamed_rows,
           (SELECT list({'value': u.val, 'rows': u.n} ORDER BY u.n DESC, u.val) FROM unnamed u WHERE u.col = j.col AND u.path = j.path) AS unnamed
    FROM judged j LEFT JOIN systems s ON s.table_name = split_part(j.path, '.', 1) || '.' || split_part(j.path, '.', 2)),
  reached AS (SELECT * FROM codes WHERE told AND contracted AND unnamed_rows > 0),
  state AS (
    SELECT EXISTS (SELECT 1 FROM codes WHERE told) AS applicable,
           (SELECT max(unnamed_rows / greatest(rows, 1)::DOUBLE) FROM reached) AS worst,
           (SELECT redefine_statement(view) FROM d) AS redefine)
  SELECT state.applicable,
         CASE WHEN NOT EXISTS (SELECT 1 FROM codes) THEN 'no column of the view tests a source column against literals; a code mapped through a join is orphan_test''s'
              WHEN NOT state.applicable THEN 'each column that tests a code does so by a range, a pattern or a function of the column, so the literals do not tell which codes it handles' END AS reason,
         CASE WHEN state.applicable THEN coalesce(state.worst, 0.0) END AS breach_rate,
         (SELECT list({'column': col, 'system': system, 'source': source, 'literals': literals, 'told': told,
                       'contracted': contracted, 'rows': rows, 'unnamed': unnamed} ORDER BY col, system, source) FROM codes) AS codes,
         CASE WHEN EXISTS (SELECT 1 FROM reached)
              THEN (SELECT string_agg(col || ' gets codes its expression does not name from ' || source || ' (' || system || '): '
                                      || (SELECT string_agg('''' || x.value || ''' ' || x.rows || CASE WHEN x.rows = 1 THEN ' row' ELSE ' rows' END, ', ')
                                          FROM (SELECT unnest(unnamed, recursive := true)) x), '; ' ORDER BY col, system, source)
                    FROM reached) END AS finding,
         CASE WHEN EXISTS (SELECT 1 FROM reached) THEN concat_ws(chr(10),
           '-- name each code in the expression (WHEN ''<code>'' THEN ...) and leave the rest to NULL, then record the definition again:',
           state.redefine,
           '-- where a person accepts the codes as they fall, record the rate with their reason:',
           '-- ' || main.gloss_statement('code_check', $subject,
                    '{"tolerance": ' || ceil(state.worst * 1000) / 1000 || ', "basis": "<who accepted the codes and why>"}')) END AS fix
  FROM state
$$ RETURNS code_check;

DECLARE TEST code_test ON code_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

--===------------------------------------------------------------------===--
-- reconciliation: per source system and period, did every row arrive,
-- and which did not. Each branch of the target's union (1 where it has
-- none) is reconciled against the table its rows come from: the one
-- table it reads that is joined to nothing before it (the lineage's
-- mapping: a read with no lookup). That table's system is its
-- system_of_record, else its load's source. A served row belongs to a
-- branch by the column that names each branch's system with a literal
-- (such as 'sap' AS source_system); a view of one branch needs none.
--
-- The comparison is at the view's grain. A source row the view's
-- condition on its table keeps gets its key (the entity's grain on the
-- view) as the view computes it: a key column the branch copies from the
-- source table (as it is, or cast) takes the row's value; one it looks
-- up through a join takes the value of each row of the joined table the
-- join's equalities and that table's condition find, and no value where
-- none is found. The row arrives where the view serves a row of its
-- branch with that key. A key column the branch computes otherwise is
-- left out of the comparison; where none is left, the branch's rows are
-- counted and not compared. Rows the view's condition leaves out are
-- counted apart, not as missing; a condition that is not comparisons
-- with literals cannot be applied, and that branch is not compared.
-- A view that groups, or joins one row to many, serves another number
-- of rows than it reads: the counts are shown, never judged.
--
-- Per system and period (the view's time column: the entity's
-- time_axis, else its column with role timestamp; a date truncated to
-- its time grain, a month where none is stated):
--   source_rows    rows of the source table the view's condition keeps
--   excluded_rows  rows of the source table the view's condition leaves out
--   target_rows    rows the view serves from that system
--   missing_rows   source rows whose key the view does not serve; NULL
--                  where the branch is not compared
--   missing_keys   those rows by the source table's own columns the key
--                  is computed from, the first ten, and how many there are
--   measures       per column with role measure, the sum at the source
--                  and the sum the view serves
-- notes says what is not compared and why. breach_rate is the share of
-- compared source rows that do not arrive; reconciliation_test is red
-- above 0, and a person may accept a rate with a tolerance. The server
-- computes it after a write on each view with a contract (x-set-by).
--===------------------------------------------------------------------===--

DECLARE PROPERTY reconciliation WITH $${
  "description": "Preview. Per source system and period, the rows and the sum of each measure at the source against what a target view serves, and the source rows whose key the view does not serve.",
  "type": "object", "x-subject": "view", "x-set-by": "contract",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "comparison": {"type": ["string", "null"]},
                 "period_column": {"type": ["string", "null"]}, "system_column": {"type": ["string", "null"]},
                 "key": {"type": ["array", "null"], "items": {"type": "string"}},
                 "rows": {"type": ["array", "null"], "items": {"type": "object"}},
                 "notes": {"type": ["array", "null"], "items": {"type": "string"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- reconciliation_period(value, grain): a period as text, a date or a
-- timestamp truncated to the grain (a month where none is stated)
CREATE OR REPLACE MACRO main.reconciliation_period(v, grain) AS
  CASE WHEN v[5] = '-' AND v[8] = '-' AND try_cast(v AS TIMESTAMP) IS NOT NULL
       THEN CASE WHEN coalesce(grain, 'month') IN ('minute', 'hour')
                 THEN strftime(date_trunc(grain, try_cast(v AS TIMESTAMP)), '%Y-%m-%d %H:%M')
                 ELSE strftime(date_trunc(coalesce(grain, 'month'), try_cast(v AS TIMESTAMP)), '%Y-%m-%d') END
       ELSE v END;

-- reconciliation_value(value): a value as text, a number written one way
-- whatever its type, so that a value cast on its way still matches
CREATE OR REPLACE MACRO main.reconciliation_value(v) AS
  coalesce(CAST(try_cast(v AS HUGEINT) AS VARCHAR), CASE WHEN regexp_full_match(v, '\s*-?[0-9.]+(e-?[0-9]+)?\s*')
                                                         THEN CAST(try_cast(v AS DOUBLE) AS VARCHAR) END, v);

-- reconciliation_key(value, cast_to): a key value as the reconciliation
-- compares it: cast to a date where the view casts it to one, a midnight
-- timestamp as its date, no value as a value of its own
CREATE OR REPLACE MACRO main.reconciliation_key(v, cast_to) AS
  coalesce(CASE WHEN upper(cast_to) = 'DATE' THEN CAST(CAST(try_cast(v AS TIMESTAMP) AS DATE) AS VARCHAR) END,
           regexp_replace(main.reconciliation_value(v), '^([0-9]{4}-[0-9]{2}-[0-9]{2})[ T]00:00:00(\.0+)?$', '\1'), chr(0));

DECLARE FUNCTION reconciliation FOR GLOBAL AS $$
  WITH RECURSIVE d AS (SELECT * FROM definition('itself')),
  cols AS (SELECT c.name AS col, c.position AS pos FROM d, unnest(d.columns) t(c)),
  -- where each target column comes from, per branch and table read (the lineage's mapping); the alias of a
  -- table read more than once is left out of the derivation and the lookup
  mapping AS (
    SELECT u.m."column" AS col, u.m.branch, regexp_replace(u.m.derivation, '\[[^\]]*\]', '', 'g') AS derivation,
           u.m.table_name, u.m.table_column, regexp_replace(u.m.lookup, '\[[^\]]*\]', '', 'g') AS lookup, u.m.literals
    FROM results('lineage', 'itself') l,
         unnest(from_json(l.value->'mapping', '[{"column": "VARCHAR", "branch": "INTEGER", "derivation": "VARCHAR", "table_name": "VARCHAR",
                                                "table_column": "VARCHAR", "lookup": "VARCHAR", "literals": ["VARCHAR"]}]')) u(m)
    WHERE u.m."column" IS NOT NULL),
  roles AS (
    SELECT substr(asset, length($subject) + 2) AS col, value->>'value' AS role FROM annotations('role', 'its columns')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  entity AS (
    SELECT value FROM annotations('entity', 'itself') WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  grains AS (
    SELECT substr(asset, length($subject) + 2) AS col, value->>'floor' AS floor FROM annotations('time_grains', 'its columns')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  period AS (
    SELECT c.col, c.pos, (SELECT max(g.floor) FROM grains g WHERE g.col = c.col) AS floor FROM cols c
    WHERE c.col = coalesce((SELECT max(value->>'time_axis') FROM entity),
                           (SELECT arg_min(r.col, x.pos) FROM roles r JOIN cols x USING (col) WHERE r.role = 'timestamp'))),
  measures AS (SELECT c.col, c.pos FROM roles r JOIN cols c USING (col) WHERE r.role = 'measure'),
  key AS (
    SELECT g[i] AS col, i FROM (SELECT from_json(max(value->'grain'), '["VARCHAR"]') AS g FROM entity), unnest(range(1, len(g) + 1)) r(i)),
  branches AS (SELECT DISTINCT branch FROM mapping),
  -- per branch, the table its rows come from: the one table it reads that is joined to nothing before it
  driving AS (
    SELECT branch, any_value(table_name) AS table_path, count(DISTINCT table_name) AS tables
    FROM mapping WHERE table_name IS NOT NULL AND lookup IS NULL GROUP BY branch),
  records AS (
    SELECT asset, value->>'value' AS system FROM annotations('system_of_record', 'its sources')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  systems AS (
    SELECT DISTINCT r.table_name, coalesce(o.system, r.source, split_part(r.table_name, '.', 2)) AS system
    FROM d, unnest(d.reads) t(r) LEFT JOIN records o ON o.asset = r.table_name),
  -- a column each branch serves as one literal, a different one per branch: it names the row's system
  constants AS (
    SELECT col, branch, CASE WHEN starts_with(any_value(literals[1]), '''') THEN replace(any_value(literals[1])[2:-2], '''''', '''')
                             ELSE any_value(literals[1]) END AS value
    FROM mapping GROUP BY col, branch
    HAVING count(*) = 1 AND bool_and(table_name IS NULL AND len(literals) = 1 AND derivation = literals[1])),
  system_column AS (
    SELECT k.col FROM constants k JOIN cols c USING (col) GROUP BY k.col, c.pos
    HAVING count(DISTINCT k.branch) = (SELECT count(*) FROM branches) AND count(DISTINCT k.value) = count(*)
    ORDER BY c.pos LIMIT 1),
  -- what the view's joins and filters require of each table it reads, per branch: applied where it is one
  -- condition, made of comparisons of the table's columns with literals
  scope AS (
    SELECT c.branch, split_part(c.table_name, '.', 2) AS t, max(c.condition) AS condition,
           count(DISTINCT coalesce(c.condition, '')) = 1 AND main.condition_applies(max(c.condition)) AS applies
    FROM d, unnest(d.conditions) u(c) GROUP BY ALL),
  -- the target columns each branch copies from a column of its source table, as it is or cast
  copies AS (
    SELECT m.branch, m.col, any_value(m.table_column) AS source_column,
           nullif(regexp_extract(any_value(m.derivation), ' as ([A-Z][A-Z0-9_ ]*)(?:\([0-9, ]+\))?\)$', 1), '') AS cast_to
    FROM mapping m JOIN driving v ON v.branch = m.branch AND v.tables = 1
    GROUP BY m.branch, m.col
    HAVING count(*) = 1 AND any_value(m.table_name) = any_value(v.table_path)
       AND regexp_extract(any_value(m.derivation),
             '^(?:cast\()?([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(?: as [A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?\))?$', 1)
           = any_value(m.table_name) || '.' || any_value(m.table_column)),
  -- the columns each branch looks up in a table it joins to its source table: a column of that table, as it
  -- is or cast, and the join's equalities, each between a column of the source table and one of that table
  lookups AS (
    SELECT m.branch, m.col, any_value(m.table_name) AS table_path, split_part(any_value(m.table_name), '.', 2) AS t,
           any_value(m.table_column) AS value_column,
           nullif(regexp_extract(any_value(m.derivation), ' as ([A-Z][A-Z0-9_ ]*)(?:\([0-9, ]+\))?\)$', 1), '') AS cast_to,
           regexp_extract_all(any_value(m.lookup), '=\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?, [A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?\)') AS equalities,
           any_value(v.table_path) AS source_path
    FROM mapping m JOIN driving v ON v.branch = m.branch AND v.tables = 1
    GROUP BY m.branch, m.col
    HAVING count(*) = 1 AND any_value(m.lookup) IS NOT NULL AND any_value(m.table_name) <> any_value(v.table_path)
       AND regexp_extract(any_value(m.derivation),
             '^(?:cast\()?([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(?: as [A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?\))?$', 1)
           = any_value(m.table_name) || '.' || any_value(m.table_column)
       AND regexp_full_match(regexp_replace(any_value(m.lookup), '=\([^()]*\)', '', 'g'), '(?:and\(|[(), ])*')),
  pairs AS (
    SELECT branch, col, t, j, n,
           CASE WHEN split_part(p.a, '.', 1) || '.' || split_part(p.a, '.', 2) = source_path THEN split_part(p.a, '.', 3) ELSE split_part(p.b, '.', 3) END AS source_column,
           CASE WHEN split_part(p.a, '.', 1) || '.' || split_part(p.a, '.', 2) = source_path THEN split_part(p.b, '.', 3) ELSE split_part(p.a, '.', 3) END AS lookup_column,
           p.ta = p.tb AS same_type,
           list_sort([split_part(p.a, '.', 1) || '.' || split_part(p.a, '.', 2), split_part(p.b, '.', 1) || '.' || split_part(p.b, '.', 2)])
             = list_sort([source_path, table_path]) AS joins_both
    FROM (SELECT *, regexp_extract(e, '^=\(([^:]+):([^,]+), ([^:]+):(.+)\)$', ['a', 'ta', 'b', 'tb']) AS p
          FROM (SELECT l.branch, l.col, l.t, l.table_path, l.source_path, len(l.equalities) AS n,
                       unnest(l.equalities) AS e, generate_subscripts(l.equalities, 1) AS j FROM lookups l))),
  -- a column looked up through a join is followed where each equality joins the source table to that table
  -- and that table's condition can be applied
  looked AS (
    SELECT l.* FROM lookups l
    WHERE len(l.equalities) > 0 AND (SELECT bool_and(joins_both) FROM pairs p WHERE p.branch = l.branch AND p.col = l.col)
      AND coalesce((SELECT bool_and(applies) FROM scope s WHERE s.branch = l.branch AND s.t = l.t), true)),
  -- per branch, the columns a source row is compared on: each key column it copies or looks up, then each
  -- other column it looks up through a join, which decides whether the row arrives
  follows AS (
    SELECT b.branch, x.col, x.i, row_number() OVER (PARTITION BY b.branch ORDER BY x.i) AS pos,
           CASE WHEN c.col IS NOT NULL THEN 'copy' ELSE 'lookup' END AS how
    FROM branches b CROSS JOIN (SELECT c.col, coalesce(k.i, 1000 + c.pos) AS i FROM cols c LEFT JOIN key k USING (col)) x
    LEFT JOIN copies c ON c.branch = b.branch AND c.col = x.col AND x.i < 1000
    LEFT JOIN looked l ON l.branch = b.branch AND l.col = x.col
    WHERE c.col IS NOT NULL OR l.col IS NOT NULL),
  -- per branch, the source table's columns the compared columns are computed from, each once
  shown_cols AS (
    SELECT branch, min(pos) AS pos, min_by(j, pos * 1000 + j) AS j, "column" FROM (
      SELECT w.branch, w.pos, 0 AS j, c.source_column AS "column" FROM follows w JOIN copies c USING (branch, col)
      UNION ALL
      SELECT w.branch, w.pos, p.j, p.source_column FROM follows w JOIN pairs p USING (branch, col) WHERE w.how = 'lookup')
    GROUP BY branch, "column"),
  followed AS (
    SELECT b.branch, v.table_path, split_part(v.table_path, '.', 2) AS table_name, coalesce(s.system, split_part(v.table_path, '.', 2)) AS system,
           (SELECT k.value FROM constants k WHERE k.branch = b.branch AND k.col = (SELECT col FROM system_column)) AS served_as,
           EXISTS (SELECT 1 FROM period p JOIN copies c ON c.col = p.col AND c.branch = b.branch) AS dated,
           coalesce((SELECT applies FROM scope x WHERE x.branch = b.branch AND x.t = split_part(v.table_path, '.', 2)), true) AS scoped,
           (SELECT count(*) FROM follows w WHERE w.branch = b.branch) AS keys
    FROM branches b JOIN driving v ON v.branch = b.branch AND v.tables = 1 LEFT JOIN systems s ON s.table_name = v.table_path),
  compared AS (SELECT branch FROM followed WHERE scoped AND keys > 0),
  sorted AS (
    SELECT (SELECT count(*) FROM branches) = 1 OR EXISTS (SELECT 1 FROM system_column) AS sorted),
  scells AS MATERIALIZED (
    SELECT "table" AS t, "column" AS col, rn, val FROM dataset_cells(split_part($subject, '.', 1), 'its sources')
    WHERE "table" IN (SELECT table_name FROM followed UNION SELECT t FROM looked)),
  tcells AS MATERIALIZED (SELECT "column" AS col, rn, val FROM dataset_cells($subject, true)),
  -- the rows of each table a branch reads that the view's condition on that table leaves out
  terms AS (
    SELECT x.branch, x.t, u.k.path, u.k.op, u.k.literals FROM scope x, unnest(main.condition_terms(x.condition)) u(k)
    WHERE x.applies AND x.condition IS NOT NULL),
  left_out AS MATERIALIZED (
    SELECT DISTINCT k.branch, k.t, c.rn FROM terms k JOIN scells c ON c.t = k.t AND c.col = split_part(k.path, '.', 3)
    WHERE NOT main.condition_holds(k.op, k.literals, c.val)),
  srows AS MATERIALIZED (
    SELECT f.branch, x.rn, o.rn IS NOT NULL AS excluded
    FROM (SELECT DISTINCT t, rn FROM scells) x JOIN followed f ON f.table_name = x.t
    LEFT JOIN left_out o ON o.branch = f.branch AND o.t = x.t AND o.rn = x.rn),
  -- each source row with each row of a joined table that every equality of the join finds: each side's
  -- values of the equalities, in their order, joined as one key (one equality at a time multiplies the rows)
  source_key AS (
    SELECT q.branch, q.col, s.rn, list(CASE WHEN q.same_type THEN s.val ELSE main.reconciliation_value(s.val) END ORDER BY q.j) AS k
    FROM pairs q JOIN looked USING (branch, col) JOIN followed f ON f.branch = q.branch
    JOIN scells s ON s.t = f.table_name AND s.col = q.source_column
    GROUP BY q.branch, q.col, s.rn
    HAVING count(CASE WHEN q.same_type THEN s.val ELSE main.reconciliation_value(s.val) END) = any_value(q.n)),
  lookup_key AS (
    SELECT q.branch, q.col, l.rn, list(CASE WHEN q.same_type THEN l.val ELSE main.reconciliation_value(l.val) END ORDER BY q.j) AS k
    FROM pairs q JOIN looked USING (branch, col)
    JOIN scells l ON l.t = q.t AND l.col = q.lookup_column
    WHERE NOT EXISTS (SELECT 1 FROM left_out o WHERE o.branch = q.branch AND o.t = q.t AND o.rn = l.rn)
    GROUP BY q.branch, q.col, l.rn
    HAVING count(CASE WHEN q.same_type THEN l.val ELSE main.reconciliation_value(l.val) END) = any_value(q.n)),
  matched AS (
    SELECT s.branch, s.col, s.rn, l.rn AS lrn
    FROM source_key s JOIN lookup_key l ON l.branch = s.branch AND l.col = s.col AND l.k = s.k),
  -- per source row the view's condition keeps, the values of each followed key column: one where it copies,
  -- one per row the join finds where it looks up, no value where the join finds none; materialized, as the
  -- recursive step of tuples reads it at each position
  src_vals AS MATERIALIZED (
    SELECT w.branch, s.rn, w.pos, main.reconciliation_key(c.val, p.cast_to) AS val
    FROM follows w JOIN copies p USING (branch, col) JOIN followed f USING (branch)
    JOIN srows s ON s.branch = w.branch AND NOT s.excluded
    JOIN scells c ON c.t = f.table_name AND c.rn = s.rn AND c.col = p.source_column
    WHERE w.how = 'copy'
    UNION ALL
    SELECT w.branch, s.rn, w.pos, main.reconciliation_key(v.val, l.cast_to)
    FROM follows w JOIN looked l USING (branch, col)
    JOIN srows s ON s.branch = w.branch AND NOT s.excluded
    LEFT JOIN matched m ON m.branch = w.branch AND m.col = w.col AND m.rn = s.rn
    LEFT JOIN scells v ON v.t = l.t AND v.rn = m.lrn AND v.col = l.value_column
    WHERE w.how = 'lookup'),
  tuples AS (
    SELECT s.branch, s.rn, 0 AS pos, []::VARCHAR[] AS tuple FROM srows s JOIN compared USING (branch) WHERE NOT s.excluded
    UNION ALL
    SELECT t.branch, t.rn, t.pos + 1, list_append(t.tuple, v.val)
    FROM tuples t JOIN src_vals v ON v.branch = t.branch AND v.rn = t.rn AND v.pos = t.pos + 1),
  -- each served row's branch: the one branch, else the branch whose literal it serves
  served AS (
    SELECT DISTINCT c.rn, f.branch FROM tcells c, followed f
    WHERE (SELECT count(*) FROM branches) = 1
    UNION ALL
    SELECT c.rn, f.branch FROM tcells c JOIN followed f ON f.served_as = c.val
    WHERE (SELECT count(*) FROM branches) > 1 AND c.col = (SELECT col FROM system_column)),
  served_keys AS (
    SELECT DISTINCT s.branch, list(main.reconciliation_key(c.val, NULL) ORDER BY w.pos) AS tuple
    FROM served s JOIN compared USING (branch) JOIN follows w ON w.branch = s.branch JOIN tcells c ON c.rn = s.rn AND c.col = w.col
    GROUP BY s.branch, s.rn),
  arrived AS (
    SELECT DISTINCT t.branch, t.rn FROM tuples t JOIN followed f ON f.branch = t.branch AND t.pos = f.keys
    SEMI JOIN served_keys k ON k.branch = t.branch AND k.tuple = t.tuple),
  -- the period and the shown key of each source row, and the period of each served row
  speriod AS (
    SELECT s.branch, s.rn, s.excluded,
           CASE WHEN f.dated THEN main.reconciliation_period(max(c.val), (SELECT max(floor) FROM period)) END AS period
    FROM srows s JOIN followed f USING (branch)
    LEFT JOIN copies p ON p.branch = s.branch AND p.col = (SELECT col FROM period)
    LEFT JOIN scells c ON c.t = f.table_name AND c.rn = s.rn AND c.col = p.source_column
    GROUP BY s.branch, s.rn, s.excluded, f.dated),
  tperiod AS (
    SELECT s.branch, s.rn,
           CASE WHEN f.dated THEN main.reconciliation_period(max(c.val), (SELECT max(floor) FROM period)) END AS period
    FROM served s JOIN followed f USING (branch)
    LEFT JOIN tcells c ON c.rn = s.rn AND c.col = (SELECT col FROM period)
    GROUP BY s.branch, s.rn, f.dated),
  missing AS (
    SELECT p.branch, p.period,
           (SELECT array_to_string(list(coalesce(c.val, 'NULL') ORDER BY k.pos, k.j), ', ')
            FROM shown_cols k JOIN scells c ON c.t = f.table_name AND c.rn = p.rn AND c.col = k."column" WHERE k.branch = p.branch) AS shown
    FROM speriod p JOIN compared USING (branch) JOIN followed f USING (branch)
    WHERE NOT p.excluded AND NOT EXISTS (SELECT 1 FROM arrived a WHERE a.branch = p.branch AND a.rn = p.rn)),
  missed AS (
    SELECT branch, period, count(*) AS rows, count(DISTINCT shown) AS keys, list(DISTINCT shown ORDER BY shown)[1:10] AS shown
    FROM missing GROUP BY ALL),
  counted AS (
    SELECT branch, period, count(*) FILTER (WHERE side = 'source') AS source_rows, count(*) FILTER (WHERE side = 'excluded') AS excluded_rows,
           count(*) FILTER (WHERE side = 'target') AS target_rows
    FROM (SELECT CASE WHEN excluded THEN 'excluded' ELSE 'source' END AS side, branch, period FROM speriod
          UNION ALL SELECT 'target', branch, period FROM tperiod)
    GROUP BY ALL),
  sums AS (
    SELECT 'source' AS side, p.branch, p.period, x.col, sum(try_cast(c.val AS DOUBLE)) AS total
    FROM speriod p JOIN followed f USING (branch) JOIN measures x ON true JOIN copies k ON k.branch = p.branch AND k.col = x.col
    JOIN scells c ON c.t = f.table_name AND c.rn = p.rn AND c.col = k.source_column
    WHERE NOT p.excluded GROUP BY ALL
    UNION ALL
    SELECT 'target', p.branch, p.period, x.col, sum(try_cast(c.val AS DOUBLE))
    FROM tperiod p JOIN measures x ON true JOIN tcells c ON c.rn = p.rn AND c.col = x.col GROUP BY ALL),
  out AS (
    SELECT f.system, c.branch, f.table_name, c.period, c.source_rows, c.excluded_rows, c.target_rows,
           CASE WHEN c.branch IN (SELECT branch FROM compared) THEN (SELECT list(w.col ORDER BY w.pos) FROM follows w WHERE w.branch = c.branch) END AS compared_on,
           CASE WHEN c.branch IN (SELECT branch FROM compared) THEN coalesce(m.rows, 0) END AS missing_rows,
           CASE WHEN c.branch IN (SELECT branch FROM compared) THEN coalesce(m.keys, 0) END AS missing_key_count,
           CASE WHEN c.branch IN (SELECT branch FROM compared) THEN coalesce(m.shown, []) END AS missing_keys,
           (SELECT list({'column': x.col, 'source': s.total, 'target': coalesce(t.total, 0.0)} ORDER BY x.pos)
            FROM measures x
            LEFT JOIN sums s ON s.side = 'source' AND s.branch = c.branch AND s.period IS NOT DISTINCT FROM c.period AND s.col = x.col
            LEFT JOIN sums t ON t.side = 'target' AND t.branch = c.branch AND t.period IS NOT DISTINCT FROM c.period AND t.col = x.col) AS measures
    FROM counted c JOIN followed f USING (branch)
    LEFT JOIN missed m ON m.branch = c.branch AND m.period IS NOT DISTINCT FROM c.period),
  -- what is not compared, and why
  notes AS (
    SELECT 1 AS o, 'no grain is stated on ' || $subject || ': a source row is compared only on the columns the view looks up through a join; state it, '
                   || main.gloss_statement('entity', $subject, '{"value": "<what one row is>", "grain": ["<key column>"]}') AS note
    WHERE NOT EXISTS (SELECT 1 FROM key)
    UNION ALL
    SELECT 2, 'no column carries role timestamp: the rows are counted over every period; annotate the period column, '
              || main.gloss_statement('role', $subject || '.<column>', '{"value": "timestamp"}')
    WHERE NOT EXISTS (SELECT 1 FROM period)
    UNION ALL
    SELECT 3, 'branch ' || b.branch || ' reads ' || CASE WHEN v.branch IS NULL THEN 'no table' ELSE v.tables || ' tables' END
              || ' joined to nothing before it, so it has no one source table: its rows are not reconciled'
    FROM branches b LEFT JOIN driving v USING (branch) WHERE v.branch IS NULL OR v.tables <> 1
    UNION ALL
    SELECT 4, f.system || ': the view''s condition on ' || f.table_name || ' is not comparisons of its columns with values: its rows are counted, not compared'
    FROM followed f WHERE NOT f.scoped
    UNION ALL
    SELECT 5, f.system || ': ' || string_agg(k.col, ', ' ORDER BY k.i) || CASE WHEN count(*) = 1 THEN ' is' ELSE ' are' END
              || ' computed, not copied from a column of ' || f.table_name || ' or looked up through a join: '
              || CASE WHEN f.keys > 0 THEN 'its rows are compared on ' || (SELECT string_agg(w.col, ', ' ORDER BY w.pos) FROM follows w WHERE w.branch = f.branch)
                      ELSE 'its rows are counted, not compared' END
    FROM followed f, key k WHERE f.scoped AND NOT EXISTS (SELECT 1 FROM follows w WHERE w.branch = f.branch AND w.col = k.col)
    GROUP BY f.branch, f.system, f.table_name, f.keys
    UNION ALL
    SELECT 6, f.system || ': ' || p.col || ' is not copied from a column of ' || f.table_name || ': its rows are counted over every period'
    FROM followed f, period p WHERE NOT f.dated
    UNION ALL
    SELECT 7, f.system || ': ' || x.col || ' is not copied from a column of ' || f.table_name || ': it has no sum at the source'
    FROM followed f, measures x WHERE x.col NOT IN (SELECT col FROM copies c WHERE c.branch = f.branch)),
  state AS (
    SELECT (SELECT bool_or(c.derivation IS NOT NULL) FROM d, unnest(d.columns) t(c)) IS TRUE AS plans,
           EXISTS (SELECT 1 FROM followed) AS rows_read, (SELECT sorted FROM sorted) AS sorted,
           EXISTS (SELECT 1 FROM compared) AS any_compared,
           (SELECT sum(missing_rows) FROM out) AS missing_rows,
           (SELECT sum(source_rows) FROM out WHERE branch IN (SELECT branch FROM compared)) AS source_rows,
           (SELECT redefine_statement(view) FROM d) AS redefine),
  rate AS (
    SELECT CASE WHEN plans AND rows_read AND sorted AND any_compared
                THEN least(1.0, coalesce(missing_rows, 0) / greatest(coalesce(source_rows, 0), 1)::DOUBLE) END AS rate
    FROM state),
  -- the view's condition on each branch's source table, as SQL over that table
  kept AS (
    SELECT f.branch, string_agg(CASE WHEN regexp_full_match(split_part(k.path, '.', 3), '[a-z_][a-z0-9_]*') THEN split_part(k.path, '.', 3)
                                     ELSE '"' || replace(split_part(k.path, '.', 3), '"', '""') || '"' END
                                || CASE WHEN k.op IN ('=', 'in') THEN ' IN ' WHEN k.op IN ('<>', '!=') THEN ' NOT IN ' ELSE ' ' || k.op || ' ' END
                                || CASE WHEN k.op IN ('=', 'in', '<>', '!=') THEN '(' ELSE '' END
                                || (SELECT string_agg('''' || replace(l, '''', '''''') || '''', ', ') FROM unnest(k.literals) u(l))
                                || CASE WHEN k.op IN ('=', 'in', '<>', '!=') THEN ')' ELSE '' END, ' AND ') AS condition
    FROM followed f JOIN terms k ON k.branch = f.branch AND k.t = f.table_name GROUP BY f.branch),
  -- the statement that lists the source rows the view does not serve, per source table
  listing AS (
    SELECT string_agg('SELECT * FROM ' || split_part($subject, '.', 1) || '.' || t.table_name || ' WHERE '
                      || (SELECT CASE WHEN count(*) = 1 THEN any_value(e) ELSE 'concat_ws('', '', ' || string_agg(e, ', ' ORDER BY pos, j) || ')' END
                          FROM (SELECT k.pos, k.j, 'CAST(' || CASE WHEN regexp_full_match(k."column", '[a-z_][a-z0-9_]*') THEN k."column"
                                                                  ELSE '"' || replace(k."column", '"', '""') || '"' END || ' AS VARCHAR)' AS e
                                FROM shown_cols k WHERE k.branch = t.branch))
                      || ' IN (' || (SELECT string_agg('''' || replace(s, '''', '''''') || '''', ', ' ORDER BY s) FROM unnest(t.keys) u(s)) || ')'
                      || coalesce(' AND ' || (SELECT condition FROM kept k WHERE k.branch = t.branch), '') || ';',
                      chr(10) ORDER BY t.system) AS statements
    FROM (SELECT o.system, o.branch, o.table_name, list(DISTINCT k ORDER BY k)[1:10] AS keys
          FROM out o, unnest(o.missing_keys) u(k) GROUP BY ALL) t)
  SELECT state.plans AND state.rows_read AND state.sorted AND state.any_compared AS applicable,
         CASE WHEN NOT state.plans THEN 'its definition does not plan'
              WHEN NOT state.rows_read THEN 'no branch of the view reads one source table its rows come from'
              WHEN NOT state.sorted THEN 'no column of the view names the system each row comes from'
              WHEN NOT state.any_compared THEN 'no branch copies a key column from its source table or looks a column up through a join: the rows are counted, not compared (see notes)' END AS reason,
         rate.rate AS breach_rate,
         CASE WHEN state.any_compared
              THEN 'each source row the view''s condition keeps, by the columns of each row''s compared_on as the view computes them (the key''s columns it copies or looks up, and each column it looks up through a join), against the rows the view serves; the row counts are shown, not compared' END AS comparison,
         (SELECT col FROM period) AS period_column, (SELECT col FROM system_column) AS system_column,
         (SELECT list(col ORDER BY i) FROM key) AS key,
         CASE WHEN state.sorted THEN (SELECT list({'system': system, 'branch': branch, 'table': table_name, 'period': period,
                                                  'compared_on': compared_on,
                                                  'source_rows': source_rows, 'excluded_rows': excluded_rows, 'target_rows': target_rows,
                                                  'missing_rows': missing_rows, 'missing_keys': missing_keys, 'missing_key_count': missing_key_count,
                                                  'measures': measures}
                                                 ORDER BY system, period, branch) FROM out) END AS rows,
         (SELECT list(note ORDER BY o, note) FROM notes) AS notes,
         CASE WHEN rate.rate > 0
              THEN split_part($subject, '.', 2) || ' does not serve every source row: '
                   || (SELECT string_agg(system || ' ' || missing || ' of ' || source || CASE WHEN source = 1 THEN ' row' ELSE ' rows' END
                                         || coalesce(' (' || periods || ')', '') || coalesce(', keys ' || keys, ''), '; ' ORDER BY system)
                       FROM (SELECT system, sum(missing_rows) AS missing, sum(source_rows) AS source,
                                    string_agg(CASE WHEN missing_rows > 0 AND period IS NOT NULL
                                                    THEN period || ': ' || missing_rows END, ', ' ORDER BY period) AS periods,
                                    nullif(array_to_string(list_sort(flatten(list(missing_keys)))[1:10], ', '), '') AS keys
                             FROM out GROUP BY system HAVING sum(missing_rows) > 0))
              WHEN NOT state.sorted THEN 'no column of ' || split_part($subject, '.', 2) || ' names the system each row comes from' END AS finding,
         CASE WHEN rate.rate > 0 THEN concat_ws(chr(10),
                '-- the source rows whose key the view does not serve, the first ten keys per table:',
                (SELECT statements FROM listing),
                '-- fix the load query or the definition so that every source row arrives (a join that finds no partner), then record the definition again:',
                state.redefine,
                '-- where a person accepts the rows as they are, record the rate with their reason:',
                '-- ' || main.gloss_statement('reconciliation', $subject,
                         '{"tolerance": ' || ceil(rate.rate * 1000) / 1000 || ', "basis": "<who accepted the rows and why>"}'))
              WHEN state.plans AND state.rows_read AND NOT state.sorted THEN concat_ws(chr(10),
                '-- serve a column that names each row''s system, a literal in each branch (''<system>'' AS source_system), then record the definition again:',
                state.redefine) END AS fix
  FROM state, rate
$$ RETURNS reconciliation;

DECLARE TEST reconciliation_test ON reconciliation BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;
