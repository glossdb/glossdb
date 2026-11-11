-- A declared fact's value (`x-kind: scalar`), served whole by
-- `fact_values()` — one row when the view is one row with a `value`,
-- none otherwise. Beside the number: the unit and meaning the
-- definition carries, and the as-of, the newest load of the tables
-- the metric definition reads.
WITH reads AS (
  SELECT DISTINCT table_name AS t FROM view_sources()
  WHERE view = CAST($view AS VARCHAR) AND table_name IS NOT NULL),
as_of AS (
  SELECT max(i.imported_at) AS loaded_at
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset
  JOIN reads r ON r.t = i.table_name)
SELECT f.view AS view,
       f.value,
       coalesce(s.unit, '') AS unit,
       coalesce(s.meaning, '') AS meaning,
       coalesce('as of ' || strftime(a.loaded_at, '%Y-%m-%d %H:%M'), '') AS asof
FROM fact_values() f
LEFT JOIN view_definitions s ON s.name = f.view
CROSS JOIN as_of a
WHERE f.view = CAST($view AS VARCHAR) AND f.value IS NOT NULL
