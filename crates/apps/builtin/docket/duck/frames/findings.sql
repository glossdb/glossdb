-- The findings: every verdict that is not green from a witness, and
-- every defect a function measured — a join that leaves rows
-- unresolved, an identity that breaks. Each is a sentence from the
-- record's fields, the numbers behind it, the metrics that read the
-- subject, and a link. Worst first. A measurement proposes and never
-- judges: a measured defect carries no hue, only a verdict does.
WITH d AS (SELECT dataset FROM current_dataset),
a AS (
  SELECT name, schema FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
reads AS (
  SELECT ms.source, string_agg(DISTINCT coalesce(json_extract_string(a.schema, '$.title'), ms.metric), ', ') AS metrics
  FROM metric_sources() ms LEFT JOIN a ON a.name = ms.metric
  WHERE ms.source IS NOT NULL
  GROUP BY ms.source),
meanings AS (
  SELECT g.subject, json_extract_string(g.body, '$.value') AS meaning,
         row_number() OVER (PARTITION BY g.subject ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.aspect = 'meaning' AND g.actor_kind IN ('human', 'agent')),
w AS (SELECT * FROM witnesses QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
verdicts AS (
  SELECT v.subject, v.aspect, v.witness, v.band, v.score, v.error, v.computed_at, w.detector, w.threshold,
         CASE v.band WHEN 'red' THEN 4 WHEN 'orange' THEN 3 WHEN 'yellow' THEN 2 ELSE 1 END AS sev
  FROM ATTEST() v JOIN w ON w.name = v.witness
  WHERE w.detector IS NOT NULL AND v.band <> 'green'),
voices AS (
  SELECT g.subject, g.aspect,
         string_agg(g.actor_kind || ': ' || coalesce(json_extract_string(g.body, '$.value'), g.body::VARCHAR), ' · '
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, g.seq DESC) AS said
  FROM glossary g JOIN d ON d.dataset = g.dataset
  JOIN (SELECT DISTINCT subject, aspect FROM verdicts) v ON v.subject = g.subject AND v.aspect = g.aspect
  GROUP BY g.subject, g.aspect),
judged AS (
  SELECT v.band AS chip, 'warn' AS bcls,
         CASE v.detector
           WHEN 'slot_entropy' THEN 'The voices on ' || v.aspect || ' differ on ' || substr(v.subject, len(d.dataset) + 2) || '.'
           ELSE CASE WHEN v.band = 'error' THEN v.witness || ' could not judge ' || substr(v.subject, len(d.dataset) + 2) || '.'
                     ELSE v.witness || ' reads ' || v.band || ' on ' || substr(v.subject, len(d.dataset) + 2) || '.' END END AS headline,
         CASE v.detector
           WHEN 'slot_entropy' THEN coalesce('The slots say ' || vo.said || '. ', '')
             || 'The score is the share of extra distinct values across the slots, '
             || CAST(round(v.score * 1000) / 1000 AS VARCHAR) || ' against the threshold ' || coalesce(CAST(v.threshold AS VARCHAR), 'none')
             || '. A person''s word settles it.'
           ELSE CASE WHEN v.band = 'error' THEN coalesce(v.error, 'the detector failed without a word')
                     ELSE 'The detector ' || v.detector || ' scored ' || CAST(round(v.score * 1000) / 1000 AS VARCHAR)
                       || coalesce(' against the threshold ' || CAST(v.threshold AS VARCHAR), '') || '.' END END AS why,
         coalesce(rd.metrics, '') AS reads,
         v.witness || ' · ' || v.detector || coalesce(' @ ' || CAST(v.threshold AS VARCHAR), '') || ' on ' || v.aspect
           || ' · measured ' || strftime(v.computed_at, '%d %b %Y %H:%M') AS meta,
         '?check=' || v.witness || '&kind=' || CASE v.detector WHEN 'slot_entropy' THEN 'voices' ELSE 'verdicts' END AS link,
         'the check' AS link_text,
         CAST(v.sev AS DOUBLE) AS sev,
         CAST(v.score AS DOUBLE) AS size
  FROM verdicts v
  CROSS JOIN d
  LEFT JOIN voices vo ON vo.subject = v.subject AND vo.aspect = v.aspect
  LEFT JOIN reads rd ON d.dataset || '.' || rd.source = v.subject),
measured AS (
  SELECT g.subject, g.aspect, g.body, g.written_at
  FROM GLOSSARY(all => true) g
  WHERE lower(g.kind) = 'measurement' AND g.current),
orphaned AS (
  SELECT json_extract_string(rel, '$.relationship') AS rel,
         json_extract(rel, '$.orphans')::BIGINT AS orphans,
         json_extract(rel, '$.filled')::BIGINT AS filled,
         written_at
  FROM (SELECT unnest(json_extract(m.body, '$.relationships')::JSON[]) AS rel, m.written_at
        FROM measured m WHERE m.aspect = 'relationship_coherence')
  WHERE json_extract(rel, '$.orphans')::BIGINT > 0),
orphans AS (
  SELECT 'measured' AS chip, '' AS bcls,
         CAST(o.orphans AS VARCHAR) || ' of ' || CAST(o.filled AS VARCHAR) || ' ' || split_part(substr(o.rel, len(d.dataset) + 2), '.', 1)
           || ' rows find no ' || split_part(substr(split_part(o.rel, ' -> ', 2), len(d.dataset) + 2), '.', 1) || '.' AS headline,
         'The join ' || o.rel || ' leaves them unresolved.'
           || coalesce(' The record says of the join: ' || m.meaning || '.', '') AS why,
         coalesce(rd.metrics, '') AS reads,
         'relationship_coherence · measured ' || strftime(o.written_at, '%d %b %Y %H:%M') AS meta,
         '/' || d.dataset || '/app/docket/p/glossary?table=' || split_part(substr(o.rel, len(d.dataset) + 2), '.', 1) AS link,
         split_part(substr(o.rel, len(d.dataset) + 2), '.', 1) AS link_text,
         0.4 AS sev,
         CAST(o.orphans AS DOUBLE) AS size
  FROM orphaned o
  CROSS JOIN d
  LEFT JOIN meanings m ON m.subject = o.rel AND m.rn = 1
  LEFT JOIN reads rd ON d.dataset || '.' || rd.source = split_part(o.rel, ' -> ', 1)),
broken AS (
  SELECT subject,
         json_extract_string(cand, '$.target') AS target,
         json_extract_string(cand, '$.form') AS form,
         json_extract_string(cand, '$.operands[0]') AS op1,
         json_extract_string(cand, '$.operands[1]') AS op2,
         json_extract(cand, '$.support')::BIGINT AS support,
         json_extract(cand, '$.violations')::BIGINT AS violations,
         written_at
  FROM (SELECT m.subject, unnest(json_extract(m.body, '$.candidates')::JSON[]) AS cand, m.written_at
        FROM measured m WHERE m.aspect = 'derivation_candidates')
  WHERE json_extract(cand, '$.violations')::BIGINT > 0),
breaks AS (
  SELECT 'measured' AS chip, '' AS bcls,
         CAST(b.violations AS VARCHAR) || ' ' || substr(b.subject, len(d.dataset) + 2) || ' rows break ' || b.target || ' = ' || b.op1
           || CASE b.form WHEN 'product' THEN ' × ' ELSE ' + ' END || b.op2 || '.' AS headline,
         'The identity holds on ' || CAST(b.support AS VARCHAR) || ' of ' || CAST(b.support + b.violations AS VARCHAR)
           || ' rows and breaks on ' || CAST(b.violations AS VARCHAR) || '.' AS why,
         coalesce(rd.metrics, '') AS reads,
         'derivation_candidates · measured ' || strftime(b.written_at, '%d %b %Y %H:%M') AS meta,
         '/' || d.dataset || '/app/docket/p/glossary?table=' || substr(b.subject, len(d.dataset) + 2) AS link,
         substr(b.subject, len(d.dataset) + 2) AS link_text,
         0.4 AS sev,
         CAST(b.violations AS DOUBLE) AS size
  FROM broken b
  CROSS JOIN d
  LEFT JOIN reads rd ON rd.source = substr(b.subject, len(d.dataset) + 2) || '.' || b.target),
every AS (
  SELECT * FROM judged
  UNION ALL SELECT * FROM orphans
  UNION ALL SELECT * FROM breaks)
SELECT chip, bcls, headline, why,
       CASE WHEN reads = '' THEN '' ELSE 'Read by ' || reads || '.' END AS reads,
       meta, link, link_text, sev, size
FROM every
ORDER BY sev DESC, size DESC, headline
