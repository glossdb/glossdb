-- A validation's evidence: per subject, the authored expectation — the
-- outcome in words and the tolerance written beside it — against the
-- breach rate the test measured, and the state the detector gave the
-- pair. Rows only for a test whose detector is rate_tolerance.
WITH d AS (SELECT dataset FROM current_dataset),
w AS (
  SELECT name, aspect, threshold FROM tests WHERE name = $test AND detector = 'rate_tolerance'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
annotations AS (
  SELECT g.subject, g.aspect, g.actor_kind, g.body
  FROM glossary g JOIN d ON d.dataset = g.dataset JOIN w ON w.aspect = g.aspect),
expected AS (
  SELECT subject, aspect,
         max(json_extract_string(body, '$.outcome')) AS outcome,
         max(json_extract(body, '$.tolerance')::DOUBLE) AS tolerance
  FROM annotations WHERE actor_kind IN ('human', 'agent') GROUP BY subject, aspect),
measured AS (
  SELECT m.subject, m.aspect, max(json_extract(m.value, '$.breach_rate')::DOUBLE) AS rate
  FROM measurements m JOIN d ON d.dataset = m.dataset JOIN w ON w.aspect = m.aspect
  GROUP BY m.subject, m.aspect)
SELECT a.subject,
       coalesce(e.outcome, 'no expectation written') AS outcome,
       coalesce('tolerance ' || CAST(e.tolerance AS VARCHAR), 'tolerance ' || coalesce(CAST(w.threshold AS VARCHAR), '0')) AS tolerance,
       coalesce('measured ' || CAST(m.rate AS VARCHAR), 'nothing measured yet') AS measured,
       a.state,
       CASE WHEN a.state = 'green' THEN 'ok' ELSE 'warn' END AS scls
FROM TESTS() a
JOIN w ON w.name = a.test
LEFT JOIN expected e ON e.subject = a.subject AND e.aspect = a.aspect
LEFT JOIN measured m ON m.subject = a.subject AND m.aspect = a.aspect
ORDER BY CASE a.state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'error' THEN 3 ELSE 4 END, a.subject
