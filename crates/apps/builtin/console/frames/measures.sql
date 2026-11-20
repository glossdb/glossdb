-- The measures: every view that serves a series, with its chip. The
-- facts and the views have their own lists. `$stopped` picks
-- the served ones (0) or the ones their author stopped (1). The rows
-- are `view_definitions` and `view_summary()`, the catalog alone: the
-- values are on each metric's own page. The axes value is the
-- dimensions the catalog names, or why the metric serves no series:
-- what its columns still miss.
WITH asked AS (
  SELECT q.property, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.property),
decided AS (
  SELECT r.property, max(r.written_at) AS decided_at FROM review_decisions r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.property)
SELECT s.title,
       s.name,
       s.kind AS view_kind,
       s.unit,
       CASE
         WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped
         WHEN x.applicable IS FALSE THEN split_part(x.reason, ':', 1)
         WHEN x.applicable AND x.additivity IS NULL THEN 'no additivity annotated'
         ELSE coalesce(nullif(array_to_string(list_sort(x.dims), ' · '), ''), 'no axes admitted') END AS axes,
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
       '?view=' || s.name AS link
FROM view_definitions s
LEFT JOIN asked q ON q.property = s.name
LEFT JOIN decided r ON r.property = s.name
LEFT JOIN view_summary() x ON x.view = s.name
WHERE s.kind NOT IN ('scalar', 'relation')
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY name
