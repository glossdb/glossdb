-- The model's edges: every declared relationship of the bound dataset,
-- spelled without the dataset's prefix. `m2o` is `->`, `o2o` is `<->`.
WITH d AS (SELECT dataset FROM current_dataset)
SELECT substr(r.left_side, len(d.dataset) + 2) AS src,
       substr(r.right_side, len(d.dataset) + 2) AS dst,
       CASE r.op WHEN '<->' THEN 'o2o' ELSE 'm2o' END AS kind
FROM relationships r JOIN d ON d.dataset = r.dataset
