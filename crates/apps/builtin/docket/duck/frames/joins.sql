-- The joins: every declared relationship with what the record says of
-- it — the meaning entry on the pair path — and what the coherence
-- measurement found: every row resolving, or how many do not. Two page
-- params narrow the list: `table` to a table's joins, `column` to a
-- column's. Endpoints are shown without the dataset's prefix.
WITH d AS (SELECT dataset FROM current_dataset),
coh AS (
  SELECT json_extract_string(rel, '$.relationship') AS rel,
         json_extract(rel, '$.orphans')::BIGINT AS orphans,
         json_extract(rel, '$.filled')::BIGINT AS filled
  FROM (SELECT unnest(json_extract(g.body, '$.relationships')::JSON[]) AS rel
        FROM GLOSSARY(all => true) g
        WHERE lower(g.kind) = 'measurement' AND g.current AND g.aspect = 'relationship_coherence')),
m AS (
  SELECT g.subject, json_extract_string(g.body, '$.value') AS meaning, g.actor_kind,
         row_number() OVER (PARTITION BY g.subject
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect = 'meaning' AND strpos(g.subject, ' -> ') > 0 AND g.actor_kind IN ('human', 'agent')),
rels AS (
  SELECT r.left_side, r.op, r.right_side,
         substr(r.left_side, len(d.dataset) + 2) AS left_path,
         substr(r.right_side, len(d.dataset) + 2) AS right_path
  FROM relationships r JOIN d ON d.dataset = r.dataset)
SELECT r.left_path || ' → ' || r.right_path AS rel,
       coalesce(m.meaning, '') AS meaning,
       CASE WHEN m.actor_kind = 'human' THEN 'ruled' ELSE '' END AS mark,
       CASE WHEN c.rel IS NULL THEN 'not yet measured'
            WHEN c.orphans = 0 THEN 'every row resolves'
            ELSE CAST(c.orphans AS VARCHAR) || ' of ' || CAST(c.filled AS VARCHAR)
              || ' rows without a ' || split_part(r.right_path, '.', 1) END AS coherence,
       coalesce(c.orphans, 0) AS orphans,
       '?table=' || split_part(r.left_path, '.', 1) AS link
FROM rels r
LEFT JOIN coh c ON c.rel = r.left_side || ' ' || r.op || ' ' || r.right_side
LEFT JOIN m ON m.subject = r.left_side || ' ' || r.op || ' ' || r.right_side AND m.rn = 1
WHERE (coalesce(CAST($table AS VARCHAR), '') = ''
       OR split_part(r.left_path, '.', 1) = CAST($table AS VARCHAR)
       OR split_part(r.right_path, '.', 1) = CAST($table AS VARCHAR))
  AND (coalesce(CAST($column AS VARCHAR), '') = ''
       OR r.left_path = CAST($column AS VARCHAR)
       OR r.right_path = CAST($column AS VARCHAR))
ORDER BY orphans DESC, rel
