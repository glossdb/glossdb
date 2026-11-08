-- An object's test results: every result on the object, or on one of
-- its columns, worst first, each linked to its test's page.
WITH d AS (SELECT dataset FROM current_dataset),
t AS (SELECT name, detector FROM tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
SELECT substr(a.subject, len(d.dataset) + 2) AS subject,
       a.aspect,
       a.test,
       a.band,
       coalesce(fmt_number(a.score), '') AS score,
       CASE a.band WHEN 'green' THEN 'ok' WHEN 'error' THEN '' ELSE 'warn' END AS bcls,
       '/' || d.dataset || '/app/console/p/quality?check=' || a.test || '&kind=' || CASE t.detector
         WHEN 'band_breach' THEN 'corridor'
         WHEN 'slot_entropy' THEN 'voices'
         WHEN 'rate_tolerance' THEN 'rate'
         ELSE 'verdicts' END AS link
FROM TESTS() a
CROSS JOIN d
LEFT JOIN t ON t.name = a.test
WHERE a.subject = d.dataset || '.' || CAST($subject AS VARCHAR)
   OR a.subject LIKE d.dataset || '.' || CAST($subject AS VARCHAR) || '.%'
ORDER BY CASE a.band WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'error' THEN 3 ELSE 4 END,
         a.subject, a.aspect
