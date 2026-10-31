-- The sources: for every source a recipe of this dataset reads, what an
-- onboarding learned about the system that wrote the export — the
-- conventions deposit, its `system` entry as the line under the name
-- and every other key folded as a line. A person's entry outranks the
-- agent's, the newest wins.
WITH d AS (SELECT dataset FROM current_dataset),
srcs AS (SELECT DISTINCT r.source FROM recipes r JOIN d ON d.dataset = r.dataset),
c AS (
  SELECT g.subject AS source, g.body,
         row_number() OVER (PARTITION BY g.subject
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, g.seq DESC) AS rn
  FROM glossary g
  WHERE g.aspect = 'conventions' AND g.subject IN (SELECT source FROM srcs) AND g.actor_kind IN ('human', 'agent')),
keyed AS (SELECT source, body, unnest(json_keys(body)) AS key FROM c WHERE rn = 1),
lines AS (
  SELECT source,
         string_agg(key || '  ·  ' || coalesce(json_extract_string(body, '$.' || key), json_extract(body, '$.' || key)::VARCHAR), chr(10) ORDER BY key) AS lines
  FROM keyed WHERE key <> 'system' GROUP BY source)
SELECT s.source,
       coalesce(json_extract_string(c.body, '$.system'), 'no conventions entry yet') AS system,
       coalesce(l.lines, '') AS lines
FROM srcs s
LEFT JOIN c ON c.source = s.source AND c.rn = 1
LEFT JOIN lines l ON l.source = s.source
ORDER BY source
