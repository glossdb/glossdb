-- What is open on the dataset, as `next` lists it: the same rows the
-- agent reads after every call, in the same order. `link` opens the
-- page of the row's step.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d)
SELECT n.step,
       substr(n.asset, len(d.dataset) + 2) AS asset,
       n.state,
       CASE n.who WHEN 'person' THEN 'a person' ELSE 'the agent' END AS who,
       n.open,
       coalesce(n.cause, '') AS cause,
       CASE WHEN n.state IN ('red', 'conflict') THEN 'warn' ELSE '' END AS scls,
       (SELECT b FROM base) || CASE n.step
         WHEN 'connect' THEN 'glossary' WHEN 'describe' THEN 'glossary'
         WHEN 'test' THEN 'quality' WHEN 'decide' THEN 'review' ELSE 'views' END AS link
FROM next n CROSS JOIN d
ORDER BY n.priority, n.ord, n.asset
