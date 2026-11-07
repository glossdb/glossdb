-- The measurement aspects nobody has run: required on their subjects by
-- grain and condition, with no loaded body on any. The agent's backlog,
-- not a question for a person; folded under the measured.
WITH a AS (
  SELECT name, lower(kind) AS kind, grains, condition FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1)
SELECT g.aspect,
       'required on ' || CAST(count(*) AS VARCHAR) || ' '
         || CASE WHEN list_contains(a.grains, 'COLUMN') THEN 'columns'
                 WHEN list_contains(a.grains, 'TABLE') THEN 'tables'
                 ELSE 'subjects' END
         || coalesce(' where ' || json_extract_string(a.condition, '$.aspect') || ' = ' || json_extract_string(a.condition, '$.value'), '')
         || ', none measured' AS owed
FROM GLOSSARY() g JOIN a ON a.name = g.aspect
WHERE a.kind = 'measurement'
GROUP BY g.aspect, a.grains, a.condition
HAVING count(*) FILTER (WHERE g.state <> 'unassessed') = 0
ORDER BY g.aspect
