-- A validation's evidence: per subject, the authored expectation — the
-- outcome in words and the tolerance written beside it — against the
-- breach rate the check measured, and the band the detector gave the
-- pair. Rows only for a witness whose detector is rate_tolerance.
WITH d AS (SELECT dataset FROM current_dataset),
w AS (
  SELECT name, aspect, threshold FROM witnesses WHERE name = $check AND detector = 'rate_tolerance'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
slots AS (
  SELECT g.subject, g.aspect, g.actor_kind, g.body
  FROM glossary g JOIN d ON d.dataset = g.dataset JOIN w ON w.aspect = g.aspect),
expected AS (
  SELECT subject, aspect,
         max(json_extract_string(body, '$.outcome')) AS outcome,
         max(json_extract(body, '$.tolerance')::DOUBLE) AS tolerance
  FROM slots WHERE actor_kind IN ('human', 'agent') GROUP BY subject, aspect),
measured AS (
  SELECT m.subject, m.aspect, max(json_extract(m.value, '$.breach_rate')::DOUBLE) AS rate
  FROM measurements m JOIN d ON d.dataset = m.dataset JOIN w ON w.aspect = m.aspect
  GROUP BY m.subject, m.aspect)
SELECT a.subject,
       coalesce(e.outcome, 'no expectation written') AS outcome,
       coalesce('tolerance ' || CAST(e.tolerance AS VARCHAR), 'tolerance ' || coalesce(CAST(w.threshold AS VARCHAR), '0')) AS tolerance,
       coalesce('measured ' || CAST(m.rate AS VARCHAR), 'no check has spoken') AS measured,
       a.band,
       CASE WHEN a.band = 'green' THEN 'ok' ELSE 'warn' END AS bcls
FROM ATTEST() a
JOIN w ON w.name = a.witness
LEFT JOIN expected e ON e.subject = a.subject AND e.aspect = a.aspect
LEFT JOIN measured m ON m.subject = a.subject AND m.aspect = a.aspect
ORDER BY CASE a.band WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'error' THEN 3 ELSE 4 END, a.subject
