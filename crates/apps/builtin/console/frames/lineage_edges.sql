-- The lineage graph's edges: every declared key edge of the bound
-- dataset, spelled without the dataset's prefix, and for every current
-- grounding the table columns its served fields descend from. `m2o` is
-- `->`, `o2o` is `<->`, `reads` is a grounding reading the column.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT substr(r.left_side, len(d.dataset) + 2) AS src,
       substr(r.right_side, len(d.dataset) + 2) AS dst,
       CASE r.op WHEN '<->' THEN 'o2o' ELSE 'm2o' END AS kind
FROM relationships r JOIN d ON d.dataset = r.dataset
UNION ALL
SELECT source AS src,
       metric || '.' || field AS dst,
       'reads' AS kind
FROM metric_sources()
WHERE field IS NOT NULL
