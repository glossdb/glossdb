-- The numbers beside each metric surface: the newest period of the
-- total series at the metric's own floor, the move into it, and the
-- slices. Data-class, joined to `frames/pulse` in the browser by
-- `name`. A metric whose value column carries no behaviour and serves
-- several rows a period has no row here; its pulse row says so.
WITH totals AS (
  SELECT metric, period, value,
         value - lag(value) OVER (PARTITION BY metric ORDER BY period) AS delta
  FROM metric_series(unclaimed := 'skip') WHERE dimension = ''
  QUALIFY row_number() OVER (PARTITION BY metric ORDER BY period DESC) = 1),
axes AS (
  SELECT metric, string_agg(dimension, ' · ' ORDER BY dimension) AS axes
  FROM (SELECT DISTINCT metric, dimension FROM metric_series(unclaimed := 'skip') WHERE dimension <> '')
  GROUP BY metric)
SELECT t.metric AS name,
       t.period,
       coalesce(fmt_number(t.value), '—') AS latest,
       coalesce(fmt_change(100.0 * t.delta / nullif(t.value - t.delta, 0)), '') AS delta,
       coalesce(x.axes, 'no axes admitted') AS axes
FROM totals t
LEFT JOIN axes x ON x.metric = t.metric
