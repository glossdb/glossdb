-- A declared fact's value (`x-kind: scalar`), served whole by
-- `fact_values()` — one row when the view is one row with a `value`,
-- none otherwise. Beside the number: the unit and meaning the
-- definition carries, and the as-of, the newest landing of the tables
-- the grounding reads.
WITH reads AS (
  SELECT DISTINCT table_name AS t FROM metric_sources()
  WHERE metric = CAST($metric AS VARCHAR) AND table_name IS NOT NULL),
as_of AS (
  SELECT max(i.imported_at) AS landed_at
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset
  JOIN reads r ON r.t = i.table_name)
SELECT f.metric,
       f.value,
       coalesce(s.unit, '') AS unit,
       coalesce(s.meaning, '') AS meaning,
       coalesce('as of ' || strftime(a.landed_at, '%Y-%m-%d %H:%M'), '') AS asof
FROM fact_values() f
LEFT JOIN metric_surfaces s ON s.name = f.metric
CROSS JOIN as_of a
WHERE f.metric = CAST($metric AS VARCHAR) AND f.value IS NOT NULL
