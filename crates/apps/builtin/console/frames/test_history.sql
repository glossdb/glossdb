-- One test's declarations, newest first: each time it was declared,
-- with its detector, threshold and who may annotate.
SELECT strftime(t.declared_at, '%Y-%m-%d %H:%M') AS "at",
       'declared' AS what,
       t.aspect AS subject,
       coalesce(array_to_string(t.actors, ', '), '') AS who,
       concat_ws(' · ', coalesce(t.detector, 'no detector'), 'threshold ' || coalesce(CAST(t.threshold AS VARCHAR), 'none')) AS value
FROM tests t
WHERE t.name = CAST($check AS VARCHAR)
ORDER BY t.seq DESC
