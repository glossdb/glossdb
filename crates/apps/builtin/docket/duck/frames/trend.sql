-- One metric's story at the viewer's grain: the total series, at the
-- value column's behaviour, windowed to the grain's rung on the server;
-- the span clips the newest periods here. A grain finer than the floor
-- serves nothing. The forecast and the plan worlds ride beside the
-- actuals once the futures kit serves them; until then the actuals
-- stand alone.
WITH story AS (
  SELECT period, dimension, member, value, num, den, behavior, world,
         dense_rank() OVER (ORDER BY period DESC) AS recency
  FROM metric_series(grain := $grain)
  WHERE metric = CAST($metric AS VARCHAR) AND dimension = ''),
a AS (
  SELECT name, schema FROM aspects WHERE name = CAST($metric AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
SELECT s.period,
  coalesce(json_extract_string(a.schema, '$.title'), CAST($metric AS VARCHAR)) AS series,
  s.value, s.num, s.den, s.behavior, s.world,
  CAST(NULL AS DOUBLE) AS low, CAST(NULL AS DOUBLE) AS high, CAST(NULL AS VARCHAR) AS held
FROM story s
LEFT JOIN a ON true
WHERE CAST($span AS VARCHAR) = 'all' OR s.recency <= TRY_CAST($span AS INT)
ORDER BY period, series
