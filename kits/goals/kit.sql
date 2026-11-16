-- The interfaces' reads that build on the kits', declared at every open
-- after the kits, where core.sql comes before them: what the server
-- brings current by itself (`results_due()`) and what it cannot, the
-- work list of the bound dataset (`next`).

--===------------------------------------------------------------------===--
-- results_due(): the results the bound dataset wants that
-- are missing or out of date, each with the statement that computes it,
-- in the order to run them: ord, function, subject, run. A result is out
-- of date when a node it read (the catalog's `inputs`) changed after the
-- snapshot it read at, or a result it read is out of date. A check that failed is
-- a result with its error, due again once it is out of date. What is
-- wanted follows from the tests on each view and on what it reads
-- (view_tests()), whatever the kind of view: each test's check, and
-- before it (ord 1) every result the check's body reads, at the place it
-- names from the test's subject, as the function's stored `reads` say
-- (join_check reads the profile of the columns a view joins on,
-- orphan_check the coherence of the relationships between the tables it
-- reads); the profile of each column a view scans, which load_changes()
-- compares to say what a load changed under the view (the cause `next`
-- names); and the measurement a metric's row names as not run (the grain
-- of its period column); and a result no test reads whose property marks
-- it `x-subject: view` and `x-set-by: <property>`, on each view that
-- carries an annotation of that property (server_results()), with the
-- results its body reads before it. The server computes these after each
-- write. Any other result about the dataset or a view (a kit's function an
-- actor runs) is the actor's to compute: once it is out of date, `next`
-- lists it with its statement.
--
-- server_results(): those results of a property no test reads, (function,
-- aspect, subject), the server's to compute
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.server_results() AS TABLE
WITH fns AS (
  SELECT name, returns FROM main.functions QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
marked AS (
  SELECT f.name AS function, f.returns AS aspect, json_extract_string(a.schema, '$.x-set-by') AS set_by
  FROM fns f JOIN main.aspects a ON a.name = f.returns
  WHERE json_extract_string(a.schema, '$.x-subject') = 'view' AND json_extract_string(a.schema, '$.x-set-by') IS NOT NULL
    AND f.returns NOT IN (SELECT aspect FROM main.tests))
SELECT DISTINCT m.function, m.aspect, current_schema() || '.' || split_part(g.subject, '.', 2) AS subject
FROM marked m JOIN main.glossary g ON g.aspect = m.set_by
WHERE g.dataset = current_schema() AND g.actor_kind IN ('agent', 'human')
  AND split_part(g.subject, '.', 2) IN (SELECT DISTINCT table_name FROM glossql_columns(current_schema()) WHERE table_type = 'VIEW');

CREATE OR REPLACE MACRO main.results_due() AS TABLE
WITH tests AS MATERIALIZED (SELECT view, subject, aspect, state, current, run FROM glossql_kept('view_tests')),
fns AS MATERIALIZED (
  SELECT name, returns, reads FROM main.functions QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
-- the check that measures a test's property, as view_tests() names it
checks AS (SELECT returns AS aspect, min(name) AS name FROM fns WHERE returns IS NOT NULL GROUP BY returns),
served AS MATERIALIZED (FROM main.server_results()),
-- the results each check reads, by the place its body names, and those each result the server
-- computes with no test reads
wants AS (
  SELECT DISTINCT t.subject, r.what AS function, r."where"
  FROM tests t JOIN checks c ON c.aspect = t.aspect JOIN fns f ON f.name = c.name,
       unnest(from_json(f.reads, '[{"kind": "VARCHAR", "read": "VARCHAR", "what": "VARCHAR", "where": "VARCHAR"}]')) u(r)
  WHERE t.run <> '' AND r.kind = 'read' AND r.read = 'results'
  UNION
  SELECT DISTINCT v.subject, r.what, r."where"
  FROM served v JOIN fns f ON f.name = v.function,
       unnest(from_json(f.reads, '[{"kind": "VARCHAR", "read": "VARCHAR", "what": "VARCHAR", "where": "VARCHAR"}]')) u(r)
  WHERE r.kind = 'read' AND r.read = 'results'),
anchored AS (SELECT p."where" FROM unnest(main.place_list()) u(p) WHERE p.anchored),
places AS MATERIALIZED (FROM main.places(current_schema()) WHERE "where" IN (SELECT "where" FROM wants)),
wanted AS (
  SELECT DISTINCT w.function, f.returns AS aspect, w.subject FROM wants w JOIN fns f ON f.name = w.function
  WHERE w."where" = 'itself'
  UNION
  SELECT DISTINCT w.function, f.returns, p.asset FROM wants w JOIN fns f ON f.name = w.function
  JOIN places p ON p."where" = w."where"
   AND p.subject = CASE WHEN w."where" IN (SELECT "where" FROM anchored) THEN current_schema() ELSE w.subject END
  UNION
  SELECT 'column_profile', 'column_profile', s.table_name || '.' || unnest(s.columns)
  FROM glossql_views_scans(current_schema()) s WHERE s.view IN (SELECT view FROM tests WHERE run <> '')),
-- a stored result is current while its inputs are, a failure too: a check that failed is not
-- run again until something it read moves
stored AS (
  SELECT subject, aspect, bool_and(current) AS current, bool_or(error IS NOT NULL) AS failed
  FROM glossql_glossary(current_schema(), NULL, true) WHERE actor = 'function' GROUP BY ALL)
SELECT 1 AS ord, w.function, w.subject, 'SELECT ' || w.function || '() FROM ' || w.subject AS run
FROM wanted w LEFT JOIN stored s ON s.subject = w.subject AND s.aspect = w.aspect
WHERE NOT coalesce(s.current, false)
UNION ALL
SELECT DISTINCT 1, split_part(w, ' over ', 1), split_part(w, ' over ', 2),
       'SELECT ' || split_part(w, ' over ', 1) || '() FROM ' || split_part(w, ' over ', 2)
FROM (SELECT unnest(measurements_to_run) AS w FROM main.view_summary())
UNION ALL
SELECT DISTINCT 2, t.aspect, t.subject, t.run
FROM tests t LEFT JOIN stored s ON s.subject = t.subject AND s.aspect = t.aspect
WHERE t.run <> '' AND NOT coalesce(s.current AND s.failed, false)
  AND (t.state = 'not_run' OR NOT t.current OR NOT coalesce(s.current, true))
UNION ALL
SELECT DISTINCT 2, v.function, v.subject, 'SELECT ' || v.function || '() FROM ' || v.subject
FROM served v LEFT JOIN stored s ON s.subject = v.subject AND s.aspect = v.aspect
WHERE NOT coalesce(s.current, false);

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

--===------------------------------------------------------------------===--
-- load_modes(): per table of the bound dataset, its newest load held
-- against the load before it and against what the source sends (the
-- `delivery` annotation on the table): table_name (<dataset>.<table>),
-- mode (replace or merge), delivery (full, incremental, or NULL where
-- nobody stated it), rows (after the load), rows_before, source_rows
-- (what the file carried), changed_rows (what a merge wrote), identical
-- (a whole replace of 100,000 rows or more that holds the same rows as the
-- load before, by the fingerprint the engine stores), keys_carried (of a merge: the
-- keys the table held before that the file carried), keys_missed (of a
-- merge: the keys the table holds that the file did not carry), key (the
-- key a whole replace could merge by: the recipe's, the table's `entity`
-- grain, else a column whose stored profile is filled and unique), state,
-- level, open, statement. state is NULL where the load says nothing:
--   keys missing  a merge whose file carried at least 90% of the keys the
--     table held and missed some: the source likely sends its complete
--     state, and a row it no longer sends is kept here. must where the
--     delivery is stated full, should otherwise.
--   unchanged  a whole replace that is identical to the load before,
--     where the delivery is not stated full: a keyed
--     load would write only the changed rows. should.
-- The numbers, measured: a complete monthly file of EIA-860M carries
-- 99.84% to 99.99% of the generators of the month before; a yearly
-- filing of FERC Form 1 in the new system carries 3.7% to 13.2% of the
-- rows filed before. A replace of 1,000,000 identical rows of ten
-- columns writes 89 MB of Parquet, 100,000 rows 9 MB; a merge of the same
-- rows writes nothing. Each needs a stored load before the newest.
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.load_modes() AS TABLE
WITH loads AS (
  SELECT table_name, mode, rows, source_rows, changed_rows, identical, end_snapshot IS NULL AS newest,
         lag(rows) OVER (PARTITION BY table_name ORDER BY begin_snapshot) AS rows_before
  FROM main.imports_history WHERE dataset = current_schema()),
stated AS (
  SELECT subject, value->>'value' AS delivery FROM glossql_glossary(current_schema(), 'delivery', false)
  WHERE value IS NOT NULL AND state IN ('current', 'stale')),
grains AS (
  SELECT subject, from_json(value->'grain', '["VARCHAR"]') AS grain FROM glossql_glossary(current_schema(), 'entity', false)
  WHERE value IS NOT NULL AND state IN ('current', 'stale') AND json_array_length(value->'grain') > 0),
unique_columns AS (
  SELECT array_to_string(string_split(subject, '.')[1:2], '.') AS tbl, min(split_part(subject, '.', 3)) AS col
  FROM main.measurements
  WHERE dataset = current_schema() AND function = 'column_profile' AND value IS NOT NULL
    AND (value->>'total')::BIGINT > 0 AND (value->>'distinct')::BIGINT = (value->>'total')::BIGINT
    AND (value->>'null_ratio')::DOUBLE = 0
  GROUP BY 1),
recipe AS (
  SELECT current_schema() || '.' || table_name AS tbl, table_name, source, sql,
         nullif(json_extract_string(settings, '$.key'), '') AS key
  FROM main.recipes WHERE dataset = current_schema()),
judged AS (
  SELECT current_schema() || '.' || l.table_name AS table_name, l.mode, d.delivery, l.rows, l.rows_before,
         l.source_rows, l.changed_rows, l.identical,
         CASE WHEN l.mode = 'merge' THEN l.source_rows - (l.rows - l.rows_before) END AS keys_carried,
         CASE WHEN l.mode = 'merge' THEN l.rows - l.source_rows END AS keys_missed,
         coalesce(r.key, array_to_string(g.grain, ', '), u.col) AS key, r.table_name AS recipe_table, r.source, r.sql
  FROM loads l
  LEFT JOIN stated d ON d.subject = current_schema() || '.' || l.table_name
  LEFT JOIN grains g ON g.subject = current_schema() || '.' || l.table_name
  LEFT JOIN unique_columns u ON u.tbl = current_schema() || '.' || l.table_name
  LEFT JOIN recipe r ON r.tbl = current_schema() || '.' || l.table_name
  WHERE l.newest AND l.rows_before IS NOT NULL),
stated_state AS (
  SELECT *,
         CASE WHEN mode = 'merge' AND rows_before > 0 AND keys_missed > 0 AND keys_carried >= 0.9 * rows_before THEN 'keys missing'
              WHEN mode = 'replace' AND identical
                   AND delivery IS DISTINCT FROM 'full' THEN 'unchanged' END AS state
  FROM judged)
SELECT table_name, mode, delivery, rows, rows_before, source_rows, changed_rows, identical, keys_carried, keys_missed, key, state,
       CASE WHEN state = 'keys missing' AND delivery = 'full' THEN 'must' WHEN state IS NOT NULL THEN 'should' END AS level,
       CASE state
         WHEN 'keys missing'
         THEN 'the newest load of ' || table_name || ' merged a file that carried ' || keys_carried || ' of the ' || rows_before
              || ' keys the table held and missed ' || keys_missed || ': a row gone at the source is kept here'
              || CASE WHEN delivery = 'full' THEN ', and the source is stated to send its complete state' ELSE '' END
         WHEN 'unchanged'
         THEN 'the newest load of ' || table_name || ' wrote its ' || rows || ' rows again, the same rows as the load before: a keyed load writes only the changed rows' END AS open,
       CASE state
         WHEN 'keys missing'
         THEN '-- where each file holds the complete state, load without the key: the table is then the file' || chr(10)
              || 'DECLARE RECIPE ' || recipe_table || ' ON ' || current_schema() || ' FROM ' || source || ' AS $$' || sql || '$$;'
              || CASE WHEN delivery = 'full' THEN ''
                      ELSE chr(10) || '-- where the source sends only new and changed rows, state it:' || chr(10)
                           || 'GLOSS delivery ON ' || table_name || ' AS $${"value": "incremental", "basis": "<what the source sends>"}$$;' END
         WHEN 'unchanged'
         THEN '-- a keyed load keeps a row the file no longer carries: merge by the key only where rows are not deleted at the source, and state what it sends:' || chr(10)
              || 'DECLARE RECIPE ' || recipe_table || ' ON ' || current_schema() || ' FROM ' || source
              || ' SET (key: ' || CASE WHEN key IS NULL THEN '<key column>' WHEN contains(key, ',') THEN '''' || key || '''' ELSE key END
              || ') AS $$' || sql || '$$;' || chr(10)
              || 'GLOSS delivery ON ' || table_name || ' AS $${"value": "<full|incremental>", "basis": "<what the source sends>"}$$;' END AS statement
FROM stated_state;

-- pairs_key(lt, rt, lc, rc): the column pairs of a join or a relationship
-- between tables lt and rt (lc and rc their columns, pair by pair) as one
-- key, the same whichever side is written first.
-- relationship_side(ds, t, cols, quoted): one side of a relationship,
-- dataset.table.column or dataset.table.(a, b), each name quoted where a
-- statement needs it.
CREATE OR REPLACE MACRO main.pairs_key(lt, rt, lc, rc) AS
  CASE WHEN lt <= rt
       THEN lt || '|' || rt || '|' || array_to_string(list_sort(list_transform(range(1, len(lc) + 1), lambda i: lc[i] || '=' || rc[i])), ',')
       ELSE rt || '|' || lt || '|' || array_to_string(list_sort(list_transform(range(1, len(lc) + 1), lambda i: rc[i] || '=' || lc[i])), ',') END;

CREATE OR REPLACE MACRO main.relationship_side(ds, t, cols, quoted) AS
  ds || '.' || t || '.' || CASE WHEN len(cols) = 1 THEN '' ELSE '(' END
  || array_to_string(list_transform(cols, lambda c: CASE WHEN NOT quoted OR regexp_full_match(c, '[a-z_][a-z0-9_]*') THEN c
                                                         ELSE '"' || replace(c, '"', '""') || '"' END), ', ')
  || CASE WHEN len(cols) = 1 THEN '' ELSE ')' END;

-- next: what is open on the bound dataset, read from the states the
-- catalog holds. One row per asset, state and level: level, ord, kind,
-- asset, state, who (agent or person), open (the finding), for_view (the
-- views that read the asset), cause (what the newest load changed),
-- statement (what opens the work; <...> marks what only the author can
-- fill). The rows are ordered by level, then ord, then asset, then the
-- finding (a test's starts with the test's name).
--
-- level:
-- must: served data is wrong or cannot be served. No table is loaded, no
--   view is defined, a metric serves no series, a test is red, two values
--   conflict, a person decided something (a load query, a review
--   decision, a formula) that is not carried yet.
-- should: the layer is incomplete for what is served. An annotation is
--   missing or outdated on what a view reads or serves, a join a view
--   makes between two loaded tables has no declared relationship, a test
--   on it is neither green nor red, an assumption waits for a person, a
--   stored result is out of date and the server does not compute it
--   (results_due() does not list it). A test stays a should while it has
--   not run, its result is out of date, it is orange or failed, or it is
--   yellow with a fix; a yellow test whose check ran, is current and
--   returns no fix has nothing to check and is no row: its statement
--   would compute it yellow again.
-- could: what sits beside. An annotation is missing or outdated on a
--   table, a column, a relationship or the dataset that no view reads.
-- Work on a dataset is complete when no must is open.
--
-- ord, inside a level, puts what blocks other work first: 1 a source, a
-- table or a view to integrate, 2 a person's decision to carry, 3 a test,
-- 4 an annotation, 5 a stored result to compute again, 6 a question for
-- a person.
--
-- kind is the kind of work: integrate, describe, test, review. The
-- kinds are labels, not stages. A test's finding and fix are the test's
-- own (`finding` and `fix` in its result), on a view, a table, a column
-- or the dataset alike, whatever declared it: a kit adds rows only
-- through its tests (view_tests()) and its stored results, and its rows
-- take their level from their state. A red test without a `fix` gets the
-- check to run again and the statement that accepts its rate. A property
-- that exists to be tested (tested_properties()) is a row where its test
-- is set, and is not asked for on the other assets.
CREATE OR REPLACE VIEW main.next AS
  WITH ds AS (SELECT current_schema() AS d),
  scans AS (SELECT view, table_name AS tbl, unnest(columns) AS col
            FROM glossql_views_scans(current_schema())),
  summary AS MATERIALIZED (SELECT * FROM main.view_summary()),
  -- a load-query change a person approved, with no load of the table since
  approved AS (
    SELECT json_extract_string(a.body, '$.table') AS tbl FROM main.glossary a CROSS JOIN ds
    LEFT JOIN (SELECT i.table_name, max(i.imported_at) AS imported_at FROM main.imports i, ds WHERE i.dataset = ds.d GROUP BY i.table_name) l
      ON l.table_name = json_extract_string(a.body, '$.table')
    WHERE a.dataset = ds.d AND a.aspect = 'recipe_change' AND a.actor_kind = 'human'
      AND json_extract_string(a.body, '$.table') IS NOT NULL
      AND NOT coalesce(l.imported_at >= a.written_at, false)),
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
  -- what the newest load changed under each view, per table it scans
  view_causes AS (
    SELECT v.view, string_agg(r.tbl || ' ' || r.cause, chr(10) ORDER BY r.tbl) AS causes
    FROM (SELECT DISTINCT view, tbl FROM scans) v JOIN reloaded r ON r.tbl = v.tbl GROUP BY v.view),
  -- the statement that records each view's definition again, as it is now
  redefines AS (
    SELECT g.aspect AS view, main.gloss_statement(g.aspect, ds.d, g.body::VARCHAR) AS statement
    FROM main.glossary g, ds WHERE g.dataset = ds.d AND g.subject = ds.d
    QUALIFY row_number() OVER (PARTITION BY g.aspect ORDER BY g.begin_snapshot DESC) = 1),
  vt AS MATERIALIZED (SELECT * FROM glossql_kept('view_tests')),
  -- the tests that are open: not green, but a yellow test whose check ran, is current and returns no
  -- fix (not applicable: nothing to check), whose statement would compute it yellow again
  vo AS (
    SELECT * FROM vt
    WHERE state <> 'green' AND NOT (state = 'yellow' AND current AND evidence IS NOT NULL AND evidence->>'fix' IS NULL)),
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
                WHEN json_extract(schema, '$.examples[0]') IS NOT NULL THEN json_extract(schema, '$.examples[0]')::VARCHAR
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
  -- an outdated annotation on a view or under it, written before the
  -- view's newest definition
  redefined AS (
    SELECT DISTINCT w.subject, w.aspect FROM written w JOIN defined d
      ON d.begin_snapshot > w.begin_snapshot AND (w.subject = d.home OR starts_with(w.subject, d.home || '.'))),
  -- what the views read, and every value withheld as a conflict; a
  -- conflict a test reports is the test's row
  homed AS (
    SELECT g.subject, g.aspect, g.state, x.views,
           CASE WHEN g.subject LIKE '% -> %' THEN g.subject
                ELSE array_to_string(string_split(g.subject, '.')[1:2], '.') END AS home,
           CASE WHEN g.state = 'conflict' THEN 'must' WHEN x.asset IS NOT NULL THEN 'should' ELSE 'could' END AS level,
           s.shape IS NULL AND g.state = 'missing' AS unshaped,
           coalesce(g.state = 'stale' AND rd.subject IS NOT NULL, false) AS redefined,
           'GLOSS ' || g.aspect || ' ON ' || g.subject || ' AS $$'
             || CASE WHEN g.state = 'stale' THEN coalesce(w.body, s.shape, '<value>') ELSE coalesce(s.shape, '<value>') END
             || '$$;' AS gloss
    FROM g JOIN stated s ON s.name = g.aspect LEFT JOIN reach x ON x.asset = g.subject
    LEFT JOIN written w ON w.aspect = g.aspect AND w.subject = g.subject
    LEFT JOIN redefined rd ON rd.subject = g.subject AND rd.aspect = g.aspect
    -- a view's own columns are asked for where a view serves them (a
    -- table view's), not beside it
    WHERE (x.asset IS NOT NULL OR g.state = 'conflict'
           OR array_to_string(string_split(g.subject, '.')[1:2], '.') NOT IN (SELECT ds.d || '.' || view FROM summary, ds))
      AND NOT (s.expectation AND g.state = 'missing')
      -- `entity` says what one row of a table is: asked on a loaded
      -- table and on a table view, not on a metric, a single value or a plan
      AND NOT (g.aspect = 'entity' AND g.state = 'missing'
               AND g.subject IN (SELECT ds.d || '.' || m.view FROM summary m, ds WHERE coalesce(m.kind, '') <> 'relation'))
      AND NOT (g.state = 'conflict'
               AND {'subject': g.subject, 'aspect': g.aspect} IN (SELECT {'subject': subject, 'aspect': aspect} FROM vt WHERE state <> 'green'))
    UNION ALL
    -- a column property asked per table (x-asked: per table): once a
    -- column of a table or a view carries it, each other column is asked
    SELECT ds.d || '.' || c.table_name || '.' || c.column_name, a.name, 'missing', x.views, ds.d || '.' || c.table_name,
           CASE WHEN x.asset IS NOT NULL THEN 'should' ELSE 'could' END, false, false,
           'GLOSS ' || a.name || ' ON ' || ds.d || '.' || c.table_name || '.' || c.column_name || ' AS $$' || coalesce(s.shape, '<value>') || '$$;'
    FROM (SELECT DISTINCT name FROM main.aspects WHERE json_extract_string(schema, '$.x-asked') = 'per table') a
    JOIN stated s ON s.name = a.name CROSS JOIN ds CROSS JOIN glossql_columns(current_schema()) c
    LEFT JOIN reach x ON x.asset = ds.d || '.' || c.table_name || '.' || c.column_name
    WHERE {'aspect': a.name, 'tbl': c.table_name} IN (
            SELECT {'aspect': w.aspect, 'tbl': split_part(w.subject, '.', 2)} FROM main.glossary w, ds
            WHERE w.dataset = ds.d AND w.actor_kind IN ('agent', 'human') AND len(string_split(w.subject, '.')) >= 3
              AND starts_with(w.subject, ds.d || '.'))
      AND {'aspect': a.name, 'subject': ds.d || '.' || c.table_name || '.' || c.column_name} NOT IN (
            SELECT {'aspect': w.aspect, 'subject': w.subject} FROM main.glossary w, ds WHERE w.dataset = ds.d)
    UNION ALL
    -- a metric's served column with no role: the statement its summary
    -- row names (`missing`, empty for every other view), on the view's own
    -- column, so that the summary row and this list ask for the same annotation
    SELECT ds.d || '.' || u.view || '.' || u.col, 'role', 'missing', u.view, ds.d || '.' || u.view, 'should', false, false, u.statement
    FROM (SELECT m.view, unnest(m.columns_without_role) AS col, unnest(m.missing) AS statement FROM summary m
          WHERE m.stopped IS NULL) u, ds),
  s_load AS (
    SELECT 'must' AS level, 1 AS ord, 'integrate' AS kind, ds.d AS asset, 'missing' AS state, 'agent' AS who,
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
    SELECT 'must', 2, 'integrate', ds.d || '.' || o.tbl, 'decided', 'agent',
           'a person approved a change to the load query of ' || o.tbl || '; it is not declared yet', '', '',
           '-- the approved SQL: SELECT body FROM glossary WHERE aspect = ''recipe_change'';' || chr(10)
             || 'DECLARE RECIPE ' || o.tbl || ' ON ' || ds.d || ' FROM <source> AS $$<the approved sql>$$;'
    FROM approved o, ds),
  s_describe AS (
    SELECT h.level, 4, 'describe', h.home, h.state, 'agent',
           count(*) || ' ' || CASE h.state WHEN 'stale' THEN 'outdated' WHEN 'conflict' THEN 'in conflict' ELSE h.state END || ': '
             || string_agg(DISTINCT h.aspect, ', ' ORDER BY h.aspect),
           coalesce(max(h.views), ''),
           -- what made the annotations outdated: the table's own load, the
           -- view's definition recorded again, or a load of a table the view scans
           CASE WHEN h.state = 'stale'
                THEN coalesce(max(l.cause),
                              CASE WHEN bool_or(h.redefined) THEN 'the definition of ' || h.home || ' was recorded again' END,
                              max(vc.causes),
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
    LEFT JOIN view_causes vc ON current_schema() || '.' || vc.view = h.home
    WHERE h.state IN ('missing', 'stale', 'conflict')
    GROUP BY h.home, h.state, h.level),
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
    SELECT CASE t.state WHEN 'red' THEN 'must' ELSE 'should' END, 3, 'test', t.subject, t.state, 'agent',
           t.test || coalesce(': ' || coalesce(t.evidence->>'finding', t.evidence->>'reason'), ''), t.view,
           coalesce(vc.causes, ''),
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
    FROM vo t LEFT JOIN accepts k ON k.test = t.test
    LEFT JOIN view_causes vc ON vc.view = t.view
    LEFT JOIN written e ON e.subject = t.subject AND e.aspect = t.aspect),
  -- a join a view makes between two loaded tables on columns no declared
  -- relationship covers: the pairs of one join, its key, in the join's
  -- order; a relationship covers it where its pairs are the join's, either
  -- way round. The statement declares it from the side that repeats the key
  -- to the side that holds it once, as a stored profile (a unique column)
  -- or the table's stated grain says; where neither does, left to right
  loaded AS (SELECT DISTINCT table_name FROM glossql_columns(current_schema()) WHERE table_type = 'BASE TABLE'),
  joined AS (
    SELECT j.view, j.join_number, split_part(j.left_column, '.', 2) AS lt, split_part(j.right_column, '.', 2) AS rt,
           list(regexp_replace(j.left_column, '^[^.]*\.[^.]*\.', '') ORDER BY j.left_column, j.right_column) AS lc,
           list(regexp_replace(j.right_column, '^[^.]*\.[^.]*\.', '') ORDER BY j.left_column, j.right_column) AS rc
    FROM glossql_views_joins(current_schema()) j
    WHERE split_part(j.left_column, '.', 1) = current_schema() AND split_part(j.right_column, '.', 1) = current_schema()
      AND split_part(j.left_column, '.', 2) <> split_part(j.right_column, '.', 2)
      AND split_part(j.left_column, '.', 2) IN (SELECT table_name FROM loaded)
      AND split_part(j.right_column, '.', 2) IN (SELECT table_name FROM loaded)
      AND j.view IN (SELECT view FROM summary WHERE stopped IS NULL)
    GROUP BY j.view, j.join_number, split_part(j.left_column, '.', 2), split_part(j.right_column, '.', 2)),
  declared_pairs AS (
    SELECT main.pairs_key(split_part(left_side, '.', 2), split_part(right_side, '.', 2),
             string_split(regexp_replace(regexp_replace(left_side, '^[^.]+\.[^.]+\.', ''), '^\((.*)\)$', '\1'), ', '),
             string_split(regexp_replace(regexp_replace(right_side, '^[^.]+\.[^.]+\.', ''), '^\((.*)\)$', '\1'), ', ')) AS key
    FROM main.relationships, ds WHERE dataset = ds.d),
  undeclared AS (
    SELECT key, string_agg(DISTINCT view, ', ' ORDER BY view) AS views,
           arg_min(lt, view) AS lt, arg_min(rt, view) AS rt, arg_min(lc, view) AS lc, arg_min(rc, view) AS rc
    FROM (SELECT *, main.pairs_key(lt, rt, lc, rc) AS key FROM joined)
    WHERE key NOT IN (SELECT key FROM declared_pairs WHERE key IS NOT NULL)
    GROUP BY key),
  held_once AS (
    SELECT split_part(subject, '.', 2) AS t, [split_part(subject, '.', 3)] AS cols FROM main.measurements, ds
    WHERE dataset = ds.d AND function = 'column_profile' AND value IS NOT NULL AND (value->>'total')::BIGINT > 0
      AND (value->>'distinct')::BIGINT >= round((value->>'total')::DOUBLE * (1 - coalesce((value->>'null_ratio')::DOUBLE, 0)))
    UNION ALL
    SELECT split_part(subject, '.', 2), from_json(value->'grain', '["VARCHAR"]') FROM glossql_glossary(current_schema(), 'entity', false)
    WHERE value IS NOT NULL AND state IN ('current', 'stale') AND json_array_length(value->'grain') > 0),
  sided AS (
    SELECT u.*,
           u.key IN (SELECT x.key FROM undeclared x JOIN held_once h ON h.t = x.lt AND list_has_all(x.lc, h.cols)) AS left_once,
           u.key IN (SELECT x.key FROM undeclared x JOIN held_once h ON h.t = x.rt AND list_has_all(x.rc, h.cols)) AS right_once
    FROM undeclared u),
  -- from the side that repeats the key to the side that holds it once
  directed AS (
    SELECT views, left_once, right_once,
           CASE WHEN left_once AND NOT right_once THEN rt ELSE lt END AS ft, CASE WHEN left_once AND NOT right_once THEN rc ELSE lc END AS fc,
           CASE WHEN left_once AND NOT right_once THEN lt ELSE rt END AS tt, CASE WHEN left_once AND NOT right_once THEN lc ELSE rc END AS tc,
           CASE WHEN left_once AND right_once THEN ' <-> ' ELSE ' -> ' END AS op
    FROM sided),
  s_joins AS (
    SELECT 'should', 4, 'describe',
           main.relationship_side(ds.d, ft, fc, false) || op || main.relationship_side(ds.d, tt, tc, false), 'missing', 'agent',
           'no relationship is declared for the join of ' || ft || ' and ' || tt || ' on '
             || array_to_string(list_transform(range(1, len(fc) + 1), lambda i: ft || '.' || fc[i] || ' = ' || tt || '.' || tc[i]), ' and ')
             || ': the orphan check and the reconciliation name no keys on it', views, '',
           CASE WHEN left_once AND right_once THEN '-- each side holds each key once'
                WHEN left_once OR right_once THEN '-- ' || tt || ' holds each key once'
                ELSE '-- no stored profile or grain says which side holds each key once: the direction is the join''s, left to right; where '
                     || ft || ' holds each key once, write it the other way round' END
             || '. Declare the relationship, and the server checks each key against the data:' || chr(10)
             || 'DECLARE RELATIONSHIP ' || main.relationship_side(ds.d, ft, fc, true) || op || main.relationship_side(ds.d, tt, tc, true) || ';'
    FROM directed, ds),
  -- a load that does not fit what the source sends (load_modes())
  s_loads AS (
    SELECT l.level, 1, 'integrate', l.table_name, l.state, 'agent', l.open, coalesce(x.views, ''), '', l.statement
    FROM main.load_modes() l LEFT JOIN reach x ON x.asset = l.table_name WHERE l.state IS NOT NULL),
  s_review AS (
    SELECT 'must', 2, 'review', ds.d || '.' || r.aspect, 'decided', 'agent',
           'a person decided ' || r.key || ' (' || r.stance || ')' || coalesce(': ' || nullif(r.note, ''), '')
             || '; the definition does not carry it yet', r.aspect, '',
           '-- set the assumption with key "' || r.key || '" to confidence 1.0 and basis "decided-by-person", change the SQL where the decision asks for it, then record the definition again:' || chr(10)
             || coalesce(rd.statement, main.gloss_statement(r.aspect, ds.d, '<the current definition>'))
    FROM main.review_decisions r CROSS JOIN ds LEFT JOIN redefines rd ON rd.view = r.aspect
    WHERE r.dataset = ds.d AND NOT r.folded_in
    UNION ALL
    SELECT 'must', 2, 'review', ds.d || '.' || o.view, 'decided', 'agent',
           'a person''s formula for ' || o.view || ' is newer than its definition', o.view, '',
           '-- the formula: SELECT formula FROM view_definitions WHERE name = ''' || o.view || '''; change the SQL to match it, then record the definition again:' || chr(10)
             || coalesce(rd.statement, main.gloss_statement(o.view, ds.d, '<the current definition>'))
    FROM formulas o CROSS JOIN ds LEFT JOIN redefines rd ON rd.view = o.view
    UNION ALL
    SELECT 'should', 6, 'review', ds.d || '.' || q.aspect, 'waiting', 'person',
           'the assumption ' || q.key || ' waits for a person''s decision: ' || q.assumption, q.aspect, '',
           'SELECT key, assumption, basis, alternative FROM open_questions WHERE aspect = ''' || q.aspect || ''' AND key = ''' || q.key || ''';'
    FROM main.open_questions q, ds WHERE q.dataset = ds.d),
  s_views AS (
    SELECT 'must', 1, 'integrate', ds.d, 'missing', 'agent', 'no view is defined (a table, a single value or a metric)', '', '',
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
    SELECT 'must', 1, 'integrate', ds.d || '.' || m.view, 'blocked', 'agent', coalesce(m.reason, 'no series is served'), m.view, '',
           CASE WHEN m.period_column IS NULL
                THEN 'GLOSS role ON ' || ds.d || '.' || m.view || '.<period column> AS $${"value": "timestamp"}$$;'
                WHEN m.value_column IS NULL
                THEN 'GLOSS role ON ' || ds.d || '.' || m.view || '.<value column> AS $${"value": "measure"}$$;'
                WHEN m.floor IS NULL AND len(m.measurements_to_run) > 0
                THEN 'SELECT temporal() FROM ' || ds.d || '.' || m.view || '.' || m.period_column || ';'
                WHEN m.floor IS NULL
                THEN 'GLOSS time_grains ON ' || ds.d || '.' || m.view || '.' || m.period_column || ' AS $${"floor": "<minute|hour|day|week|month|quarter|year>"}$$;'
                ELSE coalesce(rd.statement, main.gloss_statement(m.view, ds.d, '<the current definition>')) END
    FROM summary m CROSS JOIN ds LEFT JOIN redefines rd ON rd.view = m.view
    -- a single value and a table are served as they are; only a metric needs a series
    WHERE NOT m.applicable AND m.stopped IS NULL AND coalesce(m.kind, '') NOT IN ('scalar', 'relation')
      AND m.view NOT IN (SELECT view FROM vo)),
  -- a stored result out of date that the server does not compute: one
  -- about the dataset as a whole or about a view, whatever kit declares
  -- its function, but a check a test on the view runs (view_tests()
  -- names it as the test's `run`)
  s_results AS (
    SELECT 'should', 5, 'test', o.subject, 'stale', 'agent',
           o.function || ': computed before a read of it changed (' || o.inputs || ')',
           coalesce(o.view, ''), '',
           'SELECT ' || o.function || '() FROM ' || o.subject || ';'
    FROM (SELECT u.function, u.subject, any_value(v.view) AS view, string_agg(DISTINCT u.asset || ' ' || u.what, ', ' ORDER BY u.asset || ' ' || u.what) AS inputs
          FROM glossql_outdated() u
          LEFT JOIN (SELECT view FROM summary WHERE stopped IS NULL) v ON u.subject = current_schema() || '.' || v.view
          WHERE u.dataset = current_schema() AND (u.subject = current_schema() OR v.view IS NOT NULL)
            AND 'SELECT ' || u.function || '() FROM ' || u.subject NOT IN (SELECT run FROM vt)
            AND {'function': u.function, 'subject': u.subject} NOT IN (SELECT {'function': function, 'subject': subject} FROM main.server_results())
          GROUP BY u.function, u.subject) o)
  SELECT * FROM (
    SELECT * FROM s_load UNION ALL SELECT * FROM s_loads UNION ALL SELECT * FROM s_describe UNION ALL SELECT * FROM s_joins
    UNION ALL SELECT * FROM s_test
    UNION ALL SELECT * FROM s_review UNION ALL SELECT * FROM s_views UNION ALL SELECT * FROM s_results)
  ORDER BY CASE level WHEN 'must' THEN 1 WHEN 'should' THEN 2 ELSE 3 END, ord, asset, state, open;
