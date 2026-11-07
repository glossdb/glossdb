-- The pulse: every metric surface that is a series with its chip. The
-- facts, the views and the plans have their own lists. `$stopped` picks
-- the served surfaces (0) or the ones their author stopped (1). The rows
-- are `metric_surfaces`, the record; the numbers beside them are
-- `frames/latest`, joined in the browser by `name`. The axes slot
-- carries, until the data arrives, the fact row's own reason where the
-- metric serves no series — what its columns still owe.
WITH asked AS (
  SELECT q.aspect, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.aspect),
ruled AS (
  SELECT r.aspect, max(r.written_at) AS ruled_at FROM ruling_entries r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.aspect)
SELECT s.title,
       s.name,
       s.kind AS mkind,
       s.unit,
       '' AS period,
       '—' AS latest,
       '' AS delta,
       CASE
         WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped
         WHEN x.applicable IS FALSE THEN split_part(x.reason, ':', 1)
         WHEN x.applicable AND x.behavior IS NULL THEN 'no additivity annotated'
         ELSE 'no axes admitted' END AS axes,
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
       '?metric=' || s.name AS link
FROM metric_surfaces s
LEFT JOIN asked q ON q.aspect = s.name
LEFT JOIN ruled r ON r.aspect = s.name
LEFT JOIN metric_axes() x ON x.metric = s.name
WHERE s.kind NOT IN ('scalar', 'plan', 'relation')
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY name
