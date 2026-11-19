-- What must and what should be done on the dataset, as `next` lists it:
-- the same rows the agent's `next:` line counts after every call, in the
-- same order. What could be done is not listed here. `link` opens the
-- page of the row's kind of work.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d)
SELECT n.level || ' · ' || n.kind AS kind,
       substr(n.asset, len(d.dataset) + 2) AS asset,
       n.state,
       CASE n.who WHEN 'person' THEN 'a person' ELSE 'the agent' END AS who,
       n.open,
       CASE WHEN n.level = 'must' THEN 'warn' ELSE '' END AS scls,
       (SELECT b FROM base) || CASE n.kind
         WHEN 'describe' THEN 'glossary' WHEN 'test' THEN 'quality'
         WHEN 'review' THEN 'review' ELSE 'views' END AS link
FROM next n CROSS JOIN d
WHERE n.level <> 'could'
ORDER BY CASE n.level WHEN 'must' THEN 1 ELSE 2 END, n.ord, n.asset
