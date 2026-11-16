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
-- reconciliation: per system and period, did every row the target reads
-- from a system arrive, and if not, which rows and why. Per branch of the
-- view's union (branch_rows(), the extension's read of each branch as its
-- own steps leave the rows), the table that drives it: the one whose rows
-- the branch keeps, the first of its FROM (a RIGHT JOIN's right side),
-- followed into a subquery or a CTE. Its system is its system_of_record,
-- else its load's source. Per branch and period (the view's time column:
-- the entity's time_axis, else its column with role timestamp; a date
-- truncated to its time grain, a month where none is stated), where the
-- branch computes the period from the driving table alone; one row per
-- branch where it does not, or where the view has no time column:
--   read        rows of the driving table
--   filtered    rows a condition of the branch leaves out, per condition
--   unmatched   rows an inner join finds no partner for, per join, with
--               the relationship the join follows and its orphan keys
--               (relationship_coherence: the keys of the whole table,
--               each with its rows, and how many there are); no keys
--               where no declared relationship covers the join
--   repeated    rows a join adds: more partners than rows
--   reached     rows the branch serves
--   vanished    read - filtered - unmatched + repeated - reached, on a
--               branch whose steps are told; NULL on one that is not, and
--               on a branch that reads no table (a constant row)
--   told        false where the branch has a step the read does not
--               follow (a GROUP BY, a DISTINCT, a LIMIT, a join of
--               another kind): its rows read are the driving table's,
--               and not_told names the step
--   measures    per column with role measure, the sum the target serves
--               and, where the branch computes it from the driving table
--               alone, the sum over every row read, to hold against the
--               system's own report
-- applicable is false where a branch is not told, with the step as the
-- reason; the told branches' rows are served all the same. No test judges
-- it: on a told branch the re-read and the branch's own rows agree by
-- construction (the extension's suite holds that), so a test on vanished
-- rows could not fail. What a person reads is the account. The server
-- computes it after a write on each view with a contract (x-set-by), as
-- results_due() does for a result no test reads.
--===------------------------------------------------------------------===--

DECLARE ASPECT reconciliation WITH $${
  "description": "Preview. Per source system and period, the rows a target view reads, the rows its conditions and joins leave out and why, the rows it serves, and the sums of its measures.",
  "type": "object", "x-subject": "view", "x-set-by": "contract",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "period_column": {"type": ["string", "null"]},
                 "rows": {"type": ["array", "null"], "items": {"type": "object"}}}
}$$ AS MEASUREMENT ON TABLE;

-- reconciliation_period(value, grain): a period as text, a date or a
-- timestamp truncated to the grain (a month where none is stated)
CREATE OR REPLACE MACRO main.reconciliation_period(v, grain) AS
  CASE WHEN v[5] = '-' AND v[8] = '-' AND try_cast(v AS TIMESTAMP) IS NOT NULL
       THEN CASE WHEN coalesce(grain, 'month') IN ('minute', 'hour')
                 THEN strftime(date_trunc(grain, try_cast(v AS TIMESTAMP)), '%Y-%m-%d %H:%M')
                 ELSE strftime(date_trunc(coalesce(grain, 'month'), try_cast(v AS TIMESTAMP)), '%Y-%m-%d') END
       ELSE v END;

DECLARE FUNCTION reconciliation FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  cols AS (SELECT c.name AS col, c.position AS pos FROM d, unnest(d.columns) t(c)),
  roles AS (
    SELECT substr(asset, length($subject) + 2) AS col, value->>'value' AS role FROM annotations('role', 'its columns')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  axis AS (
    SELECT value->>'time_axis' AS col FROM annotations('entity', 'itself')
    WHERE value IS NOT NULL AND state IN ('current', 'stale') AND value->>'time_axis' IS NOT NULL),
  grains AS (
    SELECT substr(asset, length($subject) + 2) AS col, value->>'floor' AS floor FROM annotations('time_grains', 'its columns')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  period AS (
    SELECT c.col, c.pos, (SELECT max(g.floor) FROM grains g WHERE g.col = c.col) AS floor FROM cols c
    WHERE c.col = coalesce((SELECT max(col) FROM axis),
                           (SELECT arg_min(r.col, x.pos) FROM roles r JOIN cols x USING (col) WHERE r.role = 'timestamp'))),
  measures AS (SELECT c.col, c.pos FROM roles r JOIN cols c USING (col) WHERE r.role = 'measure'),
  rows_ AS NOT MATERIALIZED (SELECT * FROM branch_rows($subject)),
  branches AS (
    SELECT branch, dataset || '.' || table_name AS table_path, table_name, text AS untold, columns AS alone,
           coalesce(list_contains(columns, (SELECT col FROM period)), false) AS dated
    FROM rows_ WHERE kind = 'branch'),
  steps AS (SELECT branch, step, what AS kind, text, columns FROM rows_ WHERE kind = 'step'),
  -- each row read and each row served, with the view's time column as the branch computes it and the
  -- amount of each measure; the period counts where the branch computes it from its driving table alone
  marked AS MATERIALIZED (
    SELECT r.branch, r.kind = 'read' AS is_read, r.rid, r.step,
           main.reconciliation_period(r."values"[k.period_pos], k.floor) AS period,
           list_transform(k.measure_pos, lambda x: try_cast(r."values"[x] AS DOUBLE)) AS amounts
    FROM rows_ r,
         (SELECT (SELECT max(pos) FROM period) AS period_pos, (SELECT max(floor) FROM period) AS floor,
                 coalesce((SELECT list(pos ORDER BY pos) FROM measures), []) AS measure_pos) k
    WHERE r.kind IN ('read', 'served')),
  -- per row read: its partners, those that reach the target, and its amounts once. The driving rows are
  -- numbered 1 to n, so a branch whose partners number n has one partner per row and needs no grouping
  fanned AS (SELECT branch FROM marked WHERE is_read GROUP BY branch HAVING count(*) > max(rid)),
  per_row AS MATERIALIZED (
    SELECT branch, rid, period, 1 AS partners, CASE WHEN step IS NULL THEN 1 ELSE 0 END AS kept, amounts
    FROM marked WHERE is_read AND branch NOT IN (SELECT branch FROM fanned)
    UNION ALL
    SELECT branch, rid, any_value(period), count(*), count(*) FILTER (WHERE step IS NULL), any_value(amounts)
    FROM marked WHERE is_read AND branch IN (SELECT branch FROM fanned) GROUP BY branch, rid),
  counted AS (
    SELECT coalesce(r.branch, s.branch) AS branch, coalesce(r.period, s.period) AS period, coalesce(r.read, 0) AS read,
           coalesce(r.partners, 0) AS partners, coalesce(r.kept, 0) AS kept, coalesce(s.reached, 0) AS reached
    FROM (SELECT p.branch, CASE WHEN b.dated THEN p.period END AS period, count(*) AS read, sum(p.partners) AS partners,
                 sum(p.kept) AS kept
          FROM per_row p JOIN branches b USING (branch) GROUP BY ALL) r
    FULL JOIN (SELECT m.branch, CASE WHEN b.dated THEN m.period END AS period, count(*) AS reached
               FROM marked m JOIN branches b USING (branch) WHERE NOT m.is_read GROUP BY ALL) s
      ON s.branch = r.branch AND s.period IS NOT DISTINCT FROM r.period),
  dropped AS (
    SELECT m.branch, CASE WHEN b.dated THEN m.period END AS period, m.step, count(*) AS n
    FROM marked m JOIN branches b USING (branch) WHERE m.is_read AND m.step IS NOT NULL GROUP BY ALL),
  numbered AS (SELECT col, pos, row_number() OVER (ORDER BY pos) AS i FROM measures),
  served_sums AS (
    SELECT m.branch, CASE WHEN b.dated THEN m.period END AS period, x.col, sum(m.amounts[x.i]) AS total
    FROM marked m JOIN branches b USING (branch), numbered x WHERE NOT m.is_read GROUP BY ALL),
  read_sums AS (
    SELECT p.branch, CASE WHEN b.dated THEN p.period END AS period, x.col, sum(p.amounts[x.i]) AS total
    FROM per_row p JOIN branches b USING (branch), numbered x WHERE list_contains(b.alone, x.col) GROUP BY ALL),
  -- the system of each table the view reads: its system_of_record, else its load's source
  records AS (
    SELECT asset, value->>'value' AS system FROM annotations('system_of_record', 'its sources')
    WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  systems AS (
    SELECT r.table_name, coalesce(o.system, r.source) AS system
    FROM d, unnest(d.reads) t(r) LEFT JOIN records o ON o.asset = r.table_name),
  -- the relationship a join follows: each of its columns among those the join equates, the one with
  -- the most columns where several are (a key of several columns over one of its columns)
  coherence AS (
    SELECT c.asset AS relationship, any_value(c.value) AS value,
           list(regexp_extract(e.side, '^([^.]+\.[^.]+)\.', 1) || '.' || trim(k.name)) AS endpoints
    FROM results('relationship_coherence', 'its relationships') c,
         unnest(regexp_split_to_array(c.asset, ' <?-> ')) e(side),
         unnest(string_split(trim(regexp_replace(e.side, '^[^.]+\.[^.]+\.', ''), '()'), ',')) k(name)
    WHERE c.value IS NOT NULL GROUP BY c.asset),
  followed AS (
    SELECT s.branch, s.step, c.relationship, c.value->'orphan_keys' AS keys, (c.value->>'orphan_distinct')::BIGINT AS distinct_keys
    FROM steps s JOIN coherence c ON s.kind = 'join' AND list_has_all(s.columns, c.endpoints)
    QUALIFY row_number() OVER (PARTITION BY s.branch, s.step ORDER BY len(c.endpoints) DESC, c.relationship) = 1),
  out AS (
    SELECT y.system, c.branch, b.table_name, c.period, c.read,
           coalesce((SELECT list({'condition': s.text, 'rows': x.n} ORDER BY s.step) FROM dropped x JOIN steps s USING (branch, step)
                     WHERE x.branch = c.branch AND x.period IS NOT DISTINCT FROM c.period AND s.kind = 'condition'), []) AS filtered,
           coalesce((SELECT list({'join': s.text, 'rows': x.n, 'relationship': f.relationship,
                                  'keys': from_json(f.keys, '[{"key": "VARCHAR", "rows": "BIGINT"}]'), 'distinct_keys': f.distinct_keys} ORDER BY s.step)
                     FROM dropped x JOIN steps s USING (branch, step) LEFT JOIN followed f USING (branch, step)
                     WHERE x.branch = c.branch AND x.period IS NOT DISTINCT FROM c.period AND s.kind = 'join'), []) AS unmatched,
           c.partners - c.read AS repeated, c.reached, CASE WHEN b.untold IS NULL AND b.table_name IS NOT NULL THEN c.kept - c.reached END AS vanished,
           b.untold IS NULL AS told, b.untold AS not_told,
           (SELECT list({'column': x.col, 'target': coalesce(t.total, 0.0), 'source': r.total} ORDER BY x.pos)
            FROM measures x LEFT JOIN served_sums t ON t.branch = c.branch AND t.period IS NOT DISTINCT FROM c.period AND t.col = x.col
            LEFT JOIN read_sums r ON r.branch = c.branch AND r.period IS NOT DISTINCT FROM c.period AND r.col = x.col) AS measures
    FROM counted c JOIN branches b USING (branch) LEFT JOIN systems y ON y.table_name = b.table_path),
  state AS (
    SELECT EXISTS (SELECT 1 FROM out) AS rows_read,
           (SELECT string_agg(DISTINCT 'branch ' || branch || ' (' || coalesce(system, table_name, 'no table') || '): ' || not_told, '; ')
            FROM out WHERE NOT told) AS untold,
           (SELECT bool_or(c.derivation IS NOT NULL) FROM d, unnest(d.columns) t(c)) IS TRUE AS plans)
  SELECT state.rows_read AND state.untold IS NULL AS applicable,
         CASE WHEN NOT state.plans THEN 'its definition does not plan'
              WHEN NOT state.rows_read THEN 'the view reads no loaded table'
              WHEN state.untold IS NOT NULL THEN 'a step the reconciliation does not follow: ' || state.untold END AS reason,
         (SELECT col FROM period) AS period_column,
         (SELECT list({'system': system, 'branch': branch, 'table': table_name, 'period': period, 'read': read,
                       'filtered': filtered, 'unmatched': unmatched, 'repeated': repeated, 'reached': reached,
                       'vanished': vanished, 'told': told, 'not_told': not_told, 'measures': measures}
                      ORDER BY system, period, branch) FROM out) AS rows
  FROM state
$$ RETURNS reconciliation;
