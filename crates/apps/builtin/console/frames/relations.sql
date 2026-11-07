-- The Query tab's relations: every landed table (the newest landing is
-- the table) and every served read of the dataset, each with its rows
-- where the record counts them, and a read that puts the first fifty
-- rows in the pane. A stopped read serves nothing and is not offered;
-- a plan stands on its metric's page.
WITH latest AS (
  SELECT i.table_name, i.rows AS n,
         row_number() OVER (PARTITION BY i.table_name ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset),
tables AS (
  SELECT table_name AS name, 'table' AS kind, CAST(n AS BIGINT) AS n, '' AS what FROM latest WHERE rn = 1),
reads AS (
  SELECT s.name,
         CASE WHEN s.kind IN ('', 'measure', 'metric') THEN 'metric'
              WHEN s.kind = 'relation' THEN 'view'
              ELSE s.kind END AS kind,
         CAST(NULL AS BIGINT) AS n, s.meaning AS what
  FROM metric_surfaces s
  WHERE s.grounded AND s.stopped = '' AND s.kind <> 'plan'),
all_ AS (SELECT * FROM tables UNION ALL SELECT * FROM reads)
SELECT name, kind,
       coalesce(CAST(n AS VARCHAR), '') AS rows,
       coalesce(what, '') AS what,
       '?sql=SELECT * FROM ' || name || ' LIMIT 50' AS link
FROM all_
ORDER BY CASE kind WHEN 'table' THEN 0 WHEN 'view' THEN 1 WHEN 'metric' THEN 2 ELSE 3 END, name
