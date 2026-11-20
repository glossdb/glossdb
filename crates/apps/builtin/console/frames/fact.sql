-- A single value's number (kind value), served whole by
-- `fact_values()` — one row when the view is one row with a `value`,
-- none otherwise. Beside the number: the unit and meaning the
-- definition carries, and the as-of, the newest load of the tables
-- the definition reads.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
reads AS (
  SELECT DISTINCT source_table AS t FROM m
  WHERE view = CAST($view AS VARCHAR) AND source_table IS NOT NULL),
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
