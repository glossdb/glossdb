-- What holds among one table's columns: every identity the derivation
-- measurement found — the target, the operands, how many rows it holds
-- on and how many break it — and what the hierarchy search found, or
-- that neither has run.
WITH d AS (SELECT dataset FROM current_dataset),
tbl AS (SELECT d.dataset || '.' || CAST($table AS VARCHAR) AS subject FROM d),
m AS (
  SELECT g.aspect, g.body FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.current AND g.subject = (SELECT subject FROM tbl)
    AND g.aspect IN ('derivation_candidates', 'hierarchy_candidates')),
cands AS (
  SELECT unnest(json_extract(body, '$.candidates')::JSON[]) AS cand FROM m WHERE aspect = 'derivation_candidates'),
identities AS (
  SELECT 'identity' AS kind,
         json_extract_string(cand, '$.target') || ' = ' || json_extract_string(cand, '$.operands[0]')
           || CASE json_extract_string(cand, '$.form') WHEN 'product' THEN ' × ' ELSE ' + ' END
           || json_extract_string(cand, '$.operands[1]') AS text,
         'holds on ' || json_extract_string(cand, '$.support') || ' rows'
           || CASE WHEN json_extract(cand, '$.violations')::BIGINT > 0
                   THEN ' · ' || json_extract_string(cand, '$.violations') || ' break it'
                   ELSE ' · none break it' END AS note,
         0 AS ord
  FROM cands),
found AS (SELECT count(*) AS n FROM cands),
ran AS (
  SELECT count(*) FILTER (WHERE aspect = 'derivation_candidates') AS derivations,
         count(*) FILTER (WHERE aspect = 'hierarchy_candidates') AS hierarchies,
         max(CASE WHEN aspect = 'hierarchy_candidates' THEN json_array_length(body, '$.candidates') END) AS trees
  FROM m),
searched AS (
  SELECT 'identities' AS kind,
         CASE WHEN r.derivations = 0 THEN 'identities not yet searched'
              WHEN f.n = 0 THEN 'no identity holds among the columns'
              ELSE '' END AS text,
         '' AS note, 1 AS ord
  FROM ran r CROSS JOIN found f),
hierarchies AS (
  SELECT 'hierarchies' AS kind,
         CASE WHEN r.hierarchies = 0 THEN 'hierarchies not yet searched'
              ELSE CAST(coalesce(r.trees, 0) AS VARCHAR) || ' hierarchies found among the columns' END AS text,
         '' AS note, 2 AS ord
  FROM ran r)
SELECT kind, text, note
FROM (SELECT * FROM identities UNION ALL SELECT * FROM searched UNION ALL SELECT * FROM hierarchies)
WHERE text <> ''
ORDER BY ord, text
