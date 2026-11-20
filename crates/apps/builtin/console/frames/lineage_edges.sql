-- The lineage graph's edges. `m2o` (`->`) and `o2o` (`<->`): a
-- declared relationship between two tables, from the column that
-- refers to the column it refers to. `reads`: a table's or a view's
-- column to the view column that descends from it.
-- each column of each served view with each loaded column it is computed from (views_lineage());
-- a column computed from none has one row with no source
WITH m AS (
  SELECT view, target_column, split_part(i, '.', 2) AS source_table, nullif(split_part(i, '.', 3), '') AS source_column
  FROM (SELECT view, "column" AS target_column, unnest(CASE WHEN len(inputs) > 0 THEN inputs ELSE [NULL::VARCHAR] END) AS i
        FROM views_lineage(current_schema())
        WHERE view IN (SELECT view FROM view_kinds() WHERE stopped IS NULL AND served_kind(kind)))),
d AS (SELECT dataset FROM current_dataset)
SELECT substr(r.left_side, len(d.dataset) + 2) AS src,
       substr(r.right_side, len(d.dataset) + 2) AS dst,
       CASE r.op WHEN '<->' THEN 'o2o' ELSE 'm2o' END AS kind
FROM relationships r JOIN d ON d.dataset = r.dataset
UNION ALL
SELECT DISTINCT source_table || '.' || source_column AS src,
       view || '.' || target_column AS dst,
       'reads' AS kind
FROM m
WHERE source_column IS NOT NULL
