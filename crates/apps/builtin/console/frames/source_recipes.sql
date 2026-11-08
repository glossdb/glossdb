-- The load queries of this dataset that read one source: the table
-- each loads, its key, and its SQL.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT r.table_name,
       coalesce(json_extract_string(r.settings, '$.key'), '') AS key,
       r.sql,
       strftime(r.declared_at, '%Y-%m-%d %H:%M') AS declared,
       '/' || d.dataset || '/app/console/p/glossary?table=' || r.table_name AS link
FROM recipes r JOIN d ON d.dataset = r.dataset
WHERE r.source = CAST($source AS VARCHAR)
QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.seq DESC) = 1
ORDER BY r.table_name
