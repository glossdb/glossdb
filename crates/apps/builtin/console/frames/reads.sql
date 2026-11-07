-- Every read the dataset serves, for the Export tab: one row per VIEW
-- aspect that holds here, with the files the download interface serves for
-- its view. The chip says kind and standing in one word. `$stopped`
-- picks the served reads (0) or the stopped ones (1).
SELECT s.name,
       s.name AS read,
       s.title,
       s.unit,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped ELSE s.meaning END AS what,
       CASE
         WHEN s.stopped <> '' THEN 'stopped'
         WHEN NOT s.grounded THEN 'no definition'
         WHEN s.kind IN ('', 'measure', 'metric') THEN 'metric'
         ELSE s.kind END AS chip,
       CASE WHEN s.stopped <> '' OR NOT s.grounded THEN 'warn' ELSE 'ok' END AS ccls,
       CASE WHEN s.stopped <> '' OR NOT s.grounded THEN 'off' ELSE '' END AS fcls,
       '/' || d.dataset || '/app/export/read.' || s.name || '.csv' AS csv,
       '/' || d.dataset || '/app/export/read.' || s.name || '.parquet' AS parquet
FROM metric_surfaces s CROSS JOIN current_dataset d
WHERE (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY CASE
    WHEN s.stopped <> '' THEN 4
    WHEN NOT s.grounded THEN 3
    WHEN s.kind IN ('', 'measure', 'metric') THEN 0
    WHEN s.kind = 'scalar' THEN 1
    ELSE 2 END,
  s.name
