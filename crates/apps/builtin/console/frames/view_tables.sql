-- The tables a view reads, as one line: every loaded table the view's
-- lineage reaches (metric_sources()), in name order. One row, or none
-- for a metric definition that reads nothing landed.
WITH t AS (
  SELECT DISTINCT table_name FROM metric_sources()
  WHERE metric = $metric AND table_name IS NOT NULL)
SELECT string_agg(table_name, ', ' ORDER BY table_name) AS tables
FROM t
HAVING count(*) > 0
