-- One metric's story at the viewer's grain: the total series, at the
-- value column's behaviour, windowed to the grain's rung on the server;
-- the span clips the newest periods here. A grain finer than the floor
-- serves nothing. The plan worlds ride beside the actuals, one series
-- per plan at the viewer's grain, and the forecast world with its 80%
-- band at the metric's own grain — the futures kit's reads, the newest
-- forecast landed, nothing re-run.
WITH story AS (
  SELECT period, dimension, member, value, num, den, behavior, world,
         dense_rank() OVER (ORDER BY period DESC) AS recency
  FROM metric_series(grain := $grain)
  WHERE metric = CAST($metric AS VARCHAR) AND dimension = ''),
a AS (
  SELECT name, schema FROM aspects WHERE name = CAST($metric AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
titles AS (
  SELECT name, json_extract_string(schema, '$.title') AS title FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
plans AS (
  SELECT c.period, coalesce(t.title, c.plan) AS series, c.value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, c.behavior, 'plan' AS world,
         CAST(NULL AS DOUBLE) AS low, CAST(NULL AS DOUBLE) AS high, CAST(NULL AS VARCHAR) AS held
  FROM plan_cells(CAST($grain AS VARCHAR)) c LEFT JOIN titles t ON t.name = c.plan
  WHERE c.metric = CAST($metric AS VARCHAR)),
forecast AS (
  SELECT f.period, coalesce(json_extract_string(a.schema, '$.title'), CAST($metric AS VARCHAR)) || ' · forecast' AS series,
         f.p50 AS value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, coalesce(f.behavior, 'none') AS behavior, 'forecast' AS world,
         f.p10 AS low, f.p90 AS high,
         coalesce(CAST(CAST(round(f.held_80 * 100) AS INT) AS VARCHAR) || '% of such bands held (' || f.held_from || ')', '') AS held
  FROM forecast_points() f LEFT JOIN a ON true
  WHERE f.metric = CAST($metric AS VARCHAR) AND f.applicable AND f.span IS NULL AND f.grain = CAST($grain AS VARCHAR)),
actuals AS (
  SELECT s.period,
    coalesce(json_extract_string(a.schema, '$.title'), CAST($metric AS VARCHAR)) AS series,
    s.value, s.num, s.den, s.behavior, s.world,
    CAST(NULL AS DOUBLE) AS low, CAST(NULL AS DOUBLE) AS high, CAST(NULL AS VARCHAR) AS held
  FROM story s
  LEFT JOIN a ON true
  WHERE CAST($span AS VARCHAR) = 'all' OR s.recency <= TRY_CAST($span AS INT))
SELECT * FROM actuals
UNION ALL SELECT * FROM plans
UNION ALL SELECT period::TIMESTAMP, series, value, num, den, behavior, world, low, high, held FROM forecast
ORDER BY period, series
