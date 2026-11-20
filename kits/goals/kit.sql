-- The interfaces' reads that build on the kits', declared at every open
-- after the kits, where core.sql comes before them: what the server
-- brings current by itself (`results_due()`) and what it cannot, the
-- work list of the bound dataset (`next`).

--===------------------------------------------------------------------===--
-- results_due(): the results the bound dataset wants that
-- are missing or out of date, each with the statement that computes it,
-- in the order to run them: ord, function, subject, run. A view's lineage
-- comes first (ord 0): missing, out of date, or on a view that is gone. A result is due
-- when a node it read (the catalog's `inputs`) changed after the snapshot
-- it read at; one that read a result out of date waits until that result
-- is computed again, and is due only if its value differs. A check that failed is
-- a result with its error, due again once it is out of date. What is
-- wanted follows from the tests on each view and on what it reads
-- (view_tests()), whatever the kind of view: each test's check, and
-- before it (ord 1) every result the check's body reads, at the place it
-- names from the test's subject, as the function's stored `reads` say
-- (join_check reads the profile of the columns a view joins on,
-- orphan_check the coherence of the relationships between the tables it
-- reads); the profile of each column a view scans, which load_changes()
-- compares to say what a load changed under the view; and the measurement a metric's row names as not run (the grain
-- of its period column); then (ord 3) each test's result on
-- each subject that holds a value of its property, or will once a result
-- due before it in the round is computed, where none is stored, the
-- stored one is out of date, or its subject holds no value any more:
-- one statement per test, `SELECT <test>() FROM <dataset>`, computes them
-- all. The server computes these after each write, a statement once. Any other result about the dataset or a view (a kit's function an
-- actor runs) is the actor's to compute: once it is out of date, `next`
-- lists it with its statement.
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.results_due() AS TABLE
WITH tests AS MATERIALIZED (SELECT view, subject, property, state, current, run FROM main.view_tests()),
fns AS MATERIALIZED (
  SELECT name, returns, reads FROM main.functions QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
-- the check that measures a test's property, as view_tests() names it
checks AS (SELECT returns AS property, min(name) AS name FROM fns WHERE returns IS NOT NULL GROUP BY returns),
-- the results each check reads, by the place its body names
wants AS (
  SELECT DISTINCT t.subject, r.what AS function, r."where"
  FROM tests t JOIN checks c ON c.property = t.property JOIN fns f ON f.name = c.name,
       unnest(from_json(f.reads, '[{"kind": "VARCHAR", "read": "VARCHAR", "what": "VARCHAR", "where": "VARCHAR"}]')) u(r)
  WHERE t.run <> '' AND r.kind = 'read' AND r.read = 'results'),
anchored AS (SELECT p."where" FROM (SELECT unnest(main.place_list()) AS p) WHERE p.anchored),
places AS MATERIALIZED (FROM main.places(current_schema()) WHERE "where" IN (SELECT "where" FROM wants)),
wanted AS (
  SELECT DISTINCT w.function, f.returns AS property, w.subject FROM wants w JOIN fns f ON f.name = w.function
  WHERE w."where" = 'itself'
  UNION
  SELECT DISTINCT w.function, f.returns, p.asset FROM wants w JOIN fns f ON f.name = w.function
  JOIN places p ON p."where" = w."where"
   AND p.subject = CASE WHEN w."where" IN (SELECT "where" FROM anchored) THEN current_schema() ELSE w.subject END
  -- of a place's assets, those the function's property is declared on: a view's sources are its
  -- tables and their columns, and a column's profile is wanted on the columns
  WHERE NOT EXISTS (SELECT 1 FROM main.properties a WHERE a.name = f.returns AND len(a.grains) > 0
                    AND NOT list_contains(a.grains, main.asset_grain(p.asset)))
  UNION
  SELECT 'column_profile', 'column_profile', s.table_name || '.' || unnest(s.columns)
  FROM main.views_scans(current_schema()) s WHERE s.view IN (SELECT view FROM tests WHERE run <> '')),
-- a stored result is due while a node it read changed after it read, a failure too: a check that
-- failed is not run again until something it read moves. One that is possibly out of date waits for
-- what it read: computed again, the same value leaves it current, another makes it out of date
changed AS (SELECT DISTINCT function, subject FROM glossql_outdated()
            WHERE dataset = current_schema() AND reason = 'changed'),
stored AS (
  SELECT m.subject, m.property, bool_and(c.function IS NULL) AS current, bool_or(m.error IS NOT NULL) AS failed
  FROM main.results m LEFT JOIN changed c ON c.function = m.function AND c.subject = m.subject
  WHERE m.dataset = current_schema() GROUP BY ALL),
-- a test's result (ord 3), after what it judges: on each subject that holds a value of the tested
-- property where none is stored or the stored one is out of date, and stored on a subject that holds
-- none, which computing the test retires. One statement computes a test over the dataset
detecting AS (SELECT t.name AS test, t.property, list_contains(a.grains, 'SOURCE') AS source_grain FROM main.tests t
              JOIN main.properties a ON a.name = t.property WHERE t.detector IS NOT NULL),
holding AS (
  SELECT d.test, g.subject FROM detecting d JOIN main.glossary g ON g.property = d.property
  WHERE g.dataset = current_schema() OR (d.source_grain AND g.subject IN (SELECT name FROM main.sources))
  UNION
  SELECT d.test, m.subject FROM detecting d JOIN main.results m ON m.property = d.property
  WHERE m.dataset = current_schema() AND m.error IS NULL),
judged_now AS (SELECT function AS test, subject FROM main.results WHERE dataset = current_schema() AND property = 'test'),
-- the results due before the tests (ord 1 and 2), each with the property it fills
due AS (
  SELECT 1 AS ord, w.function, w.property, w.subject, 'SELECT ' || w.function || '() FROM ' || main.subject_path(w.subject) AS run
  FROM wanted w LEFT JOIN stored s ON s.subject = w.subject AND s.property = w.property
  WHERE NOT coalesce(s.current, false)
  UNION
  SELECT 1, split_part(x.w, ' over ', 1), f.returns, split_part(x.w, ' over ', 2),
         'SELECT ' || split_part(x.w, ' over ', 1) || '() FROM ' || main.subject_path(split_part(x.w, ' over ', 2))
  FROM (SELECT unnest(measurements_to_run) AS w FROM main.view_summary()) x
  LEFT JOIN fns f ON f.name = split_part(x.w, ' over ', 1)
  UNION
  SELECT 2, t.property, t.property, t.subject, t.run
  FROM tests t LEFT JOIN stored s ON s.subject = t.subject AND s.property = t.property
  WHERE t.run <> '' AND NOT coalesce(s.current, false)),
-- a subject whose value is due before the test holds it once that runs: the test runs after it in the
-- same round, so a value computed for the first time is judged without a round of its own
judged AS (
  (SELECT test, subject FROM holding EXCEPT SELECT test, subject FROM judged_now)
  UNION SELECT c.function, c.subject FROM changed c JOIN detecting d ON d.test = c.function
  UNION SELECT d.test, u.subject FROM due u JOIN detecting d ON d.property = u.property
  UNION (SELECT test, subject FROM judged_now WHERE test IN (SELECT test FROM detecting)
         EXCEPT SELECT test, subject FROM holding)),
-- a view's lineage first (ord 0), what reads it after: missing on a view of the dataset, out of date, or
-- stored on a view that is gone, which computing it retires
views AS (SELECT current_schema() || '.' || view_name AS subject FROM duckdb_views()
          WHERE database_name = current_database() AND schema_name = current_schema() AND NOT internal
            AND current_schema() IN (SELECT name FROM main.datasets)),
lineages AS (
  SELECT subject FROM views EXCEPT SELECT subject FROM main.results WHERE dataset = current_schema() AND function = 'lineage'
  UNION SELECT subject FROM changed WHERE function = 'lineage'
  UNION (SELECT subject FROM main.results WHERE dataset = current_schema() AND function = 'lineage'
         EXCEPT SELECT subject FROM views))
SELECT 0 AS ord, 'lineage' AS function, subject, 'SELECT lineage() FROM ' || main.subject_path(subject) AS run FROM lineages
UNION ALL
SELECT ord, function, subject, run FROM due
UNION ALL
SELECT 3, test, subject, 'SELECT ' || test || '() FROM ' || current_schema() FROM judged;

--===------------------------------------------------------------------===--
-- results_moved_since(since): what a round of results_due() leaves for
-- the next, after the snapshot `since` it began at: each result of the
-- bound dataset that read a node the round changed before it changed (a
-- result computed again with another value or retired, read through its
-- function's results or its property's values; a function's declaration
-- taken again), now due or waiting for what it read; and each view whose
-- lineage the round changed, since what is wanted follows from it.
-- A result computed after what it read, in the same round, reads it as it
-- is. The server asks after each round and stops where it is empty.
--===------------------------------------------------------------------===--
CREATE OR REPLACE MACRO main.results_moved_since(since) AS TABLE
WITH moved AS (
  SELECT dataset, function, property, lower(subject) AS asset,
         coalesce(max(changed_at) FILTER (WHERE end_snapshot IS NULL), max(end_snapshot)) AS changed_at
  FROM main.results_history
  WHERE dataset = current_schema() AND (begin_snapshot > since OR end_snapshot > since)
  GROUP BY ALL),
declared AS (SELECT lower(name) AS asset, begin_snapshot AS changed_at FROM main.functions WHERE begin_snapshot > since)
SELECT r.function, r.subject FROM moved m
JOIN main.inputs i ON lower(i.asset) = m.asset AND i.what IN ('result ' || m.function, 'value ' || m.property)
JOIN main.results r ON r.id = i.result AND r.dataset = m.dataset AND r.function <> m.function
WHERE m.changed_at > since AND m.changed_at > r.read_at
UNION
SELECT r.function, r.subject FROM declared d
JOIN main.inputs i ON lower(i.asset) = d.asset AND i.what = 'function'
JOIN main.results r ON r.id = i.result AND r.dataset = current_schema()
WHERE d.changed_at > r.read_at
UNION
SELECT 'lineage', asset FROM moved WHERE function = 'lineage' AND changed_at > since;

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
  FROM main.results_history WHERE dataset = current_schema() AND function = 'column_profile'),
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
  FROM main.results
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

-- next: what is open on the bound dataset, read from the states the
-- catalog holds: annotation states, test results, a person's decisions.
-- It judges nothing itself: a judgement is a test whose result the server
-- stores after a write, and its row is the test's. One row per asset,
-- state and level: level, ord, kind, asset, state, who (agent or person),
-- open (the finding), for_view (the views that read the asset),
-- statement (what opens the work; <...> marks what only the author can
-- fill). The rows are ordered by level, then ord, then asset, then the
-- finding (a test's starts with the test's name).
--
-- level:
-- must: served data is wrong or cannot be served. No table is loaded, no
--   view is defined, a test is red (series_test: a metric serves no
--   series), two values conflict, a person decided something (a load
--   query, a review decision) that is not carried yet.
-- should: the layer is incomplete for what is served. An annotation is
--   missing or outdated on what a view reads or serves, a test on it is
--   neither green nor red (relationship_test: a join a view makes has no
--   declared relationship), a load does not fit what the source sends,
--   an assumption waits for a person, a stored result is out of date and
--   the server does not compute it (results_due() does not list it). A test stays a should while it has
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
            FROM main.views_scans(current_schema())),
  summary AS MATERIALIZED (SELECT * FROM main.view_summary()),
  -- a load-query change a person approved, with no load of the table since
  approved AS (
    SELECT json_extract_string(a.body, '$.table') AS tbl FROM main.glossary a CROSS JOIN ds
    LEFT JOIN (SELECT i.table_name, max(i.imported_at) AS imported_at FROM main.imports i, ds WHERE i.dataset = ds.d GROUP BY i.table_name) l
      ON l.table_name = json_extract_string(a.body, '$.table')
    WHERE a.dataset = ds.d AND a.property = 'recipe_change' AND a.actor_kind = 'human'
      AND json_extract_string(a.body, '$.table') IS NOT NULL
      AND NOT coalesce(l.imported_at >= a.written_at, false)),
  -- the statement that records each view's definition again, as it is now
  redefines AS (
    SELECT g.property AS view, main.gloss_statement(g.property, ds.d, g.body::VARCHAR) AS statement
    FROM main.glossary g, ds WHERE g.dataset = ds.d AND g.subject = ds.d
    QUALIFY row_number() OVER (PARTITION BY g.property ORDER BY g.begin_snapshot DESC) = 1),
  vt AS MATERIALIZED (SELECT * FROM main.view_tests()),
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
    FROM main.properties
    WHERE kind = 'FACT' AND json_extract_string(schema, '$.x-subject') IS NULL
      -- a kit's own result, such as a metric's expected ranges, is computed, not stated
      AND name NOT IN (SELECT returns FROM main.functions WHERE returns IS NOT NULL AND declared_by LIKE 'kit:%')),
  g AS (SELECT subject, property, state FROM glossql_glossary(current_schema(), NULL, false)),
  -- the newest annotation on each asset: an outdated one is offered
  -- back to be checked and recorded again
  written AS (
    SELECT w.subject, w.property, w.body::VARCHAR AS body, w.begin_snapshot FROM main.glossary w, ds
    WHERE w.dataset = ds.d AND w.actor_kind IN ('agent', 'human')
    QUALIFY row_number() OVER (PARTITION BY w.subject, w.property ORDER BY w.begin_snapshot DESC) = 1),
  -- each view's newest definition: an annotation on the view written
  -- before it describes the definition before
  defined AS (
    SELECT ds.d || '.' || w.property AS home, w.property AS view, max(w.begin_snapshot) AS begin_snapshot FROM main.glossary w, ds
    WHERE w.dataset = ds.d AND w.subject = ds.d AND w.property IN (SELECT view FROM summary)
    GROUP BY ALL),
  -- an outdated annotation on a view or under it, written before the
  -- view's newest definition
  redefined AS (
    SELECT DISTINCT w.subject, w.property FROM written w JOIN defined d
      ON d.begin_snapshot > w.begin_snapshot AND (w.subject = d.home OR starts_with(w.subject, d.home || '.'))),
  -- what the views read, and every value withheld as a conflict; a
  -- conflict a test reports is the test's row
  homed AS (
    SELECT g.subject, g.property, g.state, x.views,
           CASE WHEN g.subject LIKE '% -> %' THEN g.subject
                ELSE array_to_string(string_split(g.subject, '.')[1:2], '.') END AS home,
           CASE WHEN g.state = 'conflict' THEN 'must' WHEN x.asset IS NOT NULL THEN 'should' ELSE 'could' END AS level,
           s.shape IS NULL AND g.state = 'missing' AS unshaped,
           coalesce(g.state = 'stale' AND rd.subject IS NOT NULL, false) AS redefined,
           'GLOSS ' || g.property || ' ON ' || main.subject_path(g.subject) || ' AS $$'
             || CASE WHEN g.state = 'stale' THEN coalesce(w.body, s.shape, '<value>') ELSE coalesce(s.shape, '<value>') END
             || '$$;' AS gloss
    FROM g JOIN stated s ON s.name = g.property LEFT JOIN reach x ON x.asset = g.subject
    LEFT JOIN written w ON w.property = g.property AND w.subject = g.subject
    LEFT JOIN redefined rd ON rd.subject = g.subject AND rd.property = g.property
    -- a view's own columns are asked for where a view serves them (a
    -- table view's), not beside it
    WHERE (x.asset IS NOT NULL OR g.state = 'conflict'
           OR array_to_string(string_split(g.subject, '.')[1:2], '.') NOT IN (SELECT ds.d || '.' || view FROM summary, ds))
      AND NOT (s.expectation AND g.state = 'missing')
      -- `entity` says what one row of a table is: asked on a loaded
      -- table and on a table view, not on a metric or a single value
      AND NOT (g.property = 'entity' AND g.state = 'missing'
               AND g.subject IN (SELECT ds.d || '.' || m.view FROM summary m, ds WHERE coalesce(m.kind, '') <> 'relation'))
      AND NOT (g.state = 'conflict'
               AND {'subject': g.subject, 'property': g.property} IN (SELECT {'subject': subject, 'property': property} FROM vt WHERE state <> 'green'))
    UNION ALL
    -- a column property asked per table (x-asked: per table): once a
    -- column of a table or a view carries it, each other column is asked
    SELECT ds.d || '.' || c.table_name || '.' || c.column_name, a.name, 'missing', x.views, ds.d || '.' || c.table_name,
           CASE WHEN x.asset IS NOT NULL THEN 'should' ELSE 'could' END, false, false,
           'GLOSS ' || a.name || ' ON ' || main.subject_path(ds.d || '.' || c.table_name || '.' || c.column_name) || ' AS $$' || coalesce(s.shape, '<value>') || '$$;'
    FROM (SELECT DISTINCT name FROM main.properties WHERE json_extract_string(schema, '$.x-asked') = 'per table') a
    JOIN stated s ON s.name = a.name CROSS JOIN ds CROSS JOIN glossql_columns(current_schema()) c
    LEFT JOIN reach x ON x.asset = ds.d || '.' || c.table_name || '.' || c.column_name
    WHERE {'property': a.name, 'tbl': c.table_name} IN (
            SELECT {'property': w.property, 'tbl': split_part(w.subject, '.', 2)} FROM main.glossary w, ds
            WHERE w.dataset = ds.d AND w.actor_kind IN ('agent', 'human') AND len(string_split(w.subject, '.')) >= 3
              AND starts_with(w.subject, ds.d || '.'))
      AND {'property': a.name, 'subject': ds.d || '.' || c.table_name || '.' || c.column_name} NOT IN (
            SELECT {'property': w.property, 'subject': w.subject} FROM main.glossary w, ds WHERE w.dataset = ds.d)
    UNION ALL
    -- a metric's served column with no role: the statement its summary
    -- row names (`missing`, empty for every other view), on the view's own
    -- column, so that the summary row and this list ask for the same annotation
    SELECT ds.d || '.' || u.view || '.' || u.col, 'role', 'missing', u.view, ds.d || '.' || u.view, 'should', false, false, u.statement
    FROM (SELECT m.view, unnest(m.columns_without_role) AS col, unnest(m.missing) AS statement FROM summary m
          WHERE m.stopped IS NULL) u, ds),
  s_load AS (
    SELECT 'must' AS level, 1 AS ord, 'integrate' AS kind, ds.d AS asset, 'missing' AS state, 'agent' AS who,
           'no table is loaded' AS open, '' AS for_view,
           'DECLARE SOURCE <source> SET (type: <csv|parquet|json|relational_db>, location: ''<directory or URL>'');' || chr(10)
             || 'PREVIEW <source> AS $$SELECT file FROM glob(''*'')$$;' || chr(10)
             || '-- a typed file (parquet, json) loads as it is:' || chr(10)
             || 'DECLARE RECIPE <table> ON ' || ds.d || ' FROM <source> AS $$SELECT <columns> FROM read_parquet(''<file>'')$$;' || chr(10)
             || '-- a CSV is read as text, with these reader options, and cast in the SELECT:' || chr(10)
             || 'DECLARE RECIPE <table> ON ' || ds.d || ' FROM <source> AS $$SELECT <columns and casts> FROM read_csv(''<file>'', all_varchar = true, nullstr = null_markers(), store_rejects = true)$$;' AS statement
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM duckdb_tables() t
                              WHERE t.database_name = current_database() AND t.schema_name = ds.d)
    UNION ALL
    SELECT 'must', 2, 'integrate', ds.d || '.' || o.tbl, 'decided', 'agent',
           'a person approved a change to the load query of ' || o.tbl || '; it is not declared yet', '',
           '-- a person approved a new load query for ' || o.tbl || '; read it, then declare it:' || chr(10)
             || 'SELECT body FROM main.glossary WHERE property = ''recipe_change'';' || chr(10)
             || 'DECLARE RECIPE ' || o.tbl || ' ON ' || ds.d || ' FROM <source> AS $$<the approved sql>$$;'
    FROM approved o, ds),
  s_describe AS (
    SELECT h.level, 4, 'describe', h.home, h.state, 'agent',
           count(*) || ' ' || CASE h.state WHEN 'stale' THEN 'outdated' WHEN 'conflict' THEN 'in conflict' ELSE h.state END || ': '
             || string_agg(DISTINCT h.property, ', ' ORDER BY h.property),
           coalesce(max(h.views), ''),
           CASE h.state
             WHEN 'conflict'
             THEN '-- two values differ. Read both, check the data, and annotate again only if the data changed your mind:' || chr(10)
                  || 'SELECT subject, property, actor, body, current FROM GLOSSARY(' || h.home || ', all => true);'
             WHEN 'stale'
             THEN CASE WHEN bool_or(h.redefined)
                       THEN '-- the definition of ' || h.home || ' changed after these annotations were written. Check each value against the new definition and record it again.'
                       ELSE '-- the data under these annotations changed. Check each value against the new data and record it again.' END || chr(10)
                  || '-- what the newest load of each table changed: SELECT table_name, cause FROM load_changes();' || chr(10)
                  || string_agg(DISTINCT h.gloss, chr(10) ORDER BY h.gloss)
             ELSE CASE WHEN bool_or(h.unshaped)
                       THEN '-- the shape of a value: SELECT name, schema FROM main.properties WHERE name = ''<property>'';' || chr(10)
                       ELSE '' END
                  || string_agg(DISTINCT h.gloss, chr(10) ORDER BY h.gloss) END
    FROM homed h
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
           w.property,
           CASE WHEN len(w.actors) > 0 THEN ' BY (' || array_to_string(w.actors, ', ') || ')' ELSE '' END AS actors
    FROM main.tests w JOIN main.properties a ON a.name = w.property
    WHERE w.detector = 'rate_tolerance'),
  s_test AS (
    SELECT CASE t.state WHEN 'red' THEN 'must' ELSE 'should' END, 3, 'test', t.subject, t.state, 'agent',
           t.test || coalesce(': ' || coalesce(t.evidence->>'finding', t.evidence->>'reason'), ''), t.view,
           coalesce('-- ' || t.test || ' is ' || t.state || ': '
                      || replace(coalesce(t.evidence->>'finding', t.evidence->>'reason',
                                          CASE WHEN t.state IN ('red', 'orange') THEN 'the data breaks the rule, measured ' || round(t.score, 4) END), chr(10), ' ')
                      || chr(10), '')
           || coalesce(t.evidence->>'fix',
                    CASE WHEN t.state IN ('red', 'orange') AND t.declared_by NOT LIKE 'kit:%'
                         THEN '-- fix the load query or the view''s definition, then run the check again.' || chr(10)
                              || '-- what the newest load of each table changed: SELECT table_name, cause FROM load_changes();' || chr(10)
                              || nullif(t.run, '') || ';'
                              || coalesce(chr(10) || '-- where a person accepts the rate as it is (measured: ' || round(t.score, 4) || '), '
                                   || CASE k.by
                                        WHEN 'tolerance' THEN 'record it with their reason:' || chr(10)
                                               || '-- ' || main.gloss_statement(k.property, t.subject,
                                               json_merge_patch(coalesce(e.body, '{}'),
                                                 '{"tolerance": ' || ceil(t.score * 1000) / 1000 || ', "basis": "<who accepted the rate and why>"}')::VARCHAR)
                                        WHEN 'threshold' THEN 'declare the test again with it, and say in the meaning of ' || t.subject || ' who accepted it and why:' || chr(10)
                                               || '-- DECLARE TEST ' || t.test || ' ON ' || k.property
                                               || k.actors || ' DETECTOR rate_tolerance THRESHOLD ' || ceil(t.score * 1000) / 1000 || ';' END, '') END,
                    nullif(t.run, ''),
                    'SELECT subject, property, actor, body, current FROM GLOSSARY(' || t.subject || ', all => true);')
    FROM vo t LEFT JOIN accepts k ON k.test = t.test
    LEFT JOIN written e ON e.subject = t.subject AND e.property = t.property),
  -- a load that does not fit what the source sends (load_modes())
  s_loads AS (
    SELECT l.level, 1, 'integrate', l.table_name, l.state, 'agent', l.open, coalesce(x.views, ''),
           '-- ' || l.open || chr(10) || l.statement
    FROM main.load_modes() l LEFT JOIN reach x ON x.asset = l.table_name WHERE l.state IS NOT NULL),
  s_review AS (
    SELECT 'must', 2, 'review', ds.d || '.' || r.property, 'decided', 'agent',
           'a person decided ' || r.key || ' (' || r.stance || ')' || coalesce(': ' || nullif(r.note, ''), '')
             || '; the definition does not carry it yet', r.property,
           '-- a person decided ' || r.key || ' (' || r.stance || ')' || coalesce(': ' || nullif(replace(r.note, chr(10), ' '), ''), '') || chr(10)
             || '-- set the assumption with key "' || r.key || '" to confidence 1.0 and basis "decided-by-person", change the SQL where the decision asks for it, then record the definition again:' || chr(10)
             || coalesce(rd.statement, main.gloss_statement(r.property, ds.d, '<the current definition>'))
    FROM main.review_decisions r CROSS JOIN ds LEFT JOIN redefines rd ON rd.view = r.property
    WHERE r.dataset = ds.d AND NOT r.folded_in

    UNION ALL
    SELECT 'should', 6, 'review', ds.d || '.' || q.property, 'waiting', 'person',
           'the assumption ' || q.key || ' waits for a person''s decision: ' || q.assumption, q.property,
           'SELECT key, assumption, basis, alternative FROM main.open_questions WHERE property = ''' || q.property || ''' AND key = ''' || q.key || ''';'
    FROM main.open_questions q, ds WHERE q.dataset = ds.d),
  s_views AS (
    SELECT 'must', 1, 'integrate', ds.d, 'missing', 'agent', 'no view is defined (a table, a single value or a metric)', '',
           '-- a view is named SQL on the dataset. Define the kind the job asks for.' || chr(10)
             || '-- a table:' || chr(10)
             || 'DECLARE PROPERTY <table_view> WITH $${"title": "<its name in the business''s words>", "x-kind": "relation"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<table_view>', ds.d, '{"sql": "SELECT <columns> FROM <table>"}') || chr(10)
             || '-- a single value:' || chr(10)
             || 'DECLARE PROPERTY <single_value> WITH $${"title": "<its name in the business''s words>", "x-kind": "scalar"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<single_value>', ds.d, '{"sql": "SELECT <expression> AS value FROM <table>"}') || chr(10)
             || '-- a metric, a value per period with its dimensions:' || chr(10)
             || 'DECLARE PROPERTY <metric> WITH $${"title": "<its name in the business''s words>"}$$ AS VIEW;' || chr(10)
             || main.gloss_statement('<metric>', ds.d, '{"sql": "SELECT <period>, <value>, <dimension columns> FROM <table>", "time": "<period column>", "measure": {"column": "<value column>", "additivity": "<additive|semi-additive|ratio|non-additive>", "unit": "<unit>"}, "dimensions": ["<column>"]}')
    FROM ds WHERE NOT EXISTS (SELECT 1 FROM summary WHERE stopped IS NULL)
      AND EXISTS (SELECT 1 FROM duckdb_tables() t WHERE t.database_name = current_database() AND t.schema_name = ds.d)),
  -- a stored result out of date that the server does not compute (a
  -- view's lineage it does, results_due()): one
  -- about the dataset as a whole, a view or an asset of a kind a kit
  -- declares, whatever kit declares
  -- its function, but a check a test on the view runs (view_tests()
  -- names it as the test's `run`)
  s_results AS (
    SELECT 'should', 5, 'test', o.subject, 'stale', 'agent',
           o.function || ': computed before a read of it changed (' || o.inputs || ')',
           coalesce(o.view, ''),
           '-- computed before ' || o.inputs || ' changed' || chr(10) || 'SELECT ' || o.function || '() FROM ' || main.subject_path(o.subject) || ';'
    FROM (SELECT u.function, u.subject, any_value(v.view) AS view, string_agg(DISTINCT u.asset || ' ' || u.what, ', ' ORDER BY u.asset || ' ' || u.what) AS inputs
          FROM glossql_outdated() u
          LEFT JOIN (SELECT view FROM summary WHERE stopped IS NULL) v ON u.subject = current_schema() || '.' || v.view
          WHERE u.dataset = current_schema() AND u.reason = 'changed' AND u.function <> 'lineage'
            AND (u.subject = current_schema() OR v.view IS NOT NULL
                 OR u.subject IN (SELECT asset FROM glossql_kind_assets(current_schema())))
            AND 'SELECT ' || u.function || '() FROM ' || main.subject_path(u.subject) NOT IN (SELECT run FROM vt)
          GROUP BY u.function, u.subject) o)
  SELECT * FROM (
    SELECT * FROM s_load UNION ALL SELECT * FROM s_loads UNION ALL SELECT * FROM s_describe
    UNION ALL SELECT * FROM s_test
    UNION ALL SELECT * FROM s_review UNION ALL SELECT * FROM s_views UNION ALL SELECT * FROM s_results)
  ORDER BY CASE level WHEN 'must' THEN 1 WHEN 'should' THEN 2 ELSE 3 END, ord, asset, state, open;
