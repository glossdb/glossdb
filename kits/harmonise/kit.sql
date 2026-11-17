-- The harmonise kit (preview): several systems of record mapped onto one
-- target table. The target is a table view (x-kind relation), each of its
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

DECLARE ASPECT system_of_record WITH $${
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

DECLARE ASPECT source_systems WITH $${
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

DECLARE ASPECT contract WITH $${
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
DECLARE ASPECT contract_check WITH $${
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

DECLARE ASPECT code_check WITH $${
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
    FROM cols, unnest(regexp_extract_all(derivation,
      '(?:^|[^a-z_<>!~=])(?:=|in)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\)')) u(m)),
  -- a test the literals do not tell: a range, a pattern, or a function of the column
  untold AS (
    SELECT DISTINCT col, regexp_extract(m, '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1) AS path
    FROM cols, unnest(regexp_extract_all(derivation,
      '(?:^|[^a-z_<>!~=])(?:(?:<>|!=|<=|>=|<|>|~~\*?|!~~\*?|regexp_matches|regexp_full_match|prefix|suffix|starts_with|contains)\(|(?:=|in)\([a-z_]+\()[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:')) u(m)),
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
  tellable AS (
    SELECT t, n = 1 AND (condition IS NULL OR regexp_replace(regexp_replace(condition, '(?:=|in|<>|!=|<=|>=|<|>)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\)', '', 'g'), 'and\(|[(), ]', '', 'g') = '') AS ok
    FROM conds),
  conjuncts AS (
    SELECT c.t, regexp_extract(m, '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1) AS path, regexp_extract(m, '((?:=|in|<>|!=|<=|>=|<|>))\([A-Za-z_]', 1) AS op,
           list_transform(regexp_extract_all(regexp_extract(m, ':[A-Z][A-Z0-9_ ]*(, .*)\)$', 1), '(?:''(?:[^'']|'''')*''|cast\([^()]* as|-?[0-9][0-9.]*)'),
             lambda l: CASE WHEN starts_with(l, '''') THEN replace(l[2:-2], '''''', '''')
                            WHEN starts_with(l, 'cast(') THEN trim(trim(l[6:-4]), '''') ELSE l END) AS literals
    FROM conds c JOIN tellable USING (t), unnest(regexp_extract_all(c.condition, '(?:^|[^a-z_<>!~=])(?:=|in|<>|!=|<=|>=|<|>)\([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*:[A-Z][A-Z0-9_ ]*(?:, (?:''(?:[^'']|'''')*''|cast\([^()]* as [A-Z]+\)|-?[0-9][0-9.]*))+\)')) u(m)
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
    WHERE NOT coalesce(CASE
      WHEN k.op IN ('=', 'in', '<>', '!=')
      THEN (list_contains(k.literals, v.val)
            OR coalesce(list_contains(list_transform(k.literals, lambda l: try_cast(l AS DOUBLE)), try_cast(v.val AS DOUBLE)), false))
           = (k.op IN ('=', 'in'))
      WHEN k.op = '<' THEN coalesce(try_cast(v.val AS DOUBLE) < try_cast(k.literals[1] AS DOUBLE), v.val < k.literals[1])
      WHEN k.op = '<=' THEN coalesce(try_cast(v.val AS DOUBLE) <= try_cast(k.literals[1] AS DOUBLE), v.val <= k.literals[1])
      WHEN k.op = '>' THEN coalesce(try_cast(v.val AS DOUBLE) > try_cast(k.literals[1] AS DOUBLE), v.val > k.literals[1])
      WHEN k.op = '>=' THEN coalesce(try_cast(v.val AS DOUBLE) >= try_cast(k.literals[1] AS DOUBLE), v.val >= k.literals[1]) END
      AND v.val IS NOT NULL, false)),
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
-- Per system and period (the view's time column: the entity's
-- time_axis, else its column with role timestamp; a date truncated to
-- its time grain, a month where none is stated):
--   source_rows   rows of the source table
--   target_rows   rows the view serves from that system
--   missing_rows  the rows that do not arrive: the shortfall of the
--                 count, or the rows whose key the view does not serve,
--                 whichever is more
--   missing_keys  the keys (the entity's grain on the view) at the
--                 source the view does not serve, the first ten, and
--                 how many there are
--   measures      per column with role measure, the sum at the source
--                 and the sum the view serves
-- The source side reads a target column where the branch copies it
-- from a column of the source table (as it is, or cast): the key, the
-- period and each measure. Where a branch computes one of them, notes
-- says so: its missing keys are not listed, its rows are counted over
-- every period, or the measure has no source sum. breach_rate is the
-- share of source rows that do not arrive; reconciliation_test is red
-- above 0, and a person may accept a rate with a tolerance. The server
-- computes it after a write on each view with a contract (x-set-by).
--===------------------------------------------------------------------===--

DECLARE ASPECT reconciliation WITH $${
  "description": "Preview. Per source system and period, the rows and the sum of each measure at the source against what a target view serves, and the keys at the source the view does not serve.",
  "type": "object", "x-subject": "view", "x-set-by": "contract",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
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

-- reconciliation_value(value): a key value as text, a number written
-- one way whatever its type, so that a key cast on its way still matches
CREATE OR REPLACE MACRO main.reconciliation_value(v) AS
  coalesce(CAST(try_cast(v AS HUGEINT) AS VARCHAR), CASE WHEN regexp_full_match(v, '\s*-?[0-9.]+(e-?[0-9]+)?\s*')
                                                         THEN CAST(try_cast(v AS DOUBLE) AS VARCHAR) END, v);

DECLARE FUNCTION reconciliation FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  cols AS (SELECT c.name AS col, c.position AS pos FROM d, unnest(d.columns) t(c)),
  -- where each target column comes from, per branch and table read (the lineage's mapping)
  mapping AS (
    SELECT u.m."column" AS col, u.m.branch, u.m.derivation, u.m.table_name, u.m.table_column, u.m.lookup, u.m.literals
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
  -- the target columns the reconciliation reads: the key's, the period's, each measure's
  wanted AS (
    SELECT col, 'key' AS what, i FROM key
    UNION ALL SELECT col, 'period', 0 FROM period
    UNION ALL SELECT col, 'measure', pos FROM measures),
  branches AS (SELECT DISTINCT branch FROM mapping),
  -- per branch, the table its rows come from: the one table it reads that is joined to nothing before it
  driving AS (
    SELECT branch, any_value(table_name) AS table_path, count(DISTINCT table_name) AS tables
    FROM mapping WHERE table_name IS NOT NULL AND lookup IS NULL GROUP BY branch),
  records AS (
    SELECT asset, value->>'value' AS system FROM annotations('system_of_record', 'its sources')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  systems AS (
    SELECT r.table_name, coalesce(o.system, r.source, split_part(r.table_name, '.', 2)) AS system
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
  -- the target columns each branch copies from a column of its source table, as it is or cast
  copies AS (
    SELECT m.branch, m.col, any_value(m.table_column) AS source_column
    FROM mapping m JOIN driving v ON v.branch = m.branch AND v.tables = 1
    GROUP BY m.branch, m.col
    HAVING count(*) = 1 AND any_value(m.table_name) = any_value(v.table_path)
       AND regexp_extract(any_value(m.derivation),
             '^(?:cast\()?([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):[A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?(?: as [A-Z][A-Z0-9_ ]*(?:\([0-9, ]+\))?\))?$', 1)
           = any_value(m.table_name) || '.' || any_value(m.table_column)),
  followed AS (
    SELECT b.branch, v.table_path, split_part(v.table_path, '.', 2) AS table_name, coalesce(s.system, split_part(v.table_path, '.', 2)) AS system,
           (SELECT k.value FROM constants k WHERE k.branch = b.branch AND k.col = (SELECT col FROM system_column)) AS served_as,
           EXISTS (SELECT 1 FROM period p JOIN copies c ON c.col = p.col AND c.branch = b.branch) AS dated,
           EXISTS (SELECT 1 FROM key) AND NOT EXISTS (SELECT 1 FROM key k WHERE k.col NOT IN (SELECT col FROM copies c WHERE c.branch = b.branch)) AS keyed
    FROM branches b JOIN driving v ON v.branch = b.branch AND v.tables = 1 LEFT JOIN systems s ON s.table_name = v.table_path),
  sorted AS (
    SELECT (SELECT count(*) FROM branches) = 1 OR EXISTS (SELECT 1 FROM system_column) AS sorted),
  scells AS MATERIALIZED (
    SELECT "table" AS t, "column" AS col, rn, val FROM dataset_cells(split_part($subject, '.', 1), 'its sources')
    WHERE "table" IN (SELECT table_name FROM followed)),
  tcells AS MATERIALIZED (SELECT "column" AS col, rn, val FROM dataset_cells($subject, true)),
  -- each served row's branch: the one branch, else the branch whose literal it serves
  served AS (
    SELECT DISTINCT c.rn, f.branch FROM tcells c, followed f
    WHERE (SELECT count(*) FROM branches) = 1
    UNION ALL
    SELECT c.rn, f.branch FROM tcells c JOIN followed f ON f.served_as = c.val
    WHERE (SELECT count(*) FROM branches) > 1 AND c.col = (SELECT col FROM system_column)),
  rowset AS (
    SELECT 'target' AS side, branch, rn FROM served
    UNION ALL SELECT DISTINCT 'source', f.branch, c.rn FROM scells c JOIN followed f ON f.table_name = c.t),
  vals AS (
    SELECT 'target' AS side, s.branch, s.rn, w.what, w.col, w.i, c.val FROM tcells c JOIN served s USING (rn) JOIN wanted w ON w.col = c.col
    UNION ALL
    SELECT 'source', f.branch, c.rn, w.what, w.col, w.i, c.val
    FROM scells c JOIN followed f ON f.table_name = c.t JOIN copies p ON p.branch = f.branch AND p.source_column = c.col
    JOIN wanted w ON w.col = p.col),
  per_row AS MATERIALIZED (
    SELECT r.side, r.branch, r.rn,
           CASE WHEN f.dated THEN main.reconciliation_period(max(x.val) FILTER (WHERE x.what = 'period'), (SELECT max(floor) FROM period)) END AS period,
           CASE WHEN f.keyed THEN list(main.reconciliation_value(x.val) ORDER BY x.i) FILTER (WHERE x.what = 'key') END AS key,
           CASE WHEN f.keyed THEN array_to_string(list(coalesce(x.val, 'NULL') ORDER BY x.i) FILTER (WHERE x.what = 'key'), ', ') END AS shown
    FROM rowset r JOIN followed f USING (branch)
    LEFT JOIN vals x ON x.side = r.side AND x.branch = r.branch AND x.rn = r.rn
    GROUP BY r.side, r.branch, r.rn, f.dated, f.keyed),
  missing AS (
    SELECT s.branch, s.period, s.shown FROM (SELECT * FROM per_row WHERE side = 'source' AND key IS NOT NULL) s
    ANTI JOIN (SELECT * FROM per_row WHERE side = 'target') t ON t.branch = s.branch AND t.key = s.key),
  missed AS (
    SELECT branch, period, count(*) AS rows, count(DISTINCT shown) AS keys, list(DISTINCT shown ORDER BY shown)[1:10] AS shown
    FROM missing GROUP BY ALL),
  counted AS (
    SELECT branch, period, count(*) FILTER (WHERE side = 'source') AS source_rows, count(*) FILTER (WHERE side = 'target') AS target_rows
    FROM per_row GROUP BY ALL),
  sums AS (
    SELECT p.side, p.branch, p.period, x.col, sum(try_cast(x.val AS DOUBLE)) AS total
    FROM per_row p JOIN vals x ON x.side = p.side AND x.branch = p.branch AND x.rn = p.rn AND x.what = 'measure' GROUP BY ALL),
  out AS (
    SELECT f.system, c.branch, f.table_name, c.period, c.source_rows, c.target_rows,
           greatest(c.source_rows - c.target_rows, coalesce(m.rows, 0), 0) AS missing_rows,
           CASE WHEN f.keyed THEN coalesce(m.keys, 0) END AS missing_key_count,
           CASE WHEN f.keyed THEN coalesce(m.shown, []) END AS missing_keys,
           (SELECT list({'column': x.col, 'source': s.total, 'target': coalesce(t.total, 0.0)} ORDER BY x.pos)
            FROM measures x
            LEFT JOIN sums s ON s.side = 'source' AND s.branch = c.branch AND s.period IS NOT DISTINCT FROM c.period AND s.col = x.col
            LEFT JOIN sums t ON t.side = 'target' AND t.branch = c.branch AND t.period IS NOT DISTINCT FROM c.period AND t.col = x.col) AS measures
    FROM counted c JOIN followed f USING (branch)
    LEFT JOIN missed m ON m.branch = c.branch AND m.period IS NOT DISTINCT FROM c.period),
  -- what is not reconciled, and why
  notes AS (
    SELECT 1 AS o, 'no grain is stated on ' || $subject || ': the missing keys are not listed; state it, '
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
    SELECT 4, f.system || ': ' || string_agg(k.col, ', ' ORDER BY k.i) || CASE WHEN count(*) = 1 THEN ' is' ELSE ' are' END || ' not copied from a column of ' || f.table_name || ': its missing keys are not listed'
    FROM followed f, key k WHERE NOT f.keyed AND k.col NOT IN (SELECT col FROM copies c WHERE c.branch = f.branch) GROUP BY f.system, f.table_name
    UNION ALL
    SELECT 5, f.system || ': ' || p.col || ' is not copied from a column of ' || f.table_name || ': its rows are counted over every period'
    FROM followed f, period p WHERE NOT f.dated
    UNION ALL
    SELECT 6, f.system || ': ' || x.col || ' is not copied from a column of ' || f.table_name || ': it has no sum at the source'
    FROM followed f, measures x WHERE x.col NOT IN (SELECT col FROM copies c WHERE c.branch = f.branch)),
  state AS (
    SELECT (SELECT bool_or(c.derivation IS NOT NULL) FROM d, unnest(d.columns) t(c)) IS TRUE AS plans,
           EXISTS (SELECT 1 FROM followed) AS rows_read, (SELECT sorted FROM sorted) AS sorted,
           (SELECT sum(missing_rows) FROM out) AS missing_rows, (SELECT sum(source_rows) FROM out) AS source_rows,
           (SELECT redefine_statement(view) FROM d) AS redefine),
  rate AS (
    SELECT CASE WHEN plans AND rows_read AND sorted THEN least(1.0, coalesce(missing_rows, 0) / greatest(coalesce(source_rows, 0), 1)::DOUBLE) END AS rate
    FROM state),
  -- the statement that lists the source rows whose key the view does not serve, per source table
  listing AS (
    SELECT string_agg('SELECT * FROM ' || split_part($subject, '.', 1) || '.' || t.table_name || ' WHERE '
                      || (SELECT CASE WHEN count(*) = 1 THEN any_value(c) ELSE 'concat_ws('', '', ' || string_agg(c, ', ' ORDER BY i) || ')' END
                          FROM (SELECT k.i, 'CAST(' || CASE WHEN regexp_full_match(c.source_column, '[a-z_][a-z0-9_]*') THEN c.source_column
                                                            ELSE '"' || replace(c.source_column, '"', '""') || '"' END || ' AS VARCHAR)' AS c
                                FROM key k JOIN copies c ON c.col = k.col AND c.branch = t.branch))
                      || ' IN (' ||(SELECT string_agg('''' || replace(s, '''', '''''') || '''', ', ' ORDER BY s) FROM unnest(t.keys) u(s)) || ');',
                      chr(10) ORDER BY t.system) AS statements
    FROM (SELECT o.system, o.branch, o.table_name, list(DISTINCT k ORDER BY k)[1:10] AS keys
          FROM out o, unnest(o.missing_keys) u(k) GROUP BY ALL) t)
  SELECT state.plans AND state.rows_read AND state.sorted AS applicable,
         CASE WHEN NOT state.plans THEN 'its definition does not plan'
              WHEN NOT state.rows_read THEN 'no branch of the view reads one source table its rows come from'
              WHEN NOT state.sorted THEN 'no column of the view names the system each row comes from' END AS reason,
         rate.rate AS breach_rate,
         (SELECT col FROM period) AS period_column, (SELECT col FROM system_column) AS system_column,
         (SELECT list(col ORDER BY i) FROM key) AS key,
         CASE WHEN state.sorted THEN (SELECT list({'system': system, 'branch': branch, 'table': table_name, 'period': period,
                                                  'source_rows': source_rows, 'target_rows': target_rows, 'missing_rows': missing_rows,
                                                  'missing_keys': missing_keys, 'missing_key_count': missing_key_count, 'measures': measures}
                                                 ORDER BY system, period, branch) FROM out) END AS rows,
         (SELECT list(note ORDER BY o, note) FROM notes) AS notes,
         CASE WHEN rate.rate > 0
              THEN split_part($subject, '.', 2) || ' does not serve every source row: '
                   || (SELECT string_agg(system || ' ' || missing || ' of ' || source || CASE WHEN source = 1 THEN ' row' ELSE ' rows' END
                                         || coalesce(' (' || periods || ')', '') || coalesce(', keys ' || keys, ''), '; ' ORDER BY system)
                       FROM (SELECT system, sum(missing_rows) AS missing, sum(source_rows) AS source,
                                    string_agg(CASE WHEN missing_rows > 0 AND period IS NOT NULL
                                                    THEN period || ': ' || target_rows || ' of ' || source_rows END, ', ' ORDER BY period) AS periods,
                                    nullif(array_to_string(list_sort(flatten(list(missing_keys)))[1:10], ', '), '') AS keys
                             FROM out GROUP BY system HAVING sum(missing_rows) > 0))
              WHEN NOT state.sorted THEN 'no column of ' || split_part($subject, '.', 2) || ' names the system each row comes from' END AS finding,
         CASE WHEN rate.rate > 0 THEN concat_ws(chr(10),
                '-- the source rows whose key the view does not serve, the first ten per table:',
                (SELECT statements FROM listing),
                '-- fix the load query or the definition so that every source row arrives (a join that finds no partner, a condition), then record the definition again:',
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
