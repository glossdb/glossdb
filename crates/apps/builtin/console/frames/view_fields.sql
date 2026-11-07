-- What a view serves: every column of the page's grounding — the view
-- the catalog holds under the metric's name — in its own order, with
-- the judged role on the column itself where one stands, else the role
-- of the column it descends from, and that column. A field no one
-- column reaches says so and shows the engine's type in place of a
-- role.
WITH d AS (SELECT dataset FROM current_dataset),
roles AS (
  SELECT subject, json_extract_string(value, '$.value') AS role
  FROM GLOSSARY() WHERE aspect = 'role' AND value IS NOT NULL),
prov AS (
  SELECT DISTINCT s.field, s.source FROM metric_sources() s
  WHERE s.metric = $metric AND s.field IS NOT NULL),
folded AS (
  SELECT p.field,
         string_agg(p.source, ', ' ORDER BY p.source) AS sources,
         string_agg(DISTINCT r.role, ', ') AS roles
  FROM prov p
  LEFT JOIN roles r ON r.subject = (SELECT dataset FROM d) || '.' || p.source
  GROUP BY p.field),
cols AS (
  SELECT c.column_name, c.ordinal_position,
         CASE
           WHEN c.data_type LIKE 'VARCHAR%' THEN 'text'
           WHEN c.data_type IN ('TINYINT', 'SMALLINT', 'INTEGER', 'BIGINT', 'HUGEINT', 'UTINYINT', 'USMALLINT', 'UINTEGER', 'UBIGINT', 'FLOAT', 'DOUBLE') OR c.data_type LIKE 'DECIMAL%' THEN 'number'
           WHEN c.data_type = 'DATE' THEN 'date'
           WHEN c.data_type LIKE 'TIMESTAMP%' THEN 'timestamp'
           WHEN c.data_type = 'BOOLEAN' THEN 'flag'
           ELSE lower(c.data_type) END AS typed
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database() AND c.table_name = $metric)
SELECT c.column_name AS field,
       coalesce(own.role, nullif(f.roles, ''), c.typed) AS role,
       coalesce(f.sources, 'computed, no one column') AS sources
FROM cols c
LEFT JOIN folded f ON f.field = c.column_name
LEFT JOIN roles own ON own.subject = (SELECT dataset FROM d) || '.' || CAST($metric AS VARCHAR) || '.' || c.column_name
ORDER BY c.ordinal_position
