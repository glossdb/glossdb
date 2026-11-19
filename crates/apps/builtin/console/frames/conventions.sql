-- The sources: for every source a recipe of this dataset reads, what an
-- onboarding learned about the system that wrote the export — the
-- conventions deposit, its `system` entry as the line under the name
-- and every other key folded as a line. A person's entry outranks the
-- agent's, the newest wins.
WITH d AS (SELECT dataset FROM current_dataset),
srcs AS (SELECT DISTINCT r.source FROM recipes r JOIN d ON d.dataset = r.dataset),
c AS (
  SELECT g.subject AS source, g.body
  FROM ranked_annotations g
  WHERE g.aspect = 'conventions' AND g.subject IN (SELECT source FROM srcs) AND g.rank = 1),
keyed AS (SELECT source, body, unnest(json_keys(body)) AS key FROM c),
lines AS (
  SELECT source,
         string_agg(key || '  ·  ' || coalesce(json_extract_string(body, '$.' || key), json_extract(body, '$.' || key)::VARCHAR), chr(10) ORDER BY key) AS lines
  FROM keyed WHERE key <> 'system' GROUP BY source)
SELECT s.source,
       coalesce(json_extract_string(c.body, '$.system'), 'no conventions entry yet') AS system,
       coalesce(l.lines, '') AS lines
FROM srcs s
LEFT JOIN c ON c.source = s.source
LEFT JOIN lines l ON l.source = s.source
ORDER BY source
