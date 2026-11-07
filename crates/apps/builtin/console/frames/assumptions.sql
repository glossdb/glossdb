-- The metric's assumptions ledger: `agent_assumptions` narrowed to this
-- metric, each row joined to its standing review decision on the declared key.
-- Full confidence renders fixed (●), less renders loose (◐). The
-- contest statement is the whole metric gloss: an assumption is a row
-- inside it, edited in place.
SELECT CASE WHEN a.conf >= 1.0 THEN '●' ELSE '◐' END AS glyph,
       CASE WHEN a.conf >= 1.0 THEN 'g-jud' ELSE 'g-fix' END AS gcls,
       a.conf,
       coalesce(a.dimension, '') AS dim,
       a.assumption AS what,
       coalesce(a.basis, '') AS basis,
       CASE
         WHEN r.stance IS NULL THEN ''
         ELSE 'decided: ' || r.stance
              || CASE WHEN coalesce(r.note, '') <> '' THEN ' — ' || r.note ELSE '' END
              || CASE WHEN a.conf < 1.0 THEN ' · not yet applied' ELSE '' END
       END AS decision,
       'GLOSS ' || a.aspect || ' ON ' || (SELECT dataset FROM current_dataset)
         || ' AS $$' || a.body::VARCHAR || '$$;' AS statement
FROM agent_assumptions a
LEFT JOIN review_decisions r
  ON r.dataset = a.dataset AND r.subject = a.subject AND r.aspect = a.aspect AND r.key = a.key
WHERE a.aspect = $metric
  AND a.dataset = (SELECT dataset FROM current_dataset)
ORDER BY a.conf, dim
