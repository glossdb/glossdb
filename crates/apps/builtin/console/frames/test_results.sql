-- One test's results, one row per asset it ran on, worst first: the
-- state and score as TESTS() holds them, when it was computed, whether
-- it is from before the newest change, and what the test compared.
-- `seen` depends on the scoring function. For rate_tolerance: the
-- tolerance and the breach rate a measurement found, with the
-- measurement's finding. For value_entropy: every annotation on the
-- asset, a person's first. Otherwise the test's error, if it has one.
-- `link` opens the asset's page.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
w AS (
  SELECT name, aspect, detector, threshold FROM tests WHERE name = $test
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
views AS (SELECT name FROM view_definitions),
said AS (
  SELECT g.subject,
         string_agg(CASE g.actor_kind WHEN 'human' THEN 'a person' ELSE 'the agent' END || ': '
                      || coalesce(json_extract_string(g.body, '$.value'), g.body::VARCHAR), ' · '
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq) AS annotations,
         max(json_extract(g.body, '$.tolerance')::DOUBLE) AS tolerance
  FROM glossary g JOIN d ON d.dataset = g.dataset JOIN w ON w.aspect = g.aspect
  WHERE g.actor_kind IN ('human', 'agent')
  GROUP BY g.subject),
measured AS (
  SELECT m.subject,
         json_extract(m.value, '$.breach_rate')::DOUBLE AS rate,
         json_extract_string(m.value, '$.finding') AS finding,
         json_extract_string(m.value, '$.reason') AS reason
  FROM measurements m JOIN d ON d.dataset = m.dataset JOIN w ON w.aspect = m.aspect
  QUALIFY row_number() OVER (PARTITION BY m.subject ORDER BY m.seq DESC) = 1),
r AS (
  SELECT a.*, substr(a.subject, len(d.dataset) + 2) AS path FROM TESTS() a CROSS JOIN d WHERE a.test = $test)
SELECT CASE WHEN r.path = '' THEN 'the dataset' ELSE r.path END AS asset,
       CASE WHEN r.path = '' THEN ''
            WHEN strpos(r.path, '.') > 0 AND split_part(r.path, '.', 1) IN (SELECT name FROM views)
              THEN (SELECT b FROM base) || 'views?view=' || split_part(r.path, '.', 1)
            WHEN strpos(r.path, '.') > 0 THEN (SELECT b FROM base) || 'glossary?column=' || r.path
            WHEN r.path IN (SELECT name FROM views) THEN (SELECT b FROM base) || 'views?view=' || r.path
            ELSE (SELECT b FROM base) || 'glossary?table=' || r.path END AS link,
       coalesce(r.error,
         CASE w.detector
           WHEN 'rate_tolerance' THEN concat_ws(' · ',
             CASE WHEN m.rate IS NULL THEN coalesce(m.reason, 'nothing measured yet')
                  ELSE fmt_number(m.rate * 100) || '% of rows fail' END,
             'tolerance ' || fmt_number(coalesce(s.tolerance, w.threshold, 0) * 100) || '%',
             m.finding)
           WHEN 'value_entropy' THEN coalesce(s.annotations, 'no annotation yet')
           ELSE coalesce(m.finding, m.reason, '') END) AS seen,
       coalesce(fmt_number(r.score), '') AS score,
       coalesce(strftime(r.computed_at, '%Y-%m-%d %H:%M'), '') AS "at",
       CASE WHEN r.current THEN '' ELSE 'computed before the newest change' END AS outdated,
       r.state,
       CASE WHEN r.state = 'green' THEN 'ok' ELSE 'warn' END AS scls
FROM r CROSS JOIN w
LEFT JOIN said s ON s.subject = r.subject
LEFT JOIN measured m ON m.subject = r.subject
ORDER BY CASE r.state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'error' THEN 2 WHEN 'yellow' THEN 3 ELSE 4 END, asset
