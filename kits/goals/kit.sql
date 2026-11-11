-- The interfaces' reads that build on the kits', declared at every open
-- after the kits, where core.sql comes before them: `open_items` and
-- `next`, the work list of the bound dataset.

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
  current_definition AS (
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
    FROM current_definition g JOIN answered h ON h.dataset = g.dataset AND h.subject = g.subject AND h.seq > g.seq
    WHERE json_extract(h.body, '$.definitions.' || g.aspect || '.formula') IS NOT NULL),
  collapsed AS (SELECT subject, aspect, state FROM glossql_glossary(current_schema(), NULL, false)),
  contests AS (
    SELECT 'conflict' AS kind, c.subject, 'conflict: ' || c.subject || ' ' || c.aspect AS what,
           'withheld at read — a detector crossed its threshold or the values differ' AS why, '' AS since
    FROM collapsed c WHERE c.state = 'conflict'),
  -- a kit's check on a metric (x-subject view) is the server's to run
  -- again, at the next touch of the metric: never an item here
  remeasures AS (
    SELECT 're-measure' AS kind, v.actor AS subject, 'stale results from ' || v.actor AS what,
           'stored before the last change — run the function again, or use Re-measure in the console' AS why, '' AS since
    FROM (SELECT DISTINCT m.function AS actor FROM glossql_glossary(current_schema(), NULL, true) r
          JOIN main.measurements m ON m.subject = r.subject AND m.aspect = r.aspect
          WHERE r.actor = 'function' AND NOT r.current
            AND r.aspect NOT IN (SELECT name FROM main.aspects
                                 WHERE json_extract_string(schema, '$.x-subject') = 'view')) v),
  wanted AS (
    SELECT DISTINCT split_part(w, ' over ', 1) AS function, split_part(w, ' over ', 2) AS over
    FROM (SELECT unnest(wanted) AS w FROM main.view_summary())),
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
      AND EXISTS (SELECT 1 FROM main.view_definitions s WHERE s.defined)
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

-- next: what is open on the bound dataset, by step of the data
-- intelligence layer (connect, describe, test, decide, serve), read
-- from the states the catalog holds and narrowed to what the metrics
-- read. One row per asset and state: priority (1 a number is wrong or
-- withheld, 2 something changed or was decided, 3 not there yet, 9
-- waiting for a person), ord (the step's order), step, asset, state,
-- who (agent or person), open (the finding), for_view, cause (what
-- the newest load changed), statement (what opens the work; <...>
-- marks what only the author can fill). It serves building the layer
-- (missing, not run) and running it (outdated after a load, red,
-- conflict) alike. A test's finding and fix are the test's own
-- (`finding` and `fix` in its result); a kit adds rows through its
-- tests, and the outlook kit through outlook_findings().
CREATE OR REPLACE VIEW main.next AS
  WITH ds AS (SELECT current_schema() AS d),
  scans AS (SELECT view, table_name AS tbl, unnest(columns) AS col
            FROM glossql_views_scans(current_schema())),
  reach AS (
    SELECT tbl AS asset, string_agg(DISTINCT view, ', ' ORDER BY view) AS views FROM scans GROUP BY 1
    UNION ALL
    SELECT tbl || '.' || col, string_agg(DISTINCT view, ', ' ORDER BY view) FROM scans GROUP BY 1
    UNION ALL
    SELECT r.left_side || ' -> ' || r.right_side, string_agg(DISTINCT s.view, ', ' ORDER BY s.view)
    FROM main.relationships r JOIN scans s ON r.left_side = s.tbl || '.' || s.col, ds
    WHERE r.dataset = ds.d GROUP BY 1
    UNION ALL
    SELECT ds.d || '.' || m.view, m.view FROM (SELECT DISTINCT view FROM scans) m, ds),
  -- what an agent or a person states: not a measurement, not a check the server runs
  stated AS (
    SELECT name FROM (SELECT *, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn FROM main.aspects)
    WHERE rn = 1 AND kind = 'FACT' AND json_extract_string(schema, '$.x-subject') IS NULL),
  g AS (SELECT subject, aspect, state FROM glossql_glossary(current_schema(), NULL, false)),
  -- what the metrics read, and every value withheld as a conflict
  homed AS (
    SELECT g.subject, g.aspect, g.state, x.views,
           CASE WHEN g.subject LIKE '% -> %' THEN g.subject
                ELSE array_to_string(string_split(g.subject, '.')[1:2], '.') END AS home
    FROM g JOIN stated s ON s.name = g.aspect LEFT JOIN reach x ON x.asset = g.subject
    WHERE x.asset IS NOT NULL OR g.state = 'conflict'),
  -- the newest load of each table against the one before it
  loads AS (
    SELECT i.dataset || '.' || i.table_name AS tbl, i.rows,
           lag(i.rows) OVER (PARTITION BY i.table_name ORDER BY i.seq) AS rows_before,
           row_number() OVER (PARTITION BY i.table_name ORDER BY i.seq DESC) AS rn
    FROM main.imports i, ds WHERE i.dataset = ds.d),
  -- what the newest load changed in a column a metric reads: its
  -- stored profile against the one before
  profiles AS (
    SELECT m.subject, m.value,
           lag(m.value) OVER (PARTITION BY m.subject ORDER BY m.seq) AS before,
           row_number() OVER (PARTITION BY m.subject ORDER BY m.seq DESC) AS rn
    FROM main.measurements m, ds WHERE m.dataset = ds.d AND m.function = 'column_profile'),
  changed AS (
    SELECT array_to_string(string_split(p.subject, '.')[1:2], '.') AS tbl,
           string_agg(string_split(p.subject, '.')[3] || ' ('
             || concat_ws(', ',
                  CASE WHEN p.value->>'distinct' IS DISTINCT FROM p.before->>'distinct'
                       THEN (p.value->>'distinct') || ' distinct values, ' || (p.before->>'distinct') || ' before' END,
                  CASE WHEN p.value->>'null_ratio' IS DISTINCT FROM p.before->>'null_ratio'
                       THEN round(CAST(p.value->>'null_ratio' AS DOUBLE) * 100, 1) || '% empty, '
                            || round(CAST(p.before->>'null_ratio' AS DOUBLE) * 100, 1) || '% before' END,
                  CASE WHEN p.value->>'min' IS DISTINCT FROM p.before->>'min'
                       THEN 'lowest ' || coalesce(p.value->>'min', 'none') || ', ' || coalesce(p.before->>'min', 'none') || ' before' END,
                  CASE WHEN p.value->>'max' IS DISTINCT FROM p.before->>'max'
                       THEN 'highest ' || coalesce(p.value->>'max', 'none') || ', ' || coalesce(p.before->>'max', 'none') || ' before' END)
             || ')', '; ' ORDER BY p.subject) AS what
    FROM profiles p
    WHERE p.rn = 1 AND p.before IS NOT NULL
      AND (p.value->>'distinct' IS DISTINCT FROM p.before->>'distinct'
        OR p.value->>'null_ratio' IS DISTINCT FROM p.before->>'null_ratio'
        OR p.value->>'min' IS DISTINCT FROM p.before->>'min'
        OR p.value->>'max' IS DISTINCT FROM p.before->>'max')
    GROUP BY 1),
  -- per table loaded more than once: the newest load against the one before
  reloaded AS (
    SELECT l.tbl, 'loaded again: ' || l.rows || ' rows, ' || l.rows_before || ' before'
                  || coalesce('; ' || c.what, '') AS cause
    FROM loads l LEFT JOIN changed c ON c.tbl = l.tbl
    WHERE l.rn = 1 AND l.rows_before IS NOT NULL),
  s_connect AS (
    SELECT 3 AS priority, 1 AS ord, 'connect' AS step, ds.d AS asset, 'missing' AS state, 'agent' AS who,
           'no table is loaded' AS open, '' AS for_view, '' AS cause,
           'PREVIEW <source> AS $$SELECT file FROM glob(''*'')$$;' AS statement
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM duckdb_tables() t
                              WHERE t.database_name = current_database() AND t.schema_name = ds.d)
    UNION ALL
    SELECT 2, 1, 'connect', ds.d || '.' || o.subject, 'decided', 'agent',
           'a change to the load query of ' || o.subject || ' is approved and not declared yet', '', '',
           'DECLARE RECIPE ' || o.subject || ' ON ' || ds.d || ' FROM <source> AS $$<the approved sql>$$;'
    FROM main.open_items o, ds WHERE o.kind = 'recipe-change'),
  s_describe AS (
    SELECT CASE h.state WHEN 'conflict' THEN 1 WHEN 'stale' THEN 2 ELSE 3 END, 2, 'describe', h.home, h.state, 'agent',
           count(*) || ' ' || CASE h.state WHEN 'stale' THEN 'outdated' WHEN 'conflict' THEN 'in conflict' ELSE h.state END || ': '
             || string_agg(DISTINCT h.aspect, ', ' ORDER BY h.aspect),
           coalesce(max(h.views), ''),
           CASE WHEN h.state = 'stale' THEN coalesce(max(l.cause), '') ELSE '' END,
           CASE WHEN h.state = 'conflict'
                THEN 'SELECT subject, aspect, actor, body, current FROM GLOSSARY(' || h.home || ', all => true);'
                ELSE '-- the shape of a property''s value: SELECT name, schema FROM aspects WHERE name = ''<property>'';' || chr(10)
                     || string_agg(DISTINCT 'GLOSS ' || h.aspect || ' ON ' || h.subject || ' AS $$<value>$$;', chr(10)
                                   ORDER BY 'GLOSS ' || h.aspect || ' ON ' || h.subject || ' AS $$<value>$$;') END
    FROM homed h LEFT JOIN reloaded l ON l.tbl = h.home
    WHERE h.state IN ('missing', 'stale', 'conflict')
    GROUP BY h.home, h.state),
  s_test AS (
    SELECT CASE t.state WHEN 'red' THEN 1 WHEN 'orange' THEN 2 ELSE 3 END, 3, 'test', t.subject, t.state, 'agent',
           t.test || coalesce(': ' || coalesce(t.evidence->>'finding', t.evidence->>'reason'), ''), t.view,
           coalesce((SELECT string_agg(l.tbl || ' ' || l.cause, chr(10) ORDER BY l.tbl)
                     FROM reloaded l WHERE l.tbl IN (SELECT s.tbl FROM scans s WHERE s.view = t.view)), ''),
           coalesce(t.evidence->>'fix', t.run)
    FROM main.view_tests() t WHERE t.state <> 'green'),
  s_decide AS (
    SELECT 2, 4, 'decide', ds.d || '.' || r.aspect, 'decided', 'agent',
           'a person decided ' || r.key || ' (' || r.stance || ')' || coalesce(': ' || nullif(r.note, ''), '')
             || '; the definition does not carry it yet', r.aspect, '',
           '-- set the assumption under key "' || r.key || '" to confidence 1.0 with basis "decided-by-person". Then record the definition again:' || chr(10)
             || main.view_redefine(ds.d, r.aspect)
    FROM main.review_decisions r, ds WHERE r.dataset = ds.d AND NOT r.folded_in
    UNION ALL
    SELECT 2, 4, 'decide', ds.d || '.' || o.subject, 'decided', 'agent',
           'a person''s formula for ' || o.subject || ' is newer than its definition', o.subject, '',
           main.view_redefine(ds.d, o.subject)
    FROM main.open_items o, ds WHERE o.kind = 'formula'
    UNION ALL
    SELECT 9, 4, 'decide', ds.d || '.' || q.aspect, 'waiting', 'person',
           count(*) || ' waiting for a person', q.aspect, '',
           'SELECT key, assumption, basis FROM open_questions WHERE aspect = ''' || q.aspect || ''';'
    FROM main.open_questions q, ds WHERE q.dataset = ds.d GROUP BY ds.d, q.aspect),
  s_serve AS (
    SELECT 3, 5, 'serve', ds.d, 'missing', 'agent', 'no view is defined (a metric, a single value or a table)', '', '',
           'DECLARE ASPECT <metric> WITH $${"title": "<its name in the business''s words>"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<metric>', ds.d, '{"sql": "SELECT <period>, <value>, <slicing columns> FROM <table>", "time": "<period column>", "measure": {"column": "<value column>", "additivity": "<additive|semi-additive|ratio>", "unit": "<unit>"}, "dimensions": ["<column>"]}')
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM main.view_summary() WHERE stopped IS NULL)
      AND EXISTS (SELECT 1 FROM duckdb_tables() t WHERE t.database_name = current_database() AND t.schema_name = ds.d)
    UNION ALL
    SELECT 2, 5, 'serve', ds.d || '.' || m.view, 'blocked', 'agent', coalesce(m.reason, 'not served'), m.view, '',
           main.view_redefine(ds.d, m.view)
    FROM main.view_summary() m, ds
    -- a single value and a table are served as they are; only a metric needs a series
    WHERE NOT m.applicable AND m.stopped IS NULL AND coalesce(m.kind, '') NOT IN ('scalar', 'relation')
      AND NOT EXISTS (SELECT 1 FROM main.view_tests() t WHERE t.view = m.view AND t.state <> 'green')),
  -- the preview features: their findings, and their measurements that are due
  s_outlook AS (
    SELECT CASE f.state WHEN 'red' THEN 1 ELSE 3 END, CASE f.step WHEN 'test' THEN 3 ELSE 5 END,
           f.step, f.asset, f.state, 'agent', f.open, f.for_view, '', f.statement
    FROM main.outlook_findings() f
    UNION ALL
    SELECT 3, 3, 'test', ds.d, 'not_run', 'agent',
           o.subject || ' (preview): ' || CASE o.kind WHEN 're-measure' THEN 'its result predates a change' ELSE 'not run yet' END,
           '', '', 'SELECT ' || o.subject || '() FROM ' || ds.d || ';'
    FROM main.open_items o JOIN main.outlook_measurements() d ON d.name = o.subject, ds
    WHERE o.kind IN ('never measured', 're-measure'))
  SELECT * FROM (
    SELECT * FROM s_connect UNION ALL SELECT * FROM s_describe UNION ALL SELECT * FROM s_test
    UNION ALL SELECT * FROM s_decide UNION ALL SELECT * FROM s_serve UNION ALL SELECT * FROM s_outlook)
  ORDER BY priority, ord, asset, state;
