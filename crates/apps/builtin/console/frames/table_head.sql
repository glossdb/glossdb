-- One table's head: what one row is, its grain and time axis from the
-- entity entry (a person's over the agent's), whether it is a fact or a
-- dimension table, how many rows and columns it holds, when it last
-- loaded and from which source, and the metrics that read it. One row,
-- or none for a name no loaded table carries.
WITH d AS (SELECT dataset FROM current_dataset),
e AS (
  SELECT g.body, g.actor_kind, g.written_at,
         row_number() OVER (ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect = 'entity' AND g.subject = d.dataset || '.' || CAST($table AS VARCHAR) AND g.actor_kind IN ('human', 'agent')),
latest AS (
  SELECT i.table_name, i.rows, i.imported_at,
         row_number() OVER (ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN d ON d.dataset = i.dataset
  WHERE i.table_name = CAST($table AS VARCHAR)),
cols AS (
  SELECT count(*) AS n FROM information_schema.columns c JOIN d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database() AND c.table_name = CAST($table AS VARCHAR)),
a AS (
  SELECT name, schema FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
reads AS (
  SELECT string_agg(DISTINCT coalesce(json_extract_string(a.schema, '$.title'), ms.metric), ', ') AS metrics
  FROM metric_sources() ms LEFT JOIN a ON a.name = ms.metric
  WHERE ms.table_name = CAST($table AS VARCHAR)),
src AS (
  SELECT max(r.source) AS source FROM recipes r JOIN d ON d.dataset = r.dataset
  WHERE r.table_name = CAST($table AS VARCHAR))
SELECT l.table_name AS name,
       coalesce(json_extract_string(e.body, '$.value'), 'no entity yet: what one row is has not been written') AS entity,
       concat_ws(' · ',
         CASE json_extract_string(e.body, '$.role') WHEN 'fact' THEN 'a fact table' WHEN 'dimension' THEN 'a dimension table' END,
         'one row per ' || array_to_string(json_extract(e.body, '$.grain')::VARCHAR[], ', '),
         'time axis ' || json_extract_string(e.body, '$.time_axis')) AS shape,
       coalesce(CAST(l.rows AS BIGINT), 0) AS rows,
       c.n AS columns,
       coalesce('the source ' || src.source, '') AS read,
       strftime(l.imported_at, '%d %b %Y %H:%M') AS "at",
       coalesce(src.source, '') AS source,
       coalesce('read by ' || r.metrics, '') AS read_by,
       CASE WHEN e.actor_kind = 'human' THEN 'ruled' ELSE '' END AS mark,
       CASE WHEN e.actor_kind = 'human' THEN 'a person''s word, ' || strftime(e.written_at, '%d %b %Y %H:%M') ELSE '' END AS mark_title
FROM latest l
CROSS JOIN cols c
CROSS JOIN reads r
CROSS JOIN src
LEFT JOIN e ON e.rn = 1
WHERE l.rn = 1
