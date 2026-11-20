-- The single values: every view of kind value with the one number its
-- definition serves (`fact_values()`) and an as-of: the newest load of
-- the tables the definition reads. Status and colour
-- follow the measures frame's rule. `$stopped` picks the served facts (0) or
-- the stopped ones (1).
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
asked AS (
  SELECT q.property, count(*) AS n FROM open_questions q
  JOIN current_dataset d ON d.dataset = q.dataset GROUP BY q.property),
decided AS (
  SELECT r.property, max(r.written_at) AS decided_at FROM review_decisions r
  JOIN current_dataset d ON d.dataset = r.dataset GROUP BY r.property),
reads AS (SELECT DISTINCT view, source_table AS t FROM m WHERE source_table IS NOT NULL),
loaded AS (
  SELECT i.table_name, max(i.imported_at) AS loaded_at
  FROM imports i JOIN current_dataset d ON d.dataset = i.dataset GROUP BY i.table_name),
as_of AS (SELECT r.view, max(l.loaded_at) AS loaded_at FROM reads r JOIN loaded l ON l.table_name = r.t GROUP BY r.view)
SELECT s.name,
       s.unit,
       CASE WHEN s.stopped <> '' THEN 'stopped: ' || s.stopped ELSE s.meaning END AS meaning,
       f.value,
       coalesce(f.reason, '') AS note,
       coalesce('as of ' || strftime(a.loaded_at, '%Y-%m-%d %H:%M'), '') AS asof,
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
       '?view=' || s.name || '&kind=value' AS link
FROM view_definitions s
LEFT JOIN fact_values() f ON f.view = s.name
LEFT JOIN as_of a ON a.view = s.name
LEFT JOIN asked q ON q.property = s.name
LEFT JOIN decided r ON r.property = s.name
WHERE s.kind = 'value'
  AND (s.stopped <> '') = (coalesce($stopped, '0') = '1')
ORDER BY s.name
