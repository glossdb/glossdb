-- What uses a table or a column: every metric whose view reads it,
-- field by field, each linked to the metric.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT s.metric,
       s.field,
       coalesce(s.source, s.table_name) AS source,
       '/' || d.dataset || '/app/console/p/metrics?metric=' || s.metric AS link
FROM metric_sources() s CROSS JOIN d
WHERE s.field IS NOT NULL
  AND (s.table_name = CAST($subject AS VARCHAR) OR s.source = CAST($subject AS VARCHAR))
ORDER BY s.metric, field
