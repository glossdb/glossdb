-- One table's head: what one row is, its grain and time axis from the
-- entity entry (a person's over the agent's), whether it is a fact or a
-- dimension table, how many rows and columns it holds, when it last
-- loaded and from which source, and the views that read it. One row,
-- or none for a name no loaded table carries.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
d AS (SELECT dataset FROM current_dataset),
e AS (
  SELECT g.body, g.actor_kind, g.written_at
  FROM ranked_annotations g JOIN d ON d.dataset = g.dataset
  WHERE g.property = 'entity' AND g.subject = d.dataset || '.' || CAST($table AS VARCHAR) AND g.rank = 1),
latest AS (
  SELECT i.table_name, i.rows, i.imported_at,
         row_number() OVER (ORDER BY i.imported_at DESC, i.begin_snapshot DESC) AS rn
  FROM imports i JOIN d ON d.dataset = i.dataset
  WHERE i.table_name = CAST($table AS VARCHAR)),
cols AS (
  SELECT count(*) AS n FROM information_schema.columns c JOIN d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database() AND c.table_name = CAST($table AS VARCHAR)),
a AS (
  SELECT name, schema FROM properties
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
reads AS (
  SELECT string_agg(DISTINCT coalesce(json_extract_string(a.schema, '$.title'), ms.view), ', ') AS views
  FROM m ms LEFT JOIN a ON a.name = ms.view
  WHERE ms.source_table = CAST($table AS VARCHAR)),
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
       coalesce('read by ' || r.views, '') AS read_by,
       CASE WHEN e.actor_kind = 'human' THEN 'decided' ELSE '' END AS mark,
       CASE WHEN e.actor_kind = 'human' THEN 'a person''s word, ' || strftime(e.written_at, '%d %b %Y %H:%M') ELSE '' END AS mark_title
FROM latest l
CROSS JOIN cols c
CROSS JOIN reads r
CROSS JOIN src
LEFT JOIN e ON true
WHERE l.rn = 1
