-- One aspect's values: every subject the collapsed read serves for it
-- — the value in words, who spoke it, the value's standing and when —
-- and every subject it is required on where nobody spoke, said so. The
-- contested first, then the stale, then the spoken, then the required; a
-- subject opens its page where it has one. Subjects are shown without
-- the dataset's own prefix.
WITH d AS (SELECT dataset FROM current_dataset),
st AS (
  SELECT subject, state, value FROM GLOSSARY() WHERE aspect = CAST($aspect AS VARCHAR)),
said AS (
  SELECT g.subject, g.actor_kind, g.actor_id, g.body, g.written_at,
         row_number() OVER (PARTITION BY g.subject
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect = CAST($aspect AS VARCHAR) AND g.actor_kind IN ('human', 'agent')),
fn AS (
  SELECT g.subject, g.actor, g.written_at, g.body
  FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.aspect = CAST($aspect AS VARCHAR) AND g.current),
landed AS (SELECT DISTINCT i.table_name FROM imports i JOIN d ON d.dataset = i.dataset),
a AS (
  SELECT lower(kind) AS kind FROM aspects WHERE name = CAST($aspect AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
SELECT CASE WHEN starts_with(st.subject, d.dataset || '.') THEN substr(st.subject, len(d.dataset) + 2) ELSE st.subject END AS subject,
       CASE
         WHEN st.state = 'unassessed' THEN CASE WHEN a.kind = 'measurement' THEN 'not yet measured' ELSE 'not yet annotated' END
         WHEN st.state = 'contested' THEN 'withheld: the annotations differ'
         WHEN a.kind = 'measurement' THEN substr(f.body::VARCHAR, 1, 200)
         WHEN a.kind = 'view' THEN 'a metric definition in SQL; its page has the assumptions and the SQL'
         ELSE CASE CAST($aspect AS VARCHAR)
           WHEN 'entity' THEN json_extract_string(s.body, '$.value')
             || coalesce(' · one row per ' || array_to_string(json_extract(s.body, '$.grain')::VARCHAR[], ', '), '')
             || coalesce(' · time axis ' || json_extract_string(s.body, '$.time_axis'), '')
           WHEN 'unit' THEN json_extract_string(s.body, '$.value') || coalesce(', varying by ' || json_extract_string(s.body, '$.source_column'), '')
           WHEN 'behavior' THEN json_extract_string(s.body, '$.value') || coalesce(' — ' || json_extract_string(s.body, '$.grounds'), '')
           WHEN 'dimension' THEN json_extract_string(s.body, '$.value') || coalesce(' — ' || json_extract_string(s.body, '$.grounds'), '')
           WHEN 'meaning' THEN json_extract_string(s.body, '$.value') || coalesce(' (the term: ' || json_extract_string(s.body, '$.term') || ')', '')
           WHEN 'conventions' THEN array_to_string(json_keys(s.body), ', ')
           WHEN 'definitions' THEN CAST(len(json_keys(s.body, '$.definitions')) AS VARCHAR) || ' definitions'
           ELSE coalesce(json_extract_string(s.body, '$.value'), substr(s.body::VARCHAR, 1, 200)) END END AS value,
       CASE WHEN st.state = 'unassessed' THEN ''
            WHEN a.kind = 'measurement' THEN coalesce(f.actor, '')
            WHEN s.actor_kind = 'human' THEN 'a person'
            WHEN s.actor_kind = 'agent' THEN 'the agent'
            ELSE coalesce(s.actor_kind, '') END AS voice,
       st.state,
       coalesce(strftime(coalesce(s.written_at, f.written_at), '%d %b %Y %H:%M'), '') AS "at",
       CASE WHEN st.state = 'contested' THEN 'contested' WHEN st.state = 'stale' THEN 'stale'
            WHEN s.actor_kind = 'human' THEN 'ruled' ELSE '' END AS mark,
       CASE WHEN st.state = 'contested' THEN 'v-open' WHEN st.state = 'stale' THEN 'v-stale'
            WHEN s.actor_kind = 'human' THEN 'v-ruled' ELSE 'v-none' END AS mcls,
       CASE WHEN st.state = 'contested' THEN 'the annotations differ; the test withholds the value'
            WHEN st.state = 'stale' THEN 'written before the subject last changed'
            WHEN s.actor_kind = 'human' THEN 'written by ' || coalesce(s.actor_id, 'a person')
            ELSE '' END AS mark_title,
       CASE
         WHEN a.kind = 'view' THEN '/' || d.dataset || '/app/console/p/metrics?metric=' || CAST($aspect AS VARCHAR)
         WHEN strpos(st.subject, ' -> ') > 0 THEN ''
         WHEN len(string_split(st.subject, '.')) = 3 THEN '?column=' || substr(st.subject, len(d.dataset) + 2)
         WHEN len(string_split(st.subject, '.')) = 2 AND l.table_name IS NOT NULL THEN '?table=' || substr(st.subject, len(d.dataset) + 2)
         ELSE '' END AS link
FROM st
CROSS JOIN a
CROSS JOIN d
LEFT JOIN said s ON s.subject = st.subject AND s.rn = 1
LEFT JOIN fn f ON f.subject = st.subject
LEFT JOIN landed l ON d.dataset || '.' || l.table_name = st.subject
ORDER BY CASE st.state WHEN 'contested' THEN 0 WHEN 'stale' THEN 1 WHEN 'current' THEN 2 ELSE 3 END, subject
