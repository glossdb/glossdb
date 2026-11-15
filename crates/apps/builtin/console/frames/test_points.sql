-- A range test's evidence: every backtested metric's newest point —
-- the one the backtest's result scores — with its actual, its range,
-- how far out it sits and on which side, the farthest out first. The
-- state beside each point is the model service's own for that metric,
-- as stored. A point whose PIT is withheld carries the service's
-- reason; a metric the backtest could not take carries its reason and
-- no numbers. `range_points()` is the stored backtest, no re-run, and
-- empty where the outlook kit is not loaded. Rows only for a test
-- whose detector is range_state, so another test's page draws nothing
-- here.
WITH w AS (
  SELECT name FROM tests WHERE name = $test AND detector = 'range_state'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1
),
newest AS (
  SELECT metric, applicable, reason, period, actual, p10, p90, pit, displacement AS far, withheld, state,
         row_number() OVER (PARTITION BY metric ORDER BY point_seq DESC) AS recency
  FROM range_points()
  WHERE metric IS NOT NULL AND (NOT applicable OR period IS NOT NULL)
),
-- The axis that moved most between the previous and the newest backtested
-- month, per metric, from the series' cells: a point's link opens the
-- metric sliced by it, so the page beyond shows where the move is
-- rather than the bare total.
cells AS (
  SELECT s.metric AS name, s.dimension AS axis, s.member, strftime(s.period, '%Y-%m') AS ym, s.value
  FROM metric_series(grain := 'month', unclaimed := 'skip') s
  WHERE s.world = 'actual' AND s.dimension <> ''
),
moves AS (
  SELECT c.name, c.axis, c.member,
         coalesce(max(CASE WHEN c.ym = n.period THEN c.value END), 0)
           - coalesce(max(CASE WHEN c.ym = p.period THEN c.value END), 0) AS delta
  FROM cells c
  JOIN newest n ON n.metric = c.name AND n.recency = 1
  LEFT JOIN newest p ON p.metric = c.name AND p.recency = 2
  WHERE c.ym = n.period OR c.ym = p.period
  GROUP BY c.name, c.axis, c.member
),
top AS (
  SELECT name, axis, row_number() OVER (PARTITION BY name ORDER BY abs(delta) DESC, axis, member) AS rn
  FROM moves
),
titles AS (
  SELECT name, json_extract_string(schema, '$.title') AS title FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1
)
SELECT coalesce(a.title, n.metric) AS title,
       n.metric AS view,
       coalesce(n.period, '') AS period,
       CASE WHEN n.actual IS NULL THEN ''
            ELSE fmt_number(n.actual) END AS actual,
       CASE WHEN n.p10 IS NULL THEN ''
            ELSE fmt_number(n.p10) || ' to ' || fmt_number(n.p90) END AS corridor,
       coalesce(fmt_number(n.far), '') AS displacement,
       CASE
         WHEN NOT n.applicable THEN 'not checked'
         WHEN n.far IS NULL THEN 'withheld'
         WHEN n.pit >= 0.5 THEN 'above the median'
         ELSE 'below the median' END AS side,
       coalesce(n.state, 'none') AS state,
       CASE WHEN n.state IS NULL THEN '' WHEN n.state = 'green' THEN 'ok' ELSE 'warn' END AS scls,
       coalesce(CASE WHEN NOT n.applicable THEN n.reason ELSE n.withheld END, '') AS note,
       '/' || d.dataset || '/app/console/p/views?view=' || n.metric || coalesce('&dim=' || t.axis, '') AS link
FROM newest n
CROSS JOIN w
CROSS JOIN current_dataset d
LEFT JOIN titles a ON a.name = n.metric
LEFT JOIN top t ON t.name = n.metric AND t.rn = 1
WHERE n.recency = 1
ORDER BY n.far DESC NULLS LAST, view
