-- The interfaces' reads that build on the kits' — declared at every open
-- after the kits, where core.sql comes before them. The `next` read
-- itself is written by the engine at open: the union of every
-- routes_<kit>() macro the kits and this file declare, in the goals'
-- order, the lowest step deciding each.

-- What waits on an action in the bound dataset, from the data
-- alone: `recipe-change`, an approved load-query change with no load since;
-- `formula`, a person's formula answer newer than the metric's recorded
-- definition; `conflict`, a value withheld at read; `re-measure`, a
-- measurement stored before the last change; `never measured`, a
-- measurement a metric's row reads and nobody ran, or a tested
-- measurement on the dataset with no result while a metric is defined;
-- `apply-decision`, a review decision whose key is still below full confidence.
-- Each row resolves by the action it names, never by a flag.
CREATE OR REPLACE VIEW main.open_items AS
  WITH ds AS (SELECT current_schema() AS dataset),
  approvals AS (
    SELECT h.dataset, json_extract_string(h.body, '$.table') AS tbl, h.written_at
    FROM main.glossary h, ds
    WHERE h.dataset = ds.dataset AND h.aspect = 'recipe_change' AND h.actor_kind = 'human'),
  recipes AS (
    SELECT 'recipe-change' AS kind, a.tbl AS subject, 'recipe change on ' || a.tbl AS what,
           'approved — not yet declared again' AS why, a.written_at::VARCHAR AS since
    FROM approvals a
    WHERE a.tbl IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM main.imports i
                      WHERE i.dataset = a.dataset AND i.table_name = a.tbl AND i.imported_at >= a.written_at)),
  -- a person's formula answer newer than the agent's current metric definition:
  -- the view keeps serving the recorded SQL until the agent recomposes it
  query_aspects AS (
    SELECT name FROM main.aspects
    QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1 AND kind = 'VIEW'),
  standing AS (
    SELECT g.dataset, g.subject, g.aspect, g.seq FROM main.glossary g, ds
    WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.actor_kind = 'agent'
      AND g.aspect IN (SELECT name FROM query_aspects)
    QUALIFY row_number() OVER (PARTITION BY g.aspect ORDER BY g.seq DESC) = 1),
  answered AS (
    SELECT h.dataset, h.subject, h.body, h.seq, h.written_at FROM main.glossary h, ds
    WHERE h.dataset = ds.dataset AND h.subject = ds.dataset AND h.aspect = 'definitions' AND h.actor_kind = 'human'
    QUALIFY row_number() OVER (ORDER BY h.seq DESC) = 1),
  formulas AS (
    SELECT 'formula' AS kind, g.aspect AS subject, 'formula answer on ' || g.aspect AS what,
           'the recorded materialization predates it' AS why, h.written_at::VARCHAR AS since
    FROM standing g JOIN answered h ON h.dataset = g.dataset AND h.subject = g.subject AND h.seq > g.seq
    WHERE json_extract(h.body, '$.definitions.' || g.aspect || '.formula') IS NOT NULL),
  collapsed AS (SELECT subject, aspect, state FROM glossql_glossary(current_schema(), NULL, false)),
  contests AS (
    SELECT 'conflict' AS kind, c.subject, 'contested: ' || c.subject || ' ' || c.aspect AS what,
           'withheld at read — a detector crossed its threshold or the values differ' AS why, '' AS since
    FROM collapsed c WHERE c.state = 'contested'),
  -- a kit's check on a metric (x-subject metric) is the server's to run
  -- again, at the next touch of the metric: never an item here
  remeasures AS (
    SELECT 're-measure' AS kind, v.actor AS subject, 'stale results from ' || v.actor AS what,
           'stored before the last change — run the function again, or use Re-measure in the console' AS why, '' AS since
    FROM (SELECT DISTINCT m.function AS actor FROM glossql_glossary(current_schema(), NULL, true) r
          JOIN main.measurements m ON m.subject = r.subject AND m.aspect = r.aspect
          WHERE r.actor = 'function' AND NOT r.current
            AND r.aspect NOT IN (SELECT name FROM main.aspects
                                 WHERE json_extract_string(schema, '$.x-subject') = 'metric')) v),
  wanted AS (
    SELECT DISTINCT split_part(w, ' over ', 1) AS function, split_part(w, ' over ', 2) AS over
    FROM (SELECT unnest(wanted) AS w FROM main.metric_axes())),
  unmeasured AS (
    SELECT 'never measured' AS kind, w.function AS subject,
           'never measured: ' || w.function || '() over ' || string_agg(w.over, ', ' ORDER BY w.over) AS what,
           'the metric''s row reads it and no result exists — run the function over the column' AS why, '' AS since
    FROM wanted w GROUP BY w.function),
  unwalked AS (
    SELECT 'never measured' AS kind, f.name AS subject,
           'never measured: ' || f.name || '() over ' || ds.dataset AS what,
           'a tested measurement on the dataset with no result — run the function' AS why, '' AS since
    FROM main.functions f, ds
    JOIN (SELECT name, grains FROM (SELECT name, kind, grains, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn FROM main.aspects) WHERE rn = 1 AND kind = 'MEASUREMENT') a
      ON a.name = f.returns
    WHERE (f.scope = 'GLOBAL' OR f.scope = ds.dataset) AND list_contains(a.grains, 'DATASET')
      AND EXISTS (SELECT 1 FROM main.tests w WHERE w.aspect = a.name)
      AND EXISTS (SELECT 1 FROM main.metric_surfaces s WHERE s.grounded)
      AND NOT EXISTS (SELECT 1 FROM main.measurements m WHERE m.dataset = ds.dataset AND m.function = f.name)
    QUALIFY row_number() OVER (PARTITION BY f.name ORDER BY f.seq DESC) = 1),
  foldins AS (
    SELECT 'apply-decision' AS kind, r.aspect AS subject, 'review decision on ' || r.aspect AS what,
           'decided (' || r.stance || ') — not yet applied to the definition' AS why, r.written_at::VARCHAR AS since
    FROM main.review_decisions r, ds WHERE r.dataset = ds.dataset AND NOT r.folded_in)
  SELECT * FROM recipes
  UNION ALL SELECT * FROM formulas
  UNION ALL SELECT * FROM contests
  UNION ALL SELECT * FROM remeasures
  UNION ALL SELECT * FROM unmeasured
  UNION ALL SELECT * FROM unwalked
  UNION ALL SELECT * FROM foldins;

-- The review goal, the core's one goal for the `next` read: what a
-- person decided or approved and the agent has not applied yet, and a
-- value withheld as contested. Served as the arms' SQL text, like a
-- kit's next steps, over the relations the engine's next read takes
-- once: ds, open_items, bodies. The metrics kit answers one goal per
-- served metric, its test report; the outlook kit bands and plan where
-- a model service is named.
CREATE OR REPLACE MACRO main.routes_core() AS TABLE
SELECT '' AS ctes, $arms$
SELECT 'review' AS surface, 1 AS step, 'next' AS state, 'GLOSS view' AS act,
       'apply the review decision on ' || r.aspect || ' (' || r.key || ': ' || r.stance || ')' AS say,
       coalesce(r.note, '') AS why,
       '-- the assumption under key "' || r.key || '" at confidence 1.0 with basis "decided-by-person"; an unclear answer means rewording the question under a new key' || chr(10)
         || 'GLOSS ' || r.aspect || ' ON ' || r.subject || ' AS $$' || coalesce(b.body, '<the current body>') || '$$;' AS statement,
       '' AS "then"
FROM main.review_decisions r LEFT JOIN bodies b ON b.metric = r.aspect, ds
WHERE r.dataset = ds.dataset AND NOT r.folded_in
UNION ALL
SELECT 'review', 2, 'next', 'DECLARE RECIPE', 'declare ' || o.subject || ' again as approved', o.why,
       'DECLARE RECIPE ' || o.subject || ' ON ' || ds.dataset || ' FROM <source> AS $$<the approved sql>$$;',
       ''
FROM open_items o, ds
WHERE o.kind = 'recipe-change'
UNION ALL
SELECT 'review', 3, 'next', 'GLOSSARY', 'read the contested value on ' || o.subject, o.why,
       'SELECT subject, aspect, actor, body, current FROM GLOSSARY(' || o.subject || ', all => true)',
       ''
FROM open_items o, ds
WHERE o.kind = 'conflict'
UNION ALL
SELECT 'review', 4, 'done', '', '', 'nothing open', '', ''
FROM ds
$arms$ AS arms;
