-- What waits on an act: the shipped `owed` read. Display only — a
-- readable timestamp, a link chosen by kind, the order. Every link
-- carries the dataset: the app is mounted under it.
SELECT o.what,
       o.why,
       replace(substr(o.since, 1, 16), 'T', ' ') AS since,
       '/' || d.dataset || CASE o.kind
         WHEN 'recipe' THEN '/app/docket/p/quality'
         WHEN 'contest' THEN '/app/docket/p/quality'
         WHEN 're-measure' THEN '/app/docket/p/metrics'
         ELSE '/app/docket/p/metrics?metric=' || o.subject
       END AS link
FROM owed o CROSS JOIN current_dataset d
ORDER BY since DESC, what
