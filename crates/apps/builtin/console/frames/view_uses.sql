-- What a metric reads: each field of its view and the loaded column it
-- comes from, linked to that column's page.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
d AS (SELECT dataset FROM current_dataset)
SELECT DISTINCT coalesce(s.target_column, '(the whole view)') AS field,
       coalesce(s.source_table || '.' || s.source_column, 'computed') AS source,
       CASE WHEN s.target_column IS NULL THEN 'the view definition does not plan' ELSE '' END AS reason,
       CASE WHEN s.source_column IS NOT NULL
            THEN '/' || d.dataset || '/app/console/p/glossary?column=' || s.source_table || '.' || s.source_column
            ELSE '#' END AS link
FROM m s CROSS JOIN d
WHERE s.view = CAST($view AS VARCHAR)
ORDER BY field, source
