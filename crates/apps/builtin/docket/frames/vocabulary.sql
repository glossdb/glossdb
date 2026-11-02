-- The vocabulary: every declared aspect of the kind the page asks for —
-- `fact`, `query`, `measurement`, or `own` for the workspace's own
-- words — with what it holds from its schema, where it is owed from its
-- grain and condition, how many owed subjects carry a value and how
-- many are contested, who may speak it, and whether a witness judges
-- it. A row opens the aspect's page.
WITH a AS (
  SELECT name, lower(kind) AS kind, grains, condition, schema,
         CASE WHEN name IN ('app', 'app_page', 'app_frame', 'app_spec', 'app_release', 'ruling', 'recipe_change') THEN 'own'
              ELSE lower(kind) END AS side
  FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
counts AS (
  SELECT aspect, count(*) AS owed,
         count(*) FILTER (WHERE state <> 'unassessed') AS spoken,
         count(*) FILTER (WHERE state = 'contested') AS contested
  FROM GLOSSARY() GROUP BY aspect),
w AS (
  SELECT aspect,
         max(CASE WHEN detector IS NOT NULL THEN 1 ELSE 0 END) AS judged,
         max(array_to_string(speakers, ', ')) AS speakers
  FROM (SELECT * FROM witnesses QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
  GROUP BY aspect),
f AS (
  SELECT returns AS aspect, string_agg(name, ', ' ORDER BY name) AS fns
  FROM (SELECT DISTINCT name, returns FROM functions WHERE returns IS NOT NULL)
  GROUP BY returns)
SELECT a.name AS aspect,
       CASE
         WHEN a.kind = 'query' THEN 'SQL with its assumptions disclosed, served as a view under the name'
         WHEN json_extract(a.schema, '$.properties.value.enum') IS NOT NULL
           THEN 'one of ' || array_to_string(json_extract(a.schema, '$.properties.value.enum')::VARCHAR[], ' · ')
         WHEN json_keys(a.schema, '$.properties') IS NOT NULL AND len(json_keys(a.schema, '$.properties')) > 0
           THEN array_to_string(json_keys(a.schema, '$.properties'), ', ')
         WHEN json_extract_string(a.schema, '$.title') IS NOT NULL THEN json_extract_string(a.schema, '$.title')
         ELSE 'a JSON object' END AS holds,
       CASE
         WHEN a.kind = 'query' THEN 'on the dataset'
         WHEN a.grains IS NULL OR len(a.grains) = 0 THEN 'anywhere'
         WHEN len(a.grains) = 1 AND a.grains[1] = 'DATASET' THEN 'on the dataset'
         ELSE 'on a ' || array_to_string(list_transform(a.grains, lambda x: replace(lower(x), 'relationship', 'join')), ', a ') END
         || coalesce(' where ' || json_extract_string(a.condition, '$.aspect') || ' = ' || json_extract_string(a.condition, '$.value'), '')
         || coalesce(' where the type is ' || array_to_string(json_extract(a.condition, '$.type')::VARCHAR[], ' or '), '') AS owed_on,
       CAST(coalesce(c.spoken, 0) AS VARCHAR) || ' of ' || CAST(coalesce(c.owed, 0) AS VARCHAR)
         || CASE WHEN coalesce(c.contested, 0) > 0 THEN ' · ' || CAST(c.contested AS VARCHAR) || ' contested' ELSE '' END AS spoken,
       CASE WHEN coalesce(c.owed, 0) = 0 THEN 0 ELSE CAST(round(c.spoken * 100.0 / c.owed) AS BIGINT) END AS share,
       CASE WHEN coalesce(c.owed, 0) > 0 AND c.spoken = c.owed THEN 'full' ELSE '' END AS full,
       CASE
         WHEN a.kind = 'measurement' THEN coalesce(f.fns, 'no function returns it')
         WHEN w.speakers IS NOT NULL THEN replace(replace(lower(w.speakers), 'human', 'a person'), 'agent', 'the agent')
         ELSE 'the agent, a person' END
         || CASE WHEN coalesce(w.judged, 0) = 1 THEN ' · judged' ELSE '' END AS speakers,
       '?aspect=' || a.name AS link
FROM a
LEFT JOIN counts c ON c.aspect = a.name
LEFT JOIN w ON w.aspect = a.name
LEFT JOIN f ON f.aspect = a.name
WHERE a.side = CAST($kind AS VARCHAR)
ORDER BY CASE array_to_string(a.grains, ',') WHEN 'COLUMN' THEN 0 WHEN 'TABLE' THEN 1 WHEN 'TABLE,COLUMN,RELATIONSHIP' THEN 2
                                              WHEN 'RELATIONSHIP' THEN 3 WHEN 'SOURCE' THEN 4 WHEN 'DATASET' THEN 5 ELSE 6 END,
         share DESC, aspect
