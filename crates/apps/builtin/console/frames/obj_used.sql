-- What uses a table or a column: every metric whose view reads it,
-- field by field, each linked to the metric.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT s.view,
       s.field,
       coalesce(s.source, s.table_name) AS source,
       '/' || d.dataset || '/app/console/p/views?view=' || s.view AS link
FROM view_sources() s CROSS JOIN d
WHERE s.field IS NOT NULL
  AND (s.table_name = CAST($subject AS VARCHAR) OR s.source = CAST($subject AS VARCHAR))
ORDER BY s.view, field
