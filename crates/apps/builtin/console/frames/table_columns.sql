-- One table's columns, every value the catalog holds on each: the judged
-- role with the slice rank beside a dimension (the engine's type where
-- none is judged), the unit and behaviour where required, the meaning or
-- `not yet said` where the meaning is required and nobody spoke, and what
-- was measured on the column. The mark is the column's worst standing
-- across its authored slots. A row opens the column's page.
WITH d AS (SELECT dataset FROM current_dataset),
tbl AS (SELECT d.dataset || '.' || CAST($table AS VARCHAR) AS subject FROM d),
slots AS (
  SELECT g.subject, g.aspect, g.actor_kind, g.body, g.written_at,
         row_number() OVER (PARTITION BY g.subject, g.aspect
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.subject LIKE (SELECT subject FROM tbl) || '.%'
    AND g.aspect IN ('role', 'meaning', 'unit', 'behavior', 'dimension') AND g.actor_kind IN ('human', 'agent')),
cur AS (SELECT subject, aspect, actor_kind, written_at, json_extract_string(body, '$.value') AS value FROM slots WHERE rn = 1),
states AS (
  SELECT subject,
         max(CASE WHEN state = 'contested' THEN 2 WHEN state = 'stale' THEN 1 ELSE 0 END) AS worst,
         count(*) FILTER (WHERE aspect = 'meaning' AND state = 'unassessed') AS meaning_owed
  FROM GLOSSARY()
  WHERE subject LIKE (SELECT subject FROM tbl) || '.%'
    AND aspect IN ('role', 'meaning', 'unit', 'behavior', 'dimension')
  GROUP BY subject),
human AS (SELECT subject, max(written_at) AS spoken_at FROM cur WHERE actor_kind = 'human' GROUP BY subject),
entity AS (
  SELECT json_extract_string(g.body, '$.time_axis') AS axis,
         row_number() OVER (ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect = 'entity' AND g.subject = (SELECT subject FROM tbl) AND g.actor_kind IN ('human', 'agent')),
measured AS (
  SELECT g.subject, g.aspect, g.body
  FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.current AND g.subject LIKE (SELECT subject FROM tbl) || '.%'),
summaries AS (
  SELECT subject,
         string_agg(
           CASE WHEN NOT coalesce(json_extract(body, '$.applicable')::BOOLEAN, true) THEN aspect || ': not applicable'
             ELSE CASE aspect
               WHEN 'temporal_profile' THEN coalesce(json_extract_string(body, '$.granularity'), 'no grain found')
                 || coalesce(', ' || json_extract_string(body, '$.completeness.actual') || ' of ' || json_extract_string(body, '$.completeness.expected') || ' periods', '')
                 || coalesce(', ' || json_extract_string(body, '$.gaps.count') || ' gaps', '')
               WHEN 'column_profile' THEN coalesce(json_extract_string(body, '$.total') || ' values', 'profiled')
                 || coalesce(', ' || fmt_number(json_extract(body, '$.null_ratio')::DOUBLE * 100) || '% null', '')
                 || coalesce(', ' || json_extract_string(body, '$.distinct') || ' distinct', '')
               WHEN 'outlier_profile' THEN 'outliers profiled'
               ELSE aspect END END,
           ' · ' ORDER BY aspect) AS measured
  FROM measured GROUP BY subject),
cols AS (
  SELECT c.column_name, c.ordinal_position, d.dataset || '.' || c.table_name || '.' || c.column_name AS subject,
         c.table_name || '.' || c.column_name AS path,
         CASE
           WHEN c.data_type LIKE 'VARCHAR%' THEN 'text'
           WHEN c.data_type IN ('TINYINT', 'SMALLINT', 'INTEGER', 'BIGINT', 'HUGEINT', 'UTINYINT', 'USMALLINT', 'UINTEGER', 'UBIGINT', 'FLOAT', 'DOUBLE') OR c.data_type LIKE 'DECIMAL%' THEN 'number'
           WHEN c.data_type = 'DATE' THEN 'date'
           WHEN c.data_type LIKE 'TIMESTAMP%' THEN 'timestamp'
           WHEN c.data_type = 'BOOLEAN' THEN 'flag'
           ELSE lower(c.data_type) END AS typed
  FROM information_schema.columns c JOIN d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database() AND c.table_name = CAST($table AS VARCHAR))
SELECT c.column_name AS name,
       coalesce(r.value, c.typed) AS role,
       CASE WHEN r.value IS NULL THEN 'column type, no role set' ELSE '' END AS role_note,
       concat_ws(' · ', u.value, b.value) AS unit,
       CASE WHEN e.axis = c.column_name THEN 'time axis' ELSE coalesce(x.value, '') END AS axis,
       coalesce(m.value, CASE WHEN coalesce(st.meaning_owed, 0) > 0 THEN 'not yet annotated' ELSE '' END) AS meaning,
       coalesce(s.measured, '') AS measured,
       CASE WHEN st.worst = 2 THEN 'contested' WHEN st.worst = 1 THEN 'stale' WHEN h.subject IS NOT NULL THEN 'ruled' ELSE '' END AS mark,
       CASE WHEN st.worst = 2 THEN 'v-open' WHEN st.worst = 1 THEN 'v-stale' WHEN h.subject IS NOT NULL THEN 'v-ruled' ELSE 'v-none' END AS mcls,
       CASE WHEN st.worst = 2 THEN 'the annotations differ; the test withholds the value'
            WHEN st.worst = 1 THEN 'an annotation was written before the column last changed'
            WHEN h.subject IS NOT NULL THEN 'a person annotated this column, ' || strftime(h.spoken_at, '%d %b %Y %H:%M')
            ELSE '' END AS mark_title,
       '?column=' || c.path AS link
FROM cols c
LEFT JOIN cur r ON r.subject = c.subject AND r.aspect = 'role'
LEFT JOIN cur x ON x.subject = c.subject AND x.aspect = 'dimension'
LEFT JOIN cur m ON m.subject = c.subject AND m.aspect = 'meaning'
LEFT JOIN cur u ON u.subject = c.subject AND u.aspect = 'unit'
LEFT JOIN cur b ON b.subject = c.subject AND b.aspect = 'behavior'
LEFT JOIN states st ON st.subject = c.subject
LEFT JOIN human h ON h.subject = c.subject
LEFT JOIN entity e ON e.rn = 1
LEFT JOIN summaries s ON s.subject = c.subject
ORDER BY c.ordinal_position
