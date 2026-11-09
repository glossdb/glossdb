-- The tests per metric, worst first: each test on a metric and on what
-- it reads, with its state, what the check found in a sentence, who
-- declared it and whether the result still holds. A metric whose tests
-- are all green is one row saying so.
WITH d AS (SELECT dataset FROM current_dataset),
t AS (SELECT * FROM metric_tests()),
open AS (
  SELECT t.metric, t.test, t.state,
         CASE WHEN t.state IN ('red', 'orange', 'yellow') THEN 'warn' ELSE '' END AS bcls,
         coalesce(
           CASE WHEN json_extract(t.evidence, '$.pairs') IS NOT NULL AND t.state = 'red'
                THEN 'the join repeats rows on ' || list_aggregate(from_json(json_extract(t.evidence, '$.pairs'), '["VARCHAR"]'), 'string_agg', ', ') END,
           CASE WHEN json_extract(t.evidence, '$.tables') IS NOT NULL AND t.state = 'red'
                THEN 'reads ' || list_aggregate(from_json(json_extract(t.evidence, '$.tables'), '["VARCHAR"]'), 'string_agg', ', ') || ' without its validity dates' END,
           CASE WHEN t.test = 'measure_additivity_test' AND t.state = 'red' THEN 'the value does not say how it adds up' END,
           json_extract_string(t.evidence, '$.reason'),
           CASE WHEN t.state = 'not_run' THEN 'not run yet' END,
           t.test || ' on ' || substr(t.subject, len(d.dataset) + 2)) AS what,
         coalesce(t.declared_by, '') AS declared_by,
         CASE WHEN t.state <> 'not_run' AND NOT t.current THEN 'from before the last change' ELSE '' END AS stale,
         '/' || d.dataset || '/app/console/p/metrics?metric=' || t.metric AS link,
         CASE t.state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'not_run' THEN 3 END AS rank
  FROM t, d WHERE t.state <> 'green'),
clean AS (
  SELECT m.metric, count(*)::VARCHAR || ' tests' AS test, 'green' AS state, 'ok' AS bcls,
         'every test is green or accepted' AS what, '' AS declared_by, '' AS stale, (SELECT '/' || dataset || '/app/console/p/metrics?metric=' FROM d) || m.metric AS link, 9 AS rank
  FROM t m WHERE m.metric NOT IN (SELECT metric FROM open) GROUP BY m.metric)
SELECT metric, test, state, bcls, what, declared_by, stale, link
FROM (SELECT * FROM open UNION ALL SELECT * FROM clean)
ORDER BY rank, metric, test
