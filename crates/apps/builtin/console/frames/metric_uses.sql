-- What a metric reads: each field of its view and the loaded column it
-- comes from, linked to that column's page.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT coalesce(s.field, '(the whole view)') AS field,
       coalesce(s.source, s.table_name, 'computed') AS source,
       coalesce(s.reason, '') AS reason,
       CASE WHEN s.source IS NOT NULL THEN '/' || d.dataset || '/app/console/p/glossary?column=' || s.source
            WHEN s.table_name IS NOT NULL THEN '/' || d.dataset || '/app/console/p/glossary?table=' || s.table_name
            ELSE '#' END AS link
FROM metric_sources(for_metric := CAST($metric AS VARCHAR)) s CROSS JOIN d
ORDER BY s.field NULLS FIRST
