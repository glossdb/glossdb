-- The console's open band: what holds open for a human to judge,
-- straight from `open_questions` — the same rows the interface asks as
-- forms. Display only: the confidence, the link, the order. `pct` fills
-- the confidence rail.
SELECT o.conf,
       CAST(CAST(round(o.conf * 100) AS INT) AS VARCHAR) AS pct,
       CASE WHEN o.conf >= 1.0 THEN '1.00'
            ELSE '0.' || lpad(CAST(CAST(round(o.conf * 100) AS INT) AS VARCHAR), 2, '0') END AS cf,
       o.aspect AS subj,
       coalesce(o.dimension, '-') || ' · ' || o.key AS asp,
       o.assumption AS what,
       coalesce(o.basis, 'unstated') AS basis,
       coalesce(o.sibling, '') AS sibling,
       coalesce('or: ' || nullif(o.alternative, ''), '') AS rival,
       o.subject AS subj_id,
       o.aspect AS asp_id,
       o.key AS key_id,
       '/' || d.dataset || '/app/console/p/metrics?metric=' || o.aspect AS link
FROM open_questions o
JOIN current_dataset d ON d.dataset = o.dataset
ORDER BY o.conf ASC, subj, asp
