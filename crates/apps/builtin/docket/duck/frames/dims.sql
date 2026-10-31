-- The slice picker: the dimensions the series slices by for this
-- metric, with their member counts. Links are boosted navigation: the
-- dim rides the URL beside the viewer's window.
SELECT dimension,
  count(DISTINCT member) AS members,
  '?metric=' || CAST($metric AS VARCHAR) || '&dim=' || dimension
    || '&grain=' || CAST($grain AS VARCHAR) || '&span=' || CAST($span AS VARCHAR) AS link
FROM metric_series(unclaimed := 'skip')
WHERE metric = CAST($metric AS VARCHAR) AND dimension <> ''
GROUP BY dimension
ORDER BY dimension
