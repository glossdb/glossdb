-- Every read the dataset serves, for the Export tab: one row per view it
-- serves (a table, a single value, a metric), with the files the download interface serves for
-- its view. The chip says kind and state in one word. `$stopped`
-- picks the served reads (0) or the stopped ones (1).
SELECT s.name,
       s.name AS read,
       s.unit,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped ELSE s.meaning END AS what,
       CASE
         WHEN s.stopped <> '' THEN 'stopped'
         WHEN NOT s.defined THEN 'no definition'
         ELSE s.kind END AS chip,
       CASE WHEN s.stopped <> '' OR NOT s.defined THEN 'warn' ELSE 'ok' END AS ccls,
       CASE WHEN s.stopped <> '' OR NOT s.defined THEN 'off' ELSE '' END AS fcls,
       '/' || d.dataset || '/app/export/read.' || s.name || '.csv' AS csv,
       '/' || d.dataset || '/app/export/read.' || s.name || '.parquet' AS parquet
FROM view_definitions s CROSS JOIN current_dataset d
WHERE (s.stopped <> '') = (coalesce($stopped, '0') = '1') AND s.kind IN ('table', 'value', 'metric')
ORDER BY CASE
    WHEN s.stopped <> '' THEN 4
    WHEN NOT s.defined THEN 3
    WHEN s.kind = 'metric' THEN 0
    WHEN s.kind = 'value' THEN 1
    ELSE 2 END,
  s.name
