-- The console's tree: the dataset's sources, its tables with their
-- columns, its metrics, its views and its tests, one row per entry.
-- `section` groups the entries, `parent` names the table a column
-- belongs to (empty otherwise), `link` is the entry's page. The
-- component nests the rows; the order here is the order shown.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
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
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
SELECT section, parent, name, label, link
FROM (
  SELECT 1 AS s, 'Sources' AS section, '' AS parent, source AS name, source AS label,
         (SELECT * FROM base) || 'glossary?source=' || source AS link, 0 AS o
  FROM (SELECT DISTINCT source FROM recipe)
  UNION ALL
  SELECT 2, 'Tables', '', table_name, table_name,
         (SELECT * FROM base) || 'glossary?table=' || table_name, 0
  FROM loaded
  UNION ALL
  SELECT 2, 'Tables', table_name, table_name || '.' || column_name, column_name,
         (SELECT * FROM base) || 'glossary?column=' || table_name || '.' || column_name, ordinal_position
  FROM cols
  UNION ALL
  SELECT 3, 'Metrics', '', name, name,
         (SELECT * FROM base) || 'metrics?metric=' || name, 0
  FROM surfaces WHERE kind NOT IN ('scalar', 'relation')
  UNION ALL
  SELECT 4, 'Views', '', name, name,
         (SELECT * FROM base) || 'metrics?metric=' || name || '&kind=' || kind, 0
  FROM surfaces WHERE kind IN ('scalar', 'relation')
  UNION ALL
  SELECT 5, 'Tests', '', name, name,
         (SELECT * FROM base) || 'quality?check=' || name || '&kind=' || CASE detector
           WHEN 'band_breach' THEN 'corridor'
           WHEN 'slot_entropy' THEN 'voices'
           WHEN 'rate_tolerance' THEN 'rate'
           ELSE 'verdicts' END, 0
  FROM test)
ORDER BY s, CASE WHEN parent = '' THEN name ELSE parent END, parent <> '', o, name
