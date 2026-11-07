-- The harness scorecard: per property the harness requires, how many
-- assets have a value against how many need one, and how many of those
-- disagree. The workspace's own bookkeeping properties are left out.
WITH a AS (
  SELECT name, lower(kind) AS kind FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
counts AS (
  SELECT aspect, count(*) AS required,
         count(*) FILTER (WHERE state <> 'unassessed') AS known,
         count(*) FILTER (WHERE state = 'contested') AS contested,
         count(*) FILTER (WHERE state = 'stale') AS stale
  FROM GLOSSARY() GROUP BY aspect)
SELECT c.aspect,
       a.kind,
       CAST(c.known AS VARCHAR) || ' of ' || CAST(c.required AS VARCHAR) AS known,
       concat_ws(' · ',
         CASE WHEN c.contested > 0 THEN CAST(c.contested AS VARCHAR) || ' contested' END,
         CASE WHEN c.stale > 0 THEN CAST(c.stale AS VARCHAR) || ' stale' END) AS issues,
       CAST(round(c.known * 100.0 / c.required) AS BIGINT) AS share,
       CASE WHEN c.known = c.required THEN 'full' ELSE '' END AS full,
       '/' || (SELECT dataset FROM current_dataset) || '/app/console/p/glossary?aspect=' || c.aspect AS link
FROM counts c JOIN a ON a.name = c.aspect
WHERE c.required > 0
  AND a.name NOT IN ('app', 'app_page', 'app_frame', 'app_spec', 'app_release', 'review_decision', 'recipe_change')
ORDER BY c.known * 1.0 / c.required, c.aspect
