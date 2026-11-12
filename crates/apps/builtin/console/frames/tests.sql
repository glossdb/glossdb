-- The tests, one row each: what it checks, in the words of the
-- property it is declared on; its results counted by state; its worst
-- state. A row opens the test's page.
WITH v AS (
  SELECT a.test, a.state,
         CASE a.state WHEN 'red' THEN 4 WHEN 'orange' THEN 3 WHEN 'yellow' THEN 2 WHEN 'error' THEN 1 ELSE 0 END AS severity
  FROM TESTS() a),
w AS (SELECT * FROM tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
about AS (
  SELECT name, json_extract_string(schema, '$.description') AS description
  FROM aspects QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
folded AS (
  SELECT w.name AS test, w.aspect, w.detector, w.threshold, any_value(b.description) AS description,
         count(v.state) AS n,
         count(*) FILTER (WHERE v.state = 'green') AS green,
         count(*) FILTER (WHERE v.state = 'yellow') AS yellow,
         count(*) FILTER (WHERE v.state = 'orange') AS orange,
         count(*) FILTER (WHERE v.state = 'red') AS red,
         count(*) FILTER (WHERE v.state = 'error') AS errors,
         coalesce(max(v.severity), -1) AS worst
  FROM w LEFT JOIN v ON v.test = w.name LEFT JOIN about b ON b.name = w.aspect
  WHERE w.detector IS NOT NULL
  GROUP BY w.name, w.aspect, w.detector, w.threshold)
SELECT test,
       coalesce(description, 'The property ' || aspect || '.') AS asks,
       'on ' || aspect AS expectation,
       n, green, yellow, orange, red, errors,
       CASE WHEN n = 0 THEN 'no result yet' ELSE concat_ws(' · ',
           CASE WHEN red > 0 THEN CAST(red AS VARCHAR) || ' red' END,
           CASE WHEN orange > 0 THEN CAST(orange AS VARCHAR) || ' orange' END,
           CASE WHEN yellow > 0 THEN CAST(yellow AS VARCHAR) || ' yellow' END,
           CASE WHEN errors > 0 THEN CAST(errors AS VARCHAR) || ' error' END,
           CASE WHEN green > 0 THEN CAST(green AS VARCHAR) || ' green' END) END AS measured,
       CASE worst WHEN 4 THEN 'red' WHEN 3 THEN 'orange' WHEN 2 THEN 'yellow' WHEN 1 THEN 'error' WHEN 0 THEN 'green' ELSE 'not run' END AS state,
       CASE WHEN worst = 0 THEN 'ok' WHEN worst < 0 THEN '' ELSE 'warn' END AS scls,
       '?test=' || test || CASE WHEN detector = 'range_breach' THEN '&kind=range' ELSE '' END AS link
FROM folded
ORDER BY worst DESC, test
