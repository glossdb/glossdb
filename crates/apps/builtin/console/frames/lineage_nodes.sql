-- The lineage graph's nodes: one row per column of every loaded table
-- of the bound dataset, in ordinal order, with the column's judged role
-- — and one row per served field of every current metric definition, the
-- metric by its name and the field's role taken from the column
-- it descends from.
WITH d AS (SELECT dataset FROM current_dataset),
roles AS (
  SELECT subject, json_extract_string(value, '$.value') AS role
  FROM GLOSSARY() WHERE aspect = 'role' AND value IS NOT NULL),
landed AS (SELECT DISTINCT i.table_name FROM imports i JOIN d ON d.dataset = i.dataset),
cols AS (
  SELECT c.table_name AS node, 'table' AS kind, c.column_name AS col,
         CAST(c.ordinal_position AS BIGINT) AS ord, coalesce(r.role, '') AS role
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN landed l ON l.table_name = c.table_name
  LEFT JOIN roles r ON r.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  WHERE c.table_catalog = current_database()),
-- a served field's role: the view's own column's where one holds, else
-- the column's it descends from
fields AS (
  SELECT s.metric AS node, 'metric' AS kind, s.field AS col,
         min(CAST(s.ord AS BIGINT)) AS ord, coalesce(max(own.role), max(r.role), '') AS role
  FROM (SELECT metric, field, source, row_number() OVER (PARTITION BY metric ORDER BY field) AS ord
        FROM metric_sources() WHERE field IS NOT NULL) s
  CROSS JOIN d
  LEFT JOIN roles own ON own.subject = d.dataset || '.' || s.metric || '.' || s.field
  LEFT JOIN roles r ON r.subject = d.dataset || '.' || s.source
  GROUP BY s.metric, s.field)
SELECT node, kind, col, ord, role FROM cols
UNION ALL
SELECT node, kind, col, ord, role FROM fields
ORDER BY kind, node, ord
