-- Step 2b: a test's result and a view's lineage stored like any result.
-- The catalog beside a DuckLake lake. A write takes the lake's next snapshot
-- id (store.py: write); rows are ended, never deleted. Builds on the
-- snapshot-as-version spike's schema: same nodes, same check.
CREATE TABLE IF NOT EXISTS g_annotation (begin_snapshot BIGINT, end_snapshot BIGINT, dataset VARCHAR,
  asset VARCHAR, property VARCHAR, actor VARCHAR, body VARCHAR);
-- a view's definition (reads: the relations and columns its SQL names, joins: 'a.x=b.y');
-- in a bench without a lake, a table's and a column's rows too (relation: the table a column is of)
CREATE TABLE IF NOT EXISTS g_definition (begin_snapshot BIGINT, end_snapshot BIGINT, dataset VARCHAR,
  asset VARCHAR, kind VARCHAR, relation VARCHAR, body VARCHAR, reads VARCHAR[], joins VARCHAR[]);
CREATE TABLE IF NOT EXISTS g_relationship (begin_snapshot BIGINT, end_snapshot BIGINT, dataset VARCHAR,
  from_asset VARCHAR, to_asset VARCHAR);
-- a function (body: returns, subjects SQL, detector SQL), a test (body: property, detector,
-- threshold), a property (body: x-kind), anything a kit declares
CREATE TABLE IF NOT EXISTS g_declaration (begin_snapshot BIGINT, end_snapshot BIGINT, asset VARCHAR,
  kind VARCHAR, body VARCHAR);
-- a stored result: of a function, of a test (function = the test's name), of a view's lineage
-- (function = 'lineage'). id: one write may store many results
CREATE TABLE IF NOT EXISTS g_result (id BIGINT, begin_snapshot BIGINT, end_snapshot BIGINT, dataset VARCHAR,
  function VARCHAR, subject VARCHAR, value VARCHAR, error VARCHAR, read_at BIGINT, changed_at BIGINT);
CREATE TABLE IF NOT EXISTS g_read (result BIGINT, asset VARCHAR, what VARCHAR);
-- the lineage edges a result holds: current while its result is
CREATE TABLE IF NOT EXISTS g_edge (result BIGINT, src VARCHAR, dst VARCHAR, kind VARCHAR);

-- @lake: a table's data and definition from the lake (replaced in the bench)
CREATE OR REPLACE VIEW g_lake_changed AS
WITH t AS (SELECT s.schema_name AS dataset, s.schema_name || '.' || t.table_name AS rel, t.table_id, t.begin_snapshot, t.end_snapshot
           FROM ducklake_table t JOIN ducklake_schema s USING (schema_id)),
log AS (SELECT id, max(snapshot_id) AS at FROM (
    SELECT snapshot_id, unnest(map_values(changes)) AS ids, unnest(map_keys(changes)) AS k
    FROM ducklake_snapshots('lake')), unnest(ids) u(id)
  WHERE k IN ('tables_inserted_into', 'tables_deleted_from', 'inlined_insert', 'inlined_delete') GROUP BY id)
SELECT t.dataset, t.rel AS asset, 'data' AS what, max(greatest(t.begin_snapshot, coalesce(t.end_snapshot, 0), coalesce(l.at, 0))) AS changed_at
FROM t LEFT JOIN log l ON l.id = t.table_id::VARCHAR GROUP BY ALL
UNION ALL  -- a table's definition: its row and its columns' rows
SELECT t.dataset, t.rel, 'definition', max(greatest(t.begin_snapshot, coalesce(t.end_snapshot, 0), c.begin_snapshot, coalesce(c.end_snapshot, 0)))
FROM t JOIN ducklake_column c USING (table_id) GROUP BY ALL
UNION ALL  -- a column's definition: its rows (retyped, dropped)
SELECT t.dataset, t.rel || '.' || c.column_name, 'definition', max(greatest(c.begin_snapshot, coalesce(c.end_snapshot, 0)))
FROM t JOIN ducklake_column c USING (table_id) GROUP BY ALL;
-- the columns of the lake's tables as they are now
CREATE OR REPLACE VIEW g_columns AS
SELECT s.schema_name AS dataset, s.schema_name || '.' || t.table_name || '.' || c.column_name AS asset,
       s.schema_name || '.' || t.table_name AS relation, c.column_type AS type
FROM ducklake_table t JOIN ducklake_schema s USING (schema_id) JOIN ducklake_column c USING (table_id)
WHERE t.end_snapshot IS NULL AND c.end_snapshot IS NULL;
-- @end

-- When each definition last changed: a view's, a column's (retyped, dropped), a table's (its
-- row and its columns' rows); from the lake, or from g_definition where there is none
CREATE OR REPLACE VIEW g_def_changed AS
SELECT dataset, asset AS node, max(greatest(begin_snapshot, coalesce(end_snapshot, 0))) AS changed_at
FROM g_definition WHERE kind IN ('view', 'column') GROUP BY ALL
UNION ALL SELECT dataset, relation, max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_definition WHERE kind IN ('table', 'column') GROUP BY ALL
UNION ALL SELECT dataset, asset, changed_at FROM g_lake_changed WHERE what = 'definition';

-- When each node last changed: the latest begin or end of its rows
CREATE OR REPLACE VIEW g_changed AS
SELECT asset, 'annotation ' || property AS what, max(greatest(begin_snapshot, coalesce(end_snapshot, 0))) AS changed_at
FROM g_annotation GROUP BY ALL
UNION ALL SELECT node, 'definition', changed_at FROM g_def_changed
UNION ALL SELECT a, 'relationships', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_relationship, unnest([from_asset, to_asset]) u(a) GROUP BY ALL
UNION ALL SELECT asset, 'declaration', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_declaration GROUP BY ALL
UNION ALL SELECT subject, 'result ' || function,
       coalesce(max(changed_at) FILTER (WHERE end_snapshot IS NULL), max(end_snapshot))
FROM g_result GROUP BY ALL
UNION ALL SELECT asset, what, changed_at FROM g_lake_changed WHERE what = 'data';

-- The node an annotation's stale mark and a test's result read for its subject: a table
-- column's own definition, else its relation's (a view's column: the view's definition)
CREATE OR REPLACE MACRO g_def_node(a) AS
  CASE WHEN len(string_split(a, '.')) < 2 THEN NULL
       WHEN len(string_split(a, '.')) >= 3 AND a IN (SELECT asset FROM g_columns) THEN a
       ELSE split_part(a, '.', 1) || '.' || split_part(a, '.', 2) END;

-- The check, for every current result (unchanged from the snapshot-as-version spike)
CREATE OR REPLACE VIEW g_check AS
WITH RECURSIVE cur AS (SELECT * FROM g_result WHERE end_snapshot IS NULL),
direct AS (
  SELECT r.id AS result, e.asset || ' ' || e.what || ' @' || n.changed_at AS node
  FROM cur r JOIN g_read e ON e.result = r.id
  JOIN g_changed n ON n.asset = e.asset AND n.what = e.what
  WHERE n.changed_at > r.read_at),
up(result) AS (
  SELECT result FROM direct
  UNION
  SELECT r.id FROM up JOIN cur q ON q.id = up.result
  JOIN g_read e ON e.asset = q.subject AND e.what = 'result ' || q.function
  JOIN cur r ON r.id = e.result),
gone AS (SELECT asset FROM g_declaration WHERE kind IN ('function', 'test')
         EXCEPT SELECT asset FROM g_declaration WHERE kind IN ('function', 'test') AND end_snapshot IS NULL)
SELECT r.id, r.dataset, r.function, r.subject, r.read_at, r.changed_at,
       CASE WHEN r.function IN (SELECT asset FROM gone) THEN 'not declared'
            WHEN r.id IN (SELECT result FROM direct) THEN 'out of date'
            WHEN r.id IN (SELECT result FROM up) THEN 'possibly out of date'
            ELSE 'current' END AS state,
       (SELECT list(node ORDER BY node) FROM direct d WHERE d.result = r.id) AS changed
FROM cur r;

-- The lineage of a dataset: what the catalog holds (contains) and the edges the current
-- results hold (a view's reads and joins, a kit's edges). A read over rows
CREATE OR REPLACE MACRO g_lineage(ds) AS TABLE
SELECT relation AS src, asset AS dst, 'contains' AS kind FROM g_definition
WHERE dataset = ds AND kind = 'column' AND end_snapshot IS NULL
UNION ALL SELECT e.src, e.dst, e.kind FROM g_edge e JOIN g_result r ON r.id = e.result
WHERE r.end_snapshot IS NULL AND r.dataset = ds;

-- The values of a property: each actor's current annotation and the current result of each
-- function that returns it. What a detector reads as `annotations`
CREATE OR REPLACE MACRO g_values(p) AS TABLE
SELECT dataset, asset AS subject, property AS aspect, actor AS actor_kind, body::JSON AS body, begin_snapshot
FROM g_annotation WHERE property = p AND end_snapshot IS NULL
UNION ALL SELECT r.dataset, r.subject, p, 'function', r.value::JSON, r.begin_snapshot FROM g_result r
WHERE r.end_snapshot IS NULL AND r.error IS NULL AND r.function IN (SELECT asset FROM g_declaration
  WHERE kind = 'function' AND end_snapshot IS NULL AND body::JSON->>'returns' = p);

-- After a write: the nodes with a row begun or ended after `since`, and the results that read
-- one of them before it changed (out of date) or read such a result (possibly out of date)
CREATE OR REPLACE MACRO g_changed_since(since) AS TABLE
SELECT asset, 'annotation ' || property AS what, max(greatest(begin_snapshot, coalesce(end_snapshot, 0))) AS changed_at
FROM g_annotation WHERE begin_snapshot > since OR end_snapshot > since GROUP BY ALL
UNION ALL SELECT node, 'definition', changed_at FROM g_def_changed WHERE changed_at > since
UNION ALL SELECT a, 'relationships', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_relationship, unnest([from_asset, to_asset]) u(a) WHERE begin_snapshot > since OR end_snapshot > since GROUP BY ALL
UNION ALL SELECT asset, 'declaration', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_declaration WHERE begin_snapshot > since OR end_snapshot > since GROUP BY ALL
UNION ALL SELECT kind, 'declarations', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_declaration WHERE begin_snapshot > since OR end_snapshot > since GROUP BY ALL
UNION ALL SELECT subject, 'result ' || function, max(changed_at) FROM g_result
WHERE end_snapshot IS NULL AND changed_at > since GROUP BY ALL
UNION ALL SELECT subject, 'result ' || function, max(end_snapshot) FROM g_result r
WHERE end_snapshot > since AND NOT EXISTS (SELECT 1 FROM g_result n WHERE n.end_snapshot IS NULL
  AND n.function = r.function AND n.subject = r.subject) GROUP BY ALL
UNION ALL SELECT asset, what, changed_at FROM g_lake_changed WHERE what = 'data' AND changed_at > since;

CREATE OR REPLACE MACRO g_after(since) AS TABLE
WITH RECURSIVE cur AS (SELECT * FROM g_result WHERE end_snapshot IS NULL),
direct AS (SELECT DISTINCT r.id FROM g_changed_since(since) n JOIN g_read e ON e.asset = n.asset AND e.what = n.what
           JOIN cur r ON r.id = e.result WHERE n.changed_at > r.read_at),
up(id) AS (SELECT id FROM direct UNION
           SELECT r.id FROM up JOIN cur q ON q.id = up.id JOIN g_read e ON e.asset = q.subject
           AND e.what = 'result ' || q.function JOIN cur r ON r.id = e.result)
SELECT id, CASE WHEN id IN (SELECT id FROM direct) THEN 'out of date' ELSE 'possibly out of date' END AS state FROM up;
