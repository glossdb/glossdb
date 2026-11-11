-- The lineage graph's edges, in the direction the data flows. `loads`:
-- a source to the table its load query produces, node to node.
-- `reads`: a table's or a view's column to the view column that
-- descends from it.
WITH d AS (SELECT dataset FROM current_dataset),
recipe AS (
  SELECT r.table_name, r.source
  FROM recipes r JOIN d ON d.dataset = r.dataset
  QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.seq DESC) = 1),
loaded AS (SELECT DISTINCT i.table_name FROM imports i JOIN d ON d.dataset = i.dataset)
SELECT r.source AS src, r.table_name AS dst, 'loads' AS kind
FROM recipe r JOIN loaded l ON l.table_name = r.table_name
UNION ALL
SELECT source AS src,
       view || '.' || field AS dst,
       'reads' AS kind
FROM view_sources()
WHERE field IS NOT NULL AND source IS NOT NULL
