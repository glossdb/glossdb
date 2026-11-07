-- The interfaces' reads that build on the kits' — declared at every open
-- after the kits, where core.sql comes before them. The `next` read
-- itself is written by the engine at open: the union of every
-- routes_<kit>() macro the kits and this file declare, in the goals'
-- order, the lowest step deciding each.

-- What waits on an action in the bound dataset, from the data
-- alone: `recipe`, an approved load-query change with no load since;
-- `formula`, a person's formula answer newer than the metric's recorded
-- definition; `contest`, a value withheld at read; `re-measure`, a
-- measurement stored before the last change; `never measured`, a
-- measurement a metric's row reads and nobody ran, or a tested
-- measurement on the dataset with no result while a metric is defined;
-- `fold-in`, a review decision whose key is still below full confidence.
-- Each row resolves by the action it names, never by a flag.
CREATE OR REPLACE VIEW main.owed AS
  WITH ds AS (SELECT current_schema() AS dataset),
  approvals AS (
    SELECT h.dataset, json_extract_string(h.body, '$.table') AS tbl, h.written_at
    FROM main.glossary h, ds
    WHERE h.dataset = ds.dataset AND h.aspect = 'recipe_change' AND h.actor_kind = 'human'),
  recipes AS (
    SELECT 'recipe' AS kind, a.tbl AS subject, 'recipe change on ' || a.tbl AS what,
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
    SELECT 'contest' AS kind, c.subject, 'contested: ' || c.subject || ' ' || c.aspect AS what,
           'withheld at read — a detector crossed its threshold or the values differ' AS why, '' AS since
    FROM collapsed c WHERE c.state = 'contested'),
  remeasures AS (
    SELECT 're-measure' AS kind, v.actor AS subject, 'stale results from ' || v.actor AS what,
           'stored before the last change — run the function again, or use Re-measure in the console' AS why, '' AS since
    FROM (SELECT DISTINCT m.function AS actor FROM glossql_glossary(current_schema(), NULL, true) r
          JOIN main.measurements m ON m.subject = r.subject AND m.aspect = r.aspect
          WHERE r.actor = 'function' AND NOT r.current) v),
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
    SELECT 'fold-in' AS kind, r.aspect AS subject, 'review decision on ' || r.aspect AS what,
           'decided (' || r.stance || ') — not yet applied to the definition' AS why, r.written_at::VARCHAR AS since
    FROM main.ruling_entries r, ds WHERE r.dataset = ds.dataset AND NOT r.folded_in)
  SELECT * FROM recipes
  UNION ALL SELECT * FROM formulas
  UNION ALL SELECT * FROM contests
  UNION ALL SELECT * FROM remeasures
  UNION ALL SELECT * FROM unmeasured
  UNION ALL SELECT * FROM unwalked
  UNION ALL SELECT * FROM foldins;

-- The goals the interfaces' own reads answer, as next steps each: structure,
-- checks, app, rulings; the metrics kit answers metrics and slices, the
-- futures kit bands and plan. Served as the arms' SQL text, like a kit's
-- next steps, over the relations the engine's next read takes once: ds,
-- axes, owed, reds, bodies, applicable.
CREATE OR REPLACE MACRO main.routes_core() AS TABLE
SELECT '' AS ctes, $arms$
SELECT 'structure' AS surface, 1 AS step, 'next' AS state, 'DECLARE SOURCE' AS act,
       'declare the source the files come from' AS say,
       'no source is declared and no table is loaded' AS why,
       'DECLARE SOURCE <name> SET (type: parquet, location: ''<the root the files sit under>'');' AS statement,
       '' AS "then"
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM main.imports i WHERE i.dataset = ds.dataset)
  AND NOT EXISTS (SELECT 1 FROM main.sources)
UNION ALL
SELECT 'structure', 2, 'next', 'DECLARE RECIPE',
       'load the tables from ' || s.name,
       s.name || ' is declared and no table is loaded; a load query (recipe) loads one table, typed, and nothing more',
       'DECLARE RECIPE <table> ON ' || ds.dataset || ' FROM ' || s.name || ' AS $$SELECT * FROM read_parquet(''<path under the root>'')$$;',
       ''
FROM (SELECT DISTINCT name FROM main.sources) s, ds
WHERE NOT EXISTS (SELECT 1 FROM main.imports i WHERE i.dataset = ds.dataset)
UNION ALL
SELECT 'structure', 3, 'next', 'detect_relationships',
       'run the relationship detector',
       'the candidates come from the detector; you judge them',
       'SELECT detect_relationships() FROM ' || ds.dataset,
       'SELECT * FROM relationship_candidates(' || chr(39) || ds.dataset || chr(39) || ')'
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM main.measurements m WHERE m.dataset = ds.dataset AND m.function = 'detect_relationships')
UNION ALL
SELECT 'structure', 4, 'next', 'DECLARE RELATIONSHIP',
       'declare the edges you judge from the candidates',
       'no edge is declared; the detector''s candidates are waiting',
       'SELECT * FROM relationship_candidates(' || chr(39) || ds.dataset || chr(39) || ')',
       'DECLARE RELATIONSHIP <child>.<column> -> <parent>.<column>;'
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM main.relationships r WHERE r.dataset = ds.dataset)
UNION ALL
SELECT 'structure', 5, 'next', 'relationship_coherence',
       'run the coherence check over the declared edges',
       'edges declared and never checked: orphan rate, child before parent',
       'SELECT relationship_coherence() FROM ' || ds.dataset, ''
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM main.measurements m WHERE m.dataset = ds.dataset AND m.function = 'relationship_coherence')
UNION ALL
SELECT 'structure', 6, 'done', '', '', 'tables loaded, edges declared and checked', '', ''
FROM ds
UNION ALL
SELECT 'checks', 1, 'next', 'EXTRACT', 're-run ' || o.subject, o.why,
       'SELECT ' || o.subject || '() FROM ' || ds.dataset, ''
FROM owed o, ds
WHERE o.kind = 're-measure'
UNION ALL
SELECT 'checks', 2, 'next', 'EXTRACT', 'run ' || o.subject, o.why,
       'SELECT ' || o.subject || '() FROM ' || ds.dataset, ''
FROM owed o, ds
WHERE o.kind = 'never measured' AND o.what LIKE '% over ' || ds.dataset
UNION ALL
SELECT 'checks', 3, 'next', 'TESTS', 'read the red test results',
       v.test || ' bands ' || v.subject || ' red',
       'SELECT subject, aspect, test, band, score FROM TESTS(' || ds.dataset || ') WHERE band = ''red'' ORDER BY test, subject',
       ''
FROM reds v, ds
WHERE v.test IS DISTINCT FROM 'bands_w'
UNION ALL
SELECT 'checks', 4, 'next', 'DECLARE TEST',
       'turn a reconciliation into a permanent test',
       'no check is open and none is yours: a tie-out you ran by hand becomes a test that runs again whenever its inputs change',
       'DECLARE ASPECT <name>_check WITH $${' || chr(10)
         || '  "type": "object", "required": ["outcome"],' || chr(10)
         || '  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "breach_rate": {"type": "number"}}' || chr(10)
         || '}$$ AS FACT ON DATASET;' || chr(10)
         || 'DECLARE FUNCTION <name>_check_fn FOR ' || ds.dataset || ' AS $$' || chr(10)
         || '  SELECT ''<what was compared>'' AS outcome, <the violation share, as DOUBLE> AS breach_rate' || chr(10)
         || '  FROM <the second route to the number>' || chr(10)
         || '$$ RETURNS <name>_check;' || chr(10)
         || 'DECLARE TEST <name>_w ON <name>_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;' || chr(10)
         || 'GLOSS <name>_check ON ' || ds.dataset || ' AS $${"outcome": "<what must hold>", "tolerance": <the rate you measured>}$$;',
       'SELECT <name>_check_fn() FROM ' || ds.dataset
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM main.functions f WHERE f.scope = ds.dataset)
UNION ALL
SELECT 'checks', 5, 'done', '', '', 'your own tests exist, every test ran, none is red', '', ''
FROM ds
UNION ALL
SELECT 'app', 1, 'blocked', '', '', 'no applicable metric exists; an app over nothing is a picture of nothing', '', ''
FROM ds
WHERE NOT EXISTS (SELECT 1 FROM axes WHERE applicable)
UNION ALL
SELECT 'app', 2, 'next', 'GLOSS app',
       'write the first page over ' || m.n || CASE WHEN m.n = 1 THEN ' metric' ELSE ' metrics' END,
       m.metrics || ' exist and no app does; the page is the proposal made concrete, shape it with the person from there',
       'GLOSS app ON review AS $${"title": "' || ds.dataset || ' review"}$$;' || chr(10)
         || 'GLOSS app_frame ON review.series AS $${"sql": "SELECT metric, period, value FROM metric_series(grain := ''month'') WHERE dimension = '''' AND metric IN (' || m.metric_list || ') ORDER BY metric, period"}$$;' || chr(10)
         || 'GLOSS app_spec ON review.trend AS $${"spec": "{\"$schema\":\"https://vega.github.io/schema/vega-lite/v6.json\",\"data\":{\"name\":\"frame\"},\"mark\":\"line\",\"encoding\":{\"x\":{\"field\":\"period\",\"type\":\"temporal\"},\"y\":{\"field\":\"value\",\"type\":\"quantitative\"},\"color\":{\"field\":\"metric\",\"type\":\"nominal\"}}}"}$$;' || chr(10)
         || 'GLOSS app_page ON review.index AS $${"html": "{% extends \"shell.html\" %}\n{% import \"modules/tiles.html\" as tiles %}\n{% block main %}\n<div class=\"tiles\">\n  {{ tiles::chart(frame=\"frames/series\", spec=\"specs/trend.vl.json\", title=\"By month\", chip=\"metric_series(grain := ''month'')\") }}\n</div>\n{% endblock %}\n"}$$;',
       '-- serves at /' || ds.dataset || '/app/review'
FROM applicable m, ds
WHERE m.n > 0 AND NOT EXISTS (SELECT 1 FROM main.app_parts p WHERE p.dataset = ds.dataset)
UNION ALL
SELECT 'app', 3, 'next', 'GLOSS app_page',
       'write the page of ' || p.app,
       p.app || ' exists without its page: the console serves index.html, so nothing is served yet; the frames and the specs are parts like it',
       'GLOSS app_page ON ' || p.app || '.index AS $${"html": "{% extends \"shell.html\" %}\n{% import \"modules/tiles.html\" as tiles %}\n{% block main %}\n<the page over the app''s frames and specs — the glossql-apps skill>\n{% endblock %}\n"}$$;',
       '-- serves at /' || ds.dataset || '/app/' || p.app
FROM (SELECT DISTINCT p.app FROM main.app_parts p, ds
      WHERE p.dataset = ds.dataset
        AND NOT EXISTS (SELECT 1 FROM main.app_parts i WHERE i.dataset = p.dataset AND i.app = p.app AND i.path = 'index.html')) p, ds
UNION ALL
SELECT 'app', 4, 'done', '', '', 'an app exists: /' || ds.dataset || '/app/' || p.app, '', ''
FROM (SELECT DISTINCT app FROM main.app_parts p, ds WHERE p.dataset = ds.dataset AND p.path = 'index.html') p, ds
UNION ALL
SELECT 'app', 5, 'done', '', '', 'an app exists', '', ''
FROM ds
UNION ALL
SELECT 'rulings', 1, 'next', 'GLOSS query',
       'apply the review decision on ' || r.aspect || ' (' || r.key || ': ' || r.stance || ')',
       coalesce(r.note, ''),
       '-- the assumption under key "' || r.key || '" at confidence 1.0 with basis "human-ruled"; an unclear answer means rewording the question under a new key' || chr(10)
         || 'GLOSS ' || r.aspect || ' ON ' || r.subject || ' AS $$' || coalesce(b.body, '<the current body>') || '$$;',
       ''
FROM main.ruling_entries r LEFT JOIN bodies b ON b.metric = r.aspect, ds
WHERE r.dataset = ds.dataset AND NOT r.folded_in
UNION ALL
SELECT 'rulings', 2, 'next', 'DECLARE RECIPE', 'declare ' || o.subject || ' again as approved', o.why,
       'DECLARE RECIPE ' || o.subject || ' ON ' || ds.dataset || ' FROM <source> AS $$<the approved sql>$$;',
       ''
FROM owed o, ds
WHERE o.kind = 'recipe'
UNION ALL
SELECT 'rulings', 3, 'next', 'GLOSSARY', 'read the contested value on ' || o.subject, o.why,
       'SELECT subject, aspect, actor, body, current FROM GLOSSARY(' || o.subject || ', all => true)',
       ''
FROM owed o, ds
WHERE o.kind = 'contest'
UNION ALL
SELECT 'rulings', 4, 'done', '', '', 'nothing open', '', ''
FROM ds
$arms$ AS arms;
