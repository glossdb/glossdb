-- The plan kit (preview): a plan against the actual of the metric it
-- plans. A plan is a VIEW aspect declared with x-kind plan and x-plan-of
-- <metric>, its rows a period and a value. The kit serves the plan as a
-- world under its metric, compares it period by period with the metric's
-- actual, and stores the comparison when an actor runs metric_plan. It
-- needs no model service. Where a forecast of the metric is stored (a
-- result of a function named metric_forecast on the metric, which the
-- outlook kit declares), the periods not yet complete are held against
-- its range; where none is, they stay open. The server computes nothing
-- after a write and runs without the kit. Loaded after the views kit.
--
--   FROM glossql_kit('kits/views/kit.sql');
--   FROM glossql_kit('kits/plan/kit.sql');

--===------------------------------------------------------------------===--
-- A plan is an asset of a kind of its own, the view under its name. Its
-- edge to the metric it plans (plans) and the place 'its metric' (the
-- metric it plans and its columns) are this kit's: the lineage reads them
-- through these three macros (SPEC §4). Called with the empty dataset,
-- the places macro names the place it adds.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.lineage_assets_plan(dataset_name) AS TABLE
SELECT dataset_name || '.' || name AS asset, 'plan' AS kind, dataset_name || '.' || name AS node_asset,
       'definition' AS node_what
FROM main.aspects
WHERE kind = 'VIEW' AND json_extract_string(schema, '$.x-kind') = 'plan'
  AND name IN (SELECT DISTINCT table_name FROM glossql_columns(dataset_name) WHERE table_type = 'VIEW');

CREATE OR REPLACE MACRO main.lineage_edges_plan(dataset_name) AS TABLE
SELECT p.asset AS "from", dataset_name || '.' || json_extract_string(a.schema, '$.x-plan-of') AS "to", 'plans' AS kind
FROM main.lineage_assets_plan(dataset_name) p JOIN main.aspects a ON dataset_name || '.' || a.name = p.asset
WHERE json_extract_string(a.schema, '$.x-plan-of') IS NOT NULL;

CREATE OR REPLACE MACRO main.lineage_places_plan(dataset_name) AS TABLE
SELECT NULL::VARCHAR AS subject, 'its metric' AS "where", NULL::VARCHAR AS asset
UNION ALL SELECT "from", 'its metric', "to" FROM main.lineage_edges_plan(dataset_name)
UNION ALL SELECT e."from", 'its metric', c."to" FROM main.lineage_edges_plan(dataset_name) e
          JOIN main.contains_edges(dataset_name) c ON c."from" = e."to";

--===------------------------------------------------------------------===--
-- plan_axes_of(plans_at, metrics_at): one row per plan of the place
-- plans_at: view, kind, plan_of, covers, stopped, applicable, reason, its
-- period and value columns, its metric's additivity, the grain it covers
-- as floor, its metric's read through view_axes_of() at metrics_at.
-- plan_rows_of(plans_at, metrics_at): every applicable plan's rows —
-- plan, metric, additivity, covers, instant, value, and grain, the
-- plan's own: the grain its rows are booked against where the declaration
-- says so, else the rows' measured grain. plan_cells(at_grain): the plan
-- world's cells per plan at a grain, or at its own where NULL — a flow
-- sums, a stock keeps the last level, anything else averages; a plan
-- coarser than the asked grain serves nothing.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.plan_axes_of(plans_at, metrics_at) AS TABLE
WITH defs AS MATERIALIZED (
  SELECT split_part(view, '.', 2) AS metric, kind, json_extract_string(schema, '$.x-plan-of') AS plan_of,
         json_extract_string(schema, '$.x-covers') AS covers, stopped, columns
  FROM definition(plans_at) WHERE kind = 'plan'),
pc AS (SELECT d.metric, list(c.name ORDER BY c.position) AS cols FROM defs d, unnest(d.columns) t(c) GROUP BY d.metric),
m AS MATERIALIZED (FROM main.view_axes_of(metrics_at, metrics_at)),
plans AS (
  SELECT p.metric, p.kind, p.plan_of, p.covers, p.stopped, p.columns,
         CASE WHEN list_contains(pc.cols, m.period_column) THEN m.period_column WHEN list_contains(pc.cols, 'period') THEN 'period' END AS period_column,
         CASE WHEN list_contains(pc.cols, m.value_column) THEN m.value_column WHEN list_contains(pc.cols, 'value') THEN 'value' END AS value_column,
         m.view IS NOT NULL AS of_declared, m.reason IS NULL AS of_applicable, m.reason AS of_reason,
         m.period_column AS of_period, m.value_column AS of_value, m.additivity
  FROM defs p LEFT JOIN pc ON pc.metric = p.metric LEFT JOIN m ON m.view = p.plan_of)
SELECT metric AS view, kind, plan_of, covers, stopped, reason IS NULL AS applicable, reason, period_column, value_column, additivity
FROM (SELECT *, main.plan_reason(stopped, plan_of, of_declared, true, covers, of_applicable, of_reason, period_column, of_period, value_column, of_value) AS reason FROM plans)
ORDER BY view;

CREATE OR REPLACE MACRO main.plan_rows_of(plans_at, metrics_at) AS TABLE
WITH p AS (
  SELECT a.view AS plan, a.plan_of AS metric, a.covers, a.period_column, a.value_column, a.additivity
  FROM main.plan_axes_of(plans_at, metrics_at) a WHERE a.applicable),
rows_ AS (
  SELECT p.plan, p.metric, p.additivity, p.covers,
         max(CASE WHEN c."column" = p.period_column THEN TRY_CAST(c.val AS TIMESTAMP) END) AS instant,
         max(CASE WHEN c."column" = p.value_column THEN TRY_CAST(c.val AS DOUBLE) END) AS value
  FROM dataset_cells(current_schema(), plans_at) c JOIN p ON p.plan = c."table"
  GROUP BY p.plan, p.metric, p.additivity, p.covers, c.rn),
gaps AS (
  SELECT plan, min(gap) AS gap
  FROM (SELECT plan, date_diff('day', lag(instant) OVER (PARTITION BY plan ORDER BY instant), instant) AS gap
        FROM (SELECT DISTINCT plan, instant FROM rows_ WHERE instant IS NOT NULL))
  GROUP BY plan)
SELECT r.plan, r.metric, r.additivity, r.covers, r.instant, r.value,
       coalesce(r.covers, CASE WHEN g.gap IS NULL THEN 'month' WHEN g.gap >= 360 THEN 'year' WHEN g.gap >= 89 THEN 'quarter'
                               WHEN g.gap >= 28 THEN 'month' WHEN g.gap >= 7 THEN 'week' ELSE 'day' END) AS grain
FROM rows_ r LEFT JOIN gaps g USING (plan);

CREATE OR REPLACE MACRO main.plan_cells(at_grain) AS TABLE
SELECT r.plan, r.metric, coalesce(at_grain, r.grain) AS grain, date_trunc(coalesce(at_grain, r.grain), r.instant) AS period,
       CASE r.additivity WHEN 'semi-additive' THEN arg_max(r.value, r.instant) WHEN 'additive' THEN sum(r.value) ELSE avg(r.value) END AS value,
       coalesce(r.additivity, 'none') AS additivity
FROM main.plan_rows_of('the dataset', 'the dataset''s metrics') r
WHERE r.instant IS NOT NULL AND r.value IS NOT NULL
  AND (at_grain IS NULL OR main.grain_rank(at_grain) >= main.grain_rank(r.grain))
GROUP BY r.plan, r.metric, coalesce(at_grain, r.grain), date_trunc(coalesce(at_grain, r.grain), r.instant), r.additivity;

--===------------------------------------------------------------------===--
-- The plan world under its metric, metric_series(world := 'plan', plan :=
-- '<name>'): refused by name where no plan is named, the name is no
-- aspect or no plan, or the plan is not served. plan_series(g): each
-- plan at a grain beside its metric's actual series, as the console's
-- chart draws it (world_series()).
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.world_plan(w, p, g) AS TABLE
WITH named AS (
  SELECT a.view AS plan, a.applicable, a.reason FROM main.view_summary() a WHERE a.kind = 'plan' AND a.view = p),
refusal AS (
  SELECT CASE WHEN w = 'plan' AND p IS NULL THEN error('plan_not_named: metric_series(world := ''plan'') names the plan it serves, plan := ''<name>'' — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>')
              WHEN w = 'plan' AND NOT EXISTS (SELECT 1 FROM named) THEN error(
                CASE WHEN NOT EXISTS (SELECT 1 FROM main.aspects WHERE name = p)
                     THEN 'unknown_plan: metric_series(plan := ''' || p || '''): no aspect of that name is declared — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>'
                     ELSE 'not_a_plan: metric_series(plan := ''' || p || '''): ' || p || ' is no plan — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>' END)
              WHEN w = 'plan' AND EXISTS (SELECT 1 FROM named WHERE NOT applicable) THEN error(
                'plan_not_served: metric_series(plan := ''' || p || '''): ' || (SELECT reason FROM named))
         END AS r)
SELECT c.metric, 'plan' AS world, '' AS dimension, '' AS member, c.period, c.value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, c.additivity
FROM main.plan_cells(g) c WHERE w = 'plan' AND c.plan = p
UNION ALL SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM refusal WHERE r IS NOT NULL;

CREATE OR REPLACE MACRO main.plan_series(g) AS TABLE
WITH titles AS (
  SELECT name, json_extract_string(schema, '$.title') AS title FROM main.aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1)
SELECT c.metric, coalesce(t.title, c.plan) AS series, 'plan' AS world, c.period::TIMESTAMP AS period, c.value, c.additivity,
       NULL::DOUBLE AS low, NULL::DOUBLE AS high, NULL::VARCHAR AS held
FROM main.plan_cells(g) c LEFT JOIN titles t ON t.name = c.plan;

--===------------------------------------------------------------------===--
-- plan_points_of(plans_at, metrics_at): every served plan of the places
-- against its metric's actual, one row per plan and period at the plan's
-- own grain and, where that is finer, at the year — plan, metric, grain,
-- period, label, value (the plan's cell), actual (the actual at that
-- grain where the period has begun; for the current period, to date),
-- variance (actual minus plan, on a complete period), low, expected, high
-- (the stored forecast's 80% range and median: the step's at the
-- metric's own grain; at a coarser grain, for a flow the actual of the
-- complete periods plus the total that runs to the period's end, for a
-- stock the range of the last period of the metric's grain inside it),
-- planned (complete: the period is over and the actuals cover every
-- period of it; not_covered: begun, and the actuals served do not reach
-- back to its start or hold no value for it, so no actual and no
-- variance; inside, below, above: where the plan lies against the range;
-- partial: begun and the rows cover part of the period, no range; open:
-- begun, no range covers the rest; ahead: not begun), covers (on the year
-- row of a plan whose rows cover part of the year: how much), coverage_80
-- (the model service's measured share of actual values inside such a
-- range on held-out data) and origin (the forecast's). A period is
-- complete once the metric's last complete period reaches its end. The
-- forecast is read where it is stored, results('metric_forecast',
-- metrics_at); without one every period not complete is open or ahead.
-- plan_points(): the same over the dataset, at read; metric_plan reads
-- its own plan, 'itself', and 'its metric'.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.plan_points_of(plans_at, metrics_at) AS TABLE
WITH prow AS MATERIALIZED (SELECT * FROM main.plan_rows_of(plans_at, metrics_at)),
g AS (
  SELECT pg.plan, pg.metric, pg.additivity, pg.grain, m.floor AS metric_floor
  FROM (SELECT DISTINCT plan, metric, additivity, grain FROM prow) pg
  JOIN main.view_axes_of(metrics_at, metrics_at) m ON m.view = pg.metric WHERE m.applicable),
floor_cells AS MATERIALIZED (
  SELECT metric, period, value, num, den, additivity FROM main.actual_series_of(metrics_at, metrics_at, unclaimed := 'skip')
  WHERE dimension = ''),
-- edge: the last period with a value; origin: the last complete one, the period before where the data ends inside the
-- edge's; first_actual: where the served actuals begin (the series serves a window of periods, not the whole history)
edges AS (SELECT metric, max(period) AS edge, min(period) AS first_actual FROM floor_cells WHERE value IS NOT NULL GROUP BY metric),
origins AS (
  SELECT e.metric, e.edge, e.first_actual,
         CASE WHEN EXISTS (SELECT 1 FROM main.partial_periods_of(metrics_at, metrics_at, NULL) pp WHERE pp.metric = e.metric AND pp.period = e.edge)
              THEN e.edge - main.grain_step(m.floor) ELSE e.edge END AS origin
  FROM edges e JOIN main.view_axes_of(metrics_at, metrics_at) m ON m.view = e.metric),
-- the plan's cells at its own grain and at the year
cells AS (
  SELECT r.plan, r.metric, gr.step_grain AS grain, date_trunc(gr.step_grain, r.instant) AS period,
         CASE r.additivity WHEN 'semi-additive' THEN arg_max(r.value, r.instant) WHEN 'additive' THEN sum(r.value) ELSE avg(r.value) END AS value
  FROM prow r, unnest(CASE WHEN r.grain = 'year' THEN ['year'] ELSE [r.grain, 'year'] END) AS gr(step_grain)
  WHERE r.instant IS NOT NULL AND r.value IS NOT NULL
  GROUP BY r.plan, r.metric, gr.step_grain, date_trunc(gr.step_grain, r.instant), r.additivity),
own AS (SELECT c.* FROM cells c JOIN g USING (plan) WHERE c.grain = g.grain),
cover AS (
  SELECT o.plan, date_trunc('year', o.period) AS year, g.grain AS own_grain, count(*) AS covered,
         min(o.period) AS first, max(o.period + main.grain_step(g.grain)) AS last_end,
         CASE g.grain WHEN 'month' THEN 12 WHEN 'quarter' THEN 4
              WHEN 'day' THEN date_diff('day', date_trunc('year', o.period), date_trunc('year', o.period) + INTERVAL 1 YEAR)
              WHEN 'week' THEN cardinality(generate_series(date_trunc('week', date_trunc('year', o.period) + INTERVAL 6 DAY),
                                                           date_trunc('year', o.period) + INTERVAL 1 YEAR - INTERVAL 1 MICROSECOND, INTERVAL 7 DAY)) END AS of_
  FROM own o JOIN g USING (plan) WHERE g.grain <> 'year'
  GROUP BY o.plan, date_trunc('year', o.period), g.grain),
actuals AS (
  SELECT f.metric, r.grain, date_trunc(r.grain, f.period) AS period,
         CASE f.additivity WHEN 'semi-additive' THEN arg_max(f.value, f.period) WHEN 'ratio' THEN sum(f.num) / nullif(sum(f.den), 0) ELSE sum(f.value) END AS value,
         -- a flow's actual over the complete periods alone: what a total to go is added to
         sum(f.value) FILTER (WHERE f.period <= o.origin) AS value_done
  FROM floor_cells f JOIN (SELECT DISTINCT metric, grain FROM cells) r USING (metric) LEFT JOIN origins o ON o.metric = f.metric
  GROUP BY f.metric, r.grain, date_trunc(r.grain, f.period), f.additivity),
judged AS (
  SELECT r.plan, r.metric, r.grain, r.period, r.value, g.additivity, g.metric_floor, g.grain AS own_grain, o.origin, o.edge, o.first_actual,
         o.origin + main.grain_step(g.metric_floor) AS origin_end,
         r.period + main.grain_step(r.grain) AS period_end,
         date_trunc(g.metric_floor, r.period + main.grain_step(r.grain) - INTERVAL 1 MICROSECOND) AS last_inside,
         r.period <= o.edge AS begun,
         a.value AS actual_cell, a.value_done AS actual_done,
         c.covered, c.of_, c.first, c.last_end,
         coalesce(r.grain = 'year' AND c.plan IS NOT NULL AND c.covered < c.of_, false) AS part
  FROM cells r JOIN g USING (plan)
  LEFT JOIN origins o ON o.metric = r.metric
  LEFT JOIN actuals a ON a.metric = r.metric AND a.grain = r.grain AND a.period = r.period
  LEFT JOIN cover c ON c.plan = r.plan AND r.grain = 'year' AND c.year = r.period),
part_actual AS (
  SELECT j.plan, j.period AS year,
         CASE j.additivity WHEN 'additive' THEN sum(a.value) WHEN 'semi-additive' THEN arg_max(a.value, a.period) END AS actual
  FROM judged j JOIN own o ON o.plan = j.plan AND date_trunc('year', o.period) = j.period
  JOIN actuals a ON a.metric = j.metric AND a.grain = o.grain AND a.period = o.period AND o.period <= j.edge
  WHERE j.part GROUP BY j.plan, j.period, j.additivity),
stated AS (
  SELECT j.*,
    CASE WHEN j.part THEN pa.actual WHEN j.begun THEN j.actual_cell END AS actual_read,
    CASE WHEN j.part THEN j.last_end <= j.origin_end ELSE j.period_end <= j.origin_end END AS complete,
    CASE WHEN j.part THEN j.first <= j.edge ELSE j.begun END AS has_begun
  FROM judged j LEFT JOIN part_actual pa ON pa.plan = j.plan AND pa.year = j.period),
-- a begun period is compared only where the actuals cover it: they hold a value for it and, for anything but a stock (whose
-- level is the last period's), the served series begins at or before its start
result AS (
  SELECT s.* EXCLUDE (actual_read),
    coalesce(s.has_begun AND NOT (s.actual_read IS NOT NULL
               AND (s.additivity = 'semi-additive' OR s.first_actual <= CASE WHEN s.part THEN s.first ELSE s.period END)), false) AS uncovered,
    CASE WHEN s.has_begun AND s.actual_read IS NOT NULL
              AND (s.additivity = 'semi-additive' OR s.first_actual <= CASE WHEN s.part THEN s.first ELSE s.period END)
         THEN s.actual_read END AS actual
  FROM stated s),
-- the stored forecast's ranges, where one is stored on the metric
fp AS MATERIALIZED (
  SELECT split_part(f.asset, '.', 2) AS metric, u.fc.grain AS grain, u.fc.origin::TIMESTAMP AS origin, p.p.step AS step, p.p.span AS span,
         p.p.to_go AS to_go, p.p.period::TIMESTAMP AS period, p.p.p10 AS p10, p.p.p50 AS p50, p.p.p90 AS p90, p.p.coverage_80 AS coverage_80
  FROM results('metric_forecast', metrics_at) f,
       (SELECT from_json(f.value, '{"applicable": "BOOLEAN", "grain": "VARCHAR", "origin": "VARCHAR",
                                    "points": [{"step": "BIGINT", "span": "BIGINT", "to_go": "VARCHAR", "period": "VARCHAR",
                                                "p10": "DOUBLE", "p50": "DOUBLE", "p90": "DOUBLE", "coverage_80": "DOUBLE"}]}') AS fc) u,
       unnest(u.fc.points) p(p)
  WHERE f.value IS NOT NULL AND u.fc.applicable),
-- the range a row is held against: the step's at the metric's own grain; at a coarser grain, for a stock the range of the
-- last period of the metric's grain inside it, for a flow that has begun the total that runs to the period's end
candidates AS (
  SELECT v.plan, v.grain, v.period, f.p10, f.p50, f.p90, f.coverage_80, f.origin,
         row_number() OVER (PARTITION BY v.plan, v.grain, v.period ORDER BY f.span NULLS FIRST, f.step) AS rn
  FROM result v JOIN fp f ON f.metric = v.metric
  WHERE NOT v.complete AND NOT v.part AND NOT v.uncovered
    AND ((v.grain = v.metric_floor AND f.span IS NULL AND f.period = v.period)
      OR (v.grain <> v.metric_floor AND v.additivity = 'semi-additive' AND f.span IS NULL AND f.period = v.last_inside)
      OR (v.grain <> v.metric_floor AND v.additivity = 'additive' AND v.has_begun AND v.actual IS NOT NULL
          AND f.span IS NOT NULL AND f.to_go = v.grain AND f.period >= v.period AND f.period < v.period_end))),
ranged AS (
  SELECT v.*, c.p10, c.p50, c.p90, c.coverage_80, c.origin AS forecast_origin,
         CASE WHEN v.grain = v.metric_floor OR v.additivity = 'semi-additive' THEN 0.0 ELSE coalesce(v.actual_done, 0.0) END AS base
  FROM result v LEFT JOIN candidates c ON c.plan = v.plan AND c.grain = v.grain AND c.period = v.period AND c.rn = 1)
SELECT plan, metric, grain, period,
       CASE grain WHEN 'year' THEN strftime(period, '%Y')
                  WHEN 'quarter' THEN strftime(period, '%Y') || '-Q' || ((month(period) - 1) // 3 + 1)
                  WHEN 'month' THEN strftime(period, '%Y-%m')
                  ELSE strftime(period, '%Y-%m-%d') END AS label,
       value, actual,
       CASE WHEN complete AND NOT uncovered THEN actual - value END AS variance,
       CASE WHEN complete OR part OR p10 IS NULL THEN NULL ELSE base + p10 END AS low,
       CASE WHEN complete OR part OR p50 IS NULL THEN NULL ELSE base + p50 END AS expected,
       CASE WHEN complete OR part OR p90 IS NULL THEN NULL ELSE base + p90 END AS high,
       CASE WHEN uncovered THEN 'not_covered'
            WHEN complete THEN 'complete'
            WHEN part THEN CASE WHEN has_begun THEN 'partial' ELSE 'ahead' END
            WHEN p10 IS NULL THEN CASE WHEN has_begun THEN 'open' ELSE 'ahead' END
            WHEN value < base + p10 THEN 'below' WHEN value > base + p90 THEN 'above' ELSE 'inside' END AS planned,
       CASE WHEN part THEN covered || ' of ' || of_ || ' ' || own_grain || 's' END AS covers,
       CASE WHEN complete OR part THEN NULL ELSE coverage_80 END AS coverage_80,
       CASE WHEN complete OR part THEN NULL ELSE strftime(forecast_origin, '%Y-%m-%d') END AS origin
FROM ranged
ORDER BY plan, CASE grain WHEN 'year' THEN 0 ELSE 1 END, period;

CREATE OR REPLACE MACRO main.plan_points() AS TABLE FROM main.plan_points_of('the dataset', 'the dataset''s metrics');

--===------------------------------------------------------------------===--
-- metric_plan: the plan compared, as a measurement on the plan — the rows
-- plan_points() serves for it as of the data, with the origin of the
-- forecast they were held against where one is stored. Refused on a view
-- that is not a plan, or a plan that is not served, by name. Out of date
-- once what it read is: the plan, its metric, and the forecast stored on
-- the metric. forecast_code and forecast_error: where the forecast
-- stored on the metric is a failed run (its error, or an answer with a
-- code and no point) and a period of the plan is open or ahead, its code
-- and its error; NULL where it holds a range, none is stored, or no
-- period waits for a range. finding and fix: where a year of the plan
-- lies below or above the forecast's range, what the gap is and the
-- assumption that records it; where the forecast failed, the failure and
-- the statements that run the forecast and the comparison again; NULL
-- elsewhere. forecast_failure_code(error): the code of a failed run's
-- error, as the interfaces class it; forecast_failure_text(error): the
-- error without the engine's prefixes. plan_gap, the test's detector:
-- yellow where the forecast failed, else red where a ranged period lies
-- outside the range, the score the share of ranged periods that do.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_plan WITH $${
  "description": "Preview. A plan against the actual of the metric it plans, and against its forecast where one is stored.",
  "type": "object",
  "properties": {
    "plan": {"type": "string"},
    "metric": {"type": ["string", "null"]},
    "grain": {"type": ["string", "null"]},
    "forecast_origin": {"type": ["string", "null"]},
    "forecast_code": {"type": ["string", "null"]},
    "forecast_error": {"type": ["string", "null"]},
    "points": {"type": "array", "items": {"type": "object"}},
    "finding": {"type": ["string", "null"]},
    "fix": {"type": ["string", "null"]}
  }
}$$ AS MEASUREMENT ON TABLE;

CREATE OR REPLACE MACRO main.forecast_failure_text(e) AS
  regexp_replace(e, '^(?:glossql: )?(?:[A-Za-z ]+ Error: )?(?:glossql: )?', '');

CREATE OR REPLACE MACRO main.forecast_failure_code(e) AS
  CASE WHEN contains(e, 'no service is named for ') THEN 'service_not_configured'
       WHEN contains(e, 'the service at ') OR contains(e, 'the service answered ') THEN 'service_failed'
       ELSE nullif(regexp_extract(main.forecast_failure_text(e), '^([a-z][a-z0-9_]*): ', 1), '') END;

DECLARE FUNCTION metric_plan FOR GLOBAL AS $$
  WITH named AS (SELECT kind, applicable, reason FROM main.plan_axes_of('itself', 'its metric') WHERE view = split_part($subject, '.', 2)),
  refusal AS (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM named WHERE kind = 'plan')
                THEN error('not_a_plan: ' || $subject || ' is not a plan: metric_plan() compares a plan, a VIEW aspect declared with x-kind plan and x-plan-of <metric>, with the actual')
                WHEN EXISTS (SELECT 1 FROM named WHERE NOT applicable)
                THEN error('plan_not_served: ' || $subject || ' is a plan that is not served: ' || (SELECT reason FROM named)) END AS r),
  pts AS (SELECT * FROM main.plan_points_of('itself', 'its metric') WHERE plan = split_part($subject, '.', 2)),
  own AS (SELECT metric, grain FROM main.plan_rows_of('itself', 'its metric') WHERE plan = split_part($subject, '.', 2) LIMIT 1),
  -- the forecast stored on the metric, where it is a failed run
  failed AS (
    SELECT f.asset, coalesce(main.forecast_failure_code(f.error), json_extract_string(f.value, '$.code')) AS code,
           coalesce(main.forecast_failure_text(f.error), json_extract_string(f.value, '$.reason')) AS error
    FROM results('metric_forecast', 'its metric') f JOIN own o ON f.asset = split_part($subject, '.', 1) || '.' || o.metric
    WHERE (f.error IS NOT NULL OR (f.value IS NOT NULL AND json_extract_string(f.value, '$.code') IS NOT NULL
                                  AND NOT coalesce(json_extract(f.value, '$.applicable')::BOOLEAN, false)))
      AND EXISTS (SELECT 1 FROM pts WHERE planned IN ('open', 'ahead'))
    LIMIT 1)
  SELECT coalesce((SELECT r FROM refusal)::VARCHAR, split_part($subject, '.', 2)) AS plan,
         (SELECT metric FROM own) AS metric,
         (SELECT grain FROM own) AS grain,
         (SELECT any_value(origin) FROM pts WHERE origin IS NOT NULL) AS forecast_origin,
         (SELECT code FROM failed) AS forecast_code,
         (SELECT error FROM failed) AS forecast_error,
         (SELECT coalesce(list({'grain': grain, 'period': strftime(period, '%Y-%m-%d'), 'label': label, 'value': value,
                                'actual': actual, 'variance': variance, 'low': low, 'expected': expected, 'high': high,
                                'planned': planned, 'covers': covers, 'coverage_80': coverage_80}
                               ORDER BY CASE grain WHEN 'year' THEN 0 ELSE 1 END, period), [])
          FROM pts) AS points,
         coalesce((SELECT 'the forecast of ' || f.asset || ' failed' || coalesce(' (' || f.code || ')', '') || ': ' || f.error
                          || '; the periods not yet complete are held against no range' FROM failed f),
                  (SELECT string_agg(plan || ' is ' || CAST(round(value, 2) AS VARCHAR) || ' at ' || label || ', ' || planned
                                       || ' the forecast''s range for ' || metric || ' of ' || CAST(round(low, 2) AS VARCHAR) || ' to ' || CAST(round(high, 2) AS VARCHAR), '; ' ORDER BY period)
                   FROM pts WHERE grain = 'year' AND planned IN ('below', 'above'))) AS finding,
         coalesce((SELECT '-- the forecast of ' || f.asset || ' failed; run it again, then compare the plan again:' || chr(10)
                          || 'SELECT metric_forecast() FROM ' || f.asset || ';' || chr(10)
                          || 'SELECT metric_plan() FROM ' || $subject || ';' FROM failed f),
         (SELECT '-- add each gap to "assumptions" of the plan as {"dimension": "definition", "key": "plan-<year>", "assumption": "<the gap and what closes it, in the business''s words>", "basis": "<what it rests on>", "confidence": 0.7}. Then record the plan again:'
                   || chr(10) || main.redefine_statement($subject)
          FROM pts WHERE grain = 'year' AND planned IN ('below', 'above') HAVING count(*) > 0)) AS fix
$$ RETURNS metric_plan;

DECLARE FUNCTION plan_gap FOR GLOBAL AS $$
  SELECT subject,
         CASE WHEN failed THEN 'yellow' WHEN outside > 0 THEN 'red' ELSE 'green' END AS state,
         CASE WHEN ranged > 0 THEN outside / ranged ELSE 0.0 END AS score
  FROM (SELECT subject, failed,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above'))), 0)::DOUBLE AS outside,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above', 'inside'))), 0)::DOUBLE AS ranged
        FROM (SELECT subject, json_extract_string(body, '$.forecast_error') IS NOT NULL AS failed,
                     list_transform(from_json(json_extract(body, '$.points'), '[{"planned": "VARCHAR"}]'), lambda p: p.planned) AS planned
              FROM annotations WHERE actor_kind = 'function'))
$$;

DECLARE TEST plan_test ON metric_plan DETECTOR plan_gap;
