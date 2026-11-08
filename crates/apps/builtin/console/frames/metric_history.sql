-- A metric's history, newest first: every version of its definition
-- and every annotation on its view's columns, the replaced ones
-- included.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT strftime(g.written_at, '%Y-%m-%d %H:%M') AS "at",
       CASE WHEN g.subject = d.dataset THEN 'defined' ELSE 'annotated ' || g.aspect END AS what,
       CASE WHEN g.subject = d.dataset THEN g.aspect ELSE substr(g.subject, len(d.dataset) + 2) END AS subject,
       CASE g.actor_kind WHEN 'human' THEN 'a person' WHEN 'agent' THEN 'the agent' ELSE g.actor_kind END
         || coalesce(' · ' || g.actor_id, '') AS who,
       left(g.body::VARCHAR, 160) || CASE WHEN length(g.body::VARCHAR) > 160 THEN '…' ELSE '' END AS value
FROM glossary g JOIN d ON d.dataset = g.dataset
WHERE (g.subject = d.dataset AND g.aspect = CAST($metric AS VARCHAR))
   OR g.subject LIKE d.dataset || '.' || CAST($metric AS VARCHAR) || '.%'
ORDER BY g.written_at DESC, g.seq DESC
