-- A voice check's evidence: every subject whose slots differ — the
-- witness's verdicts that are not green — with every voice on the slot
-- side by side, by actor kind, the human's first. Rows only for a
-- witness whose detector is slot_entropy.
WITH d AS (SELECT dataset FROM current_dataset),
w AS (
  SELECT name, aspect FROM witnesses WHERE name = $check AND detector = 'slot_entropy'
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
voices AS (
  SELECT g.subject, g.aspect,
         string_agg(g.actor_kind || ': ' || coalesce(json_extract_string(g.body, '$.value'), g.body::VARCHAR), ' · '
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, g.actor_id, g.seq) AS voices
  FROM glossary g JOIN d ON d.dataset = g.dataset JOIN w ON w.aspect = g.aspect
  GROUP BY g.subject, g.aspect)
SELECT a.subject,
       coalesce(v.voices, 'no voice yet') AS voices,
       CAST(round(a.score * 1000) / 1000 AS VARCHAR) AS score,
       a.band,
       CASE WHEN a.band = 'green' THEN 'ok' ELSE 'warn' END AS bcls
FROM ATTEST() a
JOIN w ON w.name = a.witness
LEFT JOIN voices v ON v.subject = a.subject AND v.aspect = a.aspect
WHERE a.band <> 'green'
ORDER BY a.score DESC, a.subject
