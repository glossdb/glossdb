-- The metrics kit: a metric is a view, its columns carry the vocabulary,
-- and the reads are SQL over the collapsed annotations and the view. Loaded after
-- the KPI kit, whose words the columns carry (role, additivity, dimension),
-- and the quality kit, whose temporal profile measures a time column's
-- grain. What an actor must learn about these words is the
-- glossql-modeling skill (skills/glossql-modeling/references/).
--
--   FROM glossql_kit('kits/kpi/kit.sql');
--   FROM glossql_kit('kits/quality/kit.sql');
--   FROM glossql_kit('kits/views/kit.sql');
--
-- A metric definition's view is a table of its dataset: the column that carries
-- role timestamp is the metric's period, the column that carries role
-- measure its value (the one named value where several do), the columns
-- that carry role dimension its slices. The additivity on the value column
-- says how a number combines over periods and members. Nothing is
-- re-marked at read: a claim older than its data is stale by the
-- catalog's own rule, and the reads serve it as the catalog does.

--===------------------------------------------------------------------===--
-- The time grains (aspect `time_grains`): how a time column's periods are walked. floor is the grain
-- the series is served at, by default the grain measured on the column; windows is
-- how many whole periods a read serves per grain, counted back from
-- the newest data, by default the kit's. Required where the role is timestamp.
--===------------------------------------------------------------------===--

DECLARE ASPECT time_grains WITH $${
  "type": "object",
  "properties": {
    "floor": {"enum": ["minute", "hour", "day", "week", "month", "quarter", "year"]},
    "windows": {"type": "object", "additionalProperties": false, "properties": {
      "minute": {"type": "integer", "minimum": 1}, "hour": {"type": "integer", "minimum": 1},
      "day": {"type": "integer", "minimum": 1}, "week": {"type": "integer", "minimum": 1},
      "month": {"type": "integer", "minimum": 1}, "quarter": {"type": "integer", "minimum": 1},
      "year": {"type": "integer", "minimum": 1}}},
    "basis": {"type": "string"}
  }
}$$ AS FACT ON COLUMN WHEN role = 'timestamp';

DECLARE TEST time_grains_test ON time_grains BY (AGENT, HUMAN);

-- The grains in order, a period's step, and the kit's window per grain.
CREATE OR REPLACE MACRO main.grain_rank(g) AS
  CASE g WHEN 'minute' THEN 1 WHEN 'hour' THEN 2 WHEN 'day' THEN 3 WHEN 'week' THEN 4
         WHEN 'month' THEN 5 WHEN 'quarter' THEN 6 WHEN 'year' THEN 7 END;
CREATE OR REPLACE MACRO main.grain_step(g) AS
  CASE g WHEN 'minute' THEN INTERVAL 1 MINUTE WHEN 'hour' THEN INTERVAL 1 HOUR WHEN 'day' THEN INTERVAL 1 DAY
         WHEN 'week' THEN INTERVAL 7 DAY WHEN 'month' THEN INTERVAL 1 MONTH WHEN 'quarter' THEN INTERVAL 3 MONTH
         WHEN 'year' THEN INTERVAL 1 YEAR END;
CREATE OR REPLACE MACRO main.window_default(g) AS
  CASE g WHEN 'minute' THEN 1440 WHEN 'hour' THEN 720 WHEN 'day' THEN 548 WHEN 'week' THEN 156
         WHEN 'month' THEN 48 WHEN 'quarter' THEN 40 WHEN 'year' THEN 20 END;

--===------------------------------------------------------------------===--
-- view_summary(): one row per view of the bound dataset (a metric, a
-- table, a single value) — a VIEW aspect whose definition is a
-- view — what the catalog says its columns are
-- and whether a series can be served: view, kind (the aspect's x-kind),
-- stopped (the author's text), applicable (a series can be
-- served), reason (what is missing when it cannot), period_column,
-- value_column, numerator and denominator
-- (a ratio's halves), grain_detected (the grain temporal() measured on the
-- period column), floor (the time grains', else grain_detected),
-- window_periods (how many periods a read serves at the floor), additivity
-- and additivity_state (the annotation in force on the value column, NULL and
-- 'none' where nobody annotated it, 'conflict' where the test withholds it),
-- dims (the slicing columns, primary first), dimensions_without_rank (the
-- dimension columns with no dimension annotation), columns_without_role
-- (the served columns with no role), missing (the annotation each of those
-- needs, on the view's own column: a view's column takes no role from the
-- column it reads; `next` lists the same statements under the view; a
-- table and a single value need none, since no check on them reads a
-- role, so both are empty for them),
-- measurements_to_run (the measurement the row reads that nobody ran or
-- that is out of date: a load or a new definition moves the period
-- column under its temporal profile, and every function that reads the
-- view's grain reads that profile),
-- profile_current (the period column's temporal profile is current at the
-- data's own version). A table (x-kind relation) and a single value
-- (x-kind scalar) have no series: applicable, period_column,
-- grain_detected, floor and window_periods are NULL for them, and
-- reason is filled only where the view is stopped or its definition
-- serves no view.
--
-- view_kinds(): view, kind and stopped alone, from each view's newest
-- definition, for a read that needs no more of the summary than which
-- views there are (view_tests(), fact_values(), column_mapping());
-- view_summary() reads its rows from it.
--
-- view_axes(): what metric_series() reads of the same, through the read
-- functions alone (the lineage kit's), so that a function's body can read
-- a series, on the subject's dataset: one row per served view — view,
-- kind, stopped, applicable, reason, period_column, value_column,
-- numerator, denominator, floor, window_periods, additivity,
-- additivity_state, dims, columns (the view's columns by name), newest
-- (the latest instant in the period column, as its temporal profile
-- measured it). It reads the views' definitions, role, additivity,
-- dimension and time_grains, and the temporal profiles, on the dataset's
-- metrics. A view whose definition serves no view has no row.
--===------------------------------------------------------------------===--

-- series_reason(…): why a view serves no series, NULL where it does;
-- view_summary() and view_axes() judge alike.
CREATE OR REPLACE MACRO main.series_reason(ds, metric, stopped, served, kind, period_column, period_cols, value_column, measure_cols, floor, profiled) AS
  CASE WHEN stopped IS NOT NULL THEN 'stopped: ' || stopped
       WHEN NOT served THEN 'the definition serves no view'
       WHEN kind IN ('scalar', 'relation') THEN NULL
       WHEN period_column IS NULL AND len(period_cols) > 1 THEN
            list_aggregate(period_cols, 'string_agg', ' and ') || ' carry role timestamp; the period is the column named period: name it so in the SQL, or annotate role attribute on the others'
       WHEN period_column IS NULL THEN
            'no column carries role timestamp: annotate the period column, GLOSS role ON ' || ds || '.' || metric || '.<column> AS $${"value": "timestamp"}$$'
       WHEN value_column IS NULL AND len(measure_cols) > 1 THEN
            list_aggregate(measure_cols, 'string_agg', ' and ') || ' carry role measure; the value is the column named value: name it so in the SQL, or annotate role attribute on the others'
       WHEN value_column IS NULL THEN
            'no column carries role measure: annotate the value column, GLOSS role ON ' || ds || '.' || metric || '.<column> AS $${"value": "measure"}$$'
       WHEN floor IS NULL AND NOT profiled THEN
            'the period column ' || period_column || ' is not profiled, so its grain is not known: SELECT temporal() FROM ' || ds || '.' || metric || '.' || period_column || ', or annotate time_grains with a floor'
       WHEN floor IS NULL THEN
            'the dates in ' || period_column || ' follow no regular grain; say which grain the series is served at: GLOSS time_grains ON ' || ds || '.' || metric || '.' || period_column || ' AS $${"floor": "<minute|hour|day|week|month|quarter|year>"}$$'
  END;

CREATE OR REPLACE MACRO main.view_kinds() AS TABLE
SELECT g.aspect AS view, json_extract_string(a.schema, '$.x-kind') AS kind, json_extract_string(g.body, '$.stopped') AS stopped
FROM main.glossary g JOIN main.aspects a ON a.name = g.aspect AND a.kind = 'VIEW'
WHERE g.dataset = current_schema() AND g.subject = current_schema()
QUALIFY row_number() OVER (PARTITION BY g.aspect ORDER BY g.begin_snapshot DESC) = 1;

CREATE OR REPLACE MACRO main.view_summary() AS TABLE
WITH ds AS (SELECT current_schema() AS dataset),
aspects AS (SELECT name, schema FROM main.aspects WHERE kind = 'VIEW'),
views AS (
  SELECT DISTINCT c.table_name AS view FROM glossql_columns(current_schema()) c
  WHERE c.table_type = 'VIEW' AND c.table_name IN (SELECT name FROM aspects)),
bodies AS (SELECT view, stopped FROM main.view_kinds()),
cols AS (
  SELECT c.table_name AS view, c.column_name AS col, c.ordinal_position AS pos
  FROM glossql_columns(current_schema()) c
  WHERE c.table_name IN (SELECT view FROM views)),
annotated AS MATERIALIZED (
  SELECT split_part(subject, '.', 2) AS view, substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) AS col, aspect, value, state
  -- the dataset's glossary, read once by every read of one statement that reads it whole
  FROM glossql_glossary(current_schema(), NULL, false)
  WHERE aspect IN ('role', 'additivity', 'dimension', 'time_grains', 'temporal_profile')
    AND len(string_split(subject, '.')) >= 3
    AND split_part(subject, '.', 2) IN (SELECT view FROM bodies)),
claims AS (SELECT * FROM annotated WHERE state IN ('current', 'stale') AND value IS NOT NULL),
roles AS (SELECT view, col, value->>'value' AS role FROM claims WHERE aspect = 'role'),
periods AS (
  SELECT r.view, list(r.col ORDER BY CASE WHEN r.col = 'period' THEN 0 ELSE 1 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (view, col) WHERE r.role = 'timestamp' GROUP BY r.view),
measures AS (
  SELECT r.view, list(r.col ORDER BY CASE WHEN r.col = 'value' THEN 0 ELSE 1 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (view, col) WHERE r.role = 'measure' GROUP BY r.view),
chosen AS (
  SELECT b.view,
         CASE WHEN len(p.cols) = 1 OR p.cols[1] = 'period' THEN p.cols[1] END AS period_column,
         CASE WHEN len(m.cols) = 1 OR m.cols[1] = 'value' THEN m.cols[1] END AS value_column,
         p.cols AS period_cols, m.cols AS measure_cols,
         b.view IN (SELECT view FROM views) AS served
  FROM bodies b LEFT JOIN periods p USING (view) LEFT JOIN measures m USING (view)),
additivitys AS (
  SELECT s.view, s.col,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'value' END AS additivity,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'numerator' END AS numerator,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'denominator' END AS denominator,
         CASE WHEN s.state IN ('current', 'stale') THEN s.state ELSE 'conflict' END AS additivity_state
  FROM annotated s WHERE s.aspect = 'additivity' AND s.state <> 'missing'),
profiles AS (
  SELECT view, col,
         CASE WHEN (value->>'applicable') = 'true' AND (value->>'granularity') IN ('minute', 'hour', 'day', 'week', 'month', 'quarter', 'year')
              THEN value->>'granularity' END AS grain_detected,
         state = 'current' AS profile_current
  FROM claims WHERE aspect = 'temporal_profile'),
ladders AS (SELECT view, col, value->>'floor' AS floor, value->'windows' AS windows FROM claims WHERE aspect = 'time_grains'),
dims AS (
  SELECT r.view, list(r.col ORDER BY CASE d.rank WHEN 'primary' THEN 0 WHEN 'supporting' THEN 1 ELSE 2 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (view, col)
  LEFT JOIN (SELECT view, col, value->>'value' AS rank FROM claims WHERE aspect = 'dimension') d USING (view, col)
  WHERE r.role = 'dimension' AND coalesce(d.rank, '') <> 'none'
  GROUP BY r.view),
without_rank AS (
  SELECT r.view, list(r.col ORDER BY c.pos) AS cols
  FROM roles r JOIN cols c USING (view, col)
  WHERE r.role = 'dimension'
    AND NOT EXISTS (SELECT 1 FROM claims d WHERE d.aspect = 'dimension' AND d.view = r.view AND d.col = r.col)
  GROUP BY r.view),
without_role AS (
  SELECT c.view, list(c.col ORDER BY c.pos) AS cols,
         list('GLOSS role ON ' || ds.dataset || '.' || c.view || '.' || c.col || ' AS $${"value": "<key|measure|dimension|timestamp|attribute>"}$$;' ORDER BY c.pos) AS acts
  FROM cols c, ds
  WHERE NOT EXISTS (SELECT 1 FROM roles r WHERE r.view = c.view AND r.col = c.col)
  GROUP BY c.view),
rows_ AS (
  SELECT ch.view,
         json_extract_string(a.schema, '$.x-kind') AS kind,
         b.stopped,
         ch.period_column, ch.value_column, ch.period_cols, ch.measure_cols, ch.served,
         bh.additivity, bh.numerator, bh.denominator, coalesce(bh.additivity_state, 'none') AS additivity_state,
         pr.grain_detected, coalesce(pr.profile_current, false) AS profile_current,
         coalesce(la.floor, pr.grain_detected) AS floor, la.windows,
         coalesce(d.cols, []::VARCHAR[]) AS dims, coalesce(ur.cols, []::VARCHAR[]) AS dimensions_without_rank,
         -- a table and a single value serve no series: no check on them reads a role
         CASE WHEN json_extract_string(a.schema, '$.x-kind') IN ('scalar', 'relation') THEN []::VARCHAR[]
              ELSE coalesce(u.cols, []::VARCHAR[]) END AS columns_without_role,
         CASE WHEN json_extract_string(a.schema, '$.x-kind') IN ('scalar', 'relation') THEN []::VARCHAR[]
              ELSE coalesce(u.acts, []::VARCHAR[]) END AS missing,
         pr.view IS NOT NULL AS profiled
  FROM chosen ch
  JOIN aspects a ON a.name = ch.view
  LEFT JOIN bodies b USING (view)
  LEFT JOIN additivitys bh ON bh.view = ch.view AND bh.col = ch.value_column
  LEFT JOIN profiles pr ON pr.view = ch.view AND pr.col = ch.period_column
  LEFT JOIN ladders la ON la.view = ch.view AND la.col = ch.period_column
  LEFT JOIN dims d ON d.view = ch.view
  LEFT JOIN without_rank ur ON ur.view = ch.view
  LEFT JOIN without_role u ON u.view = ch.view),
judged AS (
  SELECT *,
    main.series_reason(ds.dataset, view, stopped, served, kind, period_column, period_cols, value_column, measure_cols, floor, profiled) AS reason,
    CASE WHEN period_column IS NOT NULL AND NOT (profiled AND profile_current) AND stopped IS NULL AND coalesce(kind, '') NOT IN ('scalar', 'relation')
         THEN ['temporal over ' || ds.dataset || '.' || view || '.' || period_column] ELSE []::VARCHAR[] END AS measurements_to_run
  FROM rows_, ds)
SELECT view, kind, stopped,
       CASE WHEN series THEN reason IS NULL END AS applicable, reason,
       CASE WHEN series THEN period_column END AS period_column, value_column, numerator, denominator,
       CASE WHEN series THEN grain_detected END AS grain_detected, CASE WHEN series THEN floor END AS floor,
       CASE WHEN series AND floor IS NOT NULL THEN coalesce(json_extract(windows, '$.' || floor)::INTEGER, main.window_default(floor)) END AS window_periods,
       additivity, additivity_state, dims, dimensions_without_rank, columns_without_role, missing, measurements_to_run, profile_current
FROM (SELECT *, coalesce(kind, '') NOT IN ('scalar', 'relation') AS series FROM judged)
ORDER BY view;

CREATE OR REPLACE MACRO main.view_axes() AS TABLE
WITH defs AS MATERIALIZED (
  SELECT split_part(view, '.', 1) AS ds, split_part(view, '.', 2) AS metric, kind, stopped, columns
  FROM definition('the dataset''s metrics')),
cols AS (SELECT d.metric, c.name AS col, c.position AS pos FROM defs d, unnest(d.columns) t(c)),
annotated AS MATERIALIZED (
  SELECT split_part(asset, '.', 2) AS metric, substr(asset, length(split_part(asset, '.', 1)) + length(split_part(asset, '.', 2)) + 3) AS col,
         property AS aspect, value, state
  FROM (FROM annotations('role', 'the dataset''s metrics') UNION ALL FROM annotations('additivity', 'the dataset''s metrics')
        UNION ALL FROM annotations('dimension', 'the dataset''s metrics') UNION ALL FROM annotations('time_grains', 'the dataset''s metrics'))
  WHERE state <> 'missing' AND len(string_split(asset, '.')) >= 3 AND split_part(asset, '.', 2) IN (SELECT metric FROM defs)),
claims AS (SELECT * FROM annotated WHERE state IN ('current', 'stale') AND value IS NOT NULL),
roles AS (SELECT metric, col, value->>'value' AS role FROM claims WHERE aspect = 'role'),
picked AS (
  SELECT d.metric,
         (SELECT list(r.col ORDER BY CASE WHEN r.col = 'period' THEN 0 ELSE 1 END, c.pos) FROM roles r JOIN cols c USING (metric, col)
          WHERE r.metric = d.metric AND r.role = 'timestamp') AS period_cols,
         (SELECT list(r.col ORDER BY CASE WHEN r.col = 'value' THEN 0 ELSE 1 END, c.pos) FROM roles r JOIN cols c USING (metric, col)
          WHERE r.metric = d.metric AND r.role = 'measure') AS measure_cols,
         (SELECT list(r.col ORDER BY CASE x.value->>'value' WHEN 'primary' THEN 0 WHEN 'supporting' THEN 1 ELSE 2 END, c.pos)
          FROM roles r JOIN cols c USING (metric, col) LEFT JOIN claims x ON x.aspect = 'dimension' AND x.metric = r.metric AND x.col = r.col
          WHERE r.metric = d.metric AND r.role = 'dimension' AND coalesce(x.value->>'value', '') <> 'none') AS dims
  FROM defs d),
chosen AS (
  SELECT d.*, p.period_cols, p.measure_cols, coalesce(p.dims, []::VARCHAR[]) AS dims,
         CASE WHEN len(p.period_cols) = 1 OR p.period_cols[1] = 'period' THEN p.period_cols[1] END AS period_column,
         CASE WHEN len(p.measure_cols) = 1 OR p.measure_cols[1] = 'value' THEN p.measure_cols[1] END AS value_column
  FROM defs d JOIN picked p USING (metric)),
profiles AS (
  SELECT split_part(asset, '.', 2) AS metric, substr(asset, length(split_part(asset, '.', 1)) + length(split_part(asset, '.', 2)) + 3) AS col,
         CASE WHEN json_extract_string(value, '$.applicable') = 'true'
                   AND json_extract_string(value, '$.granularity') IN ('minute', 'hour', 'day', 'week', 'month', 'quarter', 'year')
              THEN json_extract_string(value, '$.granularity') END AS grain_detected,
         TRY_CAST(json_extract_string(value, '$.max') AS TIMESTAMP) AS newest
  FROM results('temporal', 'the dataset''s metrics') WHERE value IS NOT NULL),
rows_ AS (
  SELECT ch.*,
         CASE WHEN a.state IN ('current', 'stale') THEN a.value->>'value' END AS additivity,
         CASE WHEN a.state IN ('current', 'stale') THEN a.value->>'numerator' END AS numerator,
         CASE WHEN a.state IN ('current', 'stale') THEN a.value->>'denominator' END AS denominator,
         coalesce(CASE WHEN a.state IN ('current', 'stale') THEN a.state ELSE 'conflict' END, 'none') AS additivity_state,
         coalesce(t.value->>'floor', pr.grain_detected) AS floor, t.value->'windows' AS windows, pr.metric IS NOT NULL AS profiled,
         pr.newest
  FROM chosen ch
  LEFT JOIN annotated a ON a.aspect = 'additivity' AND a.metric = ch.metric AND a.col = ch.value_column
  LEFT JOIN claims t ON t.aspect = 'time_grains' AND t.metric = ch.metric AND t.col = ch.period_column
  LEFT JOIN profiles pr ON pr.metric = ch.metric AND pr.col = ch.period_column),
judged AS (
  SELECT *, main.series_reason(ds, metric, stopped, true, kind, period_column, period_cols, value_column, measure_cols, floor, profiled) AS reason,
         coalesce(kind, '') NOT IN ('scalar', 'relation') AS series
  FROM rows_)
SELECT metric AS view, kind, stopped, CASE WHEN series THEN reason IS NULL END AS applicable, reason,
       CASE WHEN series THEN period_column END AS period_column, value_column, numerator, denominator,
       CASE WHEN series THEN floor END AS floor,
       CASE WHEN series AND floor IS NOT NULL THEN coalesce(json_extract(windows, '$.' || floor)::INTEGER, main.window_default(floor)) END AS window_periods,
       additivity, additivity_state, dims, list_transform(columns, lambda c: c.name) AS columns,
       CASE WHEN series THEN newest END AS newest
FROM judged
ORDER BY view;


--===------------------------------------------------------------------===--
-- metric_series(view := NULL, grain := NULL, unclaimed := 'refuse'): the
-- cells of one metric of the bound dataset, the view named, or of every
-- applicable metric where no view is named — metric, world ('actual'),
-- dimension ('' the total, else a slicing column), member, period (the
-- bucket's start), value, num and den (a ratio's summed halves), additivity.
-- A named view reads that view's rows alone. Without a grain, each metric at
-- its own floor; with one, each metric at or below it at that grain, a
-- metric coarser than the asked grain serving no rows. Only the window is
-- served: the latest window_periods periods of each metric (view_summary()
-- has the number, by default 48 months or 20 years; time_grains `windows`
-- sets it), the newest period the last. A flow sums and fills its total's
-- empty periods with zero up to the data's edge: the newest instant any
-- metric served at that grain reaches, as the temporal profile of its
-- period column measured it, so a flow whose rows stopped early shows its
-- zeros, not an older window. A stock keeps the bucket's last level, summed
-- over what holds at that instant; a ratio re-divides its summed halves. A
-- dimension wider than 24 members serves its top 23 by weight and 'other'.
--
-- The no-claim rule: where rows have to be combined — a coarser grain than
-- the floor, or several rows in one period — and no additivity is annotated on
-- the value column, the read refuses and names the gloss. It defaults
-- nothing. The refusal concerns the metrics read: a named view refuses for
-- itself alone. A list over every metric asks unclaimed := 'skip' instead:
-- such a metric serves no row, and its view_summary() row says what it needs.
--
-- The rows are summed by the extension's series_aggregate() over each
-- asked view's own typed columns, per period and per member of each
-- dimension, as they are read; series_axes() names the columns at bind.
-- A function's body reads it as any read: the views' definitions, their
-- columns' annotations and profiles, and their rows, all through the
-- dataset's metrics.
--===------------------------------------------------------------------===--

-- series_axes(grain): view_axes() with what series_aggregate() reads of it
-- at bind: at_grain, the grain a metric's periods start at where it is read
-- at this grain (its floor where none is asked, none where its floor is
-- coarser than the grain); by_instant, whether its rows are summed per
-- instant within a period: a stock keeps the level at the period's last
-- instant, and a value with no additivity or a non-additive one is checked
-- for rows that share an instant.
CREATE OR REPLACE MACRO main.series_axes(grain) AS TABLE
SELECT *,
       CASE WHEN applicable AND (grain IS NULL OR main.grain_rank(grain) >= main.grain_rank(floor))
            THEN coalesce(grain, floor) END AS at_grain,
       coalesce(additivity NOT IN ('additive', 'ratio'), true) AS by_instant
FROM main.view_axes();

CREATE OR REPLACE MACRO main.metric_series(view := NULL, grain := NULL, unclaimed := 'refuse') AS TABLE
-- the sums of each asked view's typed columns per period and per member of each dimension, aggregated as
-- the rows stream: no row of a view is kept
WITH sums AS MATERIALIZED (
  FROM series_aggregate(coalesce(current_schema() || '.' || view, current_schema()), 'the dataset''s metrics',
                        'series_axes', grain)),
axes AS MATERIALIZED (FROM main.view_axes() WHERE applicable),
asked AS MATERIALIZED (
  SELECT m.* RENAME (view AS metric), coalesce(grain, m.floor) AS at_grain
  FROM axes m
  WHERE (view IS NULL OR m.view = view)
    AND (grain IS NULL OR main.grain_rank(grain) >= main.grain_rank(m.floor))),
-- the data's edge: the newest instant of every metric served at this grain, read off the profiles, so
-- that one view's read reads no other view's rows; a metric coarser than the grain with no additivity
-- to combine by is served by no read and has no part in it
data_edge AS (
  SELECT max(newest) AS last_at FROM axes
  WHERE grain IS NULL
     OR (main.grain_rank(grain) >= main.grain_rank(floor)
         AND NOT (main.grain_rank(grain) > main.grain_rank(floor) AND coalesce(additivity, 'non-additive') = 'non-additive'))),
-- a value column with no additivity or a conflicting one cannot be combined
-- over rows, and the read refuses; one marked non-additive is served where
-- it has one row per period and left out where rows would have to be combined.
-- Such a value is summed per instant, so rows share one where they outnumber the instants
combining AS (
  SELECT a.metric, a.value_column, a.additivity, a.additivity_state,
         main.grain_rank(a.at_grain) > main.grain_rank(a.floor) AS coarser,
         sum(s."rows") > count(s.instant) AS shared
  FROM asked a JOIN sums s ON s.view = a.metric AND s.dimension = ''
  WHERE a.additivity IS NULL OR a.additivity = 'non-additive'
  GROUP BY a.metric, a.value_column, a.additivity, a.additivity_state, a.at_grain, a.floor),
refused AS (
  SELECT CASE WHEN count(*) > 0 AND unclaimed = 'refuse' THEN error(string_agg(
           CASE WHEN additivity_state = 'conflict' THEN 'the additivity on ' || current_schema() || '.' || metric || '.' || value_column || ' is in conflict'
                ELSE 'no additivity is annotated on ' || current_schema() || '.' || metric || '.' || value_column END
           || CASE WHEN coarser THEN ', and ' || metric || ' is asked at a coarser grain than its floor' ELSE ', and ' || metric || ' serves several rows in one period' END
           || ': annotate it — GLOSS additivity ON ' || current_schema() || '.' || metric || '.' || value_column || ' AS $${"value": "<additive|semi-additive|ratio|non-additive>"}$$', '; ')) END AS refusal
  FROM combining WHERE (coarser OR shared) AND additivity IS DISTINCT FROM 'non-additive'),
-- the metrics served: every asked one but those that need a claim nobody made; the refusal gates the
-- cells served, below, where the rows are few. Rows with no instant have no period
served AS (
  SELECT s.* RENAME (view AS metric), coalesce(a.additivity, 'none') AS additivity
  FROM sums s JOIN asked a ON a.metric = s.view
  WHERE s.period IS NOT NULL AND s.view NOT IN (SELECT metric FROM combining WHERE coarser OR shared)),
-- a metric's edge is its last period; a flow's is the data's edge at the flow's grain, so a flow whose
-- rows stopped early shows its zeros, not an older window
own_edges AS (
  SELECT metric, min(period) AS first, max(period) AS own_edge FROM served WHERE dimension = '' GROUP BY metric),
edges AS (
  SELECT a.metric, o.first, a.at_grain, a.window_periods, coalesce(a.additivity, 'none') AS additivity,
         CASE WHEN a.additivity = 'additive' THEN greatest(o.own_edge, date_trunc(a.at_grain, (SELECT last_at FROM data_edge))) ELSE o.own_edge END AS edge
  FROM asked a JOIN own_edges o USING (metric)),
windowed AS (
  SELECT s.* FROM served s JOIN edges e ON e.metric = s.metric
  WHERE s.period > e.edge - main.grain_step(e.at_grain) * e.window_periods),
-- a stock's level in a period is what holds at the period's last instant; a ratio re-divides its summed halves
total AS (
  SELECT metric, '' AS dimension, '' AS member, period, additivity,
         CASE additivity WHEN 'semi-additive' THEN arg_max_null(value, instant)
                         WHEN 'ratio' THEN sum(num) / nullif(sum(den), 0)
                         ELSE sum(value) END AS value,
         CASE additivity WHEN 'ratio' THEN sum(num) END AS num,
         CASE additivity WHEN 'ratio' THEN sum(den) END AS den
  FROM windowed WHERE dimension = '' GROUP BY metric, period, additivity),
filled AS (
  SELECT e.metric, '' AS dimension, '' AS member, g.period, e.additivity, 0.0 AS value, NULL::DOUBLE AS num, NULL::DOUBLE AS den
  FROM edges e, unnest(generate_series(greatest(e.first, e.edge - main.grain_step(e.at_grain) * (e.window_periods - 1)), e.edge, main.grain_step(e.at_grain))) AS g(period)
  WHERE e.additivity = 'additive'
    AND NOT EXISTS (SELECT 1 FROM total t WHERE t.metric = e.metric AND t.period = g.period)),
-- a member's stock level is what holds at the member's own last instant in the period
member_periods AS (
  SELECT metric, dimension, member, period, additivity,
         CASE additivity WHEN 'semi-additive' THEN arg_max_null(value, instant) ELSE sum(value) END AS value,
         sum(num) AS num, sum(den) AS den, sum(weight) AS weight
  FROM windowed WHERE dimension <> '' GROUP BY metric, dimension, member, period, additivity),
-- ranked at seven significant digits: a parallel sum of doubles differs in
-- its last bits from run to run, and members of equal weight are then
-- ordered by name, so the same members are served each time
weights AS (
  SELECT metric, dimension, member,
         row_number() OVER (PARTITION BY metric, dimension ORDER BY TRY_CAST(sum(weight) AS FLOAT) DESC NULLS LAST, member) AS rank
  FROM member_periods GROUP BY metric, dimension, member),
member_cells AS (
  SELECT p.metric, p.dimension, CASE WHEN wt.rank <= 23 THEN p.member ELSE 'other' END AS member, p.period, p.additivity,
         CASE p.additivity WHEN 'ratio' THEN sum(p.num) / nullif(sum(p.den), 0) ELSE sum(p.value) END AS value,
         CASE p.additivity WHEN 'ratio' THEN sum(p.num) END AS num,
         CASE p.additivity WHEN 'ratio' THEN sum(p.den) END AS den
  FROM member_periods p JOIN weights wt USING (metric, dimension, member)
  GROUP BY p.metric, p.dimension, CASE WHEN wt.rank <= 23 THEN p.member ELSE 'other' END, p.period, p.additivity)
SELECT metric, 'actual' AS world, dimension, member, period, value, num, den, additivity
FROM (SELECT * FROM total UNION ALL SELECT * FROM filled UNION ALL SELECT * FROM member_cells), refused
WHERE refused.refusal IS NULL
ORDER BY metric, dimension, member, period;

--===------------------------------------------------------------------===--
-- fact_values(): the single values of the bound dataset — one row per
-- view whose aspect declares x-kind scalar: view, value where the view
-- is one row with a value column, reason where it is not. It reads the
-- rows of those views alone, through the place the dataset's single values.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.fact_values() AS TABLE
WITH facts AS (SELECT view AS metric, stopped FROM main.view_kinds() WHERE kind = 'scalar'),
cells AS (SELECT * FROM dataset_cells(current_schema(), 'the dataset''s single values')),
shape AS (
  SELECT "table" AS metric, count(DISTINCT rn) AS rows_, bool_or("column" = 'value') AS has_value,
         max(CASE WHEN "column" = 'value' THEN TRY_CAST(val AS DOUBLE) END) AS value
  FROM cells GROUP BY "table")
SELECT f.metric AS view,
       CASE WHEN f.stopped IS NULL AND s.rows_ = 1 AND s.has_value THEN s.value END AS value,
       CASE WHEN f.stopped IS NOT NULL THEN 'stopped: ' || f.stopped
            WHEN s.metric IS NULL THEN 'the view serves no row'
            WHEN NOT s.has_value THEN 'the view serves no value column'
            WHEN s.rows_ <> 1 THEN 'the view serves ' || s.rows_ || ' rows, not one' END AS reason
FROM facts f LEFT JOIN shape s USING (metric)
ORDER BY f.metric;

--===------------------------------------------------------------------===--
-- column_mapping(for_view := NULL): where each column of each view of the
-- bound dataset, or of one, comes from, read off the view's SQL. One row
-- per target column, per branch of the union the view's rows come from
-- (1 where it has none) and per source column: view, target_column,
-- branch, system (the system of record the source table states, else the
-- source it is loaded from), source_table,
-- source_column, alias (where the view reads the table more than once),
-- condition (what the view's joins and filters require of that read of the
-- table alone), lookup (the equalities of the join that joins that read to
-- the rows before it: the columns it is looked up by against the columns of
-- the side it is joined to, such as the system's own code a mapping table is
-- looked up by), expression (the branch's derivation), literals (the codes
-- the expression tests or returns, as written), complete. A column computed
-- from no source column (a constant, count(*)) has one row with no source.
-- complete is false where the lineage could not follow a step, or reads two
-- reads of one table alike; a view that does not plan has one row, no
-- target column, complete false.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.column_mapping(for_view := NULL) AS TABLE
WITH views AS (
  SELECT m.view FROM main.view_kinds() m WHERE m.stopped IS NULL AND (for_view IS NULL OR m.view = for_view)),
-- a table's system of record, where an annotation names one, else its load's source
stated AS (
  SELECT subject AS t, value->>'value' AS system FROM glossql_glossary(current_schema(), 'system_of_record', false)
  WHERE value IS NOT NULL AND state IN ('current', 'stale')),
systems AS (
  SELECT l."from" AS t, coalesce(s.system, l."to") AS system
  FROM main.loaded_from_edges(current_schema()) l LEFT JOIN stated s ON s.t = l."from")
SELECT m.view, m."column" AS target_column, m.branch, s.system,
       split_part(m.table_name, '.', 2) AS source_table, m.table_column AS source_column,
       m.alias, m.condition, m.lookup, m.derivation AS expression, m.literals, m.complete
FROM main.views_mapping(current_schema()) m
LEFT JOIN systems s ON s.t = m.table_name
WHERE m.view IN (SELECT view FROM views);

--===------------------------------------------------------------------===--
-- The built-in tests on a view: what can break its rows or its number,
-- checked against its definition and the evidence the quality kit
-- stored, never against the data again. join_check is a join that
-- repeats rows, orphan_check referential integrity on the declared
-- joins, both on every view (a table, a single value, a metric);
-- completeness_check a column a load or a new definition emptied, on
-- each column of every view;
-- additivity_check the additivity of a metric's value, which only a
-- metric has. Each is a measurement over the view,
-- `SELECT <check>() FROM <dataset>.<view>`, whose breach_rate
-- rate_tolerance scores: 0 is green. A check whose evidence is not
-- stored yet says so in `reason` and serves no rate, which reads yellow;
-- a view over one table cannot fan out and has no join to check. A
-- person who accepts a result records a tolerance at or above it on the
-- subject the result is on; their value outranks the agent's. `x-subject:
-- view` marks a test view_tests() expects on every view, run or not, and on
-- each of its columns where the property is declared on columns alone (a
-- check over the view then computes each column), `x-subject: metric` one
-- it expects on every metric, `x-subject: table` one it expects on every
-- loaded table (grain_check); `x-set-by: <property>` beside any one
-- it expects only where the view or one of its columns carries an
-- annotation of that property; the server runs each itself after a call that defined the view, annotated
-- what the check reads or loaded a table it scans. Each body reads the catalog through the read functions
-- of the lineage kit alone (annotations(), results(), definition()).
--
-- view_reads_of(ds, m): the tables and columns view m of dataset ds
-- descends from, through its lineage; none when it does not plan.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.view_reads_of(ds, m) AS TABLE
SELECT DISTINCT split_part(path, '.', 2) AS table_name, split_part(path, '.', 3) AS column_name
FROM (SELECT unnest(regexp_extract_all(l.derivation, '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1)) AS path
      FROM main.views_lineage(ds) l WHERE l.view = m)
WHERE split_part(path, '.', 1) = ds;

-- view_scans_of(ds, m): every table view m of dataset ds scans,
-- joins and filters included, from its stored lineage.
CREATE OR REPLACE MACRO main.view_scans_of(ds, m) AS TABLE
SELECT DISTINCT split_part(s.table_name, '.', 2) AS table_name
FROM main.views_scans(ds) s
WHERE s.view = m AND split_part(s.table_name, '.', 1) = ds;

-- A test brings its own advice: its check returns `finding`, one
-- sentence on what is wrong and what it does to the number, and `fix`,
-- the statement that settles it, filled from the catalog (<...> marks
-- what only the author can fill). The next steps serve both as they
-- are, so a kit that adds a test adds no branch anywhere else.
--
-- gloss_statement(aspect, subject, body): the annotation statement.
-- redefine_statement(view): the statement that records a view's
-- definition again, to edit and send, as a function's body writes it:
-- the definition is the annotation that defines the view, which a body
-- does not read (definition() serves its SQL), so it is marked <the
-- current definition>, and view_tests() fills it from the catalog when
-- it serves the fix (with_definition()).
CREATE OR REPLACE MACRO main.gloss_statement(a, subj, body) AS
  'GLOSS ' || a || ' ON ' || subj || ' AS $$' || body || '$$;';

CREATE OR REPLACE MACRO main.redefine_statement(v) AS
  main.gloss_statement(split_part(v, '.', 2), split_part(v, '.', 1), '<the current definition>');

-- view_redefine(ds, m): the same statement for view m of dataset ds,
-- read from the catalog, as a stored result's fix serves it (with_definition())
CREATE OR REPLACE MACRO main.view_redefine(ds, m) AS
  main.gloss_statement(m, ds, coalesce(
    (SELECT g.body::VARCHAR FROM main.glossary g
     WHERE g.dataset = ds AND g.subject = ds AND g.aspect = m ORDER BY g.begin_snapshot DESC LIMIT 1),
    '<the current definition>'));

-- with_definition(evidence, ds): a stored result with each statement in
-- its fix that records a view of dataset ds again filled with that view's
-- definition as it is now
CREATE OR REPLACE MACRO main.with_definition(evidence, ds) AS
  CASE WHEN contains(evidence->>'fix', '<the current definition>')
       THEN json_merge_patch(evidence, json_object('fix', coalesce(list_reduce(
              (SELECT list({'placeholder': main.redefine_statement(ds || '.' || v.name), 'statement': main.view_redefine(ds, v.name)})
               FROM (SELECT DISTINCT name FROM main.aspects WHERE kind = 'VIEW') v
               WHERE contains(evidence->>'fix', main.redefine_statement(ds || '.' || v.name))),
              lambda acc, r: replace(acc, r.placeholder, r.statement), evidence->>'fix'), evidence->>'fix')))
       ELSE evidence END;

-- validity: an effective-dated table (a slowly changing dimension, type 2):
-- each row holds from valid_from to valid_to, and a key repeats once per
-- version. open_end is the value valid_to carries on the current row
-- ('9999-01-01'), absent where it is NULL. Annotated on the table.
DECLARE ASPECT validity WITH $${
  "type": "object", "required": ["valid_from", "valid_to"],
  "properties": {"valid_from": {"type": "string"}, "valid_to": {"type": "string"},
                 "open_end": {"type": "string"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- key_repeats(path, cols): the keys on the columns cols that repeat in the
-- rows of a table or a view (dataset.table): shown (the key; its values in
-- parentheses where it has several columns), n (its rows), rows (the rows
-- read). A row with an empty key column has no key. Where the rows lack a
-- column of cols, one row with no key and n 0. The one count of a repeated
-- key: grain_check (a loaded table's stated grain) and the harmonise kit's
-- contract_check (a target view's key) read it.
CREATE OR REPLACE MACRO main.key_repeats(path, cols) AS TABLE
WITH keyed AS (
  SELECT rn, list(val ORDER BY list_position(cols, "column")) AS k, bool_or(val IS NULL) AS empty, count(*) AS width
  FROM dataset_cells(path, true) WHERE list_contains(cols, "column") GROUP BY rn),
read_ AS (SELECT count(*) AS rows, coalesce(bool_or(width < len(cols)), false) AS short FROM keyed)
SELECT CASE WHEN len(k) = 1 THEN k[1] ELSE '(' || array_to_string(k, ', ') || ')' END AS shown, count(*) AS n, any_value(r.rows) AS rows
FROM keyed, read_ r WHERE NOT empty AND NOT r.short GROUP BY k HAVING count(*) > 1
UNION ALL
SELECT NULL, 0, rows FROM read_ WHERE short;

-- grain_check: the rows of a loaded table keep the grain its `entity`
-- states, tested at each load as a target view's contract key is: the keys
-- that repeat (key_repeats()), with the rows past the first per key.
-- breach_rate is their share of the rows. Not applicable where the entity
-- states no grain, or names a column the table does not have. Set on each
-- loaded table that carries an `entity` (x-subject: table, x-set-by:
-- entity); the server runs it after a load.
DECLARE ASPECT grain_check WITH $${
  "description": "The rows of a loaded table keep the grain its entity states: no key repeats.",
  "type": "object", "x-subject": "table", "x-set-by": "entity",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]}, "grain": {"type": ["array", "null"], "items": {"type": "string"}},
                 "repeated": {"type": ["integer", "null"]}, "keys": {"type": ["array", "null"], "items": {"type": "string"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION grain_check FOR GLOBAL AS $$
  WITH stated AS (
    SELECT value AS entity, CASE WHEN json_array_length(value->'grain') > 0 THEN from_json(value->'grain', '["VARCHAR"]') END AS cols
    FROM annotations('entity', 'itself') WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  repeated AS (SELECT * FROM key_repeats($subject, (SELECT cols FROM stated))),
  state AS (
    SELECT (SELECT cols FROM stated) AS cols, (SELECT entity FROM stated) AS entity,
           EXISTS (SELECT 1 FROM repeated WHERE shown IS NULL) AS short,
           (SELECT sum(n - 1) FROM repeated WHERE shown IS NOT NULL)::BIGINT AS extra,
           (SELECT max(rows) FROM repeated) AS rows)
  SELECT state.cols IS NOT NULL AND NOT state.short AS applicable,
         CASE WHEN state.cols IS NULL THEN 'the entity of ' || split_part($subject, '.', 2) || ' states no grain'
              WHEN state.short THEN 'the grain names a column ' || split_part($subject, '.', 2) || ' does not have: '
                                    || array_to_string(state.cols, ', ') END AS reason,
         CASE WHEN state.cols IS NOT NULL AND NOT state.short THEN coalesce(state.extra / greatest(state.rows, 1)::DOUBLE, 0.0) END AS breach_rate,
         state.cols AS grain,
         CASE WHEN state.cols IS NOT NULL AND NOT state.short THEN coalesce(state.extra, 0) END AS repeated,
         (SELECT list(shown ORDER BY n DESC, shown)[1:3] FROM repeated WHERE shown IS NOT NULL) AS keys,
         CASE WHEN state.extra > 0
              THEN split_part($subject, '.', 2) || ' repeats its grain (' || array_to_string(state.cols, ', ') || ') in ' || state.extra
                   || CASE WHEN state.extra = 1 THEN ' more row: ' ELSE ' more rows: ' END
                   || (SELECT array_to_string(list(shown ORDER BY n DESC, shown)[1:3], ', ') FROM repeated WHERE shown IS NOT NULL)
                   || ', so a row counts twice in what reads it' END AS finding,
         CASE WHEN state.extra > 0 THEN concat_ws(chr(10),
           '-- find why at the source (a line sent twice, a key that needs another column), or keep one row per key in the load query (QUALIFY row_number() OVER (PARTITION BY '
             || array_to_string(state.cols, ', ') || ' ORDER BY <column>) = 1) and declare it again.',
           '-- where the rows have another grain, state it:',
           main.gloss_statement('entity', $subject, state.entity::VARCHAR),
           '-- where a person accepts the rows as they are, record the rate with their reason:',
           '-- ' || main.gloss_statement('grain_check', $subject,
                    '{"tolerance": ' || ceil(state.extra / greatest(state.rows, 1)::DOUBLE * 1000) / 1000
                    || ', "basis": "<who accepted the rows and why>"}')) END AS fix
  FROM state
$$ RETURNS grain_check;

DECLARE TEST grain_test ON grain_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- join_check: a join in the view repeats rows. Two ways: the view
-- joins two tables on columns whose values repeat on both sides, so each
-- match multiplies rows (join fan-out); or it reads an effective-dated
-- table without bounding both validity dates, so a key counts once per
-- version. The join columns come from the definition's own plan, whether
-- a column repeats from its stored column_profile, which the server runs
-- for a view's join columns. A join on several columns is judged on its
-- key as a whole, the pairs of one join between two tables: a side holds
-- each key once where one of its columns is unique, or where its columns
-- hold the grain its table's `entity` states (which grain_check tests at
-- each load); where neither side does, the profiles cannot tell, and the
-- check is not applicable until a grain is stated. A side the definition reduces to one row
-- per value before the join (grouped by the join columns, DISTINCT on
-- them, or the latest row per value by row_number() = 1) does not repeat,
-- whatever its table holds. A join on an effective-dated table repeats its
-- key by design: its validity dates judge it. A view that joins nothing
-- and reads no effective-dated table cannot repeat rows.
DECLARE ASPECT join_check WITH $${
  "description": "A join in the view must not repeat rows. Fails where the view joins two tables on columns whose values repeat on both sides, or reads a table with validity dates without bounding both, so a key counts once per version.",
  "type": "object", "x-subject": "view",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "pairs": {"type": ["array", "null"], "items": {"type": "string"}},
                 "tables": {"type": ["array", "null"], "items": {"type": "string"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION join_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  scans AS (
    SELECT DISTINCT r.table_name, r.columns FROM d, unnest(d.reads) t(r)
    WHERE split_part(r.table_name, '.', 1) = split_part($subject, '.', 1)),
  n AS (SELECT count(*) AS tables FROM scans),
  -- a view that reads no loaded table, a constant, plans and has nothing to join
  plans AS (SELECT coalesce(bool_or(c.derivation IS NOT NULL), false) AS ok FROM d, unnest(d.columns) t(c)),
  dated AS (
    SELECT asset AS table_path, value->>'valid_from' AS valid_from, value->>'valid_to' AS valid_to
    FROM annotations('validity', 'its sources') WHERE value IS NOT NULL),
  undated AS (
    SELECT DISTINCT split_part(s.table_name, '.', 2) || ' (' || x.valid_from || ', ' || x.valid_to || ')' AS scan
    FROM scans s JOIN dated x ON x.table_path = s.table_name
    WHERE NOT (list_contains(s.columns, x.valid_from) AND list_contains(s.columns, x.valid_to))),
  owners AS (
    SELECT DISTINCT r.table_name, r.table_name || '.' || c AS column_path FROM d, unnest(d.reads) t(r), unnest(r.columns) u(c)),
  sided AS (
    SELECT j.left_column, j.right_column, j.join_number, j.left_unique OR j.right_unique AS reduced,
           l.table_name AS left_table, r.table_name AS right_table
    FROM d, unnest(d.joins) t(j)
    LEFT JOIN owners l ON l.column_path = j.left_column LEFT JOIN owners r ON r.column_path = j.right_column),
  joins AS (
    SELECT * FROM sided
    WHERE left_table IS DISTINCT FROM right_table
      AND coalesce(left_table NOT IN (SELECT table_path FROM dated), true)
      AND coalesce(right_table NOT IN (SELECT table_path FROM dated), true)),
  profiles AS (
    SELECT asset AS subject, try_cast(json_extract(value, '$.distinct') AS BIGINT) AS distinct_values,
           round(try_cast(json_extract(value, '$.total') AS DOUBLE) * (1 - coalesce(try_cast(json_extract(value, '$.null_ratio') AS DOUBLE), 0))) AS filled
    FROM results('column_profile', 'the columns it joins on') WHERE value IS NOT NULL OR error IS NOT NULL),
  -- the entity each table the view reads states, and its grain
  entities AS (
    SELECT asset AS table_path, value AS entity,
           CASE WHEN json_array_length(value->'grain') > 0 THEN from_json(value->'grain', '["VARCHAR"]') END AS grain
    FROM annotations('entity', 'its sources') WHERE value IS NOT NULL AND state IN ('current', 'stale')),
  pairs AS (
    SELECT j.*, l.subject IS NOT NULL AS left_profiled, r.subject IS NOT NULL AS right_profiled,
           coalesce(l.distinct_values < l.filled, false) AS left_repeats, coalesce(r.distinct_values < r.filled, false) AS right_repeats
    FROM joins j LEFT JOIN profiles l ON l.subject = j.left_column LEFT JOIN profiles r ON r.subject = j.right_column),
  -- a join's key: its pairs between the same two tables
  keys AS (
    SELECT join_number, left_table, right_table, count(*) AS width,
           list(left_column ORDER BY left_column, right_column) AS lefts, list(right_column ORDER BY left_column, right_column) AS rights,
           bool_or(reduced) AS reduced, bool_and(left_profiled AND right_profiled) AS profiled,
           bool_and(left_repeats) AND bool_and(right_repeats) AS both_repeat,
           bool_or(left_profiled AND NOT left_repeats) AS left_column_once, bool_or(right_profiled AND NOT right_repeats) AS right_column_once
    FROM pairs GROUP BY join_number, left_table, right_table),
  judged AS (
    SELECT k.*,
           k.reduced OR k.left_column_once OR coalesce(list_has_all(list_transform(k.lefts, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', '')), l.grain), false)
             OR k.right_column_once OR coalesce(list_has_all(list_transform(k.rights, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', '')), r.grain), false) AS once,
           l.entity AS left_entity, r.entity AS right_entity
    FROM keys k LEFT JOIN entities l ON l.table_path = k.left_table LEFT JOIN entities r ON r.table_path = k.right_table),
  -- a single column repeats where both profiles say so; a key of several columns holds once on a
  -- side, or the profiles cannot tell
  decided AS (
    SELECT *, CASE WHEN width = 1 THEN reduced OR profiled ELSE once OR profiled END AS measured,
           CASE WHEN width = 1 THEN NOT reduced AND both_repeat ELSE false END AS repeats,
           width > 1 AND profiled AND NOT once AS untold,
           CASE WHEN width = 1 THEN regexp_replace(lefts[1], '^[^.]*\.', '') || ' ~ ' || regexp_replace(rights[1], '^[^.]*\.', '')
                ELSE split_part(left_table, '.', 2) || '.(' || list_aggregate(list_transform(lefts, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', '')), 'string_agg', ', ')
                     || ') ~ ' || split_part(right_table, '.', 2) || '.(' || list_aggregate(list_transform(rights, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', '')), 'string_agg', ', ') || ')' END AS pair
    FROM judged),
  unprofiled AS (
    SELECT string_agg(DISTINCT c, ', ' ORDER BY c) AS columns
    FROM (SELECT p.left_column AS c FROM pairs p JOIN decided k USING (join_number, left_table, right_table) WHERE NOT k.measured AND NOT p.left_profiled
          UNION SELECT p.right_column FROM pairs p JOIN decided k USING (join_number, left_table, right_table) WHERE NOT k.measured AND NOT p.right_profiled)),
  repeating AS (SELECT DISTINCT pair FROM decided WHERE repeats),
  untold AS (SELECT DISTINCT pair, left_table, right_table, lefts, rights, left_entity, right_entity FROM decided WHERE untold),
  state AS (
    SELECT (n.tables > 0 OR plans.ok)
             AND (EXISTS (SELECT 1 FROM undated) OR NOT EXISTS (SELECT 1 FROM decided WHERE NOT measured OR untold)) AS applicable,
           EXISTS (SELECT 1 FROM repeating) AS fans, EXISTS (SELECT 1 FROM undated) AS versions,
           EXISTS (SELECT 1 FROM decided WHERE NOT measured) AS unmeasured,
           (SELECT redefine_statement(view) FROM d) AS redefine
    FROM n, plans)
  SELECT state.applicable,
         CASE WHEN n.tables = 0 AND NOT state.applicable THEN 'its definition does not plan'
              WHEN NOT state.applicable AND state.unmeasured THEN 'the join columns are not profiled yet: run column_profile() over ' || (SELECT columns FROM unprofiled)
              WHEN NOT state.applicable
                THEN split_part($subject, '.', 2) || ' joins on ' || (SELECT string_agg(pair, ', ' ORDER BY pair) FROM untold)
                     || ': a key of several columns is judged as a whole, and neither a unique column nor a stated grain says which side holds each key once' END AS reason,
         CASE WHEN NOT state.applicable THEN NULL WHEN state.fans OR state.versions THEN 1.0 ELSE 0.0 END AS breach_rate,
         (SELECT list(pair ORDER BY pair) FROM repeating) AS pairs,
         (SELECT list(scan ORDER BY scan) FROM undated) AS tables,
         nullif(concat_ws('; ',
           CASE WHEN state.fans
                THEN split_part($subject, '.', 2) || ' joins on ' || (SELECT string_agg(pair, ', ' ORDER BY pair) FROM repeating)
                     || ', and the values repeat on both sides, so each match multiplies rows' END,
           CASE WHEN state.versions
                THEN split_part($subject, '.', 2) || ' reads ' || (SELECT string_agg(scan, ', ' ORDER BY scan) FROM undated)
                     || ' without bounding both validity dates, so a row counts once per version' END), '') AS finding,
         CASE WHEN state.fans OR state.versions THEN concat_ws(chr(10),
           CASE WHEN state.fans
                THEN '-- make one side of the join one row per value: join through the table that holds the key once, or keep one row per key in a subquery (the latest row per key, or GROUP BY the key).' END,
           CASE WHEN state.versions
                THEN '-- bound both validity dates by the period (valid_from <= period AND valid_to > period).' END,
           '-- Then record the definition again:',
           state.redefine,
           CASE WHEN state.fans
                THEN '-- where one of the tables holds a row per version, say so, and this check judges the join by its validity dates:' || chr(10)
                     || '-- ' || main.gloss_statement('validity', '<table>', '{"valid_from": "<column>", "valid_to": "<column>"}') END,
           '-- where the join is meant as it is, accept it with the reason:',
           '-- ' || main.gloss_statement('join_check', $subject, '{"tolerance": 1.0, "basis": "<why the join is meant>"}'))
              WHEN NOT state.applicable AND NOT state.unmeasured AND EXISTS (SELECT 1 FROM untold) THEN concat_ws(chr(10),
           '-- state the grain of the table that holds each key once; the server tests it at each load, and this check judges the join by it:',
           (SELECT string_agg(main.gloss_statement('entity', right_table,
                     json_merge_patch(coalesce(right_entity::VARCHAR, '{"value": "<what one row is>", "role": "<fact|dimension>"}'),
                       json_object('grain', list_transform(rights, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', ''))))::VARCHAR)
                     || chr(10) || '-- where ' || split_part(left_table, '.', 2) || ' holds each key once instead:' || chr(10) || '-- '
                     || main.gloss_statement('entity', left_table,
                     json_merge_patch(coalesce(left_entity::VARCHAR, '{"value": "<what one row is>", "role": "<fact|dimension>"}'),
                       json_object('grain', list_transform(lefts, lambda c: regexp_replace(c, '^[^.]*\.[^.]*\.', ''))))::VARCHAR),
                   chr(10) ORDER BY pair) FROM untold)) END AS fix
  FROM n, state
$$ RETURNS join_check;

DECLARE TEST join_test ON join_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- additivity_check: the metric's value column says how it adds up over
-- time and members (additive sums, semi-additive keeps the period's last
-- level, a ratio divides its summed numerator by its summed denominator),
-- and that agrees with how the column is computed: the lineage's shape says
-- a ratio, an average or a distinct count, none of which may be summed. The
-- value is the column annotated role measure, the one named value where
-- several are.
DECLARE ASPECT additivity_check WITH $${
  "description": "The metric adds its value up the way the value allows. Fails where a ratio, an average or a distinct count is summed.",
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]}, "additivity": {"type": ["string", "null"]},
                 "shape": {"type": ["string", "null"]},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION additivity_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself') WHERE sql IS NOT NULL OR stopped IS NOT NULL),
  cols AS (SELECT c.name AS col, c.position AS pos, c.shape FROM d, unnest(d.columns) t(c)),
  roles AS (SELECT substr(asset, length($subject) + 2) AS col, value->>'value' AS role
            FROM annotations('role', 'its columns') WHERE state IN ('current', 'stale') AND value IS NOT NULL),
  adds AS (SELECT substr(asset, length($subject) + 2) AS col, value, state
           FROM annotations('additivity', 'its columns') WHERE state <> 'missing'),
  measures AS (SELECT list(col ORDER BY CASE WHEN col = 'value' THEN 0 ELSE 1 END, pos) AS cols
               FROM roles JOIN cols USING (col) WHERE role = 'measure'),
  a AS (
    SELECT split_part($subject, '.', 2) AS view, d.kind,
           CASE WHEN len(m.cols) = 1 OR m.cols[1] = 'value' THEN m.cols[1] END AS value_column,
           CASE WHEN coalesce(d.kind, '') = 'scalar' THEN []::VARCHAR[]
                ELSE coalesce((SELECT list(main.gloss_statement('role', $subject || '.' || col, '{"value": "<key|measure|dimension|timestamp|attribute>"}') ORDER BY pos)
                               FROM cols WHERE col NOT IN (SELECT col FROM roles)), []::VARCHAR[]) END AS missing,
           redefine_statement(d.view) AS redefine
    FROM d, measures m),
  v AS (
    SELECT a.*,
           (SELECT CASE WHEN state IN ('current', 'stale') THEN value->>'value' END FROM adds WHERE adds.col = a.value_column) AS additivity,
           coalesce((SELECT CASE WHEN state IN ('current', 'stale') THEN state ELSE 'conflict' END FROM adds WHERE adds.col = a.value_column), 'none') AS additivity_state
    FROM a),
  ok AS (SELECT EXISTS (SELECT 1 FROM v WHERE value_column IS NOT NULL AND coalesce(kind, '') NOT IN ('scalar', 'relation')) AS applicable),
  computed AS (SELECT max(cols.shape) AS shape FROM cols JOIN v ON cols.col = v.value_column)
  SELECT ok.applicable,
         CASE WHEN NOT ok.applicable THEN coalesce((SELECT 'a ' || kind || ' has nothing to combine' FROM v WHERE coalesce(kind, '') IN ('scalar', 'relation')),
                                                  'the definition does not say yet which column is the time and which the measure') END AS reason,
         CASE WHEN ok.applicable THEN (SELECT CASE WHEN additivity IS NULL OR additivity_state <> 'current' THEN 1.0
                                                   WHEN computed.shape IN ('ratio', 'average') AND additivity IN ('additive', 'semi-additive') THEN 1.0
                                                   WHEN computed.shape = 'distinct' AND additivity = 'additive' THEN 1.0
                                                   ELSE 0.0 END FROM v) END AS breach_rate,
         (SELECT additivity FROM v) AS additivity,
         computed.shape AS shape,
         CASE WHEN NOT ok.applicable THEN NULL ELSE (SELECT CASE
              WHEN additivity IS NULL OR additivity_state <> 'current'
                THEN value_column || ' of ' || view || ' does not say how it adds up, which a total and a coarser time grain need'
              WHEN computed.shape = 'distinct' AND additivity = 'additive'
                THEN value_column || ' of ' || view || ' is a distinct count marked additive: distinct counts do not add up, so a total and a coarser time grain are wrong'
              WHEN computed.shape IN ('ratio', 'average') AND additivity IN ('additive', 'semi-additive')
                THEN value_column || ' of ' || view || ' is ' || CASE computed.shape WHEN 'ratio' THEN 'a ratio' ELSE 'an average' END
                     || ' marked ' || additivity || ': its rows are summed, so a total and a coarser time grain are wrong' END FROM v) END AS finding,
         CASE WHEN NOT ok.applicable
              THEN (SELECT CASE WHEN len(coalesce(missing, [])) > 0 THEN list_aggregate(missing, 'string_agg', chr(10)) ELSE redefine END FROM v)
              ELSE (SELECT CASE
              WHEN additivity IS NULL OR additivity_state <> 'current'
                THEN main.gloss_statement('additivity', $subject || '.' || value_column,
                       '{"value": "<additive|semi-additive|ratio|non-additive>", "basis": "<why, in the business''s words>"}')
              WHEN computed.shape = 'distinct' AND additivity = 'additive'
                THEN main.gloss_statement('additivity', $subject || '.' || value_column,
                       '{"value": "non-additive", "basis": "a distinct count"}')
              WHEN computed.shape IN ('ratio', 'average') AND additivity IN ('additive', 'semi-additive')
                THEN '-- serve the numerator and the denominator beside the value and say so in "measure": {"column": "' || value_column
                     || '", "additivity": "ratio", "numerator": "<column>", "denominator": "<column>"}. Then record the definition again:' || chr(10)
                     || redefine || chr(10)
                     || '-- where the number is right as it is, accept it with the reason:' || chr(10)
                     || '-- ' || main.gloss_statement('additivity_check', $subject, '{"tolerance": 1.0, "basis": "<why it may be summed>"}') END FROM v) END AS fix
  FROM ok, computed
$$ RETURNS additivity_check;

DECLARE TEST measure_additivity_test ON additivity_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- orphan_check: the share of rows on a declared relationship the view
-- joins over whose key finds no parent, from the coherence result stored
-- on each relationship (relationship_coherence), with the keys that find
-- none (the three with the most rows, and how many); an inner join drops them,
-- an outer join keeps them with empty parent columns. A relationship is joined over
-- when each of its columns is among the columns the definition joins on;
-- one between the tables it reads on other columns is not judged. Where
-- the view joins over no declared relationship there is nothing to
-- check; where one has no coherence result yet, the check is not
-- applicable until it has.
DECLARE ASPECT orphan_check WITH $${
  "description": "Referential integrity on the relationships the view joins over: the share of rows whose key finds no parent row.",
  "type": "object", "x-subject": "view",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "edges": {"type": ["array", "null"], "items": {"type": "object"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION orphan_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  reads AS (SELECT DISTINCT split_part(r.table_name, '.', 2) AS table_name FROM d, unnest(d.reads) t(r)
            WHERE split_part(r.table_name, '.', 1) = split_part($subject, '.', 1)),
  n AS (SELECT count(*) AS tables, string_agg(table_name, ', ' ORDER BY table_name) AS names FROM reads),
  -- a view that reads no loaded table, a constant, plans and has no key to check
  plans AS (SELECT coalesce(bool_or(c.derivation IS NOT NULL), false) AS ok FROM d, unnest(d.columns) t(c)),
  joined AS (SELECT DISTINCT side AS column_path FROM d, unnest(d.joins) t(j), unnest([j.left_column, j.right_column]) u(side)),
  coherence AS (
    SELECT asset AS relationship, value,
           regexp_extract(asset, '^[^.]+\.([^.]+)\.', 1) AS left_table,
           regexp_extract(asset, ' <?-> [^.]+\.([^.]+)\.', 1) AS right_table
    FROM results('relationship_coherence', 'its relationships')),
  endpoints AS (
    SELECT c.relationship, regexp_extract(e.side, '^([^.]+\.[^.]+)\.', 1) || '.' || trim(k.name) AS column_path
    FROM coherence c, unnest(regexp_split_to_array(c.relationship, ' <?-> ')) e(side),
         unnest(string_split(trim(regexp_replace(e.side, '^[^.]+\.[^.]+\.', ''), '()'), ',')) k(name)),
  rels AS (
    SELECT * FROM coherence c
    WHERE NOT EXISTS (SELECT 1 FROM endpoints e WHERE e.relationship = c.relationship
                      AND e.column_path NOT IN (SELECT column_path FROM joined))),
  declared AS (SELECT * FROM rels WHERE left_table <> right_table),
  mine AS (
    SELECT relationship, try_cast(json_extract(value, '$.orphan_rate') AS DOUBLE) AS orphan_rate,
           coalesce(from_json(value->'orphan_keys', '[{"key": "VARCHAR", "rows": "BIGINT"}]'), []) AS orphan_keys,
           try_cast(value->>'orphan_distinct' AS BIGINT) AS orphan_distinct
    FROM rels WHERE value IS NOT NULL)
  SELECT CASE WHEN n.tables = 0 THEN plans.ok WHEN n.tables = 1 THEN true
              WHEN NOT EXISTS (SELECT 1 FROM declared) THEN true
              ELSE NOT EXISTS (SELECT 1 FROM declared WHERE value IS NULL) END AS applicable,
         CASE WHEN n.tables = 0 AND NOT plans.ok THEN 'its definition does not plan'
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM declared) THEN 'no declared relationship is among the joins of the tables the view scans (' || n.names || '): nothing to check'
              WHEN n.tables > 1 AND EXISTS (SELECT 1 FROM declared WHERE value IS NULL)
                THEN 'no coherence result is stored for ' || (SELECT string_agg(relationship, ', ' ORDER BY relationship) FROM declared WHERE value IS NULL)
                     || ': run relationship_coherence() over each' END AS reason,
         CASE WHEN n.tables = 1 OR (n.tables = 0 AND plans.ok) THEN 0.0
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM declared) THEN 0.0
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM declared WHERE value IS NULL) THEN coalesce((SELECT max(orphan_rate) FROM mine), 0.0) END AS breach_rate,
         (SELECT list({'relationship': relationship, 'orphan_rate': orphan_rate, 'orphan_keys': orphan_keys, 'orphan_distinct': orphan_distinct}
                      ORDER BY relationship) FROM mine) AS edges,
         CASE WHEN EXISTS (SELECT 1 FROM mine WHERE orphan_rate > 0)
              THEN (SELECT string_agg(round(orphan_rate * 100, 1) || '% of rows on ' || relationship
                                      || CASE WHEN len(orphan_keys) > 0
                                              THEN ' (' || list_aggregate(list_transform(orphan_keys, lambda k: k.key || ': ' || k.rows
                                                         || CASE WHEN k.rows = 1 THEN ' row' ELSE ' rows' END), 'string_agg', ', ')
                                                   || CASE WHEN orphan_distinct > len(orphan_keys) THEN '; ' || orphan_distinct || ' keys in all' ELSE '' END || ')'
                                              ELSE '' END, ', ' ORDER BY relationship) FROM mine WHERE orphan_rate > 0)
                   || ' find no parent: an inner join drops them, an outer join keeps them with empty parent columns' END AS finding,
         CASE WHEN EXISTS (SELECT 1 FROM mine WHERE orphan_rate > 0)
              THEN concat_ws(chr(10),
                '-- add each key to the parent table at its source (a code table, a mapping table), then load that table again:',
                (SELECT string_agg(DISTINCT 'IMPORT ' || regexp_extract(relationship, ' <?-> ([^.]+\.[^.]+)\.', 1) || ';', chr(10))
                 FROM mine WHERE orphan_rate > 0),
                '-- where a person accepts the rows without a parent, record the rate with their reason:',
                '-- ' || main.gloss_statement('orphan_check', $subject, '{"tolerance": ' || (SELECT max(orphan_rate) FROM mine) || ', "basis": "<why these rows have no parent>"}')) END AS fix
  FROM n, plans
$$ RETURNS orphan_check;

DECLARE TEST orphan_test ON orphan_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- completeness_check: a column a view serves that a load or a new
-- definition emptied, one result per column: whether a column can be used
-- depends on what reads it, so each is judged and accepted on its own.
-- The column's share of empty values (NULL) comes from its stored
-- column_profile, which the server computes on each column of the view,
-- and the state before from the values that profile held (results()'
-- history): walked oldest first, a share that rose by more than the
-- tolerance over the last share within it is a column that emptied, and
-- that last share stays its state before until the column is filled again
-- or the tolerance is raised. So a column that drifts by less than the
-- tolerance per load stays quiet, a column mostly empty before cannot rise
-- past it, and a later load that moves its rows again keeps it red.
-- breach_rate is the rise; emptied_by is `load` where a table column it is
-- computed from (its sources) emptied as well, by the same walk over that
-- column's profile, else `definition`. A column with no profile yet is not
-- applicable. `SELECT completeness_check() FROM <dataset>.<view>` computes
-- each column of the view, the property being declared on columns alone.
DECLARE ASPECT completeness_check WITH $${
  "description": "The column a view serves keeps its values. Fails where a load of a table the view reads, or the view's definition recorded again, emptied the column on a larger share of the rows than the tolerance.",
  "type": "object", "x-subject": "view",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "before": {"type": ["number", "null"]}, "now": {"type": ["number", "null"]},
                 "emptied_by": {"type": ["string", "null"]},
                 "sources": {"type": ["array", "null"], "items": {"type": "string"}},
                 "cause": {"type": ["string", "null"]},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON COLUMN;

DECLARE FUNCTION completeness_check FOR GLOBAL AS $$
  WITH tol AS (
    SELECT coalesce(max(try_cast(value->>'tolerance' AS DOUBLE)), max(threshold), 0.0) AS tolerance
    FROM annotations('completeness_check', 'itself') WHERE state IN ('current', 'stale', 'missing')),
  -- the shares empty of the column and of the columns it is computed from, oldest first, each walked
  -- to the last share within the tolerance
  profiled AS (
    SELECT asset, list_transform(history, lambda v: coalesce(try_cast(v->>'null_ratio' AS DOUBLE), 0.0)) AS shares
    FROM (SELECT asset, history FROM results('column_profile', 'itself')
          UNION ALL SELECT asset, history FROM results('column_profile', 'its sources'))
    WHERE len(history) > 0),
  walked AS (
    SELECT p.asset, p.shares[-1] AS now_,
           list_reduce(p.shares, lambda b, e: CASE WHEN e - b > t.tolerance THEN b ELSE e END) AS before
    FROM profiled p, tol t),
  rose AS (SELECT asset, before, now_, round(now_ - before, 4) AS rise FROM walked, tol WHERE now_ - before > tol.tolerance),
  own AS (SELECT * FROM walked WHERE asset = $subject),
  emptied AS (SELECT * FROM rose WHERE asset = $subject),
  by_load AS (SELECT asset FROM rose WHERE asset <> $subject),
  names AS (
    SELECT split_part($subject, '.', 1) AS ds, split_part($subject, '.', 2) AS view,
           array_to_string(string_split($subject, '.')[3:], '.') AS col),
  state AS (
    SELECT EXISTS (SELECT 1 FROM own) AS applicable, EXISTS (SELECT 1 FROM emptied) AS red,
           EXISTS (SELECT 1 FROM by_load) AS loaded,
           (SELECT list(asset ORDER BY asset) FROM by_load) AS sources,
           (SELECT string_agg(split_part(asset, '.', 2) || '.' || array_to_string(string_split(asset, '.')[3:], '.'), ', ' ORDER BY asset)
            FROM by_load) AS emptied_sources,
           (SELECT string_agg(DISTINCT 'IMPORT ' || split_part(asset, '.', 1) || '.' || split_part(asset, '.', 2) || ';', chr(10))
            FROM by_load) AS loads,
           (SELECT before FROM emptied) AS before, (SELECT now_ FROM emptied) AS now_, (SELECT rise FROM emptied) AS rate),
  said AS (
    SELECT s.*, n.*,
           CASE WHEN s.red
                THEN n.col || ' of ' || n.view || ' is ' || round(s.now_ * 100, 1) || '% empty, ' || round(s.before * 100, 1) || '% before'
                     || CASE WHEN s.loaded THEN ', since a load emptied ' || s.emptied_sources
                             ELSE ', while what it is computed from is filled: the definition empties it' END
                     || ', so ' || n.view || ' serves these rows without the value' END AS finding
    FROM state s, names n)
  SELECT applicable,
         CASE WHEN NOT applicable THEN col || ' of ' || view || ' is not profiled yet: run column_profile() over it' END AS reason,
         CASE WHEN applicable THEN coalesce(rate, 0.0) END AS breach_rate,
         CASE WHEN red THEN before END AS before,
         CASE WHEN red THEN now_ END AS now,
         CASE WHEN red THEN CASE WHEN loaded THEN 'load' ELSE 'definition' END END AS emptied_by,
         CASE WHEN red AND loaded THEN sources END AS sources,
         CASE WHEN red THEN CASE WHEN loaded THEN 'a load emptied ' || emptied_sources
                                 ELSE 'the definition of ' || view || ' empties ' || col END END AS cause,
         finding,
         CASE WHEN red THEN concat_ws(chr(10),
           CASE WHEN loaded
                THEN '-- send the values again at the source, or read them in the load query (load_changes() says what the load changed), then load again:'
                     || chr(10) || loads
                ELSE '-- correct the expression of ' || col || ' and record the definition again:'
                     || chr(10) || redefine_statement(ds || '.' || view) END,
           '-- where a person confirms ' || col || ' is right as it is now, record the rate with their reason:',
           '-- ' || main.gloss_statement('completeness_check', $subject,
                    '{"tolerance": ' || ceil(rate * 1000) / 1000 || ', "basis": "<why ' || col || ' is empty now>"}')) END AS fix
  FROM said
$$ RETURNS completeness_check;

DECLARE TEST completeness_test ON completeness_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.1;

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

-- relationship_check: each join the view makes between two loaded tables
-- has a declared relationship, so the orphan check and the reconciliation
-- can test its keys. A join is the pairs of columns of one join between two
-- tables; a relationship covers it where its pairs are the join's, either
-- way round. Where one is missing, the result has no rate (yellow), the
-- finding names the join and the fix declares the relationship: from the
-- side that repeats the key to the side that holds it once, as a stored
-- column_profile (a unique column) or the table's stated grain says; where
-- neither does, in the join's order, left to right. Green where every join
-- is covered. It is computed again when the view's definition, the
-- relationships of the tables it reads, the profiles of its join columns
-- or the grains of its tables change.
DECLARE ASPECT relationship_check WITH $${
  "description": "Each join the view makes between two loaded tables has a declared relationship.",
  "type": "object", "x-subject": "view",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "joins": {"type": ["array", "null"], "items": {"type": "string"}},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION relationship_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  ds AS (SELECT split_part($subject, '.', 1) AS d),
  tables AS (SELECT DISTINCT r.table_name FROM d, unnest(d.reads) t(r), ds WHERE split_part(r.table_name, '.', 1) = ds.d),
  pairs AS (
    SELECT j.join_number, split_part(j.left_column, '.', 2) AS lt, split_part(j.right_column, '.', 2) AS rt,
           regexp_replace(j.left_column, '^[^.]*\.[^.]*\.', '') AS lc, regexp_replace(j.right_column, '^[^.]*\.[^.]*\.', '') AS rc
    FROM d, unnest(d.joins) t(j)
    WHERE array_to_string(string_split(j.left_column, '.')[1:2], '.') IN (SELECT table_name FROM tables)
      AND array_to_string(string_split(j.right_column, '.')[1:2], '.') IN (SELECT table_name FROM tables)
      AND split_part(j.left_column, '.', 2) <> split_part(j.right_column, '.', 2)),
  joined AS (
    SELECT join_number, lt, rt, list(lc ORDER BY lc, rc) AS lc, list(rc ORDER BY lc, rc) AS rc
    FROM pairs GROUP BY join_number, lt, rt),
  -- the relationships between the tables it reads, each side as table and columns
  sides AS (
    SELECT regexp_split_to_array(asset, ' <?-> ') AS s FROM results('relationship_coherence', 'its relationships')),
  declared AS (
    SELECT main.pairs_key(split_part(s[1], '.', 2), split_part(s[2], '.', 2),
             string_split(regexp_replace(regexp_replace(s[1], '^[^.]+\.[^.]+\.', ''), '^\((.*)\)$', '\1'), ', '),
             string_split(regexp_replace(regexp_replace(s[2], '^[^.]+\.[^.]+\.', ''), '^\((.*)\)$', '\1'), ', ')) AS key
    FROM sides WHERE len(s) = 2),
  undeclared AS (
    SELECT * FROM (SELECT *, main.pairs_key(lt, rt, lc, rc) AS key FROM joined)
    WHERE key NOT IN (SELECT key FROM declared WHERE key IS NOT NULL)
    QUALIFY row_number() OVER (PARTITION BY key ORDER BY join_number) = 1),
  -- a side holds each key once: a unique column by its stored profile, or the grain its table's entity states
  held_once AS (
    SELECT split_part(asset, '.', 2) AS t, [split_part(asset, '.', 3)] AS cols
    FROM results('column_profile', 'the columns it joins on')
    WHERE value IS NOT NULL AND (value->>'total')::BIGINT > 0
      AND (value->>'distinct')::BIGINT >= round((value->>'total')::DOUBLE * (1 - coalesce((value->>'null_ratio')::DOUBLE, 0)))
    UNION ALL
    SELECT split_part(asset, '.', 2), from_json(value->'grain', '["VARCHAR"]') FROM annotations('entity', 'its sources')
    WHERE value IS NOT NULL AND state IN ('current', 'stale') AND json_array_length(value->'grain') > 0),
  sided AS (
    SELECT u.*,
           EXISTS (SELECT 1 FROM held_once h WHERE h.t = u.lt AND list_has_all(u.lc, h.cols)) AS left_once,
           EXISTS (SELECT 1 FROM held_once h WHERE h.t = u.rt AND list_has_all(u.rc, h.cols)) AS right_once
    FROM undeclared u),
  -- from the side that repeats the key to the side that holds it once
  directed AS (
    SELECT key, left_once, right_once,
           CASE WHEN left_once AND NOT right_once THEN rt ELSE lt END AS ft, CASE WHEN left_once AND NOT right_once THEN rc ELSE lc END AS fc,
           CASE WHEN left_once AND NOT right_once THEN lt ELSE rt END AS tt, CASE WHEN left_once AND NOT right_once THEN lc ELSE rc END AS tc,
           CASE WHEN left_once AND right_once THEN ' <-> ' ELSE ' -> ' END AS op
    FROM sided),
  said AS (
    SELECT key, main.relationship_side(ds.d, ft, fc, false) || op || main.relationship_side(ds.d, tt, tc, false) AS relationship,
           'the join of ' || ft || ' and ' || tt || ' on '
             || array_to_string(list_transform(range(1, len(fc) + 1), lambda i: ft || '.' || fc[i] || ' = ' || tt || '.' || tc[i]), ' and ') AS join_,
           CASE WHEN left_once AND right_once THEN '-- each side holds each key once'
                WHEN left_once OR right_once THEN '-- ' || tt || ' holds each key once'
                ELSE '-- no stored profile or grain says which side holds each key once: the direction is the join''s, left to right; where '
                     || ft || ' holds each key once, write it the other way round' END
             || '. Declare the relationship, and the server checks each key against the data:' || chr(10)
             || 'DECLARE RELATIONSHIP ' || main.relationship_side(ds.d, ft, fc, true) || op || main.relationship_side(ds.d, tt, tc, true) || ';' AS statement
    FROM directed, ds)
  SELECT true AS applicable,
         CAST(NULL AS VARCHAR) AS reason,
         CASE WHEN EXISTS (SELECT 1 FROM said) THEN NULL ELSE 0.0 END AS breach_rate,
         (SELECT list(relationship ORDER BY key) FROM said) AS joins,
         (SELECT 'no relationship is declared for ' || string_agg(join_, '; ' ORDER BY key)
                 || ': the orphan check and the reconciliation name no keys on it' FROM said HAVING count(*) > 0) AS finding,
         (SELECT string_agg(statement, chr(10) ORDER BY key) FROM said HAVING count(*) > 0) AS fix
$$ RETURNS relationship_check;

DECLARE TEST relationship_test ON relationship_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- series_check: a metric serves a series. It needs a column with role
-- timestamp (the one named period where several carry it), a column with
-- role measure (the one named value where several carry it), and a grain
-- for the period column: the floor its time grains state, else the grain
-- its temporal profile measured. Where one is missing the metric serves
-- nothing, the test is red, the finding says what is missing and the fix
-- is the annotation or the measurement that brings it. Computed again when
-- the definition, the roles, the time grains or the temporal profile of
-- the metric's columns change.
DECLARE ASPECT series_check WITH $${
  "description": "The metric serves a series: a column carries role timestamp, a column carries role measure, and the period column has a grain.",
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "finding": {"type": ["string", "null"]}, "fix": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION series_check FOR GLOBAL AS $$
  WITH d AS (SELECT * FROM definition('itself')),
  cols AS (SELECT c.name AS col, c.position AS pos FROM d, unnest(d.columns) t(c)),
  claims AS (
    SELECT substr(asset, length($subject) + 2) AS col, property, value
    FROM (FROM annotations('role', 'its columns') UNION ALL FROM annotations('time_grains', 'its columns')
          UNION ALL FROM annotations('temporal_profile', 'its columns'))
    WHERE state IN ('current', 'stale') AND value IS NOT NULL),
  roles AS (SELECT col, value->>'value' AS role FROM claims WHERE property = 'role'),
  picked AS (
    SELECT (SELECT list(r.col ORDER BY CASE WHEN r.col = 'period' THEN 0 ELSE 1 END, c.pos) FROM roles r JOIN cols c USING (col)
            WHERE r.role = 'timestamp') AS period_cols,
           (SELECT list(r.col ORDER BY CASE WHEN r.col = 'value' THEN 0 ELSE 1 END, c.pos) FROM roles r JOIN cols c USING (col)
            WHERE r.role = 'measure') AS measure_cols),
  chosen AS (
    SELECT *, CASE WHEN len(period_cols) = 1 OR period_cols[1] = 'period' THEN period_cols[1] END AS period_column,
              CASE WHEN len(measure_cols) = 1 OR measure_cols[1] = 'value' THEN measure_cols[1] END AS value_column
    FROM picked),
  grained AS (
    SELECT ch.*,
           coalesce((SELECT max(value->>'floor') FROM claims WHERE property = 'time_grains' AND col = ch.period_column),
                    (SELECT max(CASE WHEN value->>'applicable' = 'true'
                                      AND value->>'granularity' IN ('minute', 'hour', 'day', 'week', 'month', 'quarter', 'year')
                                     THEN value->>'granularity' END)
                     FROM claims WHERE property = 'temporal_profile' AND col = ch.period_column)) AS floor,
           EXISTS (SELECT 1 FROM claims WHERE property = 'temporal_profile' AND col = ch.period_column) AS profiled
    FROM chosen ch),
  judged AS (
    SELECT g.*, d.kind,
           main.series_reason(split_part($subject, '.', 1), split_part($subject, '.', 2), d.stopped, coalesce(len(d.columns), 0) > 0,
                              d.kind, g.period_column, g.period_cols, g.value_column, g.measure_cols, g.floor, g.profiled) AS reason
    FROM grained g, d)
  SELECT coalesce(kind, '') NOT IN ('scalar', 'relation') AS applicable,
         CASE WHEN coalesce(kind, '') IN ('scalar', 'relation') THEN 'a ' || kind || ' serves no series' END AS reason,
         CASE WHEN coalesce(kind, '') IN ('scalar', 'relation') THEN NULL WHEN reason IS NULL THEN 0.0 ELSE 1.0 END AS breach_rate,
         CASE WHEN coalesce(kind, '') NOT IN ('scalar', 'relation') THEN reason END AS finding,
         CASE WHEN coalesce(kind, '') IN ('scalar', 'relation') OR reason IS NULL THEN NULL
              WHEN period_column IS NULL
              THEN main.gloss_statement('role', $subject || '.<period column>', '{"value": "timestamp"}')
              WHEN value_column IS NULL
              THEN main.gloss_statement('role', $subject || '.<value column>', '{"value": "measure"}')
              WHEN floor IS NULL AND NOT profiled
              THEN 'SELECT temporal() FROM ' || $subject || '.' || period_column || ';'
              WHEN floor IS NULL
              THEN main.gloss_statement('time_grains', $subject || '.' || period_column, '{"floor": "<minute|hour|day|week|month|quarter|year>"}')
              ELSE redefine_statement($subject) END AS fix
  FROM judged
$$ RETURNS series_check;

DECLARE TEST series_test ON series_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

--===------------------------------------------------------------------===--
-- view_tests(): every test on each view of the bound dataset and on
-- what it reads, and every test on a result about the dataset as a whole
-- or about a view with no tests of its own — view, test, aspect,
-- declared_by (the kit that ships the test, kit:<name>, or the agent or
-- person who wrote it), subject (the view, or a table or column it reads,
-- or the dataset), state (red, orange, yellow, green, error, or not_run
-- while the test has not run), current (false once what the result read
-- has moved: the state is kept and the test runs again at the next
-- touch), score, evidence (the stored result, with its `finding` and
-- `fix` where the check returns them), run (the statement that measures
-- the test's property again: the function that returns it, over the
-- subject; empty where the test compares annotations and no function
-- measures it, as role_test does, and on a result about the dataset or a
-- view with no tests, which an actor stores and the server does not
-- compute after a write). The tests marked x-subject view appear on
-- every view, run or not, on each of its columns where the property is
-- declared on columns alone, those marked x-subject metric on every metric,
-- those marked x-subject table on every loaded table with no view (''),
-- those marked x-set-by too only where the property it names is
-- annotated on the view or the table or on one of its columns.
-- Each view carries the tests on what it reads and the tests declared on
-- it. A test on the dataset's own result has no view (''). Ordered by what to look at
-- first.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.view_tests() AS TABLE
WITH summary AS MATERIALIZED (SELECT view, kind, stopped FROM main.view_kinds()),
-- every served view, a metric, a table and a single value alike
all_views AS (
  SELECT view, coalesce(kind, '') NOT IN ('scalar', 'relation') AS metric FROM summary
  WHERE stopped IS NULL),
results AS MATERIALIZED (SELECT subject, aspect, test, state, score, current FROM glossql_tests(current_schema(), NULL)),
authors AS (
  SELECT name AS test, declared_by FROM main.tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
-- a kit's check on each view (x-subject view), or on each metric alone
-- (x-subject metric: a check that needs a measure)
expected AS (
  SELECT t.name AS test, t.aspect, json_extract_string(a.schema, '$.x-subject') AS on_,
         json_extract_string(a.schema, '$.x-subject') = 'metric' AS metrics_only,
         json_extract_string(a.schema, '$.x-set-by') AS set_by,
         coalesce(a.grains = ['COLUMN'], false) AS on_columns
  FROM (SELECT * FROM main.tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1) t
  JOIN main.aspects a ON a.name = t.aspect
  WHERE json_extract_string(a.schema, '$.x-subject') IN ('view', 'metric', 'table')),
-- the views and the loaded tables that carry an annotation of a property on themselves or on a column
set_on AS (
  SELECT DISTINCT g.aspect, split_part(g.subject, '.', 2) AS view FROM main.glossary g
  WHERE g.dataset = current_schema() AND g.actor_kind IN ('agent', 'human')
    AND g.aspect IN (SELECT set_by FROM expected WHERE set_by IS NOT NULL)),
-- a test's evidence is the stored result of its property: no other result is read
evidence AS (
  SELECT subject, aspect, main.with_definition(value::JSON, current_schema()) AS value FROM main.measurements
  WHERE dataset = current_schema() AND aspect IN (SELECT aspect FROM main.tests)
  QUALIFY row_number() OVER (PARTITION BY subject, aspect ORDER BY begin_snapshot DESC) = 1),
view_columns AS MATERIALIZED (
  SELECT table_name AS view, column_name FROM glossql_columns(current_schema()) WHERE table_type = 'VIEW'),
-- what a test a view expects is on: the view, or each of its columns where the property is declared on
-- columns alone; the check over the view computes them all
view_subjects AS (
  SELECT m.view, m.metric, current_schema() || '.' || m.view AS subject, false AS on_columns FROM all_views m
  UNION ALL
  SELECT m.view, m.metric, current_schema() || '.' || c.view || '.' || c.column_name, true
  FROM all_views m JOIN view_columns c ON c.view = m.view),
own AS (
  SELECT m.view, e.test, e.aspect, m.subject,
         coalesce(r.state, 'not_run') AS state, coalesce(r.current, false) AS current,
         r.score, v.value::JSON AS evidence,
         'SELECT ' || e.aspect || '() FROM ' || current_schema() || '.' || m.view AS run
  FROM view_subjects m JOIN expected e ON e.on_ <> 'table' AND e.on_columns = m.on_columns AND (m.metric OR NOT e.metrics_only)
   AND (e.set_by IS NULL OR EXISTS (SELECT 1 FROM set_on o WHERE o.aspect = e.set_by AND o.view = m.view))
  LEFT JOIN results r ON r.subject = m.subject AND r.test = e.test
  LEFT JOIN evidence v ON v.subject = m.subject AND v.aspect = e.aspect
  UNION ALL
  -- a kit's check on each loaded table (x-subject table), whatever view reads it: no view
  SELECT '', e.test, e.aspect, current_schema() || '.' || l.table_name,
         coalesce(r.state, 'not_run'), coalesce(r.current, false), r.score, v.value::JSON,
         'SELECT ' || e.aspect || '() FROM ' || current_schema() || '.' || l.table_name
  FROM (SELECT DISTINCT table_name FROM glossql_columns(current_schema()) WHERE table_type = 'BASE TABLE') l
  JOIN expected e ON e.on_ = 'table'
   AND (e.set_by IS NULL OR EXISTS (SELECT 1 FROM set_on o WHERE o.aspect = e.set_by AND o.view = l.table_name))
  LEFT JOIN results r ON r.subject = current_schema() || '.' || l.table_name AND r.test = e.test
  LEFT JOIN evidence v ON v.subject = current_schema() || '.' || l.table_name AND v.aspect = e.aspect),
reads AS (
  SELECT m.view, current_schema() || '.' || r.table_name || '.' || r.column_name AS subject
  FROM all_views m, main.view_reads_of(current_schema(), m.view) r
  UNION
  SELECT m.view, current_schema() || '.' || s.table_name
  FROM all_views m, main.view_scans_of(current_schema(), m.view) s),
-- the function that returns a test's property is the check that
-- measures it: the test's `run`
checks AS (
  SELECT returns AS aspect, min(name) AS name
  FROM (SELECT name, returns FROM main.functions QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1)
  WHERE returns IS NOT NULL GROUP BY returns),
inputs AS (
  SELECT DISTINCT d.view, r.test, r.aspect, r.subject,
         r.state AS state, r.current, r.score, v.value::JSON AS evidence,
         coalesce('SELECT ' || f.name || '() FROM ' || r.subject, '') AS run
  FROM reads d JOIN results r ON r.subject = d.subject
  LEFT JOIN evidence v ON v.subject = r.subject AND v.aspect = r.aspect
  LEFT JOIN checks f ON f.aspect = r.aspect
  WHERE r.test NOT IN (SELECT test FROM expected)),
-- the view itself and its columns, for the tests the team declared
-- on them
itself AS (
  SELECT m.view, current_schema() || '.' || m.view AS subject FROM all_views m
  UNION
  SELECT m.view, current_schema() || '.' || c.view || '.' || c.column_name
  FROM all_views m JOIN view_columns c ON c.view = m.view),
declared AS (
  SELECT DISTINCT d.view, r.test, r.aspect, r.subject,
         r.state AS state, r.current, r.score, v.value::JSON AS evidence,
         coalesce('SELECT ' || f.name || '() FROM ' || r.subject, '') AS run
  FROM itself d JOIN results r ON r.subject = d.subject
  JOIN authors w ON w.test = r.test AND w.declared_by NOT LIKE 'kit:%'
  LEFT JOIN evidence v ON v.subject = r.subject AND v.aspect = r.aspect
  LEFT JOIN checks f ON f.aspect = r.aspect
  WHERE r.test NOT IN (SELECT test FROM expected)),
-- a test on a result an actor stored about the dataset as a whole,
-- about a view with no tests of its own, or about a view by a kit's
-- test no view expects (a metric's expected ranges): a kit's measurement
-- and its test come in here, by their results alone
stored AS (
  SELECT coalesce(o.view, k.view, '') AS view, r.test, r.aspect, r.subject, r.state, r.current, r.score, v.value::JSON AS evidence, '' AS run
  FROM results r
  LEFT JOIN (SELECT view FROM summary WHERE stopped IS NULL AND view NOT IN (SELECT view FROM all_views)) o
    ON r.subject = current_schema() || '.' || o.view
  LEFT JOIN (SELECT view FROM all_views) k
    ON r.subject = current_schema() || '.' || k.view AND r.test NOT IN (SELECT test FROM expected)
   AND r.test IN (SELECT test FROM authors WHERE declared_by LIKE 'kit:%')
  LEFT JOIN evidence v ON v.subject = r.subject AND v.aspect = r.aspect
  WHERE r.subject = current_schema() OR o.view IS NOT NULL OR k.view IS NOT NULL)
SELECT t.view, t.test, t.aspect, a.declared_by, t.subject, t.state, t.current, t.score, t.evidence, t.run
FROM (SELECT * FROM own UNION ALL SELECT * FROM inputs UNION ALL SELECT * FROM declared UNION ALL SELECT * FROM stored) t
LEFT JOIN authors a USING (test)
ORDER BY CASE state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'not_run' THEN 3 ELSE 4 END,
         current, view, test, subject;

--===------------------------------------------------------------------===--
-- semantic_model(): the bound dataset as one Apache Ossie document
-- (the open format for exchanging a semantic model; spec 0.3.0.dev0),
-- one row, column `document` (JSON). Each loaded table and each served
-- metric is an Ossie dataset with its fields; a column annotated as the
-- time or a dimension carries `dimension`; a table's key is the `grain`
-- of its entity; a metric's description is the `meaning` annotated on
-- the view; a metric's value is an Ossie metric whose
-- expression follows its additivity (a sum for additive, the ratio of
-- the summed halves for a ratio; a semi-additive or non-additive value
-- is exported as a sum with the additivity in `custom_extensions`, since
-- Ossie has no word for it); declared relationships are its
-- relationships. Meanings ride as descriptions.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.semantic_model() AS TABLE
WITH ds AS (SELECT current_schema() AS dataset),
known AS (SELECT subject, aspect, value FROM glossql_glossary(current_schema(), NULL, false) WHERE value IS NOT NULL),
metrics AS (
  SELECT view AS metric, value_column, period_column, additivity, numerator, denominator
  FROM main.view_summary() WHERE stopped IS NULL AND applicable AND coalesce(kind, '') NOT IN ('scalar', 'relation')),
cols AS (
  SELECT c.table_name, c.column_name, c.column_type, c.ordinal_position
  FROM glossql_columns(current_schema(), true) c
  WHERE c.table_type = 'BASE TABLE' OR c.table_name IN (SELECT metric FROM metrics)),
fields AS (
  SELECT c.table_name, c.ordinal_position,
         json_merge_patch('{}', to_json({
           'name': c.column_name,
           'expression': {'sql': '"' || c.column_name || '"'},
           'dimension': CASE WHEN r.value->>'value' = 'timestamp' THEN {'is_time': true}
                             WHEN r.value->>'value' = 'dimension' THEN {'is_time': false} END,
           'datatype': CASE WHEN c.column_type LIKE 'TIMESTAMP WITH TIME ZONE%' THEN 'DateTimeTz'
                            WHEN c.column_type LIKE 'TIMESTAMP%' THEN 'DateTime'
                            WHEN c.column_type = 'DATE' THEN 'Date' WHEN c.column_type LIKE 'TIME%' THEN 'Time'
                            WHEN c.column_type LIKE 'DECIMAL%' THEN 'Decimal'
                            WHEN c.column_type IN ('DOUBLE', 'FLOAT', 'REAL') THEN 'Float'
                            WHEN c.column_type LIKE '%INT%' THEN 'Integer'
                            WHEN c.column_type = 'BOOLEAN' THEN 'Boolean'
                            WHEN c.column_type = 'VARCHAR' THEN 'String' ELSE 'Opaque' END,
           'description': m.value->>'value',
           'custom_extensions': CASE WHEN u.value IS NOT NULL THEN
             [{'vendor_name': 'glossdb', 'data': to_json({'unit': u.value->>'value'})::VARCHAR}] END
         })) AS field
  FROM cols c CROSS JOIN ds
  LEFT JOIN known r ON r.subject = ds.dataset || '.' || c.table_name || '.' || c.column_name AND r.aspect = 'role'
  LEFT JOIN known m ON m.subject = ds.dataset || '.' || c.table_name || '.' || c.column_name AND m.aspect = 'meaning'
  LEFT JOIN known u ON u.subject = ds.dataset || '.' || c.table_name || '.' || c.column_name AND u.aspect = 'unit'),
measures AS (
  SELECT x.metric,
         json_merge_patch('{}', to_json({
           'name': x.metric,
           'expression': {'sql': CASE WHEN x.additivity = 'ratio' AND x.numerator IS NOT NULL AND x.denominator IS NOT NULL
                                      THEN 'SUM("' || x.numerator || '") / SUM("' || x.denominator || '")'
                                      ELSE 'SUM("' || x.value_column || '")' END},
           'description': coalesce(vm.value->>'value', json_extract_string(a.schema, '$.title')),
           'custom_extensions': CASE WHEN x.additivity IN ('semi-additive', 'non-additive') THEN
             [{'vendor_name': 'glossdb', 'data': to_json({'additivity': x.additivity, 'time_column': x.period_column})::VARCHAR}] END
         })) AS measure
  FROM metrics x CROSS JOIN ds
  LEFT JOIN known vm ON vm.subject = ds.dataset || '.' || x.metric AND vm.aspect = 'meaning'
  LEFT JOIN main.aspects a ON a.name = x.metric),
datasets AS (
  SELECT t.table_name,
         json_merge_patch('{}', to_json({
           'name': t.table_name,
           'source': ds.dataset || '.' || t.table_name,
           'primary_key': from_json(json_extract(e.value, '$.grain'), '["VARCHAR"]'),
           'description': coalesce(tm.value->>'value', e.value->>'value'),
           'fields': (SELECT list(f.field ORDER BY f.ordinal_position) FROM fields f WHERE f.table_name = t.table_name),
           'metrics': (SELECT list(m.measure) FROM measures m WHERE m.metric = t.table_name)
         })) AS dataset
  FROM (SELECT DISTINCT table_name FROM cols) t CROSS JOIN ds
  LEFT JOIN known e ON e.subject = ds.dataset || '.' || t.table_name AND e.aspect = 'entity'
  LEFT JOIN known tm ON tm.subject = ds.dataset || '.' || t.table_name AND tm.aspect = 'meaning'),
edges AS (
  SELECT to_json({
           'name': split_part(r.left_side, '.', 2) || '_to_' || split_part(r.right_side, '.', 2) || '_' || r.begin_snapshot,
           'from': split_part(r.left_side, '.', 2), 'to': split_part(r.right_side, '.', 2),
           'from_columns': string_split(regexp_replace(regexp_replace(r.left_side, '^[^.]*\.[^.]*\.', ''), '[() ]', '', 'g'), ','),
           'to_columns': string_split(regexp_replace(regexp_replace(r.right_side, '^[^.]*\.[^.]*\.', ''), '[() ]', '', 'g'), ',')
         }) AS edge
  FROM main.relationships r, ds WHERE r.dataset = ds.dataset)
SELECT json_merge_patch('{}', to_json({
         'version': '0.3.0.dev0',
         'name': ds.dataset,
         'description': (SELECT json_extract_string(settings, '$.purpose') FROM main.datasets WHERE name = ds.dataset),
         'datasets': (SELECT list(dataset ORDER BY table_name) FROM datasets),
         'relationships': (SELECT list(edge) FROM edges)
       })) AS document
FROM ds;

-- A stable UUID from a name: an OpenLineage run id is a UUID, and the same
-- load or view names the same run every time it is read.
CREATE OR REPLACE MACRO main.uuid_of(name) AS
  (substr(md5(name), 1, 8) || '-' || substr(md5(name), 9, 4) || '-4' || substr(md5(name), 14, 3) || '-8' || substr(md5(name), 18, 3) || '-' || substr(md5(name), 21, 12));

--===------------------------------------------------------------------===--
-- lineage_events(): the bound dataset's lineage as OpenLineage run
-- events (spec 2-0-2), one row per event, column `event` (JSON): one
-- COMPLETE event per load, its input the source and its output the
-- loaded table with the column lineage the load recorded; one per view
-- (a metric or a derived relation), its inputs the tables it scans and
-- its output the view with each column's source columns, timed at the
-- dataset's newest load. A catalog that reads OpenLineage takes the rows
-- as they are.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.lineage_events() AS TABLE
WITH ds AS (SELECT current_schema() AS dataset),
loads AS (
  SELECT i.dataset, i.table_name, i.imported_at, i.snapshot_id, i.rows, i.lineage::JSON AS lineage,
         (SELECT r.source FROM main.recipes r WHERE r.dataset = i.dataset AND r.table_name = i.table_name) AS source
  FROM main.imports_history i, ds WHERE i.dataset = ds.dataset),
load_fields AS (
  SELECT l.table_name, l.snapshot_id, k.key AS field,
         (SELECT list(DISTINCT {'namespace': 'glossdb', 'name': coalesce(l.source, split_part(leaf, '.', 1)), 'field': split_part(leaf, '.', 2)})
          FROM unnest(regexp_extract_all(json_extract_string(l.lineage, '$."' || k.key || '"'), '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1)) u(leaf)) AS inputs
  FROM loads l, (SELECT unnest(json_keys(l2.lineage)) AS key, l2.table_name, l2.snapshot_id FROM loads l2) k
  WHERE k.table_name = l.table_name AND k.snapshot_id = l.snapshot_id),
load_events AS (
  SELECT l.imported_at AS happened,
         to_json({
           'eventType': 'COMPLETE',
           'eventTime': strftime(l.imported_at, '%Y-%m-%dT%H:%M:%S.%fZ'),
           'producer': 'https://github.com/glossdb/glossdb',
           'schemaURL': 'https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent',
           'run': {'runId': uuid_of(l.dataset || '.' || l.table_name || '@' || l.snapshot_id)},
           'job': {'namespace': 'glossdb', 'name': 'load.' || l.dataset || '.' || l.table_name},
           'inputs': [{'namespace': 'glossdb', 'name': coalesce(l.source, 'source')}],
           'outputs': [{'namespace': 'glossdb', 'name': l.dataset || '.' || l.table_name,
                        'facets': {'columnLineage': {
                          '_producer': 'https://github.com/glossdb/glossdb',
                          '_schemaURL': 'https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json',
                          'fields': (SELECT json_group_object(f.field, {'inputFields': coalesce(f.inputs, [])})
                                     FROM load_fields f WHERE f.table_name = l.table_name AND f.snapshot_id = l.snapshot_id)}}}]
         }) AS event
  FROM loads l),
view_cols AS (
  SELECT v.view, v."column" AS field,
         (SELECT list(DISTINCT {'namespace': 'glossdb', 'name': split_part(leaf, '.', 1) || '.' || split_part(leaf, '.', 2), 'field': split_part(leaf, '.', 3)})
          FROM unnest(regexp_extract_all(v.derivation, '([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*):', 1)) u(leaf)) AS inputs
  FROM main.views_lineage(current_schema()) v WHERE v."column" IS NOT NULL),
view_scans AS (
  SELECT view, list(DISTINCT {'namespace': 'glossdb', 'name': table_name}) AS inputs
  FROM main.views_scans(current_schema()) GROUP BY view),
view_events AS (
  SELECT NULL::TIMESTAMP AS happened,
         to_json({
           'eventType': 'COMPLETE',
           'eventTime': strftime(coalesce((SELECT max(imported_at) FROM loads), TIMESTAMP '1970-01-01'), '%Y-%m-%dT%H:%M:%S.%fZ'),
           'producer': 'https://github.com/glossdb/glossdb',
           'schemaURL': 'https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent',
           'run': {'runId': uuid_of(ds.dataset || '.' || c.view)},
           'job': {'namespace': 'glossdb', 'name': 'view.' || ds.dataset || '.' || c.view},
           'inputs': coalesce(s.inputs, []),
           'outputs': [{'namespace': 'glossdb', 'name': ds.dataset || '.' || c.view,
                        'facets': {'columnLineage': {
                          '_producer': 'https://github.com/glossdb/glossdb',
                          '_schemaURL': 'https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json',
                          'fields': json_group_object(c.field, {'inputFields': coalesce(c.inputs, [])})}}}]
         }) AS event
  FROM view_cols c LEFT JOIN view_scans s ON s.view = c.view, ds
  GROUP BY ds.dataset, c.view, s.inputs)
SELECT event FROM (SELECT * FROM load_events UNION ALL SELECT * FROM view_events) ORDER BY happened NULLS LAST;
