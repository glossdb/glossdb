-- An object's history, newest first: every annotation ever written on
-- the object or its columns, the ones later replaced included, and
-- every load of the object when it is a table.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT "at", what, subject, who, value FROM (
  SELECT g.written_at AS ts,
         strftime(g.written_at, '%Y-%m-%d %H:%M') AS at,
         'annotated ' || g.aspect AS what,
         substr(g.subject, len(d.dataset) + 2) AS subject,
         CASE g.actor_kind WHEN 'human' THEN 'a person' WHEN 'agent' THEN 'the agent' ELSE g.actor_kind END
           || coalesce(' · ' || g.actor_id, '') AS who,
         left(g.body::VARCHAR, 160) || CASE WHEN length(g.body::VARCHAR) > 160 THEN '…' ELSE '' END AS value
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.subject = d.dataset || '.' || CAST($subject AS VARCHAR)
     OR g.subject LIKE d.dataset || '.' || CAST($subject AS VARCHAR) || '.%'
  UNION ALL
  SELECT i.imported_at,
         strftime(i.imported_at, '%Y-%m-%d %H:%M'),
         'loaded (' || i.mode || ')',
         i.table_name,
         'the load query',
         fmt_number(i.rows) || ' rows'
           || CASE WHEN coalesce(i.dropped_rows_count, 0) > 0 THEN ', ' || fmt_number(i.dropped_rows_count) || ' dropped' ELSE '' END
  FROM imports i JOIN d ON d.dataset = i.dataset
  WHERE i.table_name = CAST($subject AS VARCHAR))
ORDER BY ts DESC
