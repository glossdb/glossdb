-- The views: every derived relation of the dataset — a VIEW aspect
-- declared `x-kind: relation` — with what each is and where its
-- judgment stands, by the pulse's chip rule. `$stopped` picks the
-- served views (0) or the stopped ones (1).
WITH asked AS (
  SELECT q.aspect, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.aspect),
ruled AS (
  SELECT r.aspect, max(r.written_at) AS ruled_at FROM ruling_entries r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.aspect)
SELECT s.title,
       s.name,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped
            ELSE coalesce(nullif(s.meaning, ''), 'no definitions entry yet') END AS meaning,
       CASE
         WHEN s.stopped <> '' THEN 'stopped'
         WHEN coalesce(q.n, 0) > 0 THEN CAST(q.n AS VARCHAR) || ' open'
         WHEN r.ruled_at IS NOT NULL THEN 'decided by a person ' || strftime(r.ruled_at, '%Y-%m-%d')
         WHEN NOT s.grounded THEN 'nothing written'
         ELSE 'grounded' END AS status,
       CASE
         WHEN s.stopped <> '' THEN 'warn'
         WHEN coalesce(q.n, 0) > 0 THEN 'warn'
         WHEN r.ruled_at IS NOT NULL THEN 'ok'
         WHEN NOT s.grounded THEN 'warn'
         ELSE 'ok' END AS scls,
       '?metric=' || s.name || '&kind=relation' AS link
FROM metric_surfaces s
LEFT JOIN asked q ON q.aspect = s.name
LEFT JOIN ruled r ON r.aspect = s.name
WHERE s.kind = 'relation'
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY name
