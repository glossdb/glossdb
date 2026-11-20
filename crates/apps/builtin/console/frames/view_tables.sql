-- The tables a view reads, as one line: every loaded table the view's
-- lineage reaches (views_lineage()), in name order. One row, or none
-- for a metric definition that reads nothing loaded.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
t AS (
  SELECT DISTINCT source_table AS table_name FROM m
  WHERE view = $view AND source_table IS NOT NULL)
SELECT string_agg(table_name, ', ' ORDER BY table_name) AS tables
FROM t
HAVING count(*) > 0
