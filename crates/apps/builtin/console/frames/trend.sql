-- One metric's story at the viewer's grain: the total series, at the
-- value column's additivity, windowed to the grain's rung on the server;
-- the span clips the newest periods here. A grain finer than the floor
-- serves nothing.
WITH story AS (
  SELECT period, dimension, member, value, num, den, additivity,
         dense_rank() OVER (ORDER BY period DESC) AS recency
  FROM metric_series(view := CAST($view AS VARCHAR), grain := $grain)
  WHERE dimension = ''),
a AS (
  SELECT name, schema FROM properties WHERE name = CAST($view AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
actuals AS (
  SELECT s.period,
    coalesce(json_extract_string(a.schema, '$.title'), CAST($view AS VARCHAR)) AS series,
    s.value, s.num, s.den, s.additivity
  FROM story s
  LEFT JOIN a ON true
  WHERE CAST($span AS VARCHAR) = 'all' OR s.recency <= TRY_CAST($span AS INT))
SELECT * FROM actuals
ORDER BY period, series
