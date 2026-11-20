-- The lineage graph's nodes, in the direction the data flows: every
-- loaded table, then every view, one row per column. `tag` is the
-- source a table's load query reads. `sub` is the line under the
-- node's name: what one row of a table is (its newest load where
-- that is not annotated), a view's kind. `detail` is what a table's column
-- carries in the semantic model: its role, a measure's additivity and
-- unit, a dimension's rank, and whether it is part of the table's
-- grain or its time axis. `link` opens the node's page.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
recipe AS (
  SELECT r.table_name, r.source
  FROM recipes r JOIN d ON d.dataset = r.dataset
  QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.begin_snapshot DESC) = 1),
load AS (
  SELECT i.table_name, i.rows, i.imported_at
  FROM imports i JOIN d ON d.dataset = i.dataset
  QUALIFY row_number() OVER (PARTITION BY i.table_name ORDER BY i.begin_snapshot DESC) = 1),
said AS (
  SELECT subject, property, value FROM GLOSSARY()
  WHERE property IN ('role', 'additivity', 'unit', 'dimension', 'entity') AND value IS NOT NULL),
ent AS (
  SELECT substr(s.subject, len(d.dataset) + 2) AS tbl,
         json_extract_string(s.value, '$.value') AS what,
         json_extract_string(s.value, '$.time_axis') AS time_axis,
         coalesce(from_json(json_extract(s.value, '$.grain'), '["VARCHAR"]'), []) AS grain
  FROM said s CROSS JOIN d
  WHERE s.property = 'entity'),
colsaid AS (
  SELECT subject,
         max(CASE WHEN property = 'role' THEN json_extract_string(value, '$.value') END) AS role,
         max(CASE WHEN property = 'additivity' THEN json_extract_string(value, '$.value') END) AS additivity,
         max(CASE WHEN property = 'unit' THEN json_extract_string(value, '$.value') END) AS unit,
         max(CASE WHEN property = 'dimension' THEN json_extract_string(value, '$.value') END) AS dimension
  FROM said
  WHERE property <> 'entity'
  GROUP BY subject),
cols AS (
  SELECT c.table_name AS node, 'table' AS kind, c.column_name AS col,
         CAST(c.ordinal_position AS BIGINT) AS ord,
         coalesce(cs.role, '') AS role,
         concat_ws(' · ',
           nullif(cs.role, ''),
           CASE WHEN cs.role = 'measure' THEN nullif(cs.additivity, 'none') END,
           CASE WHEN cs.role = 'measure' THEN cs.unit END,
           CASE WHEN cs.role = 'dimension' THEN nullif(cs.dimension, 'none') END,
           CASE WHEN list_contains(e.grain, c.column_name) THEN 'grain' END,
           CASE WHEN e.time_axis = c.column_name THEN 'time axis' END) AS detail,
         coalesce(nullif(e.what, ''),
                  fmt_number(l.rows) || ' rows · loaded ' || strftime(l.imported_at, '%Y-%m-%d')) AS sub,
         (SELECT b FROM base) || 'glossary?table=' || c.table_name AS link,
         coalesce(r.source, '') AS tag
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN load l ON l.table_name = c.table_name
  LEFT JOIN recipe r ON r.table_name = c.table_name
  LEFT JOIN colsaid cs ON cs.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN ent e ON e.tbl = c.table_name
  WHERE c.table_catalog = current_database()),
defs AS (SELECT name, kind FROM view_definitions),
fields AS (
  SELECT s.view AS node, 'view' AS kind, s.target_column AS col,
         CAST(row_number() OVER (PARTITION BY s.view ORDER BY s.target_column) AS BIGINT) AS ord,
         CASE v.kind WHEN 'table' THEN 'table view' WHEN 'value' THEN 'single value' WHEN 'metric' THEN 'metric'
                     WHEN 'rule' THEN 'rule' ELSE 'plain view' END AS sub,
         (SELECT b FROM base) || 'views?view=' || s.view
           || CASE WHEN v.kind IN ('table', 'value') THEN '&kind=' || v.kind ELSE '' END AS link
  FROM (SELECT DISTINCT view, target_column FROM m WHERE target_column IS NOT NULL) s
  LEFT JOIN defs v ON v.name = s.view)
SELECT node, kind, col, ord, role, detail, sub, link, tag FROM cols
UNION ALL
SELECT node, kind, col, ord, '' AS role, '' AS detail, sub, link, '' AS tag FROM fields
ORDER BY kind, node, ord
