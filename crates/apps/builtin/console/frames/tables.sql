-- The loaded tables of the bound dataset: the newest load per table
-- is the table, with its rows, the rows the recipe dropped, and when.
-- Column counts come from the engine's own schema surface. The file
-- links are the download interface's paths.
WITH latest AS (
  SELECT i.table_name, i.rows, i.dropped_rows_count, i.imported_at,
         row_number() OVER (PARTITION BY i.table_name ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset),
cols AS (
  SELECT c.table_name, count(*) AS columns
  FROM information_schema.columns c
  JOIN current_dataset d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database()
  GROUP BY c.table_name)
SELECT l.table_name AS name,
       coalesce(c.columns, 0) AS columns,
       CASE WHEN coalesce(c.columns, 0) = 1 THEN 'column' ELSE 'columns' END AS columns_label,
       coalesce(CAST(l.rows AS BIGINT), 0) AS rows,
       nullif(coalesce(l.dropped_rows_count, 0), 0) AS nulled,
       CASE WHEN coalesce(l.dropped_rows_count, 0) > 0 THEN '' ELSE '–' END AS dash,
       CASE WHEN coalesce(l.dropped_rows_count, 0) > 0 THEN 'dropped' ELSE '' END AS nulled_label,
       CASE WHEN coalesce(l.dropped_rows_count, 0) > 0 THEN 'r-gap' ELSE '' END AS ncls,
       strftime(l.imported_at, '%Y-%m-%d %H:%M') AS landed,
       '/' || d.dataset || '/app/export/' || l.table_name || '.csv' AS csv,
       '/' || d.dataset || '/app/export/' || l.table_name || '.parquet' AS parquet
FROM latest l
CROSS JOIN current_dataset d
LEFT JOIN cols c ON c.table_name = l.table_name
WHERE l.rn = 1
ORDER BY rows DESC, name
