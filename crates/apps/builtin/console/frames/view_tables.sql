-- The tables a view reads, as one line: every loaded table the view's
-- lineage reaches (column_mapping()), in name order. One row, or none
-- for a metric definition that reads nothing loaded.
WITH t AS (
  SELECT DISTINCT source_table AS table_name FROM column_mapping()
  WHERE view = $view AND source_table IS NOT NULL)
SELECT string_agg(table_name, ', ' ORDER BY table_name) AS tables
FROM t
HAVING count(*) > 0
