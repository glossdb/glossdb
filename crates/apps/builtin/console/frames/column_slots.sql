-- One column's values, every one: each authored aspect with every value
-- on it — a person's first, then the agent's — its value in words, who
-- spoke, when, and the value's standing from the collapsed read; each
-- measurement a function loaded, summarised from its body; and each
-- value the catalog owes and nobody filled, said so.
WITH d AS (SELECT dataset FROM current_dataset),
subj AS (SELECT d.dataset || '.' || CAST($column AS VARCHAR) AS subject FROM d),
states AS (SELECT aspect, state FROM GLOSSARY() WHERE subject = (SELECT subject FROM subj)),
said AS (
  SELECT g.aspect, g.actor_kind, g.actor_id, g.body, g.written_at,
         row_number() OVER (PARTITION BY g.aspect
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.subject = (SELECT subject FROM subj) AND g.actor_kind IN ('human', 'agent')),
authored AS (
  SELECT s.aspect, 'said' AS kind,
         CASE s.aspect
           WHEN 'unit' THEN json_extract_string(s.body, '$.value') || coalesce(', varying by ' || json_extract_string(s.body, '$.source_column'), '')
           WHEN 'behavior' THEN json_extract_string(s.body, '$.value') || coalesce(' — ' || json_extract_string(s.body, '$.grounds'), '')
           WHEN 'dimension' THEN json_extract_string(s.body, '$.value') || coalesce(' — ' || json_extract_string(s.body, '$.grounds'), '')
           WHEN 'meaning' THEN json_extract_string(s.body, '$.value') || coalesce(' (the term: ' || json_extract_string(s.body, '$.term') || ')', '')
           ELSE coalesce(json_extract_string(s.body, '$.value'), substr(s.body::VARCHAR, 1, 200)) END AS value,
         CASE s.actor_kind WHEN 'human' THEN 'a person' WHEN 'agent' THEN 'the agent' ELSE s.actor_kind END AS voice,
         coalesce(s.actor_id, '') AS actor,
         CASE WHEN s.rn = 1 THEN coalesce(st.state, 'current') ELSE 'outranked' END AS state,
         s.written_at AS spoken_at,
         s.rn
  FROM said s LEFT JOIN states st ON st.aspect = s.aspect),
measured AS (
  SELECT g.aspect, 'measured' AS kind,
         CASE WHEN NOT coalesce(json_extract(g.body, '$.applicable')::BOOLEAN, true)
                THEN 'not applicable' || coalesce(': ' || json_extract_string(g.body, '$.reason'), '')
           ELSE CASE g.aspect
             WHEN 'temporal_profile' THEN coalesce(json_extract_string(g.body, '$.granularity'), 'no grain found')
               || coalesce(', ' || json_extract_string(g.body, '$.completeness.actual') || ' of ' || json_extract_string(g.body, '$.completeness.expected') || ' periods', '')
               || coalesce(', ' || json_extract_string(g.body, '$.gaps.count') || ' gaps', '')
               || coalesce(', from ' || json_extract_string(g.body, '$.min') || ' to ' || json_extract_string(g.body, '$.max'), '')
             WHEN 'column_profile' THEN coalesce(json_extract_string(g.body, '$.total') || ' values', 'profiled')
               || coalesce(', ' || fmt_number(json_extract(g.body, '$.null_ratio')::DOUBLE * 100) || '% null', '')
               || coalesce(', ' || json_extract_string(g.body, '$.distinct') || ' distinct', '')
             WHEN 'outlier_profile' THEN 'outliers profiled'
             ELSE substr(g.body::VARCHAR, 1, 200) END END AS value,
         g.actor AS voice,
         g.actor AS actor,
         CASE WHEN g.current THEN 'current' ELSE 'stale' END AS state,
         g.written_at AS spoken_at,
         1 AS rn
  FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.subject = (SELECT subject FROM subj)),
a AS (
  SELECT name, lower(kind) AS kind FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
unfilled AS (
  SELECT st.aspect, CASE WHEN a.kind = 'measurement' THEN 'measured' ELSE 'said' END AS kind,
         CASE WHEN a.kind = 'measurement' THEN 'not yet measured' ELSE 'not yet annotated' END AS value,
         '' AS voice, '' AS actor, 'unassessed' AS state, CAST(NULL AS TIMESTAMP) AS spoken_at, 1 AS rn
  FROM states st JOIN a ON a.name = st.aspect
  WHERE st.state = 'unassessed'),
every AS (SELECT * FROM authored UNION ALL SELECT * FROM measured UNION ALL SELECT * FROM unfilled)
SELECT aspect, kind, value, voice, state,
       coalesce(strftime(spoken_at, '%d %b %Y %H:%M'), '') AS "at",
       CASE WHEN state = 'contested' THEN 'contested' WHEN state = 'stale' THEN 'stale'
            WHEN state = 'outranked' THEN 'outranked'
            WHEN voice = 'a person' THEN 'ruled' ELSE '' END AS mark,
       CASE WHEN state = 'contested' THEN 'v-open' WHEN state = 'stale' THEN 'v-stale'
            WHEN state = 'outranked' THEN 'v-stale'
            WHEN voice = 'a person' THEN 'v-ruled' ELSE 'v-none' END AS mcls,
       CASE WHEN state = 'contested' THEN 'the annotations differ; the test withholds the value'
            WHEN state = 'stale' THEN 'written before the column last changed'
            WHEN state = 'outranked' THEN 'a later or higher-ranked annotation wins'
            WHEN voice = 'a person' THEN 'written by ' || actor
            ELSE '' END AS mark_title
FROM every
ORDER BY CASE kind WHEN 'said' THEN 0 ELSE 1 END,
         CASE aspect WHEN 'role' THEN 0 WHEN 'meaning' THEN 1 WHEN 'unit' THEN 2 WHEN 'behavior' THEN 3 WHEN 'dimension' THEN 4 ELSE 5 END,
         aspect, rn
