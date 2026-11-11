-- A test's results, every one: subject, state and score as TESTS()
-- holds them, the worst first. A result from before the last change
-- says so.
SELECT a.subject,
       a.aspect,
       coalesce(fmt_number(a.score), '') AS score,
       coalesce(a.error, CASE WHEN a.current THEN '' ELSE 'from before the last change' END) AS note,
       a.state,
       CASE WHEN a.state = 'green' THEN 'ok' ELSE 'warn' END AS scls
FROM TESTS() a
WHERE a.test = $test
ORDER BY CASE a.state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'error' THEN 3 ELSE 4 END, a.subject
