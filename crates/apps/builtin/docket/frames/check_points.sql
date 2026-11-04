-- A corridor check's evidence: every walked metric's newest point —
-- the one the walk's verdict scores — with its actual, its corridor,
-- how far out it sits and on which side, the farthest out first. The
-- band beside each point is the verdict's own rule on that one
-- displacement (green to 0.8, yellow to 0.9, orange to the threshold,
-- red past it); the verdict's score is the worst of them raised to
-- their number. A point whose PIT is withheld carries the service's
-- reason; a metric the walk found inapplicable carries its reason and
-- no numbers. `band_points()` is the recorded walk, no re-run. Rows
-- only for a witness whose detector is band_breach, so another check's
-- page draws nothing here.
WITH w AS (
  SELECT name, coalesce(threshold, 0.98) AS threshold
  FROM witnesses WHERE name = $check AND detector = 'band_breach'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1
),
newest AS (
  SELECT metric, applicable, reason, period, actual, p10, p90, pit, displacement AS far, withheld,
         row_number() OVER (PARTITION BY metric ORDER BY point_seq DESC) AS recency
  FROM band_points()
  WHERE NOT applicable OR period IS NOT NULL
),
-- The axis that moved most between the previous and the newest walked
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
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1
)
SELECT coalesce(a.title, n.metric) AS title,
       n.metric AS metric,
       coalesce(n.period, '') AS period,
       CASE WHEN n.actual IS NULL THEN ''
            WHEN abs(n.actual) < 10 THEN CAST(round(n.actual * 1000) / 1000 AS VARCHAR)
            ELSE CAST(CAST(round(n.actual) AS BIGINT) AS VARCHAR) END AS actual,
       CASE WHEN n.p10 IS NULL THEN ''
            WHEN abs(n.p90) < 10 THEN CAST(round(n.p10 * 1000) / 1000 AS VARCHAR) || ' to ' || CAST(round(n.p90 * 1000) / 1000 AS VARCHAR)
            ELSE CAST(CAST(round(n.p10) AS BIGINT) AS VARCHAR) || ' to ' || CAST(CAST(round(n.p90) AS BIGINT) AS VARCHAR) END AS corridor,
       coalesce(CAST(round(n.far * 1000) / 1000 AS VARCHAR), '') AS displacement,
       CASE
         WHEN NOT n.applicable THEN 'not walked'
         WHEN n.far IS NULL THEN 'withheld'
         WHEN n.far >= 0.95 AND n.pit >= 0.5 THEN 'above'
         WHEN n.far >= 0.95 THEN 'below'
         ELSE 'inside' END AS side,
       CASE
         WHEN NOT n.applicable OR n.far IS NULL THEN 'none'
         WHEN n.far <= 0.8 THEN 'green'
         WHEN n.far <= 0.9 THEN 'yellow'
         WHEN n.far <= w.threshold THEN 'orange'
         ELSE 'red' END AS band,
       CASE
         WHEN NOT n.applicable OR n.far IS NULL THEN ''
         WHEN n.far <= 0.8 THEN 'ok'
         ELSE 'warn' END AS bcls,
       coalesce(CASE WHEN NOT n.applicable THEN n.reason ELSE n.withheld END, '') AS note,
       '/' || d.dataset || '/app/docket/p/metrics?metric=' || n.metric || coalesce('&dim=' || t.axis, '') AS link
FROM newest n
CROSS JOIN w
CROSS JOIN current_dataset d
LEFT JOIN titles a ON a.name = n.metric
LEFT JOIN top t ON t.name = n.metric AND t.rn = 1
WHERE n.recency = 1
ORDER BY n.far DESC NULLS LAST, metric
