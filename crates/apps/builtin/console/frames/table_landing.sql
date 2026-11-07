-- One table's landing, as lines: what landed and when, the rows the
-- recipe dropped, what the source's conventions say, and the recipe's
-- SQL. One row per line that has something to say.
WITH d AS (SELECT dataset FROM current_dataset),
n AS (
  SELECT i.rows, i.dropped_rows_count, i.imported_at,
         row_number() OVER (ORDER BY i.imported_at DESC, i.seq DESC) AS rn
  FROM imports i JOIN d ON d.dataset = i.dataset
  WHERE i.table_name = CAST($table AS VARCHAR)
  QUALIFY rn = 1),
rec AS (
  SELECT max(r.source) AS source, max(r.sql) AS sql
  FROM recipes r JOIN d ON d.dataset = r.dataset
  WHERE r.table_name = CAST($table AS VARCHAR)),
conv AS (
  SELECT g.body,
         row_number() OVER (ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g CROSS JOIN rec
  WHERE g.aspect = 'conventions' AND g.subject = rec.source AND g.actor_kind IN ('human', 'agent')),
keyed AS (SELECT body, unnest(json_keys(body)) AS key FROM conv WHERE rn = 1),
said AS (
  SELECT string_agg(key || ': ' || coalesce(json_extract_string(body, '$.' || key), json_extract(body, '$.' || key)::VARCHAR), ' · ' ORDER BY key) AS lines
  FROM keyed WHERE key <> 'system'),
lines AS (
  SELECT 0 AS ord, 'read' AS label, 'from the source ' || rec.source AS text FROM rec WHERE rec.source IS NOT NULL
  UNION ALL
  SELECT 1, 'loaded', CAST(coalesce(n.rows, 0) AS VARCHAR) || ' rows on ' || strftime(n.imported_at, '%d %b %Y at %H:%M') FROM n
  UNION ALL
  SELECT 2, 'dropped', CAST(n.dropped_rows_count AS VARCHAR) || ' rows by the load query' FROM n WHERE coalesce(n.dropped_rows_count, 0) > 0
  UNION ALL
  SELECT 4, 'the source says', s.lines FROM said s WHERE s.lines IS NOT NULL
  UNION ALL
  SELECT 5, 'the load query', rec.sql FROM rec WHERE rec.sql IS NOT NULL)
SELECT label, text
FROM lines
WHERE text IS NOT NULL AND text <> ''
ORDER BY ord
