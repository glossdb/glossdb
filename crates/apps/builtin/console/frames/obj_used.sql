-- What uses a table or a column: every metric whose view reads it,
-- field by field, each linked to the metric.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
d AS (SELECT dataset FROM current_dataset)
SELECT DISTINCT s.view,
       s.target_column AS field,
       s.source_table || '.' || s.source_column AS source,
       '/' || d.dataset || '/app/console/p/views?view=' || s.view AS link
FROM m s CROSS JOIN d
WHERE s.source_column IS NOT NULL
  AND (s.source_table = CAST($subject AS VARCHAR) OR s.source_table || '.' || s.source_column = CAST($subject AS VARCHAR))
ORDER BY s.view, field
