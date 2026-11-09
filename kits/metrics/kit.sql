-- The metrics kit: a metric is a view, its columns carry the vocabulary,
-- and the reads are SQL over the collapsed annotations and the view. Loaded after
-- the KPI kit, whose words the columns carry (role, additivity, dimension),
-- and the quality kit, whose temporal profile measures a time column's
-- cadence. What an actor must learn about these words is SKILL.md beside
-- this file.
--
--   FROM glossql_kit('kits/kpi/kit.sql');
--   FROM glossql_kit('kits/quality/kit.sql');
--   FROM glossql_kit('kits/metrics/kit.sql');
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
-- the series is served at, by default the measured cadence; windows is the
-- rung per grain, how many whole buckets a read serves, measured back from
-- the data's edge, by default the kit's. Required where the role is timestamp.
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
    "grounds": {"type": "string"}
  }
}$$ AS FACT ON COLUMN WHEN role = 'timestamp';

DECLARE TEST time_grains_test ON time_grains BY (AGENT, HUMAN);

-- The grains in order, a bucket's step, and the kit's rung per grain.
CREATE OR REPLACE MACRO main.grain_rank(g) AS
  CASE g WHEN 'minute' THEN 1 WHEN 'hour' THEN 2 WHEN 'day' THEN 3 WHEN 'week' THEN 4
         WHEN 'month' THEN 5 WHEN 'quarter' THEN 6 WHEN 'year' THEN 7 END;
CREATE OR REPLACE MACRO main.grain_step(g) AS
  CASE g WHEN 'minute' THEN INTERVAL 1 MINUTE WHEN 'hour' THEN INTERVAL 1 HOUR WHEN 'day' THEN INTERVAL 1 DAY
         WHEN 'week' THEN INTERVAL 7 DAY WHEN 'month' THEN INTERVAL 1 MONTH WHEN 'quarter' THEN INTERVAL 3 MONTH
         WHEN 'year' THEN INTERVAL 1 YEAR END;
CREATE OR REPLACE MACRO main.rung_default(g) AS
  CASE g WHEN 'minute' THEN 1440 WHEN 'hour' THEN 720 WHEN 'day' THEN 548 WHEN 'week' THEN 156
         WHEN 'month' THEN 48 WHEN 'quarter' THEN 40 WHEN 'year' THEN 20 END;

--===------------------------------------------------------------------===--
-- metric_summary(): one row per metric of the bound dataset — a VIEW aspect
-- whose metric definition is a view — what the catalog says its columns are
-- and whether a series can be served: metric, kind (the aspect's x-kind),
-- plan_of and covers (a plan's metric and the grain its rows are booked
-- against), stopped (the author's text), applicable, reason (the road out
-- when it is not), period_column, value_column, numerator and denominator
-- (a ratio's halves), cadence (the period column's measured granularity),
-- floor (the time grains', else the cadence), rung (how many buckets the floor serves), additivity
-- and additivity_state (the collapsed claim on the value column, NULL and
-- 'none' where nobody annotated it, 'conflict' where the test withholds it),
-- dims (the slicing columns, primary first), unranked (the dimension
-- columns no dimension gloss ranks), unadmitted (the served columns with
-- no role), required (the gloss each of those wants),
-- wanted (the measurement the row reads and nobody ran), judged_current
-- (the profile is current at the data's own version). A plan (x-kind plan) is
-- read through the metric it names: its period and value are the columns
-- named as that metric's, or period and value, its additivity the metric's,
-- its floor the grain its rows are booked against where the declaration
-- says so (x-covers); nothing is glossed on a plan's own columns. A served
-- plan's row wants the judgement the outlook kit measures on the plan
-- (metric_plan over the plan) until one exists, as a metric's row wants
-- the profile over its period column.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.metric_summary() AS TABLE
WITH ds AS (SELECT current_schema() AS dataset),
aspects AS (
  SELECT name, schema FROM (
    SELECT name, kind, schema, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
    FROM main.aspects) WHERE rn = 1 AND kind = 'VIEW'),
views AS (
  SELECT DISTINCT c.table_name AS metric FROM glossql_columns(current_schema()) c
  WHERE c.table_type = 'VIEW' AND c.table_name IN (SELECT name FROM aspects)),
bodies AS (
  SELECT aspect AS metric, body FROM (
    SELECT g.aspect, g.body, row_number() OVER (PARTITION BY g.aspect ORDER BY g.seq DESC) AS rn
    FROM main.glossary g, ds
    WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.aspect IN (SELECT name FROM aspects)) WHERE rn = 1),
cols AS (
  SELECT c.table_name AS metric, c.column_name AS col, c.ordinal_position AS pos
  FROM glossql_columns(current_schema()) c
  WHERE c.table_name IN (SELECT metric FROM views)),
slots AS MATERIALIZED (
  SELECT split_part(subject, '.', 2) AS metric, substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) AS col, aspect, value, state
  FROM glossql_glossary(current_schema(), NULL, false)
  WHERE aspect IN ('role', 'additivity', 'dimension', 'time_grains', 'temporal_profile')
    AND len(string_split(subject, '.')) >= 3
    AND split_part(subject, '.', 2) IN (SELECT metric FROM bodies)),
claims AS (SELECT * FROM slots WHERE state IN ('current', 'stale') AND value IS NOT NULL),
roles AS (SELECT metric, col, value->>'value' AS role FROM claims WHERE aspect = 'role'),
periods AS (
  SELECT r.metric, list(r.col ORDER BY CASE WHEN r.col = 'period' THEN 0 ELSE 1 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (metric, col) WHERE r.role = 'timestamp' GROUP BY r.metric),
measures AS (
  SELECT r.metric, list(r.col ORDER BY CASE WHEN r.col = 'value' THEN 0 ELSE 1 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (metric, col) WHERE r.role = 'measure' GROUP BY r.metric),
chosen AS (
  SELECT b.metric,
         CASE WHEN len(p.cols) = 1 OR p.cols[1] = 'period' THEN p.cols[1] END AS period_column,
         CASE WHEN len(m.cols) = 1 OR m.cols[1] = 'value' THEN m.cols[1] END AS value_column,
         p.cols AS period_cols, m.cols AS measure_cols,
         b.metric IN (SELECT metric FROM views) AS served
  FROM bodies b LEFT JOIN periods p USING (metric) LEFT JOIN measures m USING (metric)),
additivitys AS (
  SELECT s.metric, s.col,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'value' END AS additivity,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'numerator' END AS numerator,
         CASE WHEN s.state IN ('current', 'stale') THEN s.value->>'denominator' END AS denominator,
         CASE WHEN s.state IN ('current', 'stale') THEN s.state ELSE 'conflict' END AS additivity_state
  FROM slots s WHERE s.aspect = 'additivity' AND s.state <> 'missing'),
profiles AS (
  SELECT metric, col,
         CASE WHEN (value->>'applicable') = 'true' AND (value->>'granularity') IN ('minute', 'hour', 'day', 'week', 'month', 'quarter', 'year')
              THEN value->>'granularity' END AS cadence,
         state = 'current' AS judged_current
  FROM claims WHERE aspect = 'temporal_profile'),
ladders AS (SELECT metric, col, value->>'floor' AS floor, value->'windows' AS windows FROM claims WHERE aspect = 'time_grains'),
dims AS (
  SELECT r.metric, list(r.col ORDER BY CASE d.rank WHEN 'primary' THEN 0 WHEN 'supporting' THEN 1 ELSE 2 END, c.pos) AS cols
  FROM roles r JOIN cols c USING (metric, col)
  LEFT JOIN (SELECT metric, col, value->>'value' AS rank FROM claims WHERE aspect = 'dimension') d USING (metric, col)
  WHERE r.role = 'dimension' AND coalesce(d.rank, '') <> 'none'
  GROUP BY r.metric),
unranked AS (
  SELECT r.metric, list(r.col ORDER BY c.pos) AS cols
  FROM roles r JOIN cols c USING (metric, col)
  WHERE r.role = 'dimension'
    AND NOT EXISTS (SELECT 1 FROM claims d WHERE d.aspect = 'dimension' AND d.metric = r.metric AND d.col = r.col)
  GROUP BY r.metric),
unadmitted AS (
  SELECT c.metric, list(c.col ORDER BY c.pos) AS cols,
         list('GLOSS role ON ' || ds.dataset || '.' || c.metric || '.' || c.col || ' AS $${"value": "<key|measure|dimension|timestamp|attribute>"}$$;' ORDER BY c.pos) AS acts
  FROM cols c, ds
  WHERE NOT EXISTS (SELECT 1 FROM roles r WHERE r.metric = c.metric AND r.col = c.col)
  GROUP BY c.metric),
rows_ AS (
  SELECT ch.metric,
         json_extract_string(a.schema, '$.x-kind') AS kind,
         json_extract_string(a.schema, '$.x-plan-of') AS plan_of,
         json_extract_string(a.schema, '$.x-covers') AS covers,
         json_extract_string(b.body, '$.stopped') AS stopped,
         ch.period_column, ch.value_column, ch.period_cols, ch.measure_cols, ch.served,
         bh.additivity, bh.numerator, bh.denominator, coalesce(bh.additivity_state, 'none') AS additivity_state,
         pr.cadence, coalesce(pr.judged_current, false) AS judged_current,
         coalesce(la.floor, pr.cadence) AS floor, la.windows,
         coalesce(d.cols, []::VARCHAR[]) AS dims, coalesce(ur.cols, []::VARCHAR[]) AS unranked,
         coalesce(u.cols, []::VARCHAR[]) AS unadmitted, coalesce(u.acts, []::VARCHAR[]) AS missing,
         pr.metric IS NOT NULL AS profiled
  FROM chosen ch
  JOIN aspects a ON a.name = ch.metric
  LEFT JOIN bodies b USING (metric)
  LEFT JOIN additivitys bh ON bh.metric = ch.metric AND bh.col = ch.value_column
  LEFT JOIN profiles pr ON pr.metric = ch.metric AND pr.col = ch.period_column
  LEFT JOIN ladders la ON la.metric = ch.metric AND la.col = ch.period_column
  LEFT JOIN dims d ON d.metric = ch.metric
  LEFT JOIN unranked ur ON ur.metric = ch.metric
  LEFT JOIN unadmitted u ON u.metric = ch.metric),
judged AS (
  SELECT *,
    CASE WHEN stopped IS NOT NULL THEN 'stopped: ' || stopped
         WHEN NOT served THEN 'the metric definition serves no view'
         WHEN kind = 'scalar' THEN 'a fact serves one number, read through fact_values()'
         WHEN kind = 'relation' THEN 'a relation serves rows, not a series'
         WHEN period_column IS NULL AND len(period_cols) > 1 THEN
              list_aggregate(period_cols, 'string_agg', ' and ') || ' carry role timestamp; the period is the column named period — serve it so, or gloss role attribute on the others'
         WHEN period_column IS NULL THEN
              'no column carries role timestamp: annotate the period column, GLOSS role ON ' || ds.dataset || '.' || metric || '.<column> AS $${"value": "timestamp"}$$'
         WHEN value_column IS NULL AND len(measure_cols) > 1 THEN
              list_aggregate(measure_cols, 'string_agg', ' and ') || ' carry role measure; the value is the column named value — serve it so, or gloss role attribute on the others'
         WHEN value_column IS NULL THEN
              'no column carries role measure: annotate the value column, GLOSS role ON ' || ds.dataset || '.' || metric || '.<column> AS $${"value": "measure"}$$'
         WHEN floor IS NULL AND NOT profiled THEN
              'no cadence is known on ' || period_column || ': SELECT temporal() FROM ' || ds.dataset || '.' || metric || '.' || period_column || ', or gloss time_grains with a floor'
         WHEN floor IS NULL THEN
              'the profile finds no cadence on ' || period_column || ': gloss time_grains with a floor, GLOSS time_grains ON ' || ds.dataset || '.' || metric || '.' || period_column || ' AS $${"floor": "<grain>"}$$'
    END AS reason,
    CASE WHEN period_column IS NOT NULL AND NOT profiled AND stopped IS NULL AND coalesce(kind, '') NOT IN ('scalar', 'relation')
         THEN ['temporal over ' || ds.dataset || '.' || metric || '.' || period_column] ELSE []::VARCHAR[] END AS wanted
  FROM rows_, ds WHERE coalesce(kind, '') <> 'plan'),
-- a plan's row: its columns through the metric it plans
plan_cols AS (SELECT metric, list(col ORDER BY pos) AS cols FROM cols GROUP BY metric),
plans AS (
  SELECT p.metric, p.kind, p.plan_of, p.covers, p.stopped, p.served,
         CASE WHEN list_contains(pc.cols, m.period_column) THEN m.period_column WHEN list_contains(pc.cols, 'period') THEN 'period' END AS period_column,
         CASE WHEN list_contains(pc.cols, m.value_column) THEN m.value_column WHEN list_contains(pc.cols, 'value') THEN 'value' END AS value_column,
         m.metric IS NOT NULL AS of_declared, m.reason IS NULL AS of_applicable, m.reason AS of_reason,
         m.period_column AS of_period, m.value_column AS of_value,
         m.numerator, m.denominator, m.additivity, m.additivity_state
  FROM rows_ p
  LEFT JOIN plan_cols pc ON pc.metric = p.metric
  LEFT JOIN judged m ON m.metric = p.plan_of
  WHERE p.kind = 'plan'),
judged_plans AS (
  SELECT *,
    CASE WHEN stopped IS NOT NULL THEN 'stopped: ' || stopped
         WHEN plan_of IS NULL THEN 'a plan names the metric it plans: declare it with x-plan-of'
         WHEN NOT of_declared THEN 'x-plan-of names ' || plan_of || ', which no VIEW aspect declares on this dataset'
         WHEN NOT served THEN 'the metric definition serves no view'
         WHEN covers IS NOT NULL AND covers NOT IN ('quarter', 'year') THEN 'x-covers names the grain a row is booked against, year or quarter — ' || covers || ' is neither'
         WHEN NOT of_applicable THEN 'the metric it plans is not served: ' || of_reason
         WHEN period_column IS NULL THEN 'the plan serves no column named ' || coalesce(of_period, 'period') || ' (its metric''s period) nor period'
         WHEN value_column IS NULL THEN 'the plan serves no column named ' || coalesce(of_value, 'value') || ' (its metric''s value) nor value'
    END AS reason
  FROM plans)
SELECT metric, kind, plan_of, covers, stopped, reason IS NULL AS applicable, reason,
       period_column, value_column, numerator, denominator, cadence, floor,
       CASE WHEN floor IS NOT NULL THEN coalesce(json_extract(windows, '$.' || floor)::INTEGER, main.rung_default(floor)) END AS rung,
       additivity, additivity_state, dims, unranked, unadmitted, missing, wanted, judged_current
FROM judged
UNION ALL
SELECT metric, kind, plan_of, covers, stopped, reason IS NULL AS applicable, reason,
       period_column, value_column, numerator, denominator, NULL AS cadence, covers AS floor, NULL AS rung,
       additivity, additivity_state, []::VARCHAR[], []::VARCHAR[], []::VARCHAR[], []::VARCHAR[],
       CASE WHEN reason IS NULL AND NOT EXISTS (SELECT 1 FROM main.measurements m
                                                WHERE m.dataset = current_schema() AND m.function = 'metric_plan'
                                                  AND m.subject = current_schema() || '.' || judged_plans.metric)
            THEN ['metric_plan over ' || current_schema() || '.' || metric] ELSE []::VARCHAR[] END,
       true
FROM judged_plans
ORDER BY metric;

--===------------------------------------------------------------------===--
-- metric_series(grain := NULL, world := 'actual', plan := NULL): the cells
-- of every applicable metric of the bound dataset — metric, world,
-- dimension ('' the total, else a slicing column), member, period (the
-- bucket's start), value, num and den (a ratio's summed halves), additivity.
-- Without a grain, each metric at its own floor; with one, each metric at
-- or below it at that grain, a metric coarser than the asked grain serving
-- no rows. A rung of n buckets is served, the edge's bucket the last. A
-- flow sums and fills its total's empty periods with zero up to the data's
-- edge (the last instant any served metric reaches, so a flow whose rows
-- stopped early shows its zeros, not an older window);
-- a stock keeps the bucket's last level, summed over what holds at that
-- instant; a ratio re-divides its summed halves. A dimension wider than 24
-- members serves its top 23 by weight and 'other'. The actual world is
-- this kit's; a plan (world := 'plan', plan := '<name>'), the forecast
-- (world := 'forecast') and a scenario (world := 'scenario', scenario :=
-- '<name>') are the outlook kit's, served under the metric through
-- world_cells(), which is empty until that kit is loaded.
--
-- The no-claim rule: where rows have to be combined — a coarser grain than
-- the floor, or several rows in one period — and no additivity is annotated on
-- the value column, the read refuses and names the gloss. It defaults
-- nothing. A list over every metric asks unclaimed := 'skip' instead:
-- such a metric serves no cell, and its fact row says what it needs.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.world_cells(w, p, s, g) AS TABLE
SELECT NULL::VARCHAR AS metric, NULL::VARCHAR AS world, NULL::VARCHAR AS dimension, NULL::VARCHAR AS member,
       NULL::TIMESTAMP AS period, NULL::DOUBLE AS value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, NULL::VARCHAR AS additivity
WHERE false;

CREATE OR REPLACE MACRO main.metric_series(grain := NULL, unclaimed := 'refuse', world := 'actual', plan := NULL, scenario := NULL) AS TABLE
WITH asked AS MATERIALIZED (
  SELECT m.*, coalesce(grain, m.floor) AS at_grain
  FROM main.metric_summary() m
  WHERE m.applicable AND coalesce(m.kind, '') <> 'plan' AND world = 'actual'
    AND (grain IS NULL OR main.grain_rank(grain) >= main.grain_rank(m.floor))),
cells AS (
  SELECT * FROM dataset_cells(current_schema(), 'views') WHERE "table" IN (SELECT metric FROM asked)),
all_rows AS MATERIALIZED (
  SELECT c."table" AS metric, c.rn,
         max(CASE WHEN c."column" = a.period_column THEN TRY_CAST(c.val AS TIMESTAMP) END) AS instant,
         max(CASE WHEN c."column" = a.value_column THEN TRY_CAST(c.val AS DOUBLE) END) AS value,
         max(CASE WHEN c."column" = a.numerator THEN TRY_CAST(c.val AS DOUBLE) END) AS num,
         max(CASE WHEN c."column" = a.denominator THEN TRY_CAST(c.val AS DOUBLE) END) AS den,
         list({'dimension': c."column", 'member': coalesce(c.val, 'NULL')}) FILTER (WHERE list_contains(a.dims, c."column")) AS members
  FROM cells c JOIN asked a ON a.metric = c."table"
  GROUP BY c."table", c.rn),
-- a value column with no additivity, a conflicting one, or one said not to
-- combine (none) cannot be combined over rows
combining AS (
  SELECT a.metric, a.value_column, a.additivity, a.additivity_state,
         main.grain_rank(a.at_grain) > main.grain_rank(a.floor) AS coarser,
         count(*) > count(DISTINCT r.instant) AS shared
  FROM asked a JOIN all_rows r USING (metric)
  WHERE a.additivity IS NULL OR a.additivity = 'non-additive'
  GROUP BY a.metric, a.value_column, a.additivity, a.additivity_state, a.at_grain, a.floor),
refused AS (
  SELECT CASE WHEN count(*) > 0 AND unclaimed = 'refuse' THEN error(string_agg(
           CASE WHEN additivity_state = 'conflict' THEN 'the additivity on ' || current_schema() || '.' || metric || '.' || value_column || ' is in conflict'
                WHEN additivity = 'non-additive' THEN 'the additivity on ' || current_schema() || '.' || metric || '.' || value_column || ' is non-additive, so its rows do not combine'
                ELSE 'no additivity is annotated on ' || current_schema() || '.' || metric || '.' || value_column END
           || CASE WHEN coarser THEN ', and ' || metric || ' is asked at a coarser grain than its floor' ELSE ', and ' || metric || ' serves several rows in one period' END
           || ': annotate it — GLOSS additivity ON ' || current_schema() || '.' || metric || '.' || value_column || ' AS $${"value": "<additive|semi-additive|ratio>"}$$', '; ')) END AS refusal
  FROM combining WHERE coarser OR shared),
-- the metrics served: every asked one but those that need a claim nobody made; the refusal gates the
-- cells served, below, where the rows are few
rows_ AS (
  SELECT r.* FROM all_rows r
  WHERE r.metric NOT IN (SELECT metric FROM combining WHERE coarser OR shared)),
bucketed AS (
  SELECT r.metric, r.instant, date_trunc(a.at_grain, r.instant) AS period, r.value, r.num, r.den, r.members,
         coalesce(a.additivity, 'none') AS additivity, a.at_grain, a.rung
  FROM rows_ r JOIN asked a USING (metric)
  WHERE r.instant IS NOT NULL),
-- a metric's edge is its last bucket; a flow's is the data's edge — the last instant any served metric
-- reaches, at the flow's grain — so a flow whose rows stopped early shows its zeros, not an older window
own_edges AS (
  SELECT metric, min(period) AS first, max(period) AS own_edge, max(instant) AS last_at, any_value(at_grain) AS at_grain,
         any_value(rung) AS rung, any_value(additivity) AS additivity
  FROM bucketed GROUP BY metric),
edges AS (
  SELECT metric, first, at_grain, rung, additivity,
         CASE WHEN additivity = 'additive' THEN greatest(own_edge, date_trunc(at_grain, max(last_at) OVER ())) ELSE own_edge END AS edge
  FROM own_edges),
windowed AS (
  SELECT b.* FROM bucketed b JOIN edges e USING (metric)
  WHERE b.period > e.edge - main.grain_step(e.at_grain) * e.rung),
-- a stock's level in a bucket is what holds at the bucket's last instant: that instant, per stock metric and bucket,
-- grouped rather than windowed, since a window over every row of every flow costs the read more than the rest
levels AS (
  SELECT metric, period, max(instant) AS last_at FROM windowed WHERE additivity = 'semi-additive' GROUP BY metric, period),
total AS (
  SELECT w.metric, '' AS dimension, '' AS member, w.period, w.additivity,
         CASE w.additivity WHEN 'semi-additive' THEN sum(w.value) FILTER (WHERE w.instant = l.last_at)
                         WHEN 'ratio' THEN sum(w.num) / nullif(sum(w.den), 0)
                         ELSE sum(w.value) END AS value,
         CASE w.additivity WHEN 'ratio' THEN sum(w.num) END AS num,
         CASE w.additivity WHEN 'ratio' THEN sum(w.den) END AS den
  FROM windowed w LEFT JOIN levels l USING (metric, period) GROUP BY w.metric, w.period, w.additivity),
filled AS (
  SELECT e.metric, '' AS dimension, '' AS member, g.period, e.additivity, 0.0 AS value, NULL::DOUBLE AS num, NULL::DOUBLE AS den
  FROM edges e, unnest(generate_series(greatest(e.first, e.edge - main.grain_step(e.at_grain) * (e.rung - 1)), e.edge, main.grain_step(e.at_grain))) AS g(period)
  WHERE e.additivity = 'additive'
    AND NOT EXISTS (SELECT 1 FROM total t WHERE t.metric = e.metric AND t.period = g.period)),
long AS (
  SELECT w.metric, u.m.dimension AS dimension, u.m.member AS member, w.instant, w.period, w.value, w.num, w.den, w.additivity,
         max(w.instant) OVER (PARTITION BY w.metric, u.m.dimension, u.m.member, w.period) AS member_last_at
  FROM windowed w, unnest(w.members) AS u(m)),
weights AS (
  SELECT metric, dimension, member,
         row_number() OVER (PARTITION BY metric, dimension ORDER BY sum(abs(value)) DESC NULLS LAST, member) AS rank
  FROM long GROUP BY metric, dimension, member),
member_cells AS (
  SELECT l.metric, l.dimension, CASE WHEN wt.rank <= 23 THEN l.member ELSE 'other' END AS member, l.period, l.additivity,
         CASE l.additivity WHEN 'semi-additive' THEN sum(l.value) FILTER (WHERE l.instant = l.member_last_at)
                         WHEN 'ratio' THEN sum(l.num) / nullif(sum(l.den), 0)
                         ELSE sum(l.value) END AS value,
         CASE l.additivity WHEN 'ratio' THEN sum(l.num) END AS num,
         CASE l.additivity WHEN 'ratio' THEN sum(l.den) END AS den
  FROM long l JOIN weights wt USING (metric, dimension, member)
  GROUP BY l.metric, l.dimension, CASE WHEN wt.rank <= 23 THEN l.member ELSE 'other' END, l.period, l.additivity)
SELECT metric, 'actual' AS world, dimension, member, period, value, num, den, additivity
FROM (SELECT * FROM total UNION ALL SELECT * FROM filled UNION ALL SELECT * FROM member_cells), refused
WHERE refused.refusal IS NULL
UNION ALL
SELECT metric, world, dimension, member, period, value, num, den, additivity
FROM main.world_cells(world, plan, scenario, grain) WHERE world <> 'actual'
ORDER BY metric, dimension, member, period;

--===------------------------------------------------------------------===--
-- fact_values(): the declared facts of the bound dataset, served whole —
-- one row per metric whose aspect declares x-kind scalar: metric, value where
-- the view is one row with a value column, reason where it is not.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.fact_values() AS TABLE
WITH facts AS (SELECT metric, stopped FROM main.metric_summary() WHERE kind = 'scalar'),
cells AS (SELECT * FROM dataset_cells(current_schema(), 'views') WHERE "table" IN (SELECT metric FROM facts)),
shape AS (
  SELECT "table" AS metric, count(DISTINCT rn) AS rows_, bool_or("column" = 'value') AS has_value,
         max(CASE WHEN "column" = 'value' THEN TRY_CAST(val AS DOUBLE) END) AS value
  FROM cells GROUP BY "table")
SELECT f.metric,
       CASE WHEN f.stopped IS NULL AND s.rows_ = 1 AND s.has_value THEN s.value END AS value,
       CASE WHEN f.stopped IS NOT NULL THEN 'stopped: ' || f.stopped
            WHEN s.metric IS NULL THEN 'the view serves no row'
            WHEN NOT s.has_value THEN 'the view serves no value column'
            WHEN s.rows_ <> 1 THEN 'the view serves ' || s.rows_ || ' rows, not one' END AS reason
FROM facts f LEFT JOIN shape s USING (metric)
ORDER BY f.metric;

--===------------------------------------------------------------------===--
-- metric_sources(for_metric := NULL): what feeds each metric of the bound
-- dataset, or one — one row per served field and the loaded column it
-- descends from, through the views' lineage: metric, field, source
-- (table.column), table_name; a computed field with no column behind it
-- has no row; beside those, one row per table the view reads, table_name
-- alone; a view that does not plan serves one row with reason.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.metric_sources(for_metric := NULL) AS TABLE
WITH metrics AS (
  SELECT m.metric FROM main.metric_summary() m WHERE m.stopped IS NULL AND (for_metric IS NULL OR m.metric = for_metric)),
lineage AS (
  SELECT l.view AS metric, l."column" AS field, l.derivation, l.complete
  FROM glossql_views_lineage(current_schema()) l WHERE l.view IN (SELECT metric FROM metrics)),
-- a field descends from the columns its derivation names; an aggregate
-- descends from no column — it is computed over them
fields AS (
  SELECT metric, field, unnest(regexp_extract_all(derivation, '([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*):', 1)) AS path,
         regexp_matches(derivation, '^(sum|count|avg|mean|min|max|median|mode|stddev|stddev_pop|stddev_samp|var_pop|var_samp|variance|string_agg|list|array_agg|arg_min|arg_max|first|last|any_value|bool_and|bool_or|quantile|quantile_cont|quantile_disc|approx_count_distinct|product)\(') AS aggregate
  FROM lineage WHERE field IS NOT NULL),
tables AS (
  SELECT DISTINCT metric, split_part(path, '.', 2) AS table_name FROM fields),
sources AS (
  SELECT DISTINCT metric, field, split_part(path, '.', 2) || '.' || split_part(path, '.', 3) AS source, split_part(path, '.', 2) AS table_name
  FROM fields WHERE NOT aggregate)
SELECT metric, field, source, table_name, NULL::VARCHAR AS reason FROM sources
UNION ALL
SELECT metric, NULL, NULL, table_name, NULL FROM tables
UNION ALL
SELECT metric, NULL, NULL, NULL, 'the metric definition does not plan' FROM lineage WHERE field IS NULL
ORDER BY metric, table_name NULLS LAST, field NULLS FIRST;

--===------------------------------------------------------------------===------------------------------------------------------------------===--
-- The built-in tests on a metric: what can break its number, checked
-- against its lineage and the evidence the quality kit stored, never
-- against the data again. fan_out_check is join fan-out, orphan_check
-- referential integrity on the declared joins, additivity_check the
-- additivity of the value, validity_check an effective-dated table read
-- without its validity dates. Each is a measurement over the metric's
-- view, `SELECT <check>() FROM <dataset>.<metric>`, whose breach_rate
-- rate_tolerance scores: 0 is green. A check whose evidence is not
-- stored yet says so in `reason` and serves no rate, which reads
-- yellow; a metric over one table cannot fan out and has no join to
-- check. A person who accepts a result records a tolerance at or above
-- it on the metric; their value outranks the agent's. `x-subject:
-- metric` marks a test metric_tests() expects on every metric, run or
-- not, and the test the server runs itself after a call that defined
-- the metric, glossed its columns or imported a table it scans.
--
-- metric_reads_of(ds, m): the tables and columns metric m of dataset ds
-- descends from, through its view's lineage; none when it does not plan.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.metric_reads_of(ds, m) AS TABLE
SELECT DISTINCT split_part(path, '.', 2) AS table_name, split_part(path, '.', 3) AS column_name
FROM (SELECT unnest(regexp_extract_all(l.derivation, '([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*):', 1)) AS path
      FROM glossql_views_lineage(ds) l WHERE l.view = m)
WHERE split_part(path, '.', 1) = ds;

-- metric_scans_of(ds, m): every table of ds metric m's definition scans,
-- joins and filters included, from its view's plan.
CREATE OR REPLACE MACRO main.metric_scans_of(ds, m) AS TABLE
SELECT DISTINCT split_part(s.table_name, '.', 2) AS table_name
FROM glossql_views_scans(ds) s
WHERE s.view = m AND split_part(s.table_name, '.', 1) = ds;

-- fan_out_check: the metric joins two tables on columns whose values
-- repeat on both sides, so the join multiplies rows. The join columns
-- come from the definition's own plan (glossql_views_joins), and whether
-- a column repeats from its stored column_profile, which the server runs
-- for a metric's join columns. A metric that joins nothing cannot fan out.
DECLARE ASPECT fan_out_check WITH $${
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "pairs": {"type": ["array", "null"], "items": {"type": "string"}},
                 "tolerance": {"type": "number"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION fan_out_check FOR GLOBAL AS $$
  WITH reads AS (SELECT table_name FROM main.metric_scans_of(split_part($subject, '.', 1), split_part($subject, '.', 2))),
  n AS (SELECT count(*) AS tables FROM reads),
  -- a join on an effective-dated table repeats its key by design: the
  -- validity test judges that join
  dated AS (
    SELECT g.subject AS table_path
    FROM glossql_glossary(split_part($subject, '.', 1), NULL, false) g
    WHERE g.aspect = 'validity' AND g.value IS NOT NULL),
  joins AS (
    SELECT j.left_column, j.right_column
    FROM glossql_views_joins(split_part($subject, '.', 1)) j
    WHERE j.view = split_part($subject, '.', 2)
      AND regexp_replace(j.left_column, '\.[^.]*$', '') <> regexp_replace(j.right_column, '\.[^.]*$', '')
      AND regexp_replace(j.left_column, '\.[^.]*$', '') NOT IN (SELECT table_path FROM dated)
      AND regexp_replace(j.right_column, '\.[^.]*$', '') NOT IN (SELECT table_path FROM dated)),
  profiles AS (
    SELECT subject, try_cast(json_extract(value, '$.distinct') AS BIGINT) AS distinct_values,
           round(try_cast(json_extract(value, '$.total') AS DOUBLE) * (1 - coalesce(try_cast(json_extract(value, '$.null_ratio') AS DOUBLE), 0))) AS filled
    FROM main.measurements
    WHERE dataset = split_part($subject, '.', 1) AND function = 'column_profile'
    QUALIFY row_number() OVER (PARTITION BY subject ORDER BY seq DESC) = 1),
  judged AS (
    SELECT j.left_column, j.right_column, l.subject IS NOT NULL AND r.subject IS NOT NULL AS profiled,
           coalesce(l.distinct_values < l.filled AND r.distinct_values < r.filled, false) AS repeats
    FROM joins j LEFT JOIN profiles l ON l.subject = j.left_column LEFT JOIN profiles r ON r.subject = j.right_column),
  unprofiled AS (
    SELECT string_agg(c, ', ' ORDER BY c) AS columns
    FROM (SELECT left_column AS c FROM judged WHERE NOT profiled AND left_column NOT IN (SELECT subject FROM profiles)
          UNION SELECT right_column FROM judged WHERE NOT profiled AND right_column NOT IN (SELECT subject FROM profiles)))
  SELECT n.tables > 0 AND NOT EXISTS (SELECT 1 FROM judged WHERE NOT profiled) AS applicable,
         CASE WHEN n.tables = 0 THEN 'reads no loaded table: not a metric, or its definition does not plan'
              WHEN EXISTS (SELECT 1 FROM judged WHERE NOT profiled) THEN 'the join columns are not profiled yet: run column_profile() over ' || (SELECT columns FROM unprofiled) END AS reason,
         CASE WHEN n.tables = 0 OR EXISTS (SELECT 1 FROM judged WHERE NOT profiled) THEN NULL
              WHEN EXISTS (SELECT 1 FROM judged WHERE repeats) THEN 1.0 ELSE 0.0 END AS breach_rate,
         (SELECT list(regexp_replace(left_column, '^[^.]*\.', '') || ' ~ ' || regexp_replace(right_column, '^[^.]*\.', '') ORDER BY left_column, right_column)
          FROM judged WHERE repeats) AS pairs
  FROM n
$$ RETURNS fan_out_check;

DECLARE TEST fan_out_test ON fan_out_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- additivity_check: the metric's value column says how it combines over
-- time and members (additivity: a flow sums, a stock keeps the period's last
-- level, a ratio re-divides its summed halves); without it a total or a
-- coarser grain sums whatever the column holds, a stock or a ratio included.
DECLARE ASPECT additivity_check WITH $${
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]}, "additivity": {"type": ["string", "null"]},
                 "tolerance": {"type": "number"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION additivity_check FOR GLOBAL AS $$
  WITH a AS (SELECT * FROM main.metric_summary() WHERE metric = split_part($subject, '.', 2)),
  ok AS (SELECT EXISTS (SELECT 1 FROM a WHERE value_column IS NOT NULL AND coalesce(kind, '') NOT IN ('scalar', 'relation', 'plan', 'sample')) AS applicable)
  SELECT ok.applicable,
         CASE WHEN NOT ok.applicable THEN coalesce((SELECT 'a ' || kind || ' has nothing to combine' FROM a WHERE coalesce(kind, '') IN ('scalar', 'relation')),
                                                  'the definition does not say yet which column is the time and which the measure') END AS reason,
         CASE WHEN ok.applicable THEN (SELECT CASE WHEN additivity IS NULL OR additivity_state <> 'current' THEN 1.0 ELSE 0.0 END FROM a) END AS breach_rate,
         (SELECT additivity FROM a) AS additivity
  FROM ok
$$ RETURNS additivity_check;

DECLARE TEST measure_additivity_test ON additivity_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- orphan_check: the share of rows on a declared edge between two tables the
-- metric scans whose key finds no parent, from the stored coherence result
-- (relationship_coherence' newest on the dataset); an inner join drops
-- them, an outer join counts them under no member. Where no edge is
-- declared between the tables a metric scans there is nothing to check.
DECLARE ASPECT orphan_check WITH $${
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "edges": {"type": ["array", "null"], "items": {"type": "object"}},
                 "tolerance": {"type": "number"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION orphan_check FOR GLOBAL AS $$
  WITH reads AS (SELECT table_name FROM main.metric_scans_of(split_part($subject, '.', 1), split_part($subject, '.', 2))),
  n AS (SELECT count(*) AS tables, string_agg(table_name, ', ' ORDER BY table_name) AS names FROM reads),
  declared AS (
    SELECT 1 FROM main.relationships r
    WHERE r.dataset = split_part($subject, '.', 1)
      AND split_part(r.left_side, '.', 2) IN (SELECT table_name FROM reads)
      AND split_part(r.right_side, '.', 2) IN (SELECT table_name FROM reads)
      AND split_part(r.left_side, '.', 2) <> split_part(r.right_side, '.', 2)),
  coherence AS (
    SELECT value FROM main.measurements
    WHERE dataset = split_part($subject, '.', 1) AND function = 'relationship_coherence' AND subject = split_part($subject, '.', 1)
    ORDER BY seq DESC LIMIT 1),
  edges AS (
    SELECT json_extract_string(j, '$.relationship') AS relationship, try_cast(json_extract(j, '$.orphan_rate') AS DOUBLE) AS orphan_rate
    FROM coherence, unnest(coalesce(json_extract(coherence.value, '$.relationships')::JSON[], [])) t(j)),
  mine AS (
    SELECT * FROM edges
    WHERE split_part(split_part(relationship, ' ', 1), '.', 2) IN (SELECT table_name FROM reads)
      AND split_part(split_part(relationship, ' ', 3), '.', 2) IN (SELECT table_name FROM reads))
  SELECT CASE WHEN n.tables = 0 THEN false WHEN n.tables = 1 THEN true
              WHEN NOT EXISTS (SELECT 1 FROM declared) THEN true
              ELSE EXISTS (SELECT 1 FROM coherence) END AS applicable,
         CASE WHEN n.tables = 0 THEN 'reads no loaded table: not a metric, or its definition does not plan'
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM declared) THEN 'no relationship is declared between the tables the metric scans (' || n.names || '): nothing to check'
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM coherence) THEN 'no coherence result is stored: run relationship_coherence() over the dataset' END AS reason,
         CASE WHEN n.tables = 1 THEN 0.0
              WHEN n.tables > 1 AND NOT EXISTS (SELECT 1 FROM declared) THEN 0.0
              WHEN n.tables > 1 AND EXISTS (SELECT 1 FROM coherence) THEN coalesce((SELECT max(orphan_rate) FROM mine), 0.0) END AS breach_rate,
         (SELECT list({'relationship': relationship, 'orphan_rate': orphan_rate} ORDER BY relationship) FROM mine) AS edges
  FROM n
$$ RETURNS orphan_check;

DECLARE TEST orphan_test ON orphan_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

-- validity: an effective-dated table (a slowly changing dimension, type 2):
-- each row holds from valid_from to valid_to, and a key repeats once per
-- version. open_end is the value valid_to carries on the current row
-- ('9999-01-01'), absent where it is NULL. Annotated on the table.
DECLARE ASPECT validity WITH $${
  "type": "object", "required": ["valid_from", "valid_to"],
  "properties": {"valid_from": {"type": "string"}, "valid_to": {"type": "string"},
                 "open_end": {"type": "string"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- validity_check: the metric scans an effective-dated table and reads both
-- of its validity columns, in its join, its filter or its select list; a
-- scan that reads neither or one joins every version of a key, and the
-- number counts a row once per version.
DECLARE ASPECT validity_check WITH $${
  "type": "object", "x-subject": "metric",
  "properties": {"applicable": {"type": "boolean"}, "reason": {"type": ["string", "null"]},
                 "breach_rate": {"type": ["number", "null"]},
                 "tables": {"type": ["array", "null"], "items": {"type": "string"}},
                 "tolerance": {"type": "number"}, "grounds": {"type": "string"}}
}$$ AS FACT ON TABLE;

DECLARE FUNCTION validity_check FOR GLOBAL AS $$
  WITH scans AS (
    SELECT split_part(s.table_name, '.', 2) AS table_name, s.columns
    FROM glossql_views_scans(split_part($subject, '.', 1)) s
    WHERE s.view = split_part($subject, '.', 2) AND split_part(s.table_name, '.', 1) = split_part($subject, '.', 1)),
  dated AS (
    SELECT split_part(g.subject, '.', 2) AS table_name, g.value->>'valid_from' AS valid_from, g.value->>'valid_to' AS valid_to
    FROM glossql_glossary(split_part($subject, '.', 1), NULL, false) g
    WHERE g.aspect = 'validity' AND g.value IS NOT NULL),
  undated AS (
    SELECT DISTINCT s.table_name || ' (' || d.valid_from || ', ' || d.valid_to || ')' AS scan
    FROM scans s JOIN dated d USING (table_name)
    WHERE NOT (list_contains(s.columns, d.valid_from) AND list_contains(s.columns, d.valid_to)))
  SELECT EXISTS (SELECT 1 FROM scans) AS applicable,
         CASE WHEN NOT EXISTS (SELECT 1 FROM scans) THEN 'reads no loaded table: not a metric, or its definition does not plan' END AS reason,
         CASE WHEN EXISTS (SELECT 1 FROM scans) THEN CASE WHEN EXISTS (SELECT 1 FROM undated) THEN 1.0 ELSE 0.0 END END AS breach_rate,
         (SELECT list(scan ORDER BY scan) FROM undated) AS tables
$$ RETURNS validity_check;

DECLARE TEST validity_test ON validity_check BY (AGENT, HUMAN) DETECTOR rate_tolerance THRESHOLD 0.0;

--===------------------------------------------------------------------===--
-- metric_tests(): every test on each metric of the bound dataset and on
-- what it reads — metric, test, aspect, declared_by (the kit that ships
-- the test, kit:<name>, or the agent or person who wrote it), subject
-- (the metric, or a table or column it reads), state (red, orange,
-- yellow, green, or not run while the test has not run), current
-- (false once what the result read has moved: the band stands and the
-- test runs again at the next touch), score, evidence (the check's own
-- result), run (the statement that runs it again, empty where there is
-- none). The tests marked x-subject metric appear on every metric, run
-- or not. A single value, a derived relation, a plan and a sample are
-- not metrics here. Ordered by what to look at first.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.metric_tests() AS TABLE
WITH metrics AS (
  SELECT metric FROM main.metric_summary()
  WHERE stopped IS NULL AND coalesce(kind, '') NOT IN ('plan', 'sample', 'scalar', 'relation')),
results AS (SELECT subject, aspect, test, band, score, current FROM glossql_tests(current_schema(), NULL)),
authors AS (
  SELECT name AS test, declared_by FROM main.tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
expected AS (
  SELECT t.name AS test, t.aspect
  FROM (SELECT * FROM main.tests QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1) t
  JOIN (SELECT name, schema FROM main.aspects QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1) a
    ON a.name = t.aspect
  WHERE json_extract_string(a.schema, '$.x-subject') = 'metric'),
evidence AS (
  SELECT subject, aspect, value FROM main.measurements WHERE dataset = current_schema()
  QUALIFY row_number() OVER (PARTITION BY subject, aspect ORDER BY seq DESC) = 1),
own AS (
  SELECT m.metric, e.test, e.aspect, current_schema() || '.' || m.metric AS subject,
         coalesce(r.band, 'not_run') AS state, coalesce(r.current, false) AS current,
         r.score, v.value::JSON AS evidence,
         'SELECT ' || e.aspect || '() FROM ' || current_schema() || '.' || m.metric AS run
  FROM metrics m CROSS JOIN expected e
  LEFT JOIN results r ON r.subject = current_schema() || '.' || m.metric AND r.test = e.test
  LEFT JOIN evidence v ON v.subject = current_schema() || '.' || m.metric AND v.aspect = e.aspect),
reads AS (
  SELECT m.metric, current_schema() || '.' || r.table_name || '.' || r.column_name AS subject
  FROM metrics m, main.metric_reads_of(current_schema(), m.metric) r
  UNION
  SELECT m.metric, current_schema() || '.' || s.table_name
  FROM metrics m, main.metric_scans_of(current_schema(), m.metric) s),
inputs AS (
  SELECT DISTINCT d.metric, r.test, r.aspect, r.subject,
         r.band AS state, r.current, r.score, NULL::JSON AS evidence, '' AS run
  FROM reads d JOIN results r ON r.subject = d.subject
  WHERE r.test NOT IN (SELECT test FROM expected))
SELECT t.metric, t.test, t.aspect, a.declared_by, t.subject, t.state, t.current, t.score, t.evidence, t.run
FROM (SELECT * FROM own UNION ALL SELECT * FROM inputs) t LEFT JOIN authors a USING (test)
ORDER BY CASE state WHEN 'red' THEN 0 WHEN 'orange' THEN 1 WHEN 'yellow' THEN 2 WHEN 'not_run' THEN 3 ELSE 4 END,
         current, metric, test, subject;

--===------------------------------------------------------------------===--
-- The test report this kit answers for the `next` read: one goal per
-- served metric, named by the metric, whose step is the worst test on
-- it — red, then orange, yellow (a check whose evidence is not stored
-- yet, or a definition whose columns carry no role), not run — with
-- the statement that settles it, filled from the catalog; a result that
-- predates a change to what it read keeps its band and says so; `done`
-- when every test on the metric is green or accepted. A dataset with no
-- metric is told so once. The server composes one next read from every
-- routes_<kit>() macro: this one serves its CTEs and its arms as SQL
-- text over the relations the server reads once — ds (the bound
-- dataset), axes (the fact rows), bodies (the current metric definition
-- per metric). Columns of an arm: surface, step, state (next, blocked,
-- done), act, say, why, statement (<...> marks what only the author can
-- fill), "then".
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.routes_metrics() AS TABLE
SELECT $ctes$
report AS (
  SELECT r.*,
         CASE r.state WHEN 'red' THEN 1 WHEN 'orange' THEN 2 WHEN 'yellow' THEN 3 WHEN 'not_run' THEN 4 END AS rank,
         json_extract_string(r.evidence, '$.reason') AS reason,
         coalesce(list_aggregate(from_json(json_extract(r.evidence, '$.pairs'), '["VARCHAR"]'), 'string_agg', ', '), '') AS pairs,
         coalesce(list_aggregate(from_json(json_extract(r.evidence, '$.tables'), '["VARCHAR"]'), 'string_agg', ', '), '') AS undated,
         coalesce((SELECT string_agg(round(try_cast(json_extract(e, '$.orphan_rate') AS DOUBLE) * 100, 1) || '% of rows on ' || json_extract_string(e, '$.relationship'), ', ')
                   FROM unnest(coalesce(json_extract(r.evidence, '$.edges')::JSON[], [])) t(e)
                   WHERE try_cast(json_extract(e, '$.orphan_rate') AS DOUBLE) > 0), '') AS orphans
  FROM main.metric_tests() r)
$ctes$ AS ctes, $arms$
SELECT r.metric AS surface, r.rank AS step, 'next' AS state, r.test AS act,
       CASE
         WHEN r.test = 'measure_additivity_test' AND r.state = 'red' THEN 'say how ' || r.metric || ' combines'
         WHEN r.test = 'measure_additivity_test' AND r.state = 'yellow' AND len(coalesce(a.missing, [])) > 0 THEN 'annotate the columns of ' || r.metric
         WHEN r.test = 'measure_additivity_test' AND r.state = 'yellow' THEN 'record ' || r.metric || ' again: ' || coalesce(a.reason, r.reason, 'it serves no value column')
         WHEN r.test = 'fan_out_test' AND r.state = 'red' THEN r.metric || ' joins many-to-many on ' || r.pairs
         WHEN r.test = 'fan_out_test' AND r.state = 'yellow' THEN 'profile the join columns of ' || r.metric
         WHEN r.test = 'validity_test' AND r.state = 'red' THEN r.metric || ' reads ' || r.undated || ' without its validity dates'
         WHEN r.test = 'orphan_test' AND r.state = 'red' THEN r.orphans || ' find no parent in ' || r.metric
         WHEN r.test = 'orphan_test' AND r.state = 'yellow' THEN 'run the coherence check for ' || r.metric
         WHEN r.state = 'not_run' THEN 'run ' || r.test || ' on ' || r.metric
         ELSE r.test || ' ' || r.state || ' on ' || r.subject
       END AS say,
       CASE
         WHEN r.test = 'measure_additivity_test' AND r.state = 'red' THEN 'no additivity is annotated on ' || coalesce(a.value_column, 'the value') || ' of ' || r.metric || ': a coarser grain than ' || coalesce(a.floor, 'the floor') || ' and a total over its members need it — a flow sums, a stock keeps the period''s last level, a ratio re-divides its summed halves'
         WHEN r.test = 'fan_out_test' AND r.state = 'red' THEN r.metric || ' joins on ' || r.pairs || ', and the values repeat on both sides: every match multiplies rows. Join through the table where the key is unique, aggregate one side first, or narrow the join; where the join is meant as it is, a tolerance on the metric says so'
         WHEN r.test = 'validity_test' AND r.state = 'red' THEN r.undated || ' is effective-dated: a key repeats once per version, and a join or a filter that does not bound both validity columns counts a row once per version'
         WHEN r.test = 'orphan_test' AND r.state = 'red' THEN 'rows on a declared join between tables ' || r.metric || ' scans find no parent: an inner join drops them, an outer join counts them under no member; fix the load, or record the rate as the tolerance'
         WHEN r.state = 'yellow' THEN coalesce(a.reason, r.reason, r.test || ' has no rate yet')
         WHEN r.state = 'not_run' THEN r.test || ' has not run on ' || r.metric
         ELSE coalesce(r.reason, r.test || ' scored ' || coalesce(CAST(r.score AS VARCHAR), '?') || ' on ' || r.subject)
       END || CASE WHEN r.state <> 'not_run' AND NOT r.current THEN '; the result predates a change to what it read, and runs again at the next touch' ELSE '' END AS why,
       CASE
         WHEN r.test = 'measure_additivity_test' AND r.state = 'red' THEN 'GLOSS additivity ON ' || ds.dataset || '.' || r.metric || '.' || coalesce(a.value_column, '<value column>') || ' AS $${"value": "<additive|semi-additive|ratio>", "grounds": "<why, in the business''s words>"}$$;'
         WHEN r.test = 'measure_additivity_test' AND r.state = 'yellow' AND len(coalesce(a.missing, [])) > 0 THEN list_aggregate(a.missing, 'string_agg', chr(10))
         WHEN r.test = 'measure_additivity_test' AND r.state = 'yellow' THEN 'GLOSS ' || r.metric || ' ON ' || ds.dataset || ' AS $$' || coalesce(b.body, '<the current body>') || '$$;'
         WHEN r.test = 'fan_out_test' AND r.state = 'red' THEN '-- make one side of ' || r.pairs || ' unique (aggregate it first, or join through the table that holds the key once), then record the definition again:' || chr(10) || 'GLOSS ' || r.metric || ' ON ' || ds.dataset || ' AS $$' || coalesce(b.body, '<the current body>') || '$$;'
         WHEN r.test = 'fan_out_test' AND r.state = 'yellow' THEN (SELECT string_agg('SELECT column_profile() FROM ' || trim(c) || ';', chr(10)) FROM unnest(string_split(regexp_replace(coalesce(r.reason, ''), '^.*over ', ''), ',')) u(c))
         WHEN r.test = 'validity_test' AND r.state = 'red' THEN '-- bound the validity columns of ' || r.undated || ' by the period (valid_from <= period AND valid_to > period), then record the definition again:' || chr(10) || 'GLOSS ' || r.metric || ' ON ' || ds.dataset || ' AS $$' || coalesce(b.body, '<the current body>') || '$$;'
         WHEN r.test = 'orphan_test' AND r.state = 'red' THEN '-- fix the load that leaves rows without a parent, or accept the rate:' || chr(10) || 'GLOSS orphan_check ON ' || ds.dataset || '.' || r.metric || ' AS $${"tolerance": ' || coalesce(CAST(r.score AS VARCHAR), '<the rate>') || ', "grounds": "<why these rows have no parent>"}$$;'
         WHEN r.test = 'orphan_test' AND r.state = 'yellow' THEN 'SELECT relationship_coherence() FROM ' || ds.dataset
         ELSE r.run
       END AS statement,
       CASE
         WHEN r.test = 'measure_additivity_test' AND r.state = 'red' THEN 'SELECT * FROM metric_series(grain := ''' || coalesce(a.floor, 'month') || ''') WHERE metric = ''' || r.metric || ''''
         WHEN r.test = 'fan_out_test' AND r.state = 'red' THEN '-- where one of the tables is effective-dated, say so and the validity test names the fix: GLOSS validity ON <table> AS $${"valid_from": "<column>", "valid_to": "<column>"}$$;' || chr(10) || '-- or, where the join is right as it is: GLOSS fan_out_check ON ' || ds.dataset || '.' || r.metric || ' AS $${"tolerance": 1.0, "grounds": "<why the fan-out is meant>"}$$;'
         WHEN r.state = 'yellow' AND r.test IN ('fan_out_test', 'orphan_test') THEN r.run
         ELSE ''
       END AS "then"
FROM report r LEFT JOIN axes a ON a.metric = r.metric LEFT JOIN bodies b ON b.metric = r.metric, ds
WHERE r.rank IS NOT NULL
UNION ALL
SELECT m.metric, 9, 'done', '', '', 'every test on ' || m.metric || ' is green or accepted', '', ''
FROM (SELECT DISTINCT metric FROM report) m, ds
UNION ALL
SELECT 'metrics', 1, 'next', 'GLOSS view', 'define the first metric',
       'no metric is served on ' || ds.dataset || ': the person''s question names it. A definition is SQL with one row per period and slice, and says which column is the time, which the measure and how it adds up (additive, semi-additive for a level such as a balance or a headcount, ratio), and which columns slice it',
       'DECLARE ASPECT <metric> WITH $${"title": "<its name in the business''s words>"}$$ AS VIEW;' || chr(10)
         || 'GLOSS <metric> ON ' || ds.dataset || ' AS $${"sql": "SELECT <period>, <value>, <slicing columns> FROM <table>", "time": "<period column>", "measure": {"column": "<value column>", "additivity": "<additive|semi-additive|ratio>", "unit": "<unit>"}, "dimensions": ["<column>"]}$$;',
       ''
FROM ds WHERE NOT EXISTS (SELECT 1 FROM report)
$arms$ AS arms;

--===------------------------------------------------------------------===--
-- semantic_model(): the bound dataset as one Apache Ossie document
-- (the open format for exchanging a semantic model; spec 0.3.0.dev0),
-- one row, column `document` (JSON). Each loaded table and each served
-- metric is an Ossie dataset with its fields; a column annotated as the
-- time or a dimension carries `dimension`; a table's key comes from its
-- entity's identity columns; a metric's value is an Ossie metric whose
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
  SELECT metric, value_column, period_column, additivity, numerator, denominator
  FROM main.metric_summary() WHERE stopped IS NULL AND applicable AND coalesce(kind, '') NOT IN ('plan', 'sample', 'scalar', 'relation')),
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
           'description': coalesce(json_extract_string(d.value, '$.definitions.' || x.metric || '.meaning'),
                                   json_extract_string(a.schema, '$.title')),
           'custom_extensions': CASE WHEN x.additivity IN ('semi-additive', 'non-additive') THEN
             [{'vendor_name': 'glossdb', 'data': to_json({'additivity': x.additivity, 'time_column': x.period_column})::VARCHAR}] END
         })) AS measure
  FROM metrics x CROSS JOIN ds
  LEFT JOIN known d ON d.subject = ds.dataset AND d.aspect = 'definitions'
  LEFT JOIN (SELECT name, schema FROM main.aspects QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1) a ON a.name = x.metric),
datasets AS (
  SELECT t.table_name,
         json_merge_patch('{}', to_json({
           'name': t.table_name,
           'source': ds.dataset || '.' || t.table_name,
           'primary_key': from_json(json_extract(e.value, '$.identity_columns'), '["VARCHAR"]'),
           'description': coalesce(tm.value->>'value', e.value->>'value'),
           'fields': (SELECT list(f.field ORDER BY f.ordinal_position) FROM fields f WHERE f.table_name = t.table_name),
           'metrics': (SELECT list(m.measure) FROM measures m WHERE m.metric = t.table_name)
         })) AS dataset
  FROM (SELECT DISTINCT table_name FROM cols) t CROSS JOIN ds
  LEFT JOIN known e ON e.subject = ds.dataset || '.' || t.table_name AND e.aspect = 'entity'
  LEFT JOIN known tm ON tm.subject = ds.dataset || '.' || t.table_name AND tm.aspect = 'meaning'),
edges AS (
  SELECT to_json({
           'name': split_part(r.left_side, '.', 2) || '_to_' || split_part(r.right_side, '.', 2) || '_' || r.seq,
           'from': split_part(r.left_side, '.', 2), 'to': split_part(r.right_side, '.', 2),
           'from_columns': string_split(regexp_replace(regexp_replace(r.left_side, '^[^.]*\.[^.]*\.', ''), '[() ]', '', 'g'), ','),
           'to_columns': string_split(regexp_replace(regexp_replace(r.right_side, '^[^.]*\.[^.]*\.', ''), '[() ]', '', 'g'), ',')
         }) AS edge
  FROM main.relationships r, ds WHERE r.dataset = ds.dataset)
SELECT json_merge_patch('{}', to_json({
         'version': '0.3.0.dev0',
         'name': ds.dataset,
         'description': (SELECT json_extract_string(settings, '$.purpose') FROM main.datasets WHERE name = ds.dataset ORDER BY seq DESC LIMIT 1),
         'datasets': (SELECT list(dataset ORDER BY table_name) FROM datasets),
         'relationships': (SELECT list(edge) FROM edges)
       })) AS document
FROM ds;
