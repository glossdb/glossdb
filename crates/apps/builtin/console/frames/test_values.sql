-- A value test's evidence: every subject whose values differ — the
-- test's results that are not green — with every value on the value
-- side by side, by actor kind, the human's first. Rows only for a
-- test whose detector is value_entropy.
WITH d AS (SELECT dataset FROM current_dataset),
w AS (
  SELECT name, aspect FROM tests WHERE name = $test AND detector = 'value_entropy'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
annotations AS (
  SELECT g.subject, g.aspect,
         string_agg(g.actor_kind || ': ' || coalesce(json_extract_string(g.body, '$.value'), g.body::VARCHAR), ' · '
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, g.actor_id, g.seq) AS annotations
  FROM glossary g JOIN d ON d.dataset = g.dataset JOIN w ON w.aspect = g.aspect
  GROUP BY g.subject, g.aspect)
SELECT a.subject,
       coalesce(v.annotations, 'no annotation yet') AS annotations,
       fmt_number(a.score) AS score,
       a.state,
       CASE WHEN a.state = 'green' THEN 'ok' ELSE 'warn' END AS scls
FROM TESTS() a
JOIN w ON w.name = a.test
LEFT JOIN annotations v ON v.subject = a.subject AND v.aspect = a.aspect
WHERE a.state <> 'green'
ORDER BY a.score DESC, a.subject
