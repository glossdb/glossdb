-- A view's title line: its name and kind, its newest value with the
-- unit its definition names, and the period that value is for.
WITH defs AS (SELECT name, kind, unit FROM view_definitions WHERE name = CAST($view AS VARCHAR)),
latest AS (
  SELECT period, value FROM metric_series(view := CAST($view AS VARCHAR), unclaimed := 'skip')
  WHERE dimension = ''
  QUALIFY row_number() OVER (ORDER BY period DESC) = 1)
SELECT defs.name,
       CASE defs.kind WHEN 'value' THEN 'single value' WHEN 'table' THEN 'view' WHEN 'metric' THEN 'metric'
                      WHEN 'rule' THEN 'rule' ELSE 'plain view' END AS kind,
       coalesce(fmt_number(l.value), '') AS latest,
       coalesce(defs.unit, '') AS unit,
       coalesce('for ' || strftime(l.period, '%Y-%m-%d'), '') AS period
FROM defs
LEFT JOIN latest l ON true
