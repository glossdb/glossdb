-- A metric's expected range as a picture: every backtested month with
-- its actual and the 10th-to-90th range the backtest predicted for the
-- month, and whether the point is the newest one the model service
-- judged red. The spec draws the range as an area, the actuals as a
-- line, that point in the breach hue. `range_points()` is the stored
-- backtest, no re-run; the metric is a page param the finding's frame
-- fills in.
SELECT * FROM (
  SELECT (p.period || '-01')::TIMESTAMP AS period,
         coalesce(a.title, p.metric) AS series,
         p.actual AS value,
         p.p10 AS low,
         p.p90 AS high,
         coalesce(p.newest AND p.state = 'red', false) AS outside
  FROM range_points() p
  LEFT JOIN (SELECT name, json_extract_string(schema, '$.title') AS title FROM aspects
             QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1) a ON a.name = p.metric
  WHERE p.metric = CAST($view AS VARCHAR) AND p.applicable AND p.period IS NOT NULL
)
ORDER BY period
