-- Every load of the tables one source feeds in this dataset, newest
-- first.
WITH d AS (SELECT dataset FROM current_dataset),
fed AS (
  SELECT DISTINCT r.table_name FROM recipes r JOIN d ON d.dataset = r.dataset
  WHERE r.source = CAST($source AS VARCHAR))
SELECT strftime(i.imported_at, '%Y-%m-%d %H:%M') AS "at",
       i.table_name,
       i.mode,
       fmt_number(i.rows) AS rows,
       coalesce(fmt_number(nullif(i.dropped_rows_count, 0)), '') AS dropped
FROM imports i JOIN d ON d.dataset = i.dataset
JOIN fed ON fed.table_name = i.table_name
ORDER BY i.imported_at DESC, i.seq DESC
