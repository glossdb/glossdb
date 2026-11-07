-- A metric's title line: its name and kind, its newest value with the
-- unit its definition names, and the period that value is for.
WITH a AS (
  SELECT name, schema FROM aspects WHERE name = CAST($metric AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
defs AS (
  SELECT g.body FROM glossary g JOIN current_dataset c ON c.dataset = g.dataset
  WHERE g.subject = c.dataset AND g.aspect = 'definitions' AND g.actor_kind IN ('human', 'agent')
  QUALIFY row_number() OVER (ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) = 1),
latest AS (
  SELECT period, value FROM metric_series(unclaimed := 'skip')
  WHERE metric = CAST($metric AS VARCHAR) AND dimension = ''
  QUALIFY row_number() OVER (ORDER BY period DESC) = 1)
SELECT a.name,
       coalesce(json_extract_string(a.schema, '$.title'), a.name) AS title,
       CASE coalesce(json_extract_string(a.schema, '$.x-kind'), '')
         WHEN 'scalar' THEN 'single value' WHEN 'relation' THEN 'view' WHEN 'plan' THEN 'plan' ELSE 'metric' END AS kind,
       coalesce(fmt_number(l.value), '') AS latest,
       coalesce(json_extract_string(defs.body, '$.definitions.' || a.name || '.unit'), '') AS unit,
       coalesce('for ' || strftime(l.period, '%Y-%m-%d'), '') AS period
FROM a
LEFT JOIN defs ON true
LEFT JOIN latest l ON true
