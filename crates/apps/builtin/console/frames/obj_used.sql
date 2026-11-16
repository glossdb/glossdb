-- What uses a table or a column: every metric whose view reads it,
-- field by field, each linked to the metric.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT DISTINCT s.view,
       s.target_column AS field,
       s.source_table || '.' || s.source_column AS source,
       '/' || d.dataset || '/app/console/p/views?view=' || s.view AS link
FROM column_mapping() s CROSS JOIN d
WHERE s.source_column IS NOT NULL
  AND (s.source_table = CAST($subject AS VARCHAR) OR s.source_table || '.' || s.source_column = CAST($subject AS VARCHAR))
ORDER BY s.view, field
