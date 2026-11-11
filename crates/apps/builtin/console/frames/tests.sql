-- The tests: the adjudication plane, read whole and folded
-- per test. Each test with a detector is one row — what it asks,
-- in words; its detector and threshold; its results counted by state;
-- its worst state as the chip — linked to the test's own page, where
-- the evidence is listed by the detector's kind.
WITH v AS (
  SELECT a.test, a.state,
         CASE a.state WHEN 'red' THEN 4 WHEN 'orange' THEN 3 WHEN 'yellow' THEN 2 WHEN 'error' THEN 1 ELSE 0 END AS severity
  FROM TESTS() a),
w AS (SELECT * FROM tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
folded AS (
  SELECT w.name AS test, w.aspect, w.detector, w.threshold,
         count(v.state) AS n,
         count(*) FILTER (WHERE v.state = 'green') AS green,
         count(*) FILTER (WHERE v.state = 'yellow') AS yellow,
         count(*) FILTER (WHERE v.state = 'orange') AS orange,
         count(*) FILTER (WHERE v.state = 'red') AS red,
         count(*) FILTER (WHERE v.state = 'error') AS errors,
         coalesce(max(v.severity), -1) AS worst
  FROM w LEFT JOIN v ON v.test = w.name
  WHERE w.detector IS NOT NULL
  GROUP BY w.name, w.aspect, w.detector, w.threshold)
SELECT test,
       CASE detector
         WHEN 'value_entropy' THEN 'Do the annotations on ' || aspect || ' agree, column by column?'
         WHEN 'rate_tolerance' THEN 'Does the measured breach rate on ' || aspect || ' stay within the tolerance written for it?'
         ELSE 'Does ' || detector || ' pass on ' || aspect || '?' END AS asks,
       detector || coalesce(' @ ' || CAST(threshold AS VARCHAR), '') || ' on ' || aspect AS expectation,
       n, green, yellow, orange, red, errors,
       CASE WHEN n = 0 THEN 'no result yet' ELSE concat_ws(' · ',
           CASE WHEN red > 0 THEN CAST(red AS VARCHAR) || ' red' END,
           CASE WHEN orange > 0 THEN CAST(orange AS VARCHAR) || ' orange' END,
           CASE WHEN yellow > 0 THEN CAST(yellow AS VARCHAR) || ' yellow' END,
           CASE WHEN errors > 0 THEN CAST(errors AS VARCHAR) || ' error' END,
           CASE WHEN green > 0 THEN CAST(green AS VARCHAR) || ' green' END) END AS measured,
       CASE worst WHEN 4 THEN 'red' WHEN 3 THEN 'orange' WHEN 2 THEN 'yellow' WHEN 1 THEN 'error' WHEN 0 THEN 'green' ELSE 'none' END AS state,
       CASE WHEN worst = 0 THEN 'ok' WHEN worst < 0 THEN '' ELSE 'warn' END AS scls,
       '?test=' || test || '&kind=' || CASE detector
         WHEN 'value_entropy' THEN 'values'
         WHEN 'rate_tolerance' THEN 'rate'
         ELSE 'results' END AS link
FROM folded
ORDER BY worst DESC, test
