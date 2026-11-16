-- The catalog beside a DuckLake lake, in the lake's metadata database. A write
-- takes the lake's next snapshot id (lake.py: write); it ends the row it
-- replaces and begins a new one. Rows are never deleted.
CREATE TABLE IF NOT EXISTS g_annotation (begin_snapshot BIGINT, end_snapshot BIGINT,
  asset VARCHAR, property VARCHAR, body VARCHAR);
CREATE TABLE IF NOT EXISTS g_definition (begin_snapshot BIGINT, end_snapshot BIGINT,
  asset VARCHAR, sql VARCHAR, reads VARCHAR[]);
CREATE TABLE IF NOT EXISTS g_relationship (begin_snapshot BIGINT, end_snapshot BIGINT,
  from_asset VARCHAR, to_asset VARCHAR);
-- anything else declared, of a kind the core does not know: a function, an
-- add-on's scenario, an outside service's version as last observed
CREATE TABLE IF NOT EXISTS g_declaration (begin_snapshot BIGINT, end_snapshot BIGINT,
  asset VARCHAR, kind VARCHAR, body VARCHAR);
-- read_at: the snapshot the computation read. changed_at: the snapshot its
-- value (value, error) last changed at; a recomputation with the same value keeps it
CREATE TABLE IF NOT EXISTS g_result (begin_snapshot BIGINT, end_snapshot BIGINT,
  function VARCHAR, subject VARCHAR, value VARCHAR, error VARCHAR,
  read_at BIGINT, changed_at BIGINT);
-- one row per node a result read: (asset, what), what one of
--   'annotation <property>', 'definition', 'declaration', 'data', 'result <function>';
--   a set: 'relationships' (those that touch the asset), 'declarations' (those of the kind named by asset)
CREATE TABLE IF NOT EXISTS g_read (result BIGINT, asset VARCHAR, what VARCHAR);

-- @data: when a table's data last changed: its row's begin/end and DuckLake's change log
CREATE OR REPLACE VIEW g_data_changed AS
SELECT s.schema_name || '.' || t.table_name AS asset,
       max(greatest(t.begin_snapshot, coalesce(t.end_snapshot, 0), coalesce(c.at, 0))) AS changed_at
FROM ducklake_table t JOIN ducklake_schema s USING (schema_id)
LEFT JOIN (SELECT id, max(snapshot_id) AS at FROM (
    SELECT snapshot_id, unnest(map_values(changes)) AS ids, unnest(map_keys(changes)) AS k
    FROM ducklake_snapshots('lake')), unnest(ids) u(id)
  WHERE k IN ('tables_inserted_into', 'tables_deleted_from', 'tables_altered',
              'inlined_insert', 'inlined_delete') GROUP BY id) c
  ON c.id = t.table_id::VARCHAR
GROUP BY ALL;
-- @end

-- When each node last changed: the latest begin or end of its rows.
CREATE OR REPLACE VIEW g_changed AS
SELECT asset, 'annotation ' || property AS what,
       max(greatest(begin_snapshot, coalesce(end_snapshot, 0))) AS changed_at
FROM g_annotation GROUP BY ALL
UNION ALL
SELECT asset, 'definition', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_definition GROUP BY ALL
UNION ALL
SELECT a, 'relationships', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_relationship, unnest([from_asset, to_asset]) u(a) GROUP BY ALL
UNION ALL
SELECT asset, 'declaration', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_declaration GROUP BY ALL
UNION ALL
SELECT kind, 'declarations', max(greatest(begin_snapshot, coalesce(end_snapshot, 0)))
FROM g_declaration GROUP BY ALL
UNION ALL
SELECT subject, 'result ' || function,
       coalesce(max(changed_at) FILTER (WHERE end_snapshot IS NULL), max(end_snapshot))
FROM g_result GROUP BY ALL
UNION ALL
SELECT asset, 'data', changed_at FROM g_data_changed;

-- The check, for every current result. Out of date: a node it read changed
-- after the snapshot it read at. Possibly out of date: a result it read is out
-- of date or possibly so, and has not been computed again yet. Not declared:
-- its function was declared once and is no longer.
CREATE OR REPLACE VIEW g_check AS
WITH RECURSIVE cur AS (SELECT * FROM g_result WHERE end_snapshot IS NULL),
direct AS (
  SELECT r.begin_snapshot AS result, e.asset || ' ' || e.what || ' @' || n.changed_at AS node
  FROM cur r JOIN g_read e ON e.result = r.begin_snapshot
  JOIN g_changed n ON n.asset = e.asset AND n.what = e.what
  WHERE n.changed_at > r.read_at),
up(result) AS (
  SELECT result FROM direct
  UNION
  SELECT r.begin_snapshot FROM up JOIN cur q ON q.begin_snapshot = up.result
  JOIN g_read e ON e.asset = q.subject AND e.what = 'result ' || q.function
  JOIN cur r ON r.begin_snapshot = e.result),
gone AS (SELECT asset FROM g_declaration WHERE kind = 'function'
         EXCEPT SELECT asset FROM g_declaration WHERE kind = 'function' AND end_snapshot IS NULL)
SELECT r.function, r.subject, r.read_at, r.changed_at,
       CASE WHEN r.function IN (SELECT asset FROM gone) THEN 'not declared'
            WHEN r.begin_snapshot IN (SELECT result FROM direct) THEN 'out of date'
            WHEN r.begin_snapshot IN (SELECT result FROM up) THEN 'possibly out of date'
            ELSE 'current' END AS state,
       (SELECT list(node ORDER BY node) FROM direct d WHERE d.result = r.begin_snapshot) AS changed
FROM cur r ORDER BY r.function, r.subject;
