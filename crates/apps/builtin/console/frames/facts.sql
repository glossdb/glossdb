-- The facts: every VIEW aspect declared `x-kind: scalar` with the one
-- number its metric definition serves (`fact_values()`) and an as-of: the
-- newest load of the tables the metric definition reads. Status and colour
-- follow the pulse's rule. `$stopped` picks the served facts (0) or
-- the stopped ones (1).
WITH asked AS (
  SELECT q.aspect, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.aspect),
ruled AS (
  SELECT r.aspect, max(r.written_at) AS ruled_at FROM review_decisions r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.aspect),
reads AS (SELECT DISTINCT metric, table_name AS t FROM metric_sources() WHERE table_name IS NOT NULL),
landed AS (
  SELECT i.table_name, max(i.imported_at) AS landed_at
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset GROUP BY i.table_name),
as_of AS (SELECT r.metric, max(l.landed_at) AS landed_at FROM reads r JOIN landed l ON l.table_name = r.t GROUP BY r.metric)
SELECT s.name,
       s.title,
       s.unit,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped ELSE s.meaning END AS meaning,
       f.value,
       coalesce(f.reason, '') AS note,
       coalesce('as of ' || strftime(a.landed_at, '%Y-%m-%d %H:%M'), '') AS asof,
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
       '?metric=' || s.name || '&kind=scalar' AS link
FROM metric_surfaces s
LEFT JOIN fact_values() f ON f.metric = s.name
LEFT JOIN as_of a ON a.metric = s.name
LEFT JOIN asked q ON q.aspect = s.name
LEFT JOIN ruled r ON r.aspect = s.name
WHERE s.kind = 'scalar'
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY s.name
