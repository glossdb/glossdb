-- The lineage graph's nodes, in the direction the data flows: every
-- source a load query reads, every loaded table, every view. A source
-- is one row with no column. A table and a view are one row per
-- column. `sub` is the line under the node's name: where a source is,
-- a table's newest load, a view's kind. `link` opens the node's page.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
recipe AS (
  SELECT r.table_name, r.source
  FROM recipes r JOIN d ON d.dataset = r.dataset
  QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.seq DESC) = 1),
src AS (
  SELECT s.name, json_extract_string(s.settings, '$.type') AS type
  FROM sources s
  WHERE s.name IN (SELECT source FROM recipe)
  QUALIFY row_number() OVER (PARTITION BY s.name ORDER BY s.seq DESC) = 1),
load AS (
  SELECT i.table_name, i.rows, i.imported_at
  FROM imports i JOIN d ON d.dataset = i.dataset
  QUALIFY row_number() OVER (PARTITION BY i.table_name ORDER BY i.seq DESC) = 1),
cols AS (
  SELECT c.table_name AS node, 'table' AS kind, c.column_name AS col,
         CAST(c.ordinal_position AS BIGINT) AS ord,
         fmt_number(l.rows) || ' rows · loaded ' || strftime(l.imported_at, '%Y-%m-%d') AS sub,
         (SELECT b FROM base) || 'glossary?table=' || c.table_name AS link
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN load l ON l.table_name = c.table_name
  WHERE c.table_catalog = current_database()),
defs AS (SELECT name, kind FROM view_definitions),
fields AS (
  SELECT s.view AS node, 'view' AS kind, s.field AS col,
         CAST(row_number() OVER (PARTITION BY s.view ORDER BY s.field) AS BIGINT) AS ord,
         CASE v.kind WHEN 'relation' THEN 'table' WHEN 'scalar' THEN 'single value'
                     WHEN 'plan' THEN 'plan' ELSE 'metric' END AS sub,
         (SELECT b FROM base) || 'views?view=' || s.view AS link
  FROM (SELECT DISTINCT view, field FROM view_sources() WHERE field IS NOT NULL) s
  LEFT JOIN defs v ON v.name = s.view)
SELECT name AS node, 'source' AS kind, '' AS col, CAST(0 AS BIGINT) AS ord, '' AS role,
       coalesce(type, '') AS sub, (SELECT b FROM base) || 'glossary?source=' || name AS link
FROM src
UNION ALL
SELECT node, kind, col, ord, '' AS role, sub, link FROM cols
UNION ALL
SELECT node, kind, col, ord, '' AS role, sub, link FROM fields
ORDER BY kind, node, ord
