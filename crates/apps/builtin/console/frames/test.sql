-- One test: what it checks, in the words of the property it is
-- declared on; how it scores; and its results as TESTS() holds them
-- now, counted by state, with the worst as the page's state.
WITH w AS (
  SELECT * FROM tests WHERE name = $test
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
v AS (
  SELECT a.state, a.score, a.computed_at, a.current,
         CASE a.state WHEN 'red' THEN 4 WHEN 'orange' THEN 3 WHEN 'yellow' THEN 2 WHEN 'error' THEN 1 ELSE 0 END AS severity
  FROM TESTS() a WHERE a.test = $test),
about AS (
  SELECT json_extract_string(a.schema, '$.description') AS description
  FROM aspects a JOIN w ON w.aspect = a.name
  QUALIFY row_number() OVER (ORDER BY a.begin_snapshot DESC) = 1),
folded AS (
  SELECT count(v.state) AS n,
         count(*) FILTER (WHERE v.state = 'green') AS green,
         count(*) FILTER (WHERE v.state = 'yellow') AS yellow,
         count(*) FILTER (WHERE v.state = 'orange') AS orange,
         count(*) FILTER (WHERE v.state = 'red') AS red,
         count(*) FILTER (WHERE v.state = 'error') AS errors,
         coalesce(max(v.severity), -1) AS worst,
         max(v.score) AS score,
         max(v.computed_at) AS measured_at,
         coalesce(bool_and(v.current), true) AS current
  FROM v)
SELECT w.name AS test,
       w.aspect,
       coalesce((SELECT description FROM about), 'The property ' || w.aspect || '.') AS asks,
       CASE w.detector
         WHEN 'value_entropy' THEN 'Compares the annotations of the agent and of people on each asset. Green while they agree.'
         WHEN 'rate_tolerance' THEN 'A function measures the share of rows that fail. Green while it stays within the tolerance: '
              || fmt_number(coalesce(w.threshold, 0) * 100) || '% unless an asset states its own.'
         ELSE coalesce('Scored by the function ' || w.detector
              || coalesce(', threshold ' || CAST(w.threshold AS VARCHAR), '') || '.',
              'No scoring function: the test only says who may annotate the property.') END AS scoring,
       CASE WHEN f.n = 0 THEN 'no result yet' ELSE concat_ws(' · ',
           CASE WHEN f.red > 0 THEN CAST(f.red AS VARCHAR) || ' red' END,
           CASE WHEN f.orange > 0 THEN CAST(f.orange AS VARCHAR) || ' orange' END,
           CASE WHEN f.yellow > 0 THEN CAST(f.yellow AS VARCHAR) || ' yellow' END,
           CASE WHEN f.errors > 0 THEN CAST(f.errors AS VARCHAR) || ' error' END,
           CASE WHEN f.green > 0 THEN CAST(f.green AS VARCHAR) || ' green' END) END AS measured,
       CASE f.worst WHEN 4 THEN 'red' WHEN 3 THEN 'orange' WHEN 2 THEN 'yellow' WHEN 1 THEN 'error' WHEN 0 THEN 'green' ELSE 'not run' END AS state,
       CASE WHEN f.worst = 0 THEN 'ok' WHEN f.worst < 0 THEN '' ELSE 'warn' END AS scls,
       coalesce(strftime(f.measured_at, '%Y-%m-%d %H:%M'), 'not yet') AS "at",
       CASE WHEN f.current THEN '' ELSE ' · some computed before the newest change' END AS stale
FROM w CROSS JOIN folded f
