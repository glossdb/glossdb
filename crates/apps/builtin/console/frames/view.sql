-- One view: the stored definition that serves — the winning
-- value, a human writing over the agent's — with its kind, unit and
-- meaning as view_definitions serves them, the SQL or the stop, who
-- wrote it and when, and the statement that re-records it.
WITH w AS (
  SELECT g.property, g.body, g.actor_kind, g.actor_id, g.written_at
  FROM ranked_annotations g JOIN current_dataset d ON d.dataset = g.dataset
  WHERE g.subject = d.dataset AND g.property = $view AND g.rank = 1),
d AS (SELECT name, kind, unit, meaning FROM view_definitions WHERE name = $view)
SELECT w.property,
  coalesce(d.unit, '') AS unit,
  coalesce(nullif(d.meaning, ''), 'no meaning annotated on this view') AS meaning,
  coalesce(d.kind, '') AS view_kind,
  json_extract_string(w.body, '$.sql') AS sql,
  coalesce(json_extract_string(w.body, '$.stopped'), '') AS stopped,
  concat_ws(' · ', w.property, coalesce(d.kind, 'plain view'), nullif(d.unit, '')) AS meta,
  coalesce(w.actor_id, w.actor_kind) AS actor,
  strftime(w.written_at, '%Y-%m-%d') AS written,
  'GLOSS ' || w.property || ' ON ' || (SELECT dataset FROM current_dataset) || ' AS $$' || w.body::VARCHAR || '$$;' AS statement
FROM w
LEFT JOIN d ON true
