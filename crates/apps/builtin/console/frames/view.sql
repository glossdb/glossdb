-- One view: the stored definition that serves — the winning
-- value, a human writing over the agent's — with its unit and meaning
-- as view_definitions serves them, the kind, the SQL or the stop, who
-- wrote it and when, and the statement that re-records it.
WITH a AS (
  SELECT name, schema FROM properties
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
w AS (
  SELECT g.property, g.body, g.actor_kind, g.actor_id, g.written_at
  FROM ranked_annotations g JOIN current_dataset d ON d.dataset = g.dataset
  WHERE g.subject = d.dataset AND g.property = $view AND g.rank = 1),
d AS (SELECT name, unit, meaning FROM view_definitions WHERE name = $view)
SELECT w.property,
  coalesce(json_extract_string(a.schema, '$.title'), w.property) AS title,
  coalesce(d.unit, '') AS unit,
  coalesce(nullif(d.meaning, ''), 'no meaning annotated on this view') AS meaning,
  coalesce(json_extract_string(a.schema, '$.x-kind'), '') AS view_kind,
  json_extract_string(w.body, '$.sql') AS sql,
  coalesce(json_extract_string(w.body, '$.stopped'), '') AS stopped,
  concat_ws(' · ',
    coalesce(json_extract_string(a.schema, '$.title'), w.property),
    nullif(coalesce(json_extract_string(a.schema, '$.x-kind'), ''), ''),
    nullif(d.unit, '')) AS meta,
  coalesce(w.actor_id, w.actor_kind) AS actor,
  strftime(w.written_at, '%Y-%m-%d') AS written,
  'GLOSS ' || w.property || ' ON ' || (SELECT dataset FROM current_dataset) || ' AS $$' || w.body::VARCHAR || '$$;' AS statement
FROM w
JOIN a ON a.name = w.property
LEFT JOIN d ON true
