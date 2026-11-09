-- One aspect's declaration: its kind, what it holds from its schema,
-- where it is required from its grain and condition, who may speak it, the
-- test that holds on it with its detector and threshold, the
-- schema's own description where it has one, and the schema itself.
-- One row, or none for a name no aspect carries.
WITH a AS (
  SELECT name, lower(kind) AS kind, grains, condition, schema,
         CASE
           WHEN json_extract(schema, '$.properties.value.enum') IS NOT NULL
             THEN 'one of ' || array_to_string(json_extract(schema, '$.properties.value.enum')::VARCHAR[], ' · ')
           WHEN json_keys(schema, '$.properties') IS NOT NULL AND len(json_keys(schema, '$.properties')) > 0
             THEN array_to_string(json_keys(schema, '$.properties'), ', ')
           ELSE 'a JSON object' END AS holds
  FROM aspects WHERE name = CAST($aspect AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
w AS (
  SELECT string_agg(
           name || coalesce(' by ' || lower(array_to_string(actors, ', ')), '')
             || coalesce(', tested by ' || detector || coalesce(' at ' || CAST(threshold AS VARCHAR), ''), ''),
           ' · ' ORDER BY name) AS tests
  FROM (SELECT * FROM tests WHERE aspect = CAST($aspect AS VARCHAR)
        QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)),
f AS (
  SELECT string_agg(name, ', ' ORDER BY name) AS fns
  FROM (SELECT DISTINCT name FROM functions WHERE returns = CAST($aspect AS VARCHAR))),
counts AS (
  SELECT count(*) AS owed, count(*) FILTER (WHERE state <> 'missing') AS spoken,
         count(*) FILTER (WHERE state = 'conflict') AS conflict
  FROM GLOSSARY() WHERE aspect = CAST($aspect AS VARCHAR))
SELECT a.name,
       CASE a.kind WHEN 'fact' THEN 'asserted: written by the agent or a person'
                   WHEN 'view' THEN 'a view: SQL with its assumptions disclosed'
                   WHEN 'measurement' THEN 'a measurement: computed by a function, never written by hand'
                   ELSE a.kind END AS kind,
       CASE WHEN a.kind = 'view' THEN 'SQL with its assumptions disclosed, served as a view under the name'
            ELSE a.holds END AS holds,
       CASE
         WHEN a.kind = 'view' THEN 'on the dataset'
         WHEN a.grains IS NULL OR len(a.grains) = 0 THEN 'anywhere'
         WHEN len(a.grains) = 1 AND a.grains[1] = 'DATASET' THEN 'on the dataset'
         ELSE 'on a ' || array_to_string(list_transform(a.grains, lambda x: replace(lower(x), 'relationship', 'join')), ', a ') END
         || coalesce(' where ' || json_extract_string(a.condition, '$.aspect') || ' = ' || json_extract_string(a.condition, '$.value'), '')
         || coalesce(' where the type is ' || array_to_string(json_extract(a.condition, '$.type')::VARCHAR[], ' or '), '') AS owed_on,
       CASE WHEN a.kind = 'measurement' THEN coalesce('computed by ' || f.fns, 'no function returns it')
            ELSE coalesce('test ' || w.tests, 'no test: anyone may annotate, nothing scores it') END AS guard,
       CAST(c.spoken AS VARCHAR) || ' of ' || CAST(c.owed AS VARCHAR) || ' required assets carry a value'
         || CASE WHEN c.conflict > 0 THEN ', ' || CAST(c.conflict AS VARCHAR) || ' conflict' ELSE '' END AS spoken,
       coalesce(json_extract_string(a.schema, '$.description'), '') AS description,
       regexp_replace(a.schema::VARCHAR, '[[:space:]]+', ' ', 'g') AS schema
FROM a CROSS JOIN w CROSS JOIN f CROSS JOIN counts c
