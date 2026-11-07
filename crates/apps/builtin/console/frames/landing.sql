-- The loads, one line per table: the newest landing of each — what
-- landed and when, the rows the recipe dropped. The table opens its
-- page on the Glossary tab.
WITH d AS (SELECT dataset FROM current_dataset),
newest AS (
  SELECT i.table_name, i.rows, i.dropped_rows_count, i.imported_at,
         row_number() OVER (PARTITION BY i.table_name ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN d ON d.dataset = i.dataset),
rec AS (SELECT r.table_name, max(r.source) AS source FROM recipes r JOIN d ON d.dataset = r.dataset GROUP BY r.table_name)
SELECT n.table_name AS name,
       coalesce('the source ' || r.source, '') AS read,
       coalesce(CAST(n.rows AS BIGINT), 0) AS landed,
       strftime(n.imported_at, '%d %b %Y %H:%M') AS "at",
       CASE WHEN coalesce(n.dropped_rows_count, 0) > 0
            THEN CAST(n.dropped_rows_count AS VARCHAR) || ' rows dropped by the load query'
            ELSE '' END AS dropped,
       '' AS refused,
       '' AS casts,
       '/' || d.dataset || '/app/console/p/glossary?table=' || n.table_name AS link
FROM newest n
CROSS JOIN d
LEFT JOIN rec r ON r.table_name = n.table_name
WHERE n.rn = 1
ORDER BY landed DESC, name
