-- One metric surface: the recorded grounding that serves — the winning
-- slot, a human writing over the agent's — with the definitions entry's
-- unit, meaning and formula, the kind, the SQL or the stop, who wrote it
-- and when, and the statement that re-records it.
WITH a AS (
  SELECT name, schema FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
q AS (
  SELECT g.aspect, g.body, g.actor_kind, g.actor_id, g.written_at
  FROM glossary g JOIN current_dataset d ON d.dataset = g.dataset
  WHERE g.subject = d.dataset AND g.aspect = $metric AND g.actor_kind IN ('human', 'agent')
  QUALIFY row_number() OVER (PARTITION BY g.aspect, g.actor_kind ORDER BY g.seq DESC) = 1),
w AS (
  SELECT * FROM q
  QUALIFY row_number() OVER (PARTITION BY aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1),
d AS (
  SELECT g.body FROM glossary g JOIN current_dataset c ON c.dataset = g.dataset
  WHERE g.subject = c.dataset AND g.aspect = 'definitions' AND g.actor_kind IN ('human', 'agent')
  QUALIFY row_number() OVER (ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) = 1)
SELECT w.aspect,
  coalesce(json_extract_string(a.schema, '$.title'), w.aspect) AS title,
  coalesce(json_extract_string(d.body, '$.definitions.' || w.aspect || '.unit'), '') AS unit,
  coalesce(json_extract_string(d.body, '$.definitions.' || w.aspect || '.meaning'),
           'no meaning written — the definitions registry has no entry for this metric') AS meaning,
  coalesce(json_extract_string(a.schema, '$.x-kind'), '') AS mkind,
  json_extract_string(w.body, '$.sql') AS sql,
  coalesce(json_extract_string(w.body, '$.stopped'), '') AS stopped,
  concat_ws(' · ',
    coalesce(json_extract_string(a.schema, '$.title'), w.aspect),
    nullif(coalesce(json_extract_string(a.schema, '$.x-kind'), ''), ''),
    nullif(json_extract_string(d.body, '$.definitions.' || w.aspect || '.unit'), '')) AS meta,
  coalesce(json_extract_string(d.body, '$.definitions.' || w.aspect || '.formula'), 'no formula written') AS formula,
  coalesce(w.actor_id, w.actor_kind) AS actor,
  strftime(w.written_at, '%Y-%m-%d') AS written,
  'GLOSS ' || w.aspect || ' ON ' || (SELECT dataset FROM current_dataset) || ' AS $$' || w.body::VARCHAR || '$$;' AS statement
FROM w
JOIN a ON a.name = w.aspect
LEFT JOIN d ON true
