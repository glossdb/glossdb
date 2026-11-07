-- One row while any measurement in the dataset stands from before the
-- last change — a function voice landed at an earlier pin, served and
-- marked — or while one a metric's row or a witness reads was never
-- made (`owed`'s `never measured` rows). Record-class: the banner
-- appears with the write that caused it and clears when re-measure
-- lands.
WITH stale AS (
  SELECT actor, count(*) AS n FROM GLOSSARY(all => true)
  WHERE NOT current AND lower(kind) = 'measurement' GROUP BY actor),
unmade AS (SELECT subject AS actor FROM owed WHERE kind = 'never measured'),
counts AS (
  SELECT (SELECT coalesce(sum(n), 0) FROM stale) AS n,
         (SELECT count(*) FROM unmade) AS m,
         (SELECT string_agg(actor, ', ' ORDER BY actor)
          FROM (SELECT actor FROM stale UNION SELECT actor FROM unmade)) AS functions)
SELECT n, m,
       coalesce(functions, '') AS functions,
       concat_ws(', ',
         CASE WHEN n > 0 THEN CAST(n AS VARCHAR) || ' measurements are from before the last change' END,
         CASE WHEN m > 0 THEN CAST(m AS VARCHAR) || ' measurements that a metric or a test reads were never run' END)
         || ' (' || coalesce(functions, '') || ') — the numbers are current; the column roles, the slices and the test results may not be.' AS hint
FROM counts
WHERE n > 0 OR m > 0
