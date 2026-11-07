-- What waits on an act: the shipped `open_items` read. Display only — a
-- readable timestamp, a link chosen by kind, the order. Every link
-- carries the dataset: the app is mounted under it.
SELECT o.what,
       o.why,
       replace(substr(o.since, 1, 16), 'T', ' ') AS since,
       '/' || d.dataset || CASE o.kind
         WHEN 'recipe-change' THEN '/app/console/p/quality'
         WHEN 'conflict' THEN '/app/console/p/quality'
         WHEN 're-measure' THEN '/app/console/p/metrics'
         ELSE '/app/console/p/metrics?metric=' || o.subject
       END AS link
FROM open_items o CROSS JOIN current_dataset d
ORDER BY since DESC, what
