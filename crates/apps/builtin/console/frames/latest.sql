-- The numbers beside each metric: the newest period of the
-- total series at the metric's own floor, the move into it, and the
-- dimensions the catalog names for it. Data-class, joined to
-- `frames/measures` in the browser by `name`. A metric whose value column
-- carries no additivity and serves several rows a period has no row here;
-- its row in `frames/measures` says so.
WITH totals AS (
  SELECT metric, period, value,
         value - lag(value) OVER (PARTITION BY metric ORDER BY period) AS delta
  FROM metric_series(unclaimed := 'skip') WHERE dimension = ''
  QUALIFY row_number() OVER (PARTITION BY metric ORDER BY period DESC) = 1)
SELECT t.metric AS name,
       t.period,
       coalesce(fmt_number(t.value), '—') AS latest,
       coalesce(fmt_change(100.0 * t.delta / nullif(t.value - t.delta, 0)), '') AS delta,
       coalesce(nullif(array_to_string(list_sort(x.dims), ' · '), ''), 'no axes admitted') AS axes
FROM totals t
LEFT JOIN view_axes() x ON x.view = t.metric
