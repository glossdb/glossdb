-- What the vocabulary still owes, by name: every slot a witnessed fact
-- aspect is owed on that no voice has filled, grouped by aspect and,
-- under it, by table. The row opens the aspect on the Glossary tab.
WITH d AS (SELECT dataset FROM current_dataset),
a AS (SELECT name, lower(kind) AS kind FROM aspects QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
unspoken AS (
  SELECT g.aspect, CASE WHEN starts_with(g.subject, d.dataset || '.') THEN substr(g.subject, len(d.dataset) + 2) ELSE g.subject END AS subject
  FROM GLOSSARY() g JOIN a ON a.name = g.aspect CROSS JOIN d
  WHERE a.kind = 'fact' AND g.state = 'unassessed'),
named AS (
  SELECT aspect,
         CASE WHEN strpos(subject, ' -> ') > 0 THEN 'joins'
              WHEN strpos(subject, '.') > 0 THEN split_part(subject, '.', 1)
              ELSE 'whole tables' END AS grp,
         CASE WHEN strpos(subject, ' -> ') > 0 OR strpos(subject, '.') = 0 THEN subject
              ELSE split_part(subject, '.', 2) END AS name
  FROM unspoken),
grouped AS (
  SELECT aspect, grp, count(*) AS n, string_agg(name, ', ' ORDER BY name) AS names
  FROM named GROUP BY aspect, grp)
SELECT aspect,
       sum(n) AS owed,
       string_agg(grp || ': ' || names, ' · ' ORDER BY CASE grp WHEN 'whole tables' THEN 0 WHEN 'joins' THEN 2 ELSE 1 END, grp) AS names,
       '/' || d.dataset || '/app/docket/p/glossary?aspect=' || aspect AS link
FROM grouped CROSS JOIN d
GROUP BY aspect, d.dataset
ORDER BY owed DESC, aspect
