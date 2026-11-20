-- The views: every derived relation of the dataset — a VIEW property
-- declared `x-kind: relation` — with what each is and where its
-- judgment holds, by the measures frame's chip rule. `$stopped` picks the
-- served views (0) or the stopped ones (1).
WITH asked AS (
  SELECT q.property, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.property),
decided AS (
  SELECT r.property, max(r.written_at) AS decided_at FROM review_decisions r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.property)
SELECT s.title,
       s.name,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped
            ELSE coalesce(nullif(s.meaning, ''), 'no meaning annotated yet') END AS meaning,
       CASE
         WHEN s.stopped <> '' THEN 'stopped'
         WHEN coalesce(q.n, 0) > 0 THEN CAST(q.n AS VARCHAR) || ' open'
         WHEN r.decided_at IS NOT NULL THEN 'decided by a person ' || strftime(r.decided_at, '%Y-%m-%d')
         WHEN NOT s.defined THEN 'nothing written'
         ELSE 'defined' END AS status,
       CASE
         WHEN s.stopped <> '' THEN 'warn'
         WHEN coalesce(q.n, 0) > 0 THEN 'warn'
         WHEN r.decided_at IS NOT NULL THEN 'ok'
         WHEN NOT s.defined THEN 'warn'
         ELSE 'ok' END AS scls,
       '?view=' || s.name || '&kind=relation' AS link
FROM view_definitions s
LEFT JOIN asked q ON q.property = s.name
LEFT JOIN decided r ON r.property = s.name
WHERE s.kind = 'relation'
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY name
