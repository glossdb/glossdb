-- A metric's title line: its name and kind, its newest value with the
-- unit its definition names, and the period that value is for.
WITH a AS (
  SELECT name, schema FROM aspects WHERE name = CAST($view AS VARCHAR)
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
defs AS (SELECT unit FROM view_definitions WHERE name = CAST($view AS VARCHAR)),
latest AS (
  SELECT period, value FROM metric_series(unclaimed := 'skip')
  WHERE metric = CAST($view AS VARCHAR) AND dimension = ''
  QUALIFY row_number() OVER (ORDER BY period DESC) = 1)
SELECT a.name,
       coalesce(json_extract_string(a.schema, '$.title'), a.name) AS title,
       CASE coalesce(json_extract_string(a.schema, '$.x-kind'), '')
         WHEN 'scalar' THEN 'single value' WHEN 'relation' THEN 'view' ELSE 'metric' END AS kind,
       coalesce(fmt_number(l.value), '') AS latest,
       coalesce(defs.unit, '') AS unit,
       coalesce('for ' || strftime(l.period, '%Y-%m-%d'), '') AS period
FROM a
LEFT JOIN defs ON true
LEFT JOIN latest l ON true
