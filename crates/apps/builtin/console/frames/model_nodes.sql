-- The model: every loaded table as its entity, and every metric with
-- its time grain, one row per column. `sub` and `link` belong to the
-- node and repeat on its rows: a table's is what one row is, a
-- metric's the grain it is served at and its additivity. `detail` is
-- what the column carries: its role, a measure's additivity and unit,
-- a dimension's rank, and whether it is the table's grain or time
-- axis. A column with no detail folds under its table.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
said AS (
  SELECT subject, aspect, value FROM GLOSSARY()
  WHERE aspect IN ('role', 'behavior', 'unit', 'dimension', 'entity') AND value IS NOT NULL),
landed AS (SELECT DISTINCT i.table_name FROM imports i JOIN d ON d.dataset = i.dataset),
ent AS (
  SELECT substr(s.subject, len(d.dataset) + 2) AS tbl,
         json_extract_string(s.value, '$.value') AS what,
         json_extract_string(s.value, '$.time_axis') AS time_axis,
         coalesce(from_json(json_extract(s.value, '$.grain'), '["VARCHAR"]'), []) AS grain
  FROM said s CROSS JOIN d
  WHERE s.aspect = 'entity'),
colsaid AS (
  SELECT subject,
         max(CASE WHEN aspect = 'role' THEN json_extract_string(value, '$.value') END) AS role,
         max(CASE WHEN aspect = 'behavior' THEN json_extract_string(value, '$.value') END) AS behavior,
         max(CASE WHEN aspect = 'unit' THEN json_extract_string(value, '$.value') END) AS unit,
         max(CASE WHEN aspect = 'dimension' THEN json_extract_string(value, '$.value') END) AS dimension
  FROM said
  WHERE aspect <> 'entity'
  GROUP BY subject),
cols AS (
  SELECT c.table_name AS node, 'table' AS kind, c.column_name AS col,
         CAST(c.ordinal_position AS BIGINT) AS ord,
         coalesce(cs.role, '') AS role,
         concat_ws(' · ',
           nullif(cs.role, ''),
           CASE WHEN cs.role = 'measure' THEN nullif(cs.behavior, 'none') END,
           CASE WHEN cs.role = 'measure' THEN cs.unit END,
           CASE WHEN cs.role = 'dimension' THEN nullif(cs.dimension, 'none') END,
           CASE WHEN list_contains(e.grain, c.column_name) THEN 'grain' END,
           CASE WHEN e.time_axis = c.column_name THEN 'time axis' END) AS detail,
         coalesce(e.what, '') AS sub,
         (SELECT b FROM base) || 'glossary?table=' || c.table_name AS link
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN landed l ON l.table_name = c.table_name
  LEFT JOIN colsaid cs ON cs.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN ent e ON e.tbl = c.table_name
  WHERE c.table_catalog = current_database()),
axes AS (
  SELECT metric, "floor" AS grain, behavior FROM metric_axes()),
-- a served field's role: the view's own column's where one holds, else
-- the column's it descends from
fields AS (
  SELECT s.metric AS node, 'metric' AS kind, s.field AS col,
         min(CAST(s.ord AS BIGINT)) AS ord,
         coalesce(max(own.role), max(r.role), '') AS role
  FROM (SELECT metric, field, source, row_number() OVER (PARTITION BY metric ORDER BY field) AS ord
        FROM metric_sources() WHERE field IS NOT NULL) s
  CROSS JOIN d
  LEFT JOIN colsaid own ON own.subject = d.dataset || '.' || s.metric || '.' || s.field
  LEFT JOIN colsaid r ON r.subject = d.dataset || '.' || s.source
  GROUP BY s.metric, s.field)
SELECT node, kind, col, ord, role, detail, sub, link FROM cols
UNION ALL
SELECT f.node, f.kind, f.col, f.ord, f.role, f.role AS detail,
       concat_ws(' · ', 'by ' || a.grain, nullif(a.behavior, 'none')) AS sub,
       (SELECT b FROM base) || 'metrics?metric=' || f.node AS link
FROM fields f
LEFT JOIN axes a ON a.metric = f.node
ORDER BY kind, node, ord
