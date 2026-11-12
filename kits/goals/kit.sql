-- The interfaces' reads that build on the kits', declared at every open
-- after the kits, where core.sql comes before them: what the server
-- brings current by itself (`results_due()`) and what it cannot, the
-- work list of the bound dataset (`next`).

--===------------------------------------------------------------------===--
-- results_due(preview := false): the results the bound dataset wants that
-- are missing or out of date, each with the statement that computes it,
-- in the order to run them: ord, function, subject, run. A result is out
-- of date when an input it read has another version now (the catalog's
-- `inputs`). What a metric needs: the profile of each column it reads or
-- joins on, the relationship check of its dataset, and the tests on it
-- and on what it reads. A profile and the relationship check come first:
-- the tests read them, and so does a measurement a metric's row names as
-- not run (the grain of its period column). The server computes these
-- after each write. With preview := true the preview measurements that
-- are due come last (outlook_measurements()): they call the model
-- service, so a person or an agent runs them, and `next` lists them.
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.results_due(preview := false) AS TABLE
WITH ds AS (SELECT current_schema() AS d),
metrics AS (
  SELECT view FROM main.view_summary()
  WHERE stopped IS NULL AND coalesce(kind, '') NOT IN ('plan', 'sample', 'scalar', 'relation')),
columns AS (
  SELECT s.table_name || '.' || unnest(s.columns) AS subject
  FROM glossql_views_scans(current_schema()) s WHERE s.view IN (SELECT view FROM metrics)
  UNION SELECT j.left_column FROM glossql_views_joins(current_schema()) j WHERE j.view IN (SELECT view FROM metrics)
  UNION SELECT j.right_column FROM glossql_views_joins(current_schema()) j WHERE j.view IN (SELECT view FROM metrics)),
stored AS (
  SELECT subject, aspect, bool_and(current) AS current
  FROM glossql_glossary(current_schema(), NULL, true) WHERE actor = 'function' GROUP BY ALL)
SELECT 1 AS ord, 'column_profile' AS function, c.subject, 'SELECT column_profile() FROM ' || c.subject AS run
FROM columns c LEFT JOIN stored s ON s.subject = c.subject AND s.aspect = 'column_profile'
WHERE NOT coalesce(s.current, false)
UNION ALL
SELECT DISTINCT 1, split_part(w, ' over ', 1), split_part(w, ' over ', 2),
       'SELECT ' || split_part(w, ' over ', 1) || '() FROM ' || split_part(w, ' over ', 2)
FROM (SELECT unnest(measurements_to_run) AS w FROM main.view_summary() WHERE coalesce(kind, '') <> 'plan')
UNION ALL
SELECT 2, 'relationship_coherence', ds.d, 'SELECT relationship_coherence() FROM ' || ds.d
FROM ds LEFT JOIN stored s ON s.subject = ds.d AND s.aspect = 'relationship_coherence'
WHERE EXISTS (SELECT 1 FROM metrics) AND NOT coalesce(s.current, false)
UNION ALL
SELECT DISTINCT 3, t.aspect, t.subject, t.run
FROM main.view_tests_without_preview() t
WHERE t.run <> '' AND (t.state = 'not_run' OR NOT t.current)
UNION ALL
SELECT 4, m.name, ds.d, 'SELECT ' || m.name || '() FROM ' || ds.d
FROM main.outlook_measurements() m, ds WHERE preview AND m.due;

--===------------------------------------------------------------------===--
-- load_changes(): per table of the bound dataset loaded more than once,
-- what its newest load changed against the load before: the row count,
-- and each column whose stored profile moved (distinct values, the share
-- empty, the lowest and the highest value). Columns: table_name
-- (<dataset>.<table>), cause.
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.load_changes() AS TABLE
WITH loads AS (
  SELECT dataset || '.' || table_name AS tbl, rows, end_snapshot IS NULL AS newest,
         lag(rows) OVER (PARTITION BY table_name ORDER BY begin_snapshot) AS rows_before
  FROM main.imports_history WHERE dataset = current_schema()),
profiles AS (
  SELECT subject, value AS now_, end_snapshot IS NULL AS newest,
         lag(value) OVER (PARTITION BY subject ORDER BY begin_snapshot) AS before
  FROM main.measurements_history WHERE dataset = current_schema() AND function = 'column_profile'),
moved AS (
  SELECT array_to_string(string_split(subject, '.')[1:2], '.') AS tbl, subject,
         concat_ws(', ',
           CASE WHEN now_->>'distinct' IS DISTINCT FROM before->>'distinct'
                THEN (now_->>'distinct') || ' distinct values, ' || (before->>'distinct') || ' before' END,
           CASE WHEN now_->>'null_ratio' IS DISTINCT FROM before->>'null_ratio'
                THEN round(CAST(now_->>'null_ratio' AS DOUBLE) * 100, 1) || '% empty, '
                     || round(CAST(before->>'null_ratio' AS DOUBLE) * 100, 1) || '% before' END,
           CASE WHEN now_->>'min' IS DISTINCT FROM before->>'min'
                THEN 'lowest ' || coalesce(now_->>'min', 'none') || ', ' || coalesce(before->>'min', 'none') || ' before' END,
           CASE WHEN now_->>'max' IS DISTINCT FROM before->>'max'
                THEN 'highest ' || coalesce(now_->>'max', 'none') || ', ' || coalesce(before->>'max', 'none') || ' before' END) AS what
  FROM profiles WHERE newest AND before IS NOT NULL),
changed AS (
  SELECT tbl, string_agg(string_split(subject, '.')[3] || ' (' || what || ')', '; ' ORDER BY subject) AS what
  FROM moved WHERE what <> '' GROUP BY tbl)
SELECT l.tbl AS table_name, 'loaded again: ' || l.rows || ' rows, ' || l.rows_before || ' before' || coalesce('; ' || c.what, '') AS cause
FROM loads l LEFT JOIN changed c USING (tbl)
WHERE l.newest AND l.rows_before IS NOT NULL;

-- next: what is open on the bound dataset, read from the states the
-- catalog holds and narrowed to what the views read and serve. One
-- row per asset and state: priority (1 a number is wrong or withheld,
-- 2 something changed or was decided, 3 not there yet, 9 waiting for
-- a person), ord (the order of the rows inside one priority), step
-- (the kind of work: integrate, describe, test, review), asset,
-- state, who (agent or person), open (the finding), for_view, cause
-- (what the newest load changed), statement (what opens the work;
-- <...> marks what only the author can fill). The kinds of work are
-- labels, not stages: integrate is a source to connect, a table to
-- load or a view to define; review is a question for a named person
-- or a person's decision to apply. The rows are ordered by priority,
-- not by kind. It serves building the layer (missing, not run) and
-- running it (outdated after a load, red, conflict) alike. A test's
-- finding and fix are the test's own (`finding` and `fix` in its
-- result), on a view, a table or a column alike; a red test without
-- a `fix` gets the check to run again and the statement that accepts
-- its rate. A property that exists to be tested (tested_properties())
-- is a row where its test is set, and is not asked for on the other
-- assets. A kit adds rows through its tests, and the outlook kit
-- through outlook_findings(). An assumption that waits for a person
-- is one row each.
CREATE OR REPLACE VIEW main.next AS
  WITH ds AS (SELECT current_schema() AS d),
  scans AS (SELECT view, table_name AS tbl, unnest(columns) AS col
            FROM glossql_views_scans(current_schema())),
  summary AS MATERIALIZED (SELECT * FROM main.view_summary()),
  -- a load-query change a person approved, with no load of the table since
  approved AS (
    SELECT json_extract_string(a.body, '$.table') AS tbl FROM main.glossary a, ds
    WHERE a.dataset = ds.d AND a.aspect = 'recipe_change' AND a.actor_kind = 'human'
      AND json_extract_string(a.body, '$.table') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM main.imports i WHERE i.dataset = ds.d
                        AND i.table_name = json_extract_string(a.body, '$.table') AND i.imported_at >= a.written_at)),
  -- a person's formula newer than the agent's definition of the view:
  -- the view serves the recorded SQL until the agent records it again
  formulas AS (
    SELECT g.aspect AS view
    FROM main.glossary g JOIN main.glossary h ON h.dataset = g.dataset AND h.subject = g.subject AND h.begin_snapshot > g.begin_snapshot, ds
    WHERE g.dataset = ds.d AND g.subject = ds.d AND g.actor_kind = 'agent'
      AND g.aspect IN (SELECT name FROM main.aspects WHERE kind = 'VIEW')
      AND h.aspect = 'definitions' AND h.actor_kind = 'human'
      AND json_extract(h.body, '$.definitions.' || g.aspect || '.formula') IS NOT NULL),
  reloaded AS (SELECT table_name AS tbl, cause FROM main.load_changes()),
  -- the preview features' tests come in through outlook_findings(), below
  vt AS MATERIALIZED (SELECT * FROM main.view_tests_without_preview()),
  -- the assets a view reads, the view itself, and the columns of a
  -- table view: a table is handed over with its columns described
  reach AS (
    SELECT asset, string_agg(DISTINCT view, ', ' ORDER BY view) AS views FROM (
      SELECT tbl AS asset, view FROM scans
      UNION ALL
      SELECT tbl || '.' || col, view FROM scans
      UNION ALL
      SELECT r.left_side || ' -> ' || r.right_side, s.view
      FROM main.relationships r JOIN scans s ON r.left_side = s.tbl || '.' || s.col, ds
      WHERE r.dataset = ds.d
      UNION ALL
      SELECT ds.d || '.' || m.view, m.view FROM (SELECT DISTINCT view FROM scans) m, ds
      UNION ALL
      SELECT ds.d || '.' || c.table_name || '.' || c.column_name, c.table_name
      FROM glossql_columns(current_schema()) c, ds
      WHERE c.table_name IN (SELECT view FROM summary WHERE kind = 'relation' AND stopped IS NULL))
    GROUP BY asset),
  -- what an agent or a person states: not a measurement, not a check
  -- the server runs; `shape` is the value to fill in: the fields the
  -- skill asks for on a table's entity, else the property's single
  -- `value`
  stated AS (
    SELECT name,
           CASE WHEN name = 'entity'
                THEN '{"value": "<what one row is>", "role": "<fact|dimension>", "grain": ["<key column>"], "time_axis": "<date column, where the rows are events>"}'
                WHEN name = 'meaning' THEN '{"value": "<one sentence>"}'
                WHEN json_extract(schema, '$.properties.value.enum') IS NOT NULL
                THEN '{"value": "<' || array_to_string(json_extract_string(schema, '$.properties.value.enum[*]'), '|') || '>"}'
                WHEN json_extract(schema, '$.properties.value') IS NOT NULL
                THEN '{"value": "<' || name || '>"}'
                WHEN json_extract(schema, '$.properties.floor.enum') IS NOT NULL
                THEN '{"floor": "<' || array_to_string(json_extract_string(schema, '$.properties.floor.enum[*]'), '|') || '>"}' END AS shape,
           -- an expectation a test scores: asked for where it is set, not on every asset
           name IN (SELECT p.name FROM main.tested_properties() p) AS expectation
    FROM main.aspects
    WHERE kind = 'FACT' AND json_extract_string(schema, '$.x-subject') IS NULL),
  g AS (SELECT subject, aspect, state FROM glossql_glossary(current_schema(), NULL, false)),
  -- the newest annotation on each asset: an outdated one is offered
  -- back to be checked and recorded again
  written AS (
    SELECT w.subject, w.aspect, w.body::VARCHAR AS body, w.begin_snapshot FROM main.glossary w, ds
    WHERE w.dataset = ds.d AND w.actor_kind IN ('agent', 'human')
    QUALIFY row_number() OVER (PARTITION BY w.subject, w.aspect ORDER BY w.begin_snapshot DESC) = 1),
  -- each view's newest definition: an annotation on the view written
  -- before it describes the definition before
  defined AS (
    SELECT ds.d || '.' || w.aspect AS home, w.aspect AS view, max(w.begin_snapshot) AS begin_snapshot FROM main.glossary w, ds
    WHERE w.dataset = ds.d AND w.subject = ds.d AND w.aspect IN (SELECT view FROM summary)
    GROUP BY ALL),
  -- what the views read, and every value withheld as a conflict; a
  -- conflict a test reports is the test's row
  homed AS (
    SELECT g.subject, g.aspect, g.state, x.views,
           CASE WHEN g.subject LIKE '% -> %' THEN g.subject
                ELSE array_to_string(string_split(g.subject, '.')[1:2], '.') END AS home,
           s.shape IS NULL AND g.state = 'missing' AS unshaped,
           coalesce(g.state = 'stale' AND EXISTS (
             SELECT 1 FROM defined d
             WHERE d.begin_snapshot > w.begin_snapshot AND (g.subject = d.home OR starts_with(g.subject, d.home || '.'))), false) AS redefined,
           'GLOSS ' || g.aspect || ' ON ' || g.subject || ' AS $$'
             || CASE WHEN g.state = 'stale' THEN coalesce(w.body, s.shape, '<value>') ELSE coalesce(s.shape, '<value>') END
             || '$$;' AS gloss
    FROM g JOIN stated s ON s.name = g.aspect LEFT JOIN reach x ON x.asset = g.subject
    LEFT JOIN written w ON w.aspect = g.aspect AND w.subject = g.subject
    WHERE (x.asset IS NOT NULL OR g.state = 'conflict')
      AND NOT (s.expectation AND g.state = 'missing')
      -- `entity` says what one row of a table is: asked on a loaded
      -- table and on a table view, not on a metric, a single value or a plan
      AND NOT (g.aspect = 'entity' AND g.state = 'missing' AND EXISTS (
        SELECT 1 FROM summary m, ds WHERE g.subject = ds.d || '.' || m.view AND coalesce(m.kind, '') <> 'relation'))
      AND NOT (g.state = 'conflict' AND EXISTS (
        SELECT 1 FROM vt WHERE vt.subject = g.subject AND vt.aspect = g.aspect AND vt.state <> 'green'))
    UNION ALL
    -- a metric's served column with no role: the statement its summary
    -- row names (`missing`), on the view's own column, so that the
    -- summary row and this list ask for the same annotation
    SELECT ds.d || '.' || u.view || '.' || u.col, 'role', 'missing', u.view, ds.d || '.' || u.view, false, false, u.statement
    FROM (SELECT m.view, unnest(m.columns_without_role) AS col, unnest(m.missing) AS statement FROM summary m
          WHERE m.stopped IS NULL AND coalesce(m.kind, '') NOT IN ('scalar', 'relation', 'plan')) u, ds),
  s_load AS (
    SELECT 3 AS priority, 1 AS ord, 'integrate' AS step, ds.d AS asset, 'missing' AS state, 'agent' AS who,
           'no table is loaded' AS open, '' AS for_view, '' AS cause,
           '-- name where the data is, list what is there, then load each table with a load query' || chr(10)
             || 'DECLARE SOURCE <source> SET (type: <csv|parquet|json|relational_db>, location: ''<directory or URL>'');' || chr(10)
             || 'PREVIEW <source> AS $$SELECT file FROM glob(''*'')$$;' || chr(10)
             || '-- a typed file loads as it is; a CSV takes these reader options and its casts in the SELECT' || chr(10)
             || 'DECLARE RECIPE <table> ON ' || ds.d || ' FROM <source> AS $$SELECT <columns> FROM read_parquet(''<file>'')$$;' || chr(10)
             || 'DECLARE RECIPE <table> ON ' || ds.d || ' FROM <source> AS $$SELECT <columns and casts> FROM read_csv(''<file>'', all_varchar = true, nullstr = null_markers(), store_rejects = true)$$;' AS statement
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM duckdb_tables() t
                              WHERE t.database_name = current_database() AND t.schema_name = ds.d)
    UNION ALL
    SELECT 2, 1, 'integrate', ds.d || '.' || o.tbl, 'decided', 'agent',
           'a person approved a change to the load query of ' || o.tbl || '; it is not declared yet', '', '',
           '-- the approved SQL: SELECT body FROM glossary WHERE aspect = ''recipe_change'';' || chr(10)
             || 'DECLARE RECIPE ' || o.tbl || ' ON ' || ds.d || ' FROM <source> AS $$<the approved sql>$$;'
    FROM approved o, ds),
  s_describe AS (
    SELECT CASE h.state WHEN 'conflict' THEN 1 WHEN 'stale' THEN 2 ELSE 3 END, 2, 'describe', h.home, h.state, 'agent',
           count(*) || ' ' || CASE h.state WHEN 'stale' THEN 'outdated' WHEN 'conflict' THEN 'in conflict' ELSE h.state END || ': '
             || string_agg(DISTINCT h.aspect, ', ' ORDER BY h.aspect),
           coalesce(max(h.views), ''),
           -- what made the annotations outdated: the table's own load, the
           -- view's definition recorded again, or a load of a table the view scans
           CASE WHEN h.state = 'stale'
                THEN coalesce(max(l.cause),
                              CASE WHEN bool_or(h.redefined) THEN 'the definition of ' || h.home || ' was recorded again' END,
                              (SELECT string_agg(r.tbl || ' ' || r.cause, chr(10) ORDER BY r.tbl) FROM reloaded r
                               WHERE r.tbl IN (SELECT s.tbl FROM scans s, ds WHERE ds.d || '.' || s.view = h.home)),
                              '')
                ELSE '' END,
           CASE h.state
             WHEN 'conflict'
             THEN '-- two values differ. Read both, check the data, and annotate again only if the data changed your mind:' || chr(10)
                  || 'SELECT subject, aspect, actor, body, current FROM GLOSSARY(' || h.home || ', all => true);'
             WHEN 'stale'
             THEN CASE WHEN max(l.cause) IS NULL AND bool_or(h.redefined)
                       THEN '-- the definition of ' || h.home || ' changed after these annotations were written. Check each value against the new definition and record it again:'
                       ELSE '-- the data under these annotations changed. Check each value against the new data and record it again:' END || chr(10)
                  || string_agg(DISTINCT h.gloss, chr(10) ORDER BY h.gloss)
             ELSE CASE WHEN bool_or(h.unshaped)
                       THEN '-- the shape of a value: SELECT name, schema FROM aspects WHERE name = ''<property>'';' || chr(10)
                       ELSE '' END
                  || string_agg(DISTINCT h.gloss, chr(10) ORDER BY h.gloss) END
    FROM homed h LEFT JOIN reloaded l ON l.tbl = h.home
    WHERE h.state IN ('missing', 'stale', 'conflict')
    GROUP BY h.home, h.state),
  -- how a rate is accepted where the data is right as it is: a
  -- tolerance annotated on the test's property where its schema has
  -- one (a person's outranks the agent's), else the test declared
  -- again with the rate as its threshold
  accepts AS (
    SELECT w.name AS test,
           CASE WHEN a.kind = 'FACT' AND json_extract(a.schema, '$.properties.tolerance') IS NOT NULL THEN 'tolerance'
                ELSE 'threshold' END AS by,
           w.aspect
    FROM main.tests w JOIN main.aspects a ON a.name = w.aspect
    WHERE w.detector = 'rate_tolerance'),
  s_test AS (
    SELECT CASE t.state WHEN 'red' THEN 1 WHEN 'orange' THEN 2 ELSE 3 END, 3, 'test', t.subject, t.state, 'agent',
           t.test || coalesce(': ' || coalesce(t.evidence->>'finding', t.evidence->>'reason'), ''), t.view,
           coalesce((SELECT string_agg(l.tbl || ' ' || l.cause, chr(10) ORDER BY l.tbl)
                     FROM reloaded l WHERE l.tbl IN (SELECT s.tbl FROM scans s WHERE s.view = t.view)), ''),
           coalesce(t.evidence->>'fix',
                    CASE WHEN t.state IN ('red', 'orange') AND t.declared_by NOT LIKE 'kit:%'
                         THEN '-- the data breaks the rule. Fix the load query or the view''s definition, then run the check again:' || chr(10)
                              || nullif(t.run, '') || ';'
                              || coalesce(chr(10) || '-- where a person accepts the rate as it is (measured: ' || round(t.score, 4) || '), '
                                   || CASE k.by
                                        WHEN 'tolerance' THEN 'record it with their reason:' || chr(10)
                                               || '-- ' || main.gloss_statement(k.aspect, t.subject,
                                               json_merge_patch(coalesce(e.body, '{}'),
                                                 '{"tolerance": ' || ceil(t.score * 1000) / 1000 || ', "basis": "<who accepted the rate and why>"}')::VARCHAR)
                                        WHEN 'threshold' THEN 'declare the test again with it, and say in the meaning of ' || t.subject || ' who accepted it and why:' || chr(10)
                                               || '-- DECLARE TEST ' || t.test || ' ON ' || k.aspect
                                               || ' DETECTOR rate_tolerance THRESHOLD ' || ceil(t.score * 1000) / 1000 || ';' END, '') END,
                    nullif(t.run, ''),
                    'SELECT subject, aspect, actor, body, current FROM GLOSSARY(' || t.subject || ', all => true);')
    FROM vt t LEFT JOIN accepts k ON k.test = t.test
    LEFT JOIN written e ON e.subject = t.subject AND e.aspect = t.aspect
    WHERE t.state <> 'green'),
  s_review AS (
    SELECT 2, 4, 'review', ds.d || '.' || r.aspect, 'decided', 'agent',
           'a person decided ' || r.key || ' (' || r.stance || ')' || coalesce(': ' || nullif(r.note, ''), '')
             || '; the definition does not carry it yet', r.aspect, '',
           '-- set the assumption with key "' || r.key || '" to confidence 1.0 and basis "decided-by-person", change the SQL where the decision asks for it, then record the definition again:' || chr(10)
             || main.view_redefine(ds.d, r.aspect)
    FROM main.review_decisions r, ds WHERE r.dataset = ds.d AND NOT r.folded_in
    UNION ALL
    SELECT 2, 4, 'review', ds.d || '.' || o.view, 'decided', 'agent',
           'a person''s formula for ' || o.view || ' is newer than its definition', o.view, '',
           '-- the formula: SELECT formula FROM view_definitions WHERE name = ''' || o.view || '''; change the SQL to match it, then record the definition again:' || chr(10)
             || main.view_redefine(ds.d, o.view)
    FROM formulas o, ds
    UNION ALL
    SELECT 9, 4, 'review', ds.d || '.' || q.aspect, 'waiting', 'person',
           'the assumption ' || q.key || ' waits for a person''s decision: ' || q.assumption, q.aspect, '',
           'SELECT key, assumption, basis, alternative FROM open_questions WHERE aspect = ''' || q.aspect || ''' AND key = ''' || q.key || ''';'
    FROM main.open_questions q, ds WHERE q.dataset = ds.d),
  s_views AS (
    SELECT 3, 5, 'integrate', ds.d, 'missing', 'agent', 'no view is defined (a table, a single value or a metric)', '', '',
           '-- a view is named SQL on the dataset. Define the kind the job asks for.' || chr(10)
             || '-- a table:' || chr(10)
             || 'DECLARE ASPECT <table_view> WITH $${"title": "<its name in the business''s words>", "x-kind": "relation"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<table_view>', ds.d, '{"sql": "SELECT <columns> FROM <table>"}') || chr(10)
             || '-- a single value:' || chr(10)
             || 'DECLARE ASPECT <single_value> WITH $${"title": "<its name in the business''s words>", "x-kind": "scalar"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<single_value>', ds.d, '{"sql": "SELECT <expression> AS value FROM <table>"}') || chr(10)
             || '-- a metric, a value per period with its dimensions:' || chr(10)
             || 'DECLARE ASPECT <metric> WITH $${"title": "<its name in the business''s words>"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<metric>', ds.d, '{"sql": "SELECT <period>, <value>, <dimension columns> FROM <table>", "time": "<period column>", "measure": {"column": "<value column>", "additivity": "<additive|semi-additive|ratio|non-additive>", "unit": "<unit>"}, "dimensions": ["<column>"]}')
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM summary WHERE stopped IS NULL)
      AND EXISTS (SELECT 1 FROM duckdb_tables() t WHERE t.database_name = current_database() AND t.schema_name = ds.d)
    UNION ALL
    -- a metric with no series yet: the statement is the annotation or
    -- the measurement its summary row names, else the definition again
    SELECT 2, 5, 'integrate', ds.d || '.' || m.view, 'blocked', 'agent', coalesce(m.reason, 'no series is served'), m.view, '',
           CASE WHEN m.period_column IS NULL
                THEN 'GLOSS role ON ' || ds.d || '.' || m.view || '.<period column> AS $${"value": "timestamp"}$$;'
                WHEN m.value_column IS NULL
                THEN 'GLOSS role ON ' || ds.d || '.' || m.view || '.<value column> AS $${"value": "measure"}$$;'
                WHEN m.floor IS NULL AND len(m.measurements_to_run) > 0
                THEN 'SELECT temporal() FROM ' || ds.d || '.' || m.view || '.' || m.period_column || ';'
                WHEN m.floor IS NULL
                THEN 'GLOSS time_grains ON ' || ds.d || '.' || m.view || '.' || m.period_column || ' AS $${"floor": "<minute|hour|day|week|month|quarter|year>"}$$;'
                ELSE main.view_redefine(ds.d, m.view) END
    FROM summary m, ds
    -- a single value and a table are served as they are; only a metric needs a series
    WHERE NOT m.applicable AND m.stopped IS NULL AND coalesce(m.kind, '') NOT IN ('scalar', 'relation')
      AND NOT EXISTS (SELECT 1 FROM vt t WHERE t.view = m.view AND t.state <> 'green')),
  -- the preview features: their findings, and their measurements that are due
  s_outlook AS (
    SELECT CASE f.state WHEN 'red' THEN 1 ELSE 3 END, CASE f.step WHEN 'test' THEN 3 ELSE 5 END,
           f.step, f.asset, f.state, 'agent', f.open, f.for_view, '', f.statement
    FROM main.outlook_findings() f
    UNION ALL
    SELECT 3, 3, 'test', ds.d, 'not_run', 'agent',
           m.name || ' (preview): ' || CASE WHEN m.stored THEN 'the data or a definition it reads changed since its result' ELSE 'not run yet' END,
           '', '', 'SELECT ' || m.name || '() FROM ' || ds.d || ';'
    FROM main.outlook_measurements() m, ds
    WHERE m.due)
  SELECT * FROM (
    SELECT * FROM s_load UNION ALL SELECT * FROM s_describe UNION ALL SELECT * FROM s_test
    UNION ALL SELECT * FROM s_review UNION ALL SELECT * FROM s_views UNION ALL SELECT * FROM s_outlook)
  ORDER BY priority, ord, asset, state;
