-- What a metric reads: each field of its view and the loaded column it
-- comes from, linked to that column's page.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT DISTINCT coalesce(s.target_column, '(the whole view)') AS field,
       coalesce(s.source_table || '.' || s.source_column, 'computed') AS source,
       CASE WHEN s.target_column IS NULL THEN 'the view definition does not plan' ELSE '' END AS reason,
       CASE WHEN s.source_column IS NOT NULL
            THEN '/' || d.dataset || '/app/console/p/glossary?column=' || s.source_table || '.' || s.source_column
            ELSE '#' END AS link
FROM column_mapping(for_view := CAST($view AS VARCHAR)) s CROSS JOIN d
ORDER BY field, source
