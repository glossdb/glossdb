-- One metric's story at the viewer's grain: the total series, at the
-- value column's additivity, windowed to the grain's rung on the server;
-- the span clips the newest periods here. A grain finer than the floor
-- serves nothing. The series a kit serves beside the actual one ride
-- with it (world_series(): a plan, the forecast with its 80% range),
-- nothing re-run; none where no kit serves them.
WITH story AS (
  SELECT period, dimension, member, value, num, den, additivity, world,
         dense_rank() OVER (ORDER BY period DESC) AS recency
  FROM metric_series(grain := $grain)
  WHERE metric = CAST($view AS VARCHAR) AND dimension = ''),
a AS (
  SELECT name, schema FROM aspects WHERE name = CAST($view AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
worlds AS (
  SELECT w.period, w.series, w.value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, w.additivity, w.world, w.low, w.high, w.held
  FROM world_series(CAST($grain AS VARCHAR)) w
  WHERE w.metric = CAST($view AS VARCHAR)),
actuals AS (
  SELECT s.period,
    coalesce(json_extract_string(a.schema, '$.title'), CAST($view AS VARCHAR)) AS series,
    s.value, s.num, s.den, s.additivity, s.world,
    CAST(NULL AS DOUBLE) AS low, CAST(NULL AS DOUBLE) AS high, CAST(NULL AS VARCHAR) AS held
  FROM story s
  LEFT JOIN a ON true
  WHERE CAST($span AS VARCHAR) = 'all' OR s.recency <= TRY_CAST($span AS INT))
SELECT * FROM actuals
UNION ALL SELECT period::TIMESTAMP, series, value, num, den, additivity, world, low, high, held FROM worlds
ORDER BY period, series
