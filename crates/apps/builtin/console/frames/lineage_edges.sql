-- The lineage graph's edges. `m2o` (`->`) and `o2o` (`<->`): a
-- declared relationship between two tables, from the column that
-- refers to the column it refers to. `reads`: a table's or a view's
-- column to the view column that descends from it.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT substr(r.left_side, len(d.dataset) + 2) AS src,
       substr(r.right_side, len(d.dataset) + 2) AS dst,
       CASE r.op WHEN '<->' THEN 'o2o' ELSE 'm2o' END AS kind
FROM relationships r JOIN d ON d.dataset = r.dataset
UNION ALL
SELECT DISTINCT source_table || '.' || source_column AS src,
       view || '.' || target_column AS dst,
       'reads' AS kind
FROM column_mapping()
WHERE source_column IS NOT NULL
