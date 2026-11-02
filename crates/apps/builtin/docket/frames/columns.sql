-- The Glossary's tables: every landed table with what one row is, its
-- grain and its time axis from the entity entry, then its columns
-- folded as lines — the column, its judged role with the slice rank
-- beside a dimension (the engine's type where no role is judged), its
-- behaviour and unit where it has them, and what it means. One row per
-- table; the name opens the table's page.
WITH d AS (SELECT dataset FROM current_dataset),
g AS (
  SELECT g.subject, g.aspect, g.body,
         row_number() OVER (PARTITION BY g.subject, g.aspect
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect IN ('role', 'meaning', 'unit', 'behavior', 'entity', 'dimension') AND g.actor_kind IN ('human', 'agent')),
cur AS (SELECT subject, aspect, body, json_extract_string(body, '$.value') AS value FROM g WHERE rn = 1),
landed AS (SELECT DISTINCT i.table_name FROM imports i JOIN d ON d.dataset = i.dataset),
cols AS (
  SELECT c.table_name, c.column_name, c.ordinal_position,
         CASE
           WHEN c.data_type LIKE 'VARCHAR%' THEN 'text'
           WHEN c.data_type IN ('TINYINT', 'SMALLINT', 'INTEGER', 'BIGINT', 'HUGEINT', 'UTINYINT', 'USMALLINT', 'UINTEGER', 'UBIGINT', 'FLOAT', 'DOUBLE') OR c.data_type LIKE 'DECIMAL%' THEN 'number'
           WHEN c.data_type = 'DATE' THEN 'date'
           WHEN c.data_type LIKE 'TIMESTAMP%' THEN 'timestamp'
           WHEN c.data_type = 'BOOLEAN' THEN 'flag'
           ELSE lower(c.data_type) END AS typed,
         r.value AS role, x.value AS axis, m.value AS meaning, u.value AS unit, b.value AS behavior
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN landed l ON l.table_name = c.table_name
  LEFT JOIN cur r ON r.aspect = 'role' AND r.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN cur x ON x.aspect = 'dimension' AND x.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN cur m ON m.aspect = 'meaning' AND m.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN cur u ON u.aspect = 'unit' AND u.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  LEFT JOIN cur b ON b.aspect = 'behavior' AND b.subject = d.dataset || '.' || c.table_name || '.' || c.column_name
  WHERE c.table_catalog = current_database()),
folded AS (
  SELECT table_name, count(*) AS n,
         string_agg(
           column_name || '  ·  ' || coalesce(role, typed) || coalesce(', ' || axis, '')
             || coalesce('  ·  ' || behavior, '') || coalesce('  ·  ' || unit, '')
             || coalesce('  —  ' || meaning, ''),
           chr(10) ORDER BY ordinal_position) AS lines
  FROM cols GROUP BY table_name),
latest AS (
  SELECT i.table_name, i.rows,
         row_number() OVER (PARTITION BY i.table_name ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN d ON d.dataset = i.dataset)
SELECT f.table_name AS name,
       f.n AS columns,
       coalesce(CAST(l.rows AS BIGINT), 0) AS rows,
       coalesce(e.value, '') AS entity,
       concat_ws(' · ',
         'one row per ' || array_to_string(json_extract(e.body, '$.grain')::VARCHAR[], ', '),
         'time axis ' || json_extract_string(e.body, '$.time_axis')) AS shape,
       f.lines,
       '?table=' || f.table_name AS link
FROM folded f
CROSS JOIN d
LEFT JOIN cur e ON e.aspect = 'entity' AND e.subject = d.dataset || '.' || f.table_name
LEFT JOIN latest l ON l.table_name = f.table_name AND l.rn = 1
ORDER BY rows DESC, name
