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
-- key repeats: the rows past the first per key, the repeated keys),
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
  keyed AS (
    SELECT c.rn, list(c.val ORDER BY list_position(k.cols, c.col)) AS k, bool_or(c.val IS NULL) AS empty
    FROM cells c, key k WHERE list_contains(k.cols, c.col) GROUP BY c.rn),
  repeated AS (
    SELECT CASE WHEN len(k) = 1 THEN k[1] ELSE '(' || array_to_string(k, ', ') || ')' END AS shown, count(*) AS n
    FROM keyed WHERE NOT empty GROUP BY k HAVING count(*) > 1),
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
