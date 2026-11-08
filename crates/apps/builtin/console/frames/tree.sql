-- The console's left nav: one row per entry, each tagged with the bar's
-- section it belongs to (`top`). The component shows the current
-- section's rows. `section` groups them under a heading (empty: the
-- section's own pages, listed first without one), `parent` names the
-- table a column belongs to (empty otherwise), `link` is the entry's
-- page. The order here is the order shown.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
root AS (SELECT '/' || dataset || '/app/console' AS r FROM d),
recipe AS (
  SELECT r.table_name, r.source
  FROM recipes r JOIN d ON d.dataset = r.dataset
  QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.seq DESC) = 1),
loaded AS (
  SELECT DISTINCT i.table_name
  FROM imports i JOIN d ON d.dataset = i.dataset),
cols AS (
  SELECT c.table_name, c.column_name, c.ordinal_position
  FROM information_schema.columns c
  JOIN d ON d.dataset = c.table_schema
  JOIN loaded l ON l.table_name = c.table_name
  WHERE c.table_catalog = current_database()),
surfaces AS (
  SELECT name, kind FROM metric_surfaces WHERE kind <> 'plan'),
test AS (
  SELECT name, aspect, detector
  FROM tests
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
pages(top, label, link, o) AS (
  SELECT 'Overview', 'Scorecard', (SELECT * FROM root), 1
  UNION ALL SELECT 'Overview', 'Model', (SELECT * FROM base) || 'model', 2
  UNION ALL SELECT 'Overview', 'History', (SELECT * FROM base) || 'history', 3
  UNION ALL SELECT 'Overview', 'Lineage', (SELECT * FROM base) || 'lineage', 4
  UNION ALL SELECT 'Catalog', 'Properties', (SELECT * FROM base) || 'glossary', 1
  UNION ALL SELECT 'Metrics', 'All metrics', (SELECT * FROM base) || 'metrics', 1
  UNION ALL SELECT 'Quality', 'All results', (SELECT * FROM base) || 'quality', 1
  UNION ALL SELECT 'Review', 'The queue', (SELECT * FROM base) || 'review', 1
  UNION ALL SELECT 'Review', 'Decisions', (SELECT * FROM base) || 'review#decisions', 2
  UNION ALL SELECT 'Data', 'Export', (SELECT * FROM base) || 'export', 1
  UNION ALL SELECT 'Data', 'Query', (SELECT * FROM base) || 'query', 2)
SELECT top, section, parent, name, label, link
FROM (
  SELECT top, 0 AS s, '' AS section, '' AS parent, label AS name, label, link, o
  FROM pages
  UNION ALL
  SELECT 'Catalog', 1, 'Sources', '', source, source,
         (SELECT * FROM base) || 'glossary?source=' || source, 0
  FROM (SELECT DISTINCT source FROM recipe)
  UNION ALL
  SELECT 'Catalog', 2, 'Tables', '', table_name, table_name,
         (SELECT * FROM base) || 'glossary?table=' || table_name, 0
  FROM loaded
  UNION ALL
  SELECT 'Catalog', 2, 'Tables', table_name, table_name || '.' || column_name, column_name,
         (SELECT * FROM base) || 'glossary?column=' || table_name || '.' || column_name, ordinal_position
  FROM cols
  UNION ALL
  SELECT 'Catalog', 3, 'Views', '', name, name,
         (SELECT * FROM base) || 'metrics?metric=' || name || '&kind=' || kind, 0
  FROM surfaces WHERE kind IN ('scalar', 'relation')
  UNION ALL
  SELECT 'Metrics', 1, 'Metrics', '', name, name,
         (SELECT * FROM base) || 'metrics?metric=' || name, 0
  FROM surfaces WHERE kind NOT IN ('scalar', 'relation')
  UNION ALL
  SELECT 'Metrics', 2, 'Single values', '', name, name,
         (SELECT * FROM base) || 'metrics?metric=' || name || '&kind=scalar', 0
  FROM surfaces WHERE kind = 'scalar'
  UNION ALL
  SELECT 'Quality', 1, 'Tests', '', name, name,
         (SELECT * FROM base) || 'quality?check=' || name || '&kind=' || CASE detector
           WHEN 'band_breach' THEN 'corridor'
           WHEN 'slot_entropy' THEN 'voices'
           WHEN 'rate_tolerance' THEN 'rate'
           ELSE 'verdicts' END, 0
  FROM test)
ORDER BY CASE top WHEN 'Overview' THEN 0 WHEN 'Catalog' THEN 1 WHEN 'Metrics' THEN 2
                  WHEN 'Quality' THEN 3 WHEN 'Review' THEN 4 ELSE 5 END,
         s, CASE WHEN s = 0 THEN o END,
         CASE WHEN parent = '' THEN name ELSE parent END, parent <> '', o, name
