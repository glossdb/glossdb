-- The harmonise kit (preview): several systems of record mapped onto one
-- target table. The target is a table view (kind table), each of its
-- branches reading one system's loaded tables. A source table's system is
-- its `system_of_record` where the table states one, else the source its
-- load query reads (the lineage's 'loaded from' edge). The target carries
-- a contract on its columns; the server checks the rows against it after a
-- write wherever it is stated, and runs without the kit. Loaded after the
-- views kit.
--
--   FROM glossql_kit('kits/views/kit.sql');
--   FROM glossql_kit('kits/harmonise/kit.sql');

--===------------------------------------------------------------------===--
-- system_of_record, on a loaded table: the system its rows come from,
-- where that is not the source its load query reads (one source that
-- loads two filing systems).
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
-- contract_check on the view after each write (x-set-by: contract).
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
    SELECT coalesce((SELECT max(len(columns)) FROM d), 0) > 0 AS plans,
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
