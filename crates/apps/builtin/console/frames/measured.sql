-- What the functions measured: one row per loaded measurement property
-- with what it found, in words from its own body, how many subjects it
-- reached and when. The kits' measurements have a sentence; another
-- is counted.
WITH m AS (
  SELECT g.subject, g.property, g.body, g.written_at
  FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.current),
rels AS (
  SELECT body AS rel FROM m
  WHERE property = 'relationship_coherence' AND json_extract_string(body, '$.relationship') IS NOT NULL),
coherence AS (
  SELECT 'relationship_coherence' AS property,
         CAST(count(*) AS VARCHAR) || CASE WHEN count(*) = 1 THEN ' join' ELSE ' joins' END AS subjects,
         CAST(count(*) FILTER (WHERE json_extract(rel, '$.orphans')::BIGINT = 0) AS VARCHAR) || ' of '
           || CAST(count(*) AS VARCHAR) || ' joins resolve every row.'
           || coalesce(' ' || string_agg(
                json_extract_string(rel, '$.relationship') || ' leaves ' || json_extract_string(rel, '$.orphans')
                  || ' of ' || json_extract_string(rel, '$.filled') || ' rows', '; ')
                FILTER (WHERE json_extract(rel, '$.orphans')::BIGINT > 0) || '.', '') AS found
  FROM rels
  HAVING count(*) > 0),
temporal AS (
  SELECT 'temporal_profile' AS property,
         CAST(count(*) AS VARCHAR) || CASE WHEN count(*) = 1 THEN ' date column' ELSE ' date columns' END AS subjects,
         string_agg(
           subject || ': ' || coalesce(json_extract_string(body, '$.granularity'), 'no grain found')
             || coalesce(', ' || json_extract_string(body, '$.completeness.actual') || ' of ' || json_extract_string(body, '$.completeness.expected') || ' periods', '')
             || coalesce(', ' || json_extract_string(body, '$.gaps.count') || ' gaps', ''),
           '; ' ORDER BY subject) || '.' AS found
  FROM m WHERE property = 'temporal_profile'
  HAVING count(*) > 0),
cands AS (
  SELECT subject, unnest(json_extract(body, '$.candidates')::JSON[]) AS cand FROM m WHERE property = 'derivation_candidates'),
derivations AS (
  SELECT 'derivation_candidates' AS property,
         CAST(count(DISTINCT subject) AS VARCHAR) || CASE WHEN count(DISTINCT subject) = 1 THEN ' table' ELSE ' tables' END AS subjects,
         string_agg(
           subject || ': ' || json_extract_string(cand, '$.target') || ' = '
             || json_extract_string(cand, '$.operands[0]')
             || CASE json_extract_string(cand, '$.form') WHEN 'product' THEN ' × ' ELSE ' + ' END
             || json_extract_string(cand, '$.operands[1]')
             || ' holds on ' || json_extract_string(cand, '$.support') || ' rows, '
             || json_extract_string(cand, '$.violations') || ' break it',
           '; ' ORDER BY subject) || '.' AS found
  FROM cands
  HAVING count(*) > 0),
collisions AS (
  SELECT 'definition_collisions' AS property, 'the dataset' AS subjects,
         json_extract_string(body, '$.definitions') || ' metric definitions, '
           || CAST(json_array_length(body, '$.collisions') AS VARCHAR) || ' serving one name differently.' AS found
  FROM m WHERE property = 'definition_collisions'),
candidates AS (
  SELECT 'relationship_candidates' AS property, 'the dataset' AS subjects,
         CAST(json_array_length(body, '$.candidates') AS VARCHAR) || ' candidate joins found in the data.' AS found
  FROM m WHERE property = 'relationship_candidates'),
worded AS (
  SELECT * FROM coherence
  UNION ALL SELECT * FROM temporal
  UNION ALL SELECT * FROM derivations
  UNION ALL SELECT * FROM collisions
  UNION ALL SELECT * FROM candidates),
others AS (
  SELECT property,
         CAST(count(*) AS VARCHAR) || CASE WHEN count(*) = 1 THEN ' subject' ELSE ' subjects' END AS subjects,
         '' AS found
  FROM m
  WHERE property NOT IN (SELECT property FROM worded)
  GROUP BY property),
every AS (SELECT * FROM worded UNION ALL SELECT * FROM others),
a AS (SELECT name, lower(kind) AS kind FROM properties QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
backlog AS (
  SELECT g.property, count(*) FILTER (WHERE g.state = 'missing') AS unannotated
  FROM GLOSSARY() g JOIN a ON a.name = g.property
  WHERE a.kind = 'measurement'
  GROUP BY g.property),
loaded AS (SELECT property, max(written_at) AS newest FROM m GROUP BY property)
SELECT e.property,
       e.subjects || CASE WHEN coalesce(o.unannotated, 0) > 0 THEN ', ' || CAST(o.unannotated AS VARCHAR) || ' not yet' ELSE '' END AS subjects,
       e.found,
       coalesce(strftime(t.newest, '%d %b %Y %H:%M'), '') AS "at"
FROM every e
LEFT JOIN backlog o ON o.property = e.property
LEFT JOIN loaded t ON t.property = e.property
ORDER BY CASE e.property WHEN 'relationship_coherence' THEN 0 WHEN 'temporal_profile' THEN 1
                       WHEN 'derivation_candidates' THEN 2 WHEN 'definition_collisions' THEN 4
                       WHEN 'relationship_candidates' THEN 5 ELSE 8 END, e.property
