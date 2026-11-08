-- A check's results, every one: subject, band and score as TESTS()
-- holds them, the worst first. A result from before the last change
-- says so.
SELECT a.subject,
       a.aspect,
       coalesce(fmt_number(a.score), '') AS score,
       coalesce(a.error, CASE WHEN a.current THEN '' ELSE 'from before the last change' END) AS note,
       a.band,
       CASE WHEN a.band = 'green' THEN 'ok' ELSE 'warn' END AS bcls
FROM TESTS() a
WHERE a.test = $check
ORDER BY CASE a.band WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'error' THEN 3 ELSE 4 END, a.subject
