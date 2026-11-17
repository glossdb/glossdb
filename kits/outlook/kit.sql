-- The outlook kit (preview): what the model service answers about the
-- metrics. Three functions an actor may run, each building its request
-- from the lake, calling the service, storing the answer and serving it
-- back as SQL: metric_ranges on a metric (its newest complete month
-- against the range its own history predicted), metric_forecast on a
-- metric (its periods ahead) and metric_scenario on a scenario (the
-- estimate of each metric it sets a lever on). A scenario is an asset of
-- a kind of this kit's, <dataset>.<scenario> (lineage_assets_scenario). The server
-- computes none after a write, and runs without the kit. The service
-- owns its topic and returns the verdicts: the ranges, the PIT and why it
-- is withheld, the displacement, each metric's score and state, the
-- coverage of a range, the sign and the effect of a scenario, and the
-- code of what failed. The kit owns the calendar and sends complete
-- periods only. The service is named once for the instance
-- (glossql_service_url, glossql_service_token); every call goes through
-- main.service, one macro over glossql_service, so a suite stands in for
-- the service by declaring the macro again. Loaded after the views kit.
--
--   FROM glossql_kit('kits/views/kit.sql');
--   FROM glossql_kit('kits/outlook/kit.sql');

CREATE OR REPLACE MACRO main.service(path, body) AS glossql_service(path, body);

--===------------------------------------------------------------------===--
-- complete_series_of(views_at, columns_at, g): every applicable metric's
-- total at grain g (its floor where NULL) without the last period where
-- its data ends inside it — metric, period, value, additivity. The
-- backtest, the forecast and the scenario all read it, so they drop the
-- same period. no_series_reason(…): why it holds no period of a metric.
-- service_reason(code, needed, given): what a code in the service's
-- answer means for a metric, in words; the kit maps codes, never the
-- service's text.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.complete_series_of(views_at, columns_at, g) AS TABLE
WITH s AS (
  SELECT metric, period, value, additivity, max(period) OVER (PARTITION BY metric) AS last
  FROM main.actual_series_of(views_at, columns_at, grain := g, unclaimed := 'skip')
  WHERE dimension = '' AND value IS NOT NULL)
SELECT s.metric, s.period, s.value, s.additivity FROM s
WHERE NOT (s.period = s.last
           AND EXISTS (SELECT 1 FROM main.partial_periods_of(views_at, columns_at, g) p WHERE p.metric = s.metric AND p.period = s.period));

CREATE OR REPLACE MACRO main.no_series_reason(m, value_column, additivity, additivity_state, g) AS
  CASE WHEN additivity IS NULL
       THEN CASE WHEN additivity_state = 'conflict' THEN 'the additivity on ' ELSE 'no additivity is annotated on ' END
            || current_schema() || '.' || m || '.' || value_column || ', so its rows cannot be combined by ' || g || ': '
            || main.gloss_statement('additivity', current_schema() || '.' || m || '.' || value_column, '{"value": "<additive|semi-additive|ratio|non-additive>"}')
       WHEN additivity = 'non-additive' THEN m || ' is non-additive and has several rows per ' || g || ', which cannot be combined'
       ELSE m || ' has no complete ' || g || ' yet' END;

CREATE OR REPLACE MACRO main.service_reason(code, needed, given) AS
  CASE code WHEN 'history_short' THEN 'the history is too short: ' || needed || ' periods are needed, ' || given || ' are loaded'
            WHEN 'origins_short' THEN 'the backtest takes ' || needed || ' periods, ' || given || ' are loaded'
            WHEN 'no_history' THEN 'no actual value is loaded'
            WHEN 'nothing_changed' THEN 'the scenario moves no input of the metric'
            WHEN 'model_failed' THEN 'the model failed on this series'
            WHEN 'origin_unknown' THEN 'an origin asked is not an actual period'
            ELSE code END;

-- answer_errors(a): the members, columns and origins the service could not answer, typed
CREATE OR REPLACE MACRO main.answer_errors(a) AS
  coalesce(from_json(json_extract(a, '$.answer.errors'),
    '[{"member": "VARCHAR", "column": "VARCHAR", "origin": "VARCHAR", "code": "VARCHAR", "needed": "BIGINT", "given": "BIGINT"}]'), []);

--===------------------------------------------------------------------===--
-- The backtest, on a metric: each metric is its own request.
-- range_request_of(views_at, columns_at): one row per metric of the place
-- — additivity, the complete months, applicable and reason.
-- range_body_of(views_at, columns_at, t): the request as the service's
-- contract spells it, the test's threshold t in the specification.
-- range_request() is the same for every metric of the dataset.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.range_request_of(views_at, columns_at) AS TABLE
WITH counted AS (
  SELECT metric, count(*) AS months FROM main.complete_series_of(views_at, columns_at, 'month') GROUP BY metric)
SELECT a.metric, a.additivity, coalesce(c.months, 0) AS months, c.metric IS NOT NULL AS applicable,
       CASE WHEN NOT a.applicable THEN a.reason
            WHEN c.metric IS NULL AND main.grain_rank(a.floor) > main.grain_rank('month')
              THEN a.metric || ' is served by ' || a.floor || ', and expected ranges are computed by month'
            WHEN c.metric IS NULL THEN main.no_series_reason(a.metric, a.value_column, a.additivity, a.additivity_state, 'month') END AS reason
FROM (SELECT * RENAME (view AS metric) FROM main.view_axes_of(views_at, columns_at)) a LEFT JOIN counted c USING (metric)
ORDER BY a.metric;

CREATE OR REPLACE MACRO main.range_request() AS TABLE
FROM main.range_request_of('the dataset''s metrics', 'the dataset''s metrics');

CREATE OR REPLACE MACRO main.range_body_of(views_at, columns_at, t) AS TABLE
WITH s AS (SELECT * FROM main.complete_series_of(views_at, columns_at, 'month')),
spec AS (SELECT json_merge_patch(json_object('targets', ['value'], 'origins', 6, 'horizon', 1, 'levels', [0.05, 0.1, 0.5, 0.9, 0.95],
                                             'grain', 'month'), json_object('threshold', t)) AS spec)
SELECT CASE WHEN count(s.metric) > 0 THEN json_object(
         'spec', (SELECT spec FROM spec),
         'table', json_object('member', list(s.metric ORDER BY s.metric, s.period),
                              'period', list(strftime(s.period, '%Y-%m') ORDER BY s.metric, s.period),
                              'status', list('actual' ORDER BY s.metric, s.period),
                              'value', list(s.value ORDER BY s.metric, s.period))) END AS body
FROM (SELECT 1) one LEFT JOIN s ON true;

--===------------------------------------------------------------------===--
-- metric_ranges: the backtest's answer on a metric. served_by names
-- the service and its version; threshold is the one the service judged
-- with, the test's; state is the worst metric's and score the largest;
-- metrics holds one row per metric — applicable and reason, code (what
-- the service could not answer), additivity, backtested, held_80 and
-- held_90 (the share of backtested months inside the 10-90 and the 5-95
-- range), period (the newest month backtested), score and state (that
-- month's, the service's), errors and points, one per backtested month:
-- period, actual, p05 to p95, pit, displacement, withheld, coverage_80
-- and coverage_90. finding and fix: the metrics the service judged red,
-- and how a person accepts the change. A person accepts a red result as
-- for the views' checks, with a tolerance at or above the score on the
-- metric (range_state reads it; a person's outranks an agent's).
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_ranges WITH $${
  "description": "Preview. A metric's newest complete month against the range its own history predicted, as the model service judges it.",
  "type": "object",
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "threshold": {"type": ["number", "null"]},
    "score": {"type": ["number", "null"]},
    "state": {"type": ["string", "null"]},
    "metrics": {"type": "array", "items": {"type": "object"}},
    "finding": {"type": ["string", "null"]},
    "fix": {"type": ["string", "null"]},
    "tolerance": {"type": "number"}, "basis": {"type": "string"}
  }
}$$ AS FACT ON TABLE;

DECLARE FUNCTION metric_ranges FOR GLOBAL AS $$
  WITH req AS (SELECT * FROM main.range_request_of('itself', 'its columns')),
  refusal AS (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM req)
                THEN error('not_a_metric: ' || $subject || ' is no metric: metric_ranges() backtests a metric, a view with a period and a value') END AS r),
  th AS (SELECT max(threshold) AS threshold FROM annotations('metric_ranges', 'itself')),
  b AS (SELECT body FROM main.range_body_of('itself', 'its columns', (SELECT threshold FROM th))),
  a AS (SELECT CASE WHEN body IS NOT NULL THEN main.service('/forecast', body) END AS a FROM b),
  rows_ AS (
    SELECT unnest(json_extract(a, '$.table.member')::VARCHAR[]) AS metric,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value,
           unnest(json_extract(a, '$.table.actual')::DOUBLE[]) AS actual,
           unnest(json_extract(a, '$.table.pit')::DOUBLE[]) AS pit,
           unnest(json_extract(a, '$.table.displacement')::DOUBLE[]) AS displacement,
           unnest(json_extract(a, '$.table.withheld')::VARCHAR[]) AS withheld,
           unnest(json_extract(a, '$.table.coverage_80')::DOUBLE[]) AS coverage_80,
           unnest(json_extract(a, '$.table.coverage_90')::DOUBLE[]) AS coverage_90
    FROM a WHERE a IS NOT NULL),
  points AS (
    SELECT metric, period, any_value(actual) AS actual,
           max(CASE WHEN level = 0.05 THEN value END) AS p05, max(CASE WHEN level = 0.1 THEN value END) AS p10,
           max(CASE WHEN level = 0.5 THEN value END) AS p50, max(CASE WHEN level = 0.9 THEN value END) AS p90,
           max(CASE WHEN level = 0.95 THEN value END) AS p95,
           any_value(pit) AS pit, any_value(displacement) AS displacement, any_value(withheld) AS withheld,
           any_value(coverage_80) AS coverage_80, any_value(coverage_90) AS coverage_90
    FROM rows_ WHERE period IS NOT NULL GROUP BY metric, period),
  members AS (
    SELECT u.m.member AS metric, u.m.backtested, u.m.held_80, u.m.held_90, u.m.period, u.m.score, u.m.state
    FROM a, unnest(from_json(json_extract(a, '$.answer.backtest.members'),
           '[{"member": "VARCHAR", "column": "VARCHAR", "backtested": "BIGINT", "held_80": "DOUBLE", "held_90": "DOUBLE",
              "period": "VARCHAR", "score": "DOUBLE", "state": "VARCHAR"}]')) u(m)
    WHERE a IS NOT NULL),
  errs AS (
    SELECT e.e.member AS metric, list({'code': e.e.code, 'origin': e.e.origin, 'needed': e.e.needed, 'given': e.e.given} ORDER BY e.e.origin NULLS FIRST) AS errors
    FROM a, unnest(main.answer_errors(a)) e(e) WHERE a IS NOT NULL GROUP BY e.e.member),
  per_metric AS (
    SELECT r.metric, r.additivity, r.applicable AND m.metric IS NOT NULL AS applicable,
           CASE WHEN NOT r.applicable THEN r.reason
                WHEN m.metric IS NULL THEN coalesce(main.service_reason(f.errors[1].code, f.errors[1].needed, f.errors[1].given), 'the service answered no point') END AS reason,
           CASE WHEN r.applicable AND m.metric IS NULL THEN f.errors[1].code END AS code,
           m.backtested, m.held_80, m.held_90, m.period, m.score, m.state, coalesce(f.errors, []) AS errors,
           (SELECT coalesce(list({'period': p.period, 'actual': p.actual, 'p05': p.p05, 'p10': p.p10, 'p50': p.p50, 'p90': p.p90, 'p95': p.p95,
                                  'pit': p.pit, 'displacement': p.displacement, 'withheld': p.withheld,
                                  'coverage_80': p.coverage_80, 'coverage_90': p.coverage_90} ORDER BY p.period), [])
            FROM points p WHERE p.metric = r.metric) AS points
    FROM req r LEFT JOIN members m USING (metric) LEFT JOIN errs f USING (metric)),
  red AS (
    SELECT m.metric, p.period, p.actual, p.p05, p.p95
    FROM per_metric m JOIN points p ON p.metric = m.metric AND p.period = m.period WHERE m.state = 'red'),
  judged AS (
    SELECT max(score) AS score,
           arg_max(state, CASE state WHEN 'red' THEN 3 WHEN 'orange' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END) AS state
    FROM per_metric WHERE state IS NOT NULL)
  SELECT coalesce((SELECT r FROM refusal)::VARCHAR,
                  (SELECT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version') FROM a)) AS served_by,
         (SELECT json_extract(a, '$.answer.backtest.threshold')::DOUBLE FROM a) AS threshold,
         judged.score, judged.state,
         (SELECT coalesce(list({'metric': metric, 'applicable': applicable, 'reason': reason, 'code': code, 'additivity': additivity,
                                'backtested': backtested, 'held_80': held_80, 'held_90': held_90, 'period': period, 'score': score,
                                'state': state, 'errors': errors, 'points': points} ORDER BY metric), [])
          FROM per_metric) AS metrics,
         (SELECT string_agg(metric || ' is ' || CAST(round(actual, 2) AS VARCHAR) || ' at ' || period
                              || ', outside its expected range of ' || CAST(round(p05, 2) AS VARCHAR) || ' to ' || CAST(round(p95, 2) AS VARCHAR), '; ' ORDER BY metric)
          FROM red) AS finding,
         CASE WHEN judged.state = 'red' THEN
           '-- a defect in the data is fixed in the load or the definition; then the backtest runs again:' || chr(10)
           || 'SELECT metric_ranges() FROM ' || $subject || ';' || chr(10)
           || '-- where a person accepts the change as real, they record it with their reason:' || chr(10)
           || '-- ' || main.gloss_statement('metric_ranges', $subject,
                         '{"tolerance": ' || ceil(judged.score * 1000) / 1000 || ', "basis": "<what changed, in the business''s words>"}') END AS fix
  FROM judged
$$ RETURNS metric_ranges;

-- range_state: the result is the service's: the worst metric's state and
-- the largest score, green where a tolerance at or above the score is
-- annotated on the metric (a person's outranks an agent's). A backtest
-- that scored no month has no state and no row.
DECLARE FUNCTION range_state FOR GLOBAL AS $$
  WITH s AS (
    SELECT subject,
           max(body->>'state') FILTER (WHERE actor_kind = 'function') AS state,
           max(try_cast(body->>'score' AS DOUBLE)) FILTER (WHERE actor_kind = 'function') AS score,
           coalesce(max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'human'),
                    max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'agent')) AS tolerance
    FROM annotations GROUP BY subject)
  SELECT subject, CASE WHEN score <= tolerance THEN 'green' ELSE state END AS state, score
  FROM s WHERE state IS NOT NULL
$$;

DECLARE TEST range_test ON metric_ranges BY (AGENT, HUMAN) DETECTOR range_state THRESHOLD 0.98;

-- range_points(): the stored backtests, one row per metric and backtested
-- month, the newest marked; a metric not backtested is one row with its
-- reason and code, a backtest that failed one row with its error.
CREATE OR REPLACE MACRO main.range_points() AS TABLE
WITH stored AS (
  SELECT value, error, computed_at, split_part(subject, '.', 2) AS subject_metric FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_ranges'),
metrics AS (
  SELECT computed_at, json_extract_string(value, '$.served_by') AS served_by,
         unnest(from_json(json_extract(value, '$.metrics'),
           '[{"metric": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "code": "VARCHAR", "backtested": "BIGINT",
              "held_80": "DOUBLE", "held_90": "DOUBLE", "period": "VARCHAR", "score": "DOUBLE", "state": "VARCHAR",
              "points": [{"period": "VARCHAR", "actual": "DOUBLE", "p05": "DOUBLE", "p10": "DOUBLE", "p50": "DOUBLE", "p90": "DOUBLE",
                          "p95": "DOUBLE", "pit": "DOUBLE", "displacement": "DOUBLE", "withheld": "VARCHAR",
                          "coverage_80": "DOUBLE", "coverage_90": "DOUBLE"}]}]')) AS m
  FROM stored WHERE value IS NOT NULL),
backtested AS (SELECT m, unnest(m.points) AS p, served_by, computed_at FROM metrics WHERE cardinality(m.points) > 0)
SELECT m.metric, m.applicable, m.reason, m.code, m.backtested, m.held_80, m.held_90, m.score, m.state,
       p.period, p.actual, p.p05, p.p10, p.p50, p.p90, p.p95, p.pit, p.displacement, p.withheld, p.coverage_80, p.coverage_90,
       p.period = m.period AS newest, row_number() OVER (PARTITION BY m.metric ORDER BY p.period) AS point_seq,
       served_by, computed_at, NULL::VARCHAR AS error
FROM backtested
UNION ALL
SELECT m.metric, m.applicable, m.reason, m.code, m.backtested, m.held_80, m.held_90, m.score, m.state,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, served_by, computed_at, NULL
FROM metrics WHERE cardinality(m.points) = 0
UNION ALL
SELECT subject_metric, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, computed_at, error
FROM stored WHERE value IS NULL
ORDER BY metric NULLS FIRST, point_seq NULLS FIRST;

--===------------------------------------------------------------------===--
-- The forecast, on a metric: the service answers each metric in its own
-- request, so a metric declared or loaded leaves the others' forecasts,
-- and the plans that read them, current. forecast_request_of(views_at,
-- columns_at): one row per metric — kind, additivity, grain (its floor),
-- horizon (31 days, 13 weeks, 12 months, 4 quarters, the kit's reach for
-- a plan), origin (the last complete period with a value), history, the
-- periods ahead, and for a flow the spans it asks totals for: the
-- periods left in the month (a day), the quarter (a week), the quarter
-- and the year (a month), the year (a quarter) that the first period
-- ahead falls in, where the horizon reaches the span's end; two spans of
-- one length are asked once and served under both names.
-- forecast_request() is the same for every metric of the dataset.
-- forecast_bodies_of(views_at, columns_at): one request per metric, the
-- history as actual rows and the periods ahead as forecast rows, so the
-- answer carries their labels.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.forecast_request_of(views_at, columns_at) AS TABLE
WITH axes AS (SELECT * RENAME (view AS metric) FROM main.view_axes_of(views_at, columns_at)),
hist AS (
  SELECT metric, max(period) AS origin, list({'period': period, 'value': value} ORDER BY period) AS history
  FROM main.complete_series_of(views_at, columns_at, NULL) GROUP BY metric),
judged AS (
  SELECT a.metric, a.kind, a.additivity, a.floor AS grain,
         CASE a.floor WHEN 'day' THEN 31 WHEN 'week' THEN 13 WHEN 'month' THEN 12 WHEN 'quarter' THEN 4 END AS horizon,
         h.origin, h.history,
         CASE WHEN NOT a.applicable THEN a.reason
              WHEN a.floor NOT IN ('day', 'week', 'month', 'quarter')
                THEN a.metric || ' is served by ' || a.floor || ', and a forecast is asked by day, week, month or quarter'
              WHEN h.metric IS NULL THEN main.no_series_reason(a.metric, a.value_column, a.additivity, a.additivity_state, a.floor) END AS reason
  FROM axes a LEFT JOIN hist h USING (metric)
  WHERE coalesce(a.kind, '') NOT IN ('scalar', 'relation', 'sample')),
ahead AS (
  SELECT j.metric, list(g.period ORDER BY g.period) AS periods
  FROM judged j, unnest(generate_series(j.origin + main.grain_step(j.grain),
                                        j.origin + main.grain_step(j.grain) * (j.horizon + 1),
                                        main.grain_step(j.grain))) AS g(period)
  WHERE j.reason IS NULL GROUP BY j.metric),
spans AS (
  SELECT metric, list({'span': n, 'to_go': to_go} ORDER BY n, to_go) AS spans
  FROM (
    SELECT j.metric, s.to_go, j.horizon,
           count(*) FILTER (WHERE u.p < date_trunc(s.to_go, ah.periods[1]) + main.grain_step(s.to_go)) AS reached,
           least(count(*) FILTER (WHERE u.p < date_trunc(s.to_go, ah.periods[1]) + main.grain_step(s.to_go)), j.horizon) AS n
    FROM judged j JOIN ahead ah USING (metric),
         unnest(CASE j.grain WHEN 'day' THEN ['month'] WHEN 'week' THEN ['quarter'] WHEN 'month' THEN ['quarter', 'year']
                             WHEN 'quarter' THEN ['year'] ELSE []::VARCHAR[] END) AS s(to_go),
         unnest(ah.periods) AS u(p)
    WHERE j.additivity = 'additive'
    GROUP BY j.metric, s.to_go, j.horizon)
  WHERE n >= 1 AND reached <= horizon
  GROUP BY metric)
SELECT j.metric, j.kind, j.additivity, j.grain, j.horizon, j.origin, j.reason, j.reason IS NULL AS applicable, j.history,
       coalesce(ah.periods[1:j.horizon], []::TIMESTAMP[]) AS ahead,
       coalesce(s.spans, []::STRUCT(span BIGINT, to_go VARCHAR)[]) AS spans
FROM judged j LEFT JOIN ahead ah USING (metric) LEFT JOIN spans s USING (metric)
ORDER BY j.metric;

CREATE OR REPLACE MACRO main.forecast_request() AS TABLE
FROM main.forecast_request_of('the dataset''s metrics', 'the dataset''s metrics');

CREATE OR REPLACE MACRO main.forecast_bodies_of(views_at, columns_at) AS TABLE
WITH r AS (SELECT * FROM main.forecast_request_of(views_at, columns_at) WHERE applicable),
rows_ AS (
  SELECT r.metric, cell.period AS period, cell.value AS value, 'actual' AS status
  FROM r, unnest(r.history) AS hs(cell)
  UNION ALL
  SELECT r.metric, ap.p, NULL::DOUBLE, 'forecast'
  FROM r, unnest(r.ahead) AS ap(p))
SELECT r.metric, r.grain, list_sort(list_distinct(list_transform(r.spans, lambda s: s.span))) AS totals,
       json_object('spec', json_object('targets', ['value'], 'horizon', r.horizon, 'levels', [0.05, 0.1, 0.5, 0.9, 0.95],
                                       'grain', r.grain, 'totals', list_sort(list_distinct(list_transform(r.spans, lambda s: s.span)))),
                   'table', json_object('member', list(w.metric ORDER BY w.period),
                                        'period', list(strftime(w.period, '%Y-%m-%d') ORDER BY w.period),
                                        'status', list(w.status ORDER BY w.period),
                                        'value', list(w.value ORDER BY w.period))) AS body
FROM r JOIN rows_ w USING (metric)
GROUP BY r.metric, r.grain, r.horizon, r.spans;

--===------------------------------------------------------------------===--
-- metric_forecast: the forecast's answer on a metric, at an origin:
-- served_by, metric, additivity, grain, origin, applicable, reason and
-- code (what the service could not answer), errors, and its points — a
-- step (one period past the origin) or a span (the total of the first so
-- many steps, to_go naming the month, the quarter or the year it runs
-- to) with its period, p05 to p95, and the service's coverage of such a
-- range on held-out data: coverage_80 and coverage_90 with their
-- standard errors, coverage_points and coverage_datasets. Refused by
-- name on a view that is no metric.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_forecast WITH $${
  "description": "Preview. A metric's periods ahead and the totals a plan reads, with the coverage the model service measured for such a range.",
  "type": "object",
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "metric": {"type": "string"},
    "grain": {"type": ["string", "null"]},
    "origin": {"type": ["string", "null"]},
    "applicable": {"type": "boolean"},
    "points": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT ON TABLE;

DECLARE FUNCTION metric_forecast FOR GLOBAL AS $$
  WITH req AS (SELECT * FROM main.forecast_request_of('itself', 'its columns')),
  refusal AS (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM req)
                THEN error('not_a_metric: ' || $subject || ' is no metric: metric_forecast() forecasts a metric, a view with a period and a value') END AS r),
  b AS (SELECT body, main.service('/forecast', body) AS a FROM main.forecast_bodies_of('itself', 'its columns')),
  rows_ AS (
    SELECT unnest(json_extract(a, '$.table.step')::BIGINT[]) AS step,
           unnest(json_extract(a, '$.table.span')::BIGINT[]) AS span,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value,
           unnest(json_extract(a, '$.table.coverage_80')::DOUBLE[]) AS coverage_80,
           unnest(json_extract(a, '$.table.coverage_80_se')::DOUBLE[]) AS coverage_80_se,
           unnest(json_extract(a, '$.table.coverage_90')::DOUBLE[]) AS coverage_90,
           unnest(json_extract(a, '$.table.coverage_90_se')::DOUBLE[]) AS coverage_90_se,
           unnest(json_extract(a, '$.table.coverage_points')::BIGINT[]) AS coverage_points,
           unnest(json_extract(a, '$.table.coverage_datasets')::BIGINT[]) AS coverage_datasets
    FROM b),
  points AS (
    SELECT step, span, any_value(period) AS period,
           max(CASE WHEN level = 0.05 THEN value END) AS p05, max(CASE WHEN level = 0.1 THEN value END) AS p10,
           max(CASE WHEN level = 0.5 THEN value END) AS p50, max(CASE WHEN level = 0.9 THEN value END) AS p90,
           max(CASE WHEN level = 0.95 THEN value END) AS p95,
           any_value(coverage_80) AS coverage_80, any_value(coverage_80_se) AS coverage_80_se,
           any_value(coverage_90) AS coverage_90, any_value(coverage_90_se) AS coverage_90_se,
           any_value(coverage_points) AS coverage_points, any_value(coverage_datasets) AS coverage_datasets
    FROM rows_ WHERE step IS NOT NULL GROUP BY step, span),
  errs AS (
    SELECT list({'code': e.e.code, 'origin': e.e.origin, 'needed': e.e.needed, 'given': e.e.given}) AS errors
    FROM b, unnest(main.answer_errors(b.a)) e(e)),
  named AS (
    SELECT p.*, sp.s.to_go AS to_go
    FROM points p LEFT JOIN (SELECT unnest(spans) AS s FROM req) sp ON sp.s.span = p.span)
  SELECT coalesce((SELECT r FROM refusal)::VARCHAR,
                  (SELECT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version') FROM b)) AS served_by,
         r.metric, r.additivity, r.grain, strftime(r.origin, '%Y-%m-%d') AS origin,
         r.applicable AND EXISTS (SELECT 1 FROM points) AS applicable,
         CASE WHEN NOT r.applicable THEN r.reason
              WHEN NOT EXISTS (SELECT 1 FROM points)
                THEN coalesce(main.service_reason(e.errors[1].code, e.errors[1].needed, e.errors[1].given), 'the service answered no point') END AS reason,
         CASE WHEN r.applicable AND NOT EXISTS (SELECT 1 FROM points) THEN e.errors[1].code END AS code,
         coalesce(e.errors, []) AS errors,
         (SELECT coalesce(list({'step': n.step, 'span': n.span, 'to_go': n.to_go, 'period': n.period,
                                'p05': n.p05, 'p10': n.p10, 'p50': n.p50, 'p90': n.p90, 'p95': n.p95,
                                'coverage_80': n.coverage_80, 'coverage_80_se': n.coverage_80_se,
                                'coverage_90': n.coverage_90, 'coverage_90_se': n.coverage_90_se,
                                'coverage_points': n.coverage_points, 'coverage_datasets': n.coverage_datasets}
                               ORDER BY n.span NULLS FIRST, n.step, n.to_go), [])
          FROM named n) AS points
  FROM errs e LEFT JOIN req r ON true
$$ RETURNS metric_forecast;

-- forecast_points(): every metric's stored forecast, one row per metric
-- and point — metric, applicable, reason, code, error (a run that
-- failed: its error, and no point), additivity, grain, origin,
-- served_by, computed_at, current (false once the stored forecast is out
-- of date), point_seq, step, span, to_go, period, p05 to p95,
-- coverage_80, coverage_80_se, coverage_90, coverage_90_se,
-- coverage_points, coverage_datasets; a metric not forecast is one row
-- with its reason.
CREATE OR REPLACE MACRO main.forecast_points() AS TABLE
WITH stored AS (
  SELECT split_part(m.subject, '.', 2) AS metric, m.value, m.error, m.computed_at, coalesce(c.current, false) AS current
  FROM main.measurements m
  LEFT JOIN (SELECT subject, bool_and(current) AS current FROM glossql_glossary(current_schema(), 'metric_forecast', true)
             WHERE actor = 'function' GROUP BY subject) c ON c.subject = m.subject
  WHERE m.dataset = current_schema() AND m.function = 'metric_forecast'),
typed AS (
  SELECT metric, error, computed_at, current,
         from_json(value, '{"served_by": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "code": "VARCHAR", "additivity": "VARCHAR",
                            "grain": "VARCHAR", "origin": "VARCHAR",
                            "points": [{"step": "BIGINT", "span": "BIGINT", "to_go": "VARCHAR", "period": "VARCHAR", "p05": "DOUBLE", "p10": "DOUBLE",
                                        "p50": "DOUBLE", "p90": "DOUBLE", "p95": "DOUBLE", "coverage_80": "DOUBLE", "coverage_80_se": "DOUBLE",
                                        "coverage_90": "DOUBLE", "coverage_90_se": "DOUBLE", "coverage_points": "BIGINT",
                                        "coverage_datasets": "BIGINT"}]}') AS f
  FROM stored),
pts AS (SELECT t.*, unnest(t.f.points) AS p, unnest(generate_series(0, len(t.f.points) - 1)) AS point_seq FROM typed t WHERE len(t.f.points) > 0)
SELECT metric, f.applicable, f.reason, f.code, error, f.additivity, f.grain, f.origin, f.served_by, computed_at, current,
       point_seq, p.step, p.span, p.to_go, p.period, p.p05, p.p10, p.p50, p.p90, p.p95,
       p.coverage_80, p.coverage_80_se, p.coverage_90, p.coverage_90_se, p.coverage_points, p.coverage_datasets
FROM pts
UNION ALL
SELECT metric, coalesce(f.applicable, false), f.reason, f.code, error, f.additivity, f.grain, f.origin, f.served_by, computed_at, current,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM typed WHERE coalesce(len(f.points), 0) = 0
ORDER BY metric, point_seq NULLS FIRST;

-- The forecast world under its metric, metric_series(world :=
-- 'forecast'): each stored forecast's medians at its grain.
-- forecast_series(g): the same with its 80% range and the service's
-- measured coverage of such a range, as the console's chart draws it.
CREATE OR REPLACE MACRO main.world_forecast(w, g) AS TABLE
SELECT metric, 'forecast' AS world, '' AS dimension, '' AS member, period::TIMESTAMP AS period, p50 AS value,
       NULL::DOUBLE AS num, NULL::DOUBLE AS den, coalesce(additivity, 'none') AS additivity
FROM main.forecast_points()
WHERE w = 'forecast' AND applicable AND span IS NULL AND period IS NOT NULL AND (g IS NULL OR g = grain);

CREATE OR REPLACE MACRO main.forecast_series(g) AS TABLE
WITH titles AS (
  SELECT name, json_extract_string(schema, '$.title') AS title FROM main.aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1)
SELECT f.metric, coalesce(t.title, f.metric) || ' · forecast' AS series, 'forecast' AS world, f.period::TIMESTAMP AS period, f.p50 AS value,
       coalesce(f.additivity, 'none') AS additivity, f.p10 AS low, f.p90 AS high,
       coalesce('such a range held ' || CAST(CAST(round(f.coverage_80 * 100) AS INT) AS VARCHAR) || '% ± '
                || CAST(CAST(round(f.coverage_80_se * 100) AS INT) AS VARCHAR) || '% of the time on held-out data', '') AS held
FROM main.forecast_points() f LEFT JOIN titles t ON t.name = f.metric
WHERE f.applicable AND f.span IS NULL AND f.grain = g;

--===------------------------------------------------------------------===--
-- The levers and the scenarios. A lever is a FACT on a column of a
-- metric's view — a list price, a discount rate — annotated true where
-- someone sets it, false where it was looked at and nobody does. A
-- scenario is the actor's own FACT aspect on the dataset, x-kind
-- scenario, its body a factor per period on declared levers: {"levers":
-- [{"column": "<metric>.<column>", "factor": {"YYYY-MM": 1.15, …},
-- "basis": "…"}]}; a period is a month or a day, one not named keeps a
-- factor of one. judge_levers(levers, set_levers, served, columns) judges
-- each lever, scenario_reason(body, levers) the scenario.
-- scenarios_of(scenarios_at, views_at, columns_at, m): every scenario
-- declared, judged over the levers it names (on metric m alone, or all
-- where NULL) — scenario, body (the one judged: a person's newest
-- annotation, else an agent's), annotated, applicable, reason, levers,
-- fix (the statement that annotates the scenario again, with the body
-- judged). scenarios(): the dataset's, as one read.
--===------------------------------------------------------------------===--

DECLARE ASPECT lever WITH $${
  "type": "object", "required": ["value"],
  "properties": {"value": {"type": "boolean"}, "basis": {"type": "string"}}
}$$ AS FACT ON COLUMN;

CREATE OR REPLACE MACRO main.judge_levers(levers, set_levers, served, columns) AS
  list_sort(list_transform(levers,
    lambda l: {'lever': l."column", 'metric': split_part(l."column", '.', 1),
               'column': substr(l."column", length(split_part(l."column", '.', 1)) + 2), 'factor': l.factor, 'basis': l.basis,
               'reason': CASE WHEN l."column" IS NULL OR substr(l."column", length(split_part(l."column", '.', 1)) + 2) = ''
                                THEN 'a lever names a served metric''s column, <metric>.<column>'
                              WHEN NOT list_contains(set_levers, l."column")
                                THEN l."column" || ' is not annotated as a lever: a lever is a column someone sets, annotated lever true on the metric''s view'
                              WHEN NOT list_contains(served, split_part(l."column", '.', 1))
                                THEN split_part(l."column", '.', 1) || ' is no served metric of this dataset'
                              WHEN NOT list_contains(columns, l."column")
                                THEN split_part(l."column", '.', 1) || ' serves no column named ' || substr(l."column", length(split_part(l."column", '.', 1)) + 2)
                              WHEN json_type(l.factor) <> 'OBJECT' THEN 'the factor on ' || l."column" || ' is a factor per period, {"YYYY-MM": 1.15}'
                         END}));

CREATE OR REPLACE MACRO main.scenario_reason(body, levers) AS
  CASE WHEN body IS NULL THEN 'declared and not annotated: a scenario is a factor per period on declared levers'
       WHEN len(levers) = 0 THEN 'the scenario names no lever'
       ELSE nullif(array_to_string(list_filter(list_transform(levers, lambda l: l.reason), lambda r: r IS NOT NULL), '; '), '') END;

CREATE OR REPLACE MACRO main.scenarios_of(scenarios_at, views_at, columns_at, m) AS TABLE
WITH bodies AS (
  SELECT property AS scenario, value AS body,
         from_json(json_extract(value, '$.levers'), '[{"column": "VARCHAR", "factor": "JSON", "basis": "VARCHAR"}]') AS named
  FROM annotations('x-kind scenario', scenarios_at) WHERE NOT contains(asset, '.') OR scenarios_at = 'itself'),
axes AS MATERIALIZED (SELECT view, applicable, columns FROM main.view_axes_of(views_at, columns_at)),
facts AS (
  SELECT (SELECT coalesce(list(split_part(asset, '.', 2) || '.' || split_part(asset, '.', 3)), []) FROM annotations('lever', columns_at)
          WHERE state = 'current' AND (value->>'value') = 'true') AS set_levers,
         (SELECT coalesce(list(view), []) FROM axes WHERE applicable) AS served,
         (SELECT coalesce(list(view || '.' || c), []) FROM axes, unnest(columns) t(c)) AS columns),
judged AS (
  SELECT b.scenario, b.body,
         coalesce(main.judge_levers(list_filter(b.named, lambda l: m IS NULL OR split_part(l."column", '.', 1) = m),
                                    f.set_levers, f.served, f.columns), []) AS levers
  FROM bodies b, facts f)
SELECT scenario, body, body IS NOT NULL AS annotated, main.scenario_reason(body, levers) IS NULL AS applicable,
       main.scenario_reason(body, levers) AS reason, levers,
       CASE WHEN body IS NOT NULL AND main.scenario_reason(body, levers) IS NOT NULL
            THEN '-- correct the levers, then annotate the scenario again:' || chr(10)
                 || main.gloss_statement(scenario, current_schema(), body::VARCHAR) END AS fix
FROM judged
WHERE m IS NULL OR len(levers) > 0
ORDER BY scenario;

CREATE OR REPLACE MACRO main.scenarios() AS TABLE
FROM main.scenarios_of('its dataset', 'the dataset''s metrics', 'the dataset''s metrics', NULL);

-- A scenario annotated on a dataset is an asset, <dataset>.<scenario>,
-- declared by that annotation, with an edge (sets) to each lever column
-- it names, and two places: 'its levers', those columns, and 'its
-- metrics', the metrics they belong to and their columns. The lineage
-- reads them through these three macros (SPEC §4); a result on a scenario
-- reads its own annotation, so a scenario declared or changed leaves the
-- others' results current.
CREATE OR REPLACE MACRO main.lineage_assets_scenario(dataset_name) AS TABLE
SELECT DISTINCT dataset_name || '.' || g.aspect AS asset, 'scenario' AS kind, dataset_name AS node_asset,
       'annotation ' || g.aspect AS node_what
FROM main.glossary g JOIN main.aspects a ON a.name = g.aspect AND json_extract_string(a.schema, '$.x-kind') = 'scenario'
WHERE g.dataset = dataset_name AND g.subject = dataset_name AND g.actor_kind IN ('human', 'agent');

CREATE OR REPLACE MACRO main.lineage_edges_scenario(dataset_name) AS TABLE
SELECT DISTINCT dataset_name || '.' || g.aspect AS "from", dataset_name || '.' || (l.lever->>'column') AS "to", 'sets' AS kind
FROM main.glossary g, unnest(coalesce(from_json(g.body->'levers', '["JSON"]'), [])) l(lever)
WHERE g.dataset = dataset_name AND g.subject = dataset_name AND g.actor_kind IN ('human', 'agent')
  AND g.aspect IN (SELECT name FROM main.aspects WHERE json_extract_string(schema, '$.x-kind') = 'scenario')
  AND l.lever->>'column' IS NOT NULL;

CREATE OR REPLACE MACRO main.lineage_places_scenario(dataset_name) AS TABLE
WITH e AS (SELECT "from", "to", split_part("to", '.', 2) AS metric FROM main.lineage_edges_scenario(dataset_name))
SELECT NULL::VARCHAR AS subject, u.w AS "where", NULL::VARCHAR AS asset FROM unnest(['its levers', 'its metrics']) u(w)
UNION ALL SELECT "from", 'its levers', "to" FROM e
UNION ALL SELECT DISTINCT "from", 'its metrics', dataset_name || '.' || metric FROM e
UNION ALL SELECT DISTINCT e."from", 'its metrics', dataset_name || '.' || c.table_name || '.' || c.column_name
FROM e JOIN glossql_columns(dataset_name) c ON c.table_name = e.metric;

--===------------------------------------------------------------------===--
-- The estimate, on a scenario: /whatif answers each metric on its own,
-- so a scenario's result holds one answer per metric it sets a lever on.
-- scenario_request_of(scenarios_at, views_at, columns_at, m): one row per
-- scenario of the place scenarios_at and metric (m alone where named) — grain (the metric's floor), additivity, origin
-- (the last complete actual, as the forecast's), the periods ahead up to
-- the end of the last period the scenario names, and per lever its
-- factor, its series (the mean of the column per period) and the value
-- held as planned (the last at or before the origin); reason where the
-- scenario names no period after the origin. lever_bodies_of(…): one
-- forecast request per scenario and lever, the lever's own series as
-- the member and the periods ahead as the horizon, within the forecast's
-- reach per grain. scenario_bodies_of(…, paths): one what-if request per
-- scenario as the service's contract spells it — the history as actual
-- rows, the periods ahead twice, as planned and under the scenario
-- (planned times the period's factor), every lever an input column. The
-- planned input is the lever's own forecast where paths carries one
-- ({"<scenario>|<lever>": [{period, value}]}, its last median held past
-- its reach), else the lever's last actual value held. No metric
-- definition is replayed over the data: the scenario world is the
-- estimate ahead.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.scenario_request_of(scenarios_at, views_at, columns_at, m) AS TABLE
WITH lv AS (
  SELECT s.scenario, u.l.lever AS lever, u.l.metric AS metric, u.l."column" AS col, u.l.factor AS factor
  FROM main.scenarios_of(scenarios_at, views_at, columns_at, m) s, unnest(s.levers) AS u(l) WHERE s.applicable),
axes AS (SELECT view AS metric, floor, period_column, additivity FROM main.view_axes_of(views_at, columns_at) WHERE applicable),
origins AS (SELECT metric, max(period) AS origin FROM main.complete_series_of(views_at, columns_at, NULL) GROUP BY metric),
-- the lever's series: the mean of the column per period at the metric's floor
lever_rows AS (
  SELECT l.scenario, l.lever, c.rn,
         max(CASE WHEN c."column" = a.period_column THEN TRY_CAST(c.val AS TIMESTAMP) END) AS instant,
         max(CASE WHEN c."column" = l.col THEN TRY_CAST(c.val AS DOUBLE) END) AS at_row
  FROM lv l JOIN axes a ON a.metric = l.metric
  JOIN dataset_cells(current_schema(), views_at) c ON c."table" = l.metric AND c."column" IN (a.period_column, l.col)
  GROUP BY l.scenario, l.lever, c.rn),
lever_series AS (
  SELECT r.scenario, r.lever, date_trunc(a.floor, r.instant) AS period, avg(r.at_row) AS value
  FROM lever_rows r JOIN lv l USING (scenario, lever) JOIN axes a ON a.metric = l.metric
  WHERE r.instant IS NOT NULL AND r.at_row IS NOT NULL
  GROUP BY r.scenario, r.lever, date_trunc(a.floor, r.instant)),
-- the end of the last period a lever's factor names
reach AS (
  SELECT l.scenario, l.metric, a.floor AS grain, a.additivity, o.origin,
         max(CASE WHEN len(k) = 7 THEN (k || '-01')::TIMESTAMP + INTERVAL 1 MONTH ELSE k::TIMESTAMP + INTERVAL 1 DAY END) AS until
  FROM lv l JOIN axes a USING (metric) LEFT JOIN origins o USING (metric), unnest(json_keys(l.factor)) AS u(k)
  GROUP BY l.scenario, l.metric, a.floor, a.additivity, o.origin),
judged AS (
  SELECT r.*,
         CASE WHEN r.origin IS NULL THEN r.metric || ' has no complete ' || r.grain || ' in its series yet'
              WHEN r.until <= r.origin + main.grain_step(r.grain)
                THEN 'the scenario names no period after ' || strftime(r.origin, '%Y-%m-%d') || ', the last actual of ' || r.metric END AS reason
  FROM reach r),
ahead AS (
  SELECT j.scenario, j.metric, list(g.p ORDER BY g.p) AS periods
  FROM judged j, unnest(generate_series(j.origin + main.grain_step(j.grain), j.until - main.grain_step(j.grain), main.grain_step(j.grain))) AS g(p)
  WHERE j.reason IS NULL GROUP BY j.scenario, j.metric),
inputs AS (
  SELECT l.scenario, l.metric,
         list({'lever': l.lever, 'factor': l.factor,
               'planned': (SELECT arg_max(ls.value, ls.period) FROM lever_series ls, judged j
                           WHERE ls.scenario = l.scenario AND ls.lever = l.lever AND j.scenario = l.scenario AND j.metric = l.metric
                             AND ls.period <= j.origin),
               'series': (SELECT coalesce(list({'period': ls.period, 'value': ls.value} ORDER BY ls.period), [])
                          FROM lever_series ls WHERE ls.scenario = l.scenario AND ls.lever = l.lever)} ORDER BY l.lever) AS levers
  FROM lv l GROUP BY l.scenario, l.metric)
SELECT j.scenario, j.metric, j.grain, j.additivity, j.origin, j.reason, j.reason IS NULL AS applicable,
       coalesce(a.periods, []::TIMESTAMP[]) AS ahead, i.levers
FROM judged j LEFT JOIN ahead a USING (scenario, metric) JOIN inputs i USING (scenario, metric)
ORDER BY j.scenario, j.metric;

CREATE OR REPLACE MACRO main.scenario_request() AS TABLE
FROM main.scenario_request_of('its dataset', 'the dataset''s metrics', 'the dataset''s metrics', NULL);

CREATE OR REPLACE MACRO main.lever_bodies_of(scenarios_at, views_at, columns_at, m) AS TABLE
WITH lv AS (
  SELECT r.scenario, r.grain, r.ahead, u.l.lever AS lever, u.l.series AS series,
         least(len(r.ahead), CASE r.grain WHEN 'day' THEN 31 WHEN 'week' THEN 13 WHEN 'month' THEN 12 WHEN 'quarter' THEN 4 ELSE 0 END) AS horizon
  FROM main.scenario_request_of(scenarios_at, views_at, columns_at, m) r, unnest(r.levers) AS u(l) WHERE r.applicable),
rows_ AS (
  SELECT l.scenario, l.lever, sp.s.period AS period, sp.s.value AS value, 'actual' AS status
  FROM lv l, unnest(l.series) AS sp(s)
  UNION ALL
  SELECT l.scenario, l.lever, ap.p, NULL::DOUBLE, 'forecast'
  FROM lv l, unnest(l.ahead[1:l.horizon]) AS ap(p))
SELECT l.scenario, l.lever, l.grain, l.horizon,
       json_object('spec', json_object('targets', ['value'], 'horizon', l.horizon, 'levels', [0.5], 'grain', l.grain),
                   'table', json_object('member', list(l.lever ORDER BY w.period, w.status), 'period', list(strftime(w.period, '%Y-%m-%d') ORDER BY w.period, w.status),
                                        'status', list(w.status ORDER BY w.period, w.status), 'value', list(w.value ORDER BY w.period, w.status))) AS body
FROM lv l JOIN rows_ w USING (scenario, lever)
WHERE l.horizon > 0
GROUP BY l.scenario, l.lever, l.grain, l.horizon
ORDER BY l.scenario, l.lever;

CREATE OR REPLACE MACRO main.scenario_bodies_of(scenarios_at, views_at, columns_at, m, paths) AS TABLE
WITH r AS (SELECT * FROM main.scenario_request_of(scenarios_at, views_at, columns_at, m) WHERE applicable),
hist AS (
  SELECT r.scenario, r.metric, s.period, 'actual' AS status, s.value, 0 AS ord
  FROM r JOIN main.complete_series_of(views_at, columns_at, NULL) s USING (metric)),
ahead AS (
  SELECT r.scenario, r.metric, u.p AS period, st.status, NULL::DOUBLE AS value, st.ord
  FROM r, unnest(r.ahead) AS u(p), (VALUES ('plan', 1), ('scenario', 2)) st(status, ord)),
rows_ AS (SELECT * FROM hist UNION ALL SELECT * FROM ahead),
inputs AS (
  SELECT r.scenario, r.metric, u.l.lever AS lever, u.l.factor AS factor, u.l.planned AS held, u.l.series AS series,
         from_json(coalesce(json_extract(paths, '$."' || r.scenario || '|' || u.l.lever || '"'), '[]'::JSON),
                   '[{"period": "VARCHAR", "value": "DOUBLE"}]') AS path
  FROM r, unnest(r.levers) AS u(l)),
-- the input at a row: its actual value in the history; as planned, the lever's forecast median there (its last
-- median past the forecast's reach), else the held value; under the scenario, the planned value times the factor
input_cells AS (
  SELECT w.scenario, w.metric, i.lever, w.period, w.ord,
         CASE w.status WHEN 'actual' THEN list_extract(list_filter(i.series, lambda e: e.period = w.period), 1).value
                       ELSE CASE WHEN len(i.path) > 0
                                 THEN coalesce(list_extract(list_filter(i.path, lambda e: e.period::TIMESTAMP = w.period), 1).value, i.path[-1].value)
                                 ELSE i.held END
                            * CASE WHEN w.status = 'scenario'
                                   THEN coalesce(json_extract(i.factor, '$."' || strftime(w.period, '%Y-%m-%d') || '"')::DOUBLE,
                                                 json_extract(i.factor, '$."' || strftime(w.period, '%Y-%m') || '"')::DOUBLE, 1.0)
                                   ELSE 1.0 END END AS value
  FROM rows_ w JOIN inputs i USING (scenario, metric)),
base AS (
  SELECT w.scenario, w.metric,
         json_object('member', list(w.metric ORDER BY w.period, w.ord), 'period', list(strftime(w.period, '%Y-%m-%d') ORDER BY w.period, w.ord),
                     'status', list(w.status ORDER BY w.period, w.ord), 'value', list(w.value ORDER BY w.period, w.ord)) AS cols
  FROM rows_ w GROUP BY w.scenario, w.metric),
levered AS (
  SELECT scenario, metric, json_group_object(lever, vals) AS cols
  FROM (SELECT scenario, metric, lever, list(value ORDER BY period, ord) AS vals FROM input_cells GROUP BY scenario, metric, lever)
  GROUP BY scenario, metric)
SELECT b.scenario, b.metric,
       json_object('spec', json_object('targets', ['value'], 'levels', [0.1, 0.5, 0.9]), 'table', json_merge_patch(b.cols, l.cols)) AS body
FROM base b JOIN levered l USING (scenario, metric)
ORDER BY b.scenario, b.metric;

--===------------------------------------------------------------------===--
-- metric_scenario: the estimate's answer on a scenario: its judgement
-- (applicable, reason) and per metric it sets a lever on: its levers
-- (each with where its planned value came from), the service's sign,
-- basis, explains and error, the code of what it could not answer, the
-- points ahead (period, low, value, high at the 10, 50 and 90 levels
-- under the scenario; baseline, the median as planned; effect, the
-- service's difference of the two; the history's own reading with its
-- 90% interval) and the parts (per lever, what it alone does by the
-- history). No coverage is stated for a what-if range.
-- scenario_points(s): the stored estimates, one row per scenario (or
-- every one, NULL), metric and period ahead; a metric not estimated is
-- one row with its reason, a run that failed one row for its scenario
-- with its error (the service's error of the level is level_error).
-- scenario_levers(s): the parts.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_scenario WITH $${
  "description": "Preview. A scenario's estimate of each metric it sets a lever on, as the model service answers it.",
  "type": "object",
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "scenario": {"type": "string"},
    "applicable": {"type": "boolean"},
    "reason": {"type": ["string", "null"]},
    "metrics": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT;

DECLARE FUNCTION metric_scenario FOR GLOBAL AS $$
  WITH sc AS (SELECT * FROM main.scenarios_of('itself', 'its metrics', 'its metrics', NULL)),
  refusal AS (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM sc)
                THEN error('not_a_scenario: ' || $subject || ' is no scenario: metric_scenario() estimates a scenario, <dataset>.<scenario>, annotated with a factor per period on declared levers') END AS r),
  req AS (SELECT * FROM main.scenario_request_of('itself', 'its metrics', 'its metrics', NULL)),
  -- each lever's own forecast: where the service answers no median, the lever is held
  lf AS (SELECT scenario, lever, main.service('/forecast', body) AS fa
         FROM main.lever_bodies_of('itself', 'its metrics', 'its metrics', NULL)),
  medians AS (
    SELECT scenario, lever,
           unnest(json_extract(fa, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(fa, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(fa, '$.table.value')::DOUBLE[]) AS value
    FROM lf),
  paths AS (
    SELECT scenario, lever, list({'period': period, 'value': value} ORDER BY period) AS path
    FROM medians WHERE level = 0.5 AND period IS NOT NULL AND value IS NOT NULL GROUP BY scenario, lever),
  planned_json AS (SELECT json_group_object(scenario || '|' || lever, path) AS j FROM paths),
  planned_from AS (
    SELECT r.metric, u.l.lever AS lever,
           CASE WHEN p.lever IS NOT NULL THEN 'forecast'
                WHEN lf.lever IS NULL THEN 'held: the lever is not forecast at this grain'
                ELSE 'held: ' || coalesce(main.service_reason(main.answer_errors(lf.fa)[1].code, main.answer_errors(lf.fa)[1].needed,
                                                              main.answer_errors(lf.fa)[1].given), 'the forecast answered no median') END AS planned_from
    FROM req r, unnest(r.levers) AS u(l)
    LEFT JOIN lf ON lf.scenario = r.scenario AND lf.lever = u.l.lever
    LEFT JOIN paths p ON p.scenario = r.scenario AND p.lever = u.l.lever),
  b AS (SELECT scenario, metric, main.service('/whatif', body) AS a
        FROM main.scenario_bodies_of('itself', 'its metrics', 'its metrics', NULL, (SELECT j FROM planned_json))),
  rows_ AS (
    SELECT b.metric,
           unnest(json_extract(a, '$.table.member')::VARCHAR[]) AS member,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.status')::VARCHAR[]) AS status,
           unnest(json_extract(a, '$.table.column')::VARCHAR[]) AS target,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value,
           unnest(json_extract(a, '$.table.effect')::DOUBLE[]) AS effect,
           unnest(json_extract(a, '$.table.history_value')::DOUBLE[]) AS history_value,
           unnest(json_extract(a, '$.table.history_low')::DOUBLE[]) AS history_low,
           unnest(json_extract(a, '$.table.history_high')::DOUBLE[]) AS history_high,
           unnest(json_extract(a, '$.table.sign')::VARCHAR[]) AS sign,
           unnest(json_extract(a, '$.table.basis')::VARCHAR[]) AS basis,
           unnest(json_extract(a, '$.table.explains')::DOUBLE[]) AS explains,
           unnest(json_extract(a, '$.table.error')::DOUBLE[]) AS error
    FROM b),
  points AS (
    SELECT metric, period,
           max(CASE WHEN status = 'scenario' AND level = 0.1 THEN value END) AS low,
           max(CASE WHEN status = 'scenario' AND level = 0.5 THEN value END) AS value,
           max(CASE WHEN status = 'scenario' AND level = 0.9 THEN value END) AS high,
           max(CASE WHEN status = 'plan' AND level = 0.5 THEN value END) AS baseline,
           any_value(effect) FILTER (WHERE status = 'scenario') AS effect,
           any_value(history_value) FILTER (WHERE status = 'scenario') AS history_value,
           any_value(history_low) FILTER (WHERE status = 'scenario') AS history_low,
           any_value(history_high) FILTER (WHERE status = 'scenario') AS history_high
    FROM rows_ WHERE member = metric AND status IN ('scenario', 'plan') AND target = 'value' AND period IS NOT NULL
    GROUP BY metric, period
    HAVING count(*) FILTER (WHERE status = 'scenario') > 0),
  said AS (
    SELECT metric, any_value(sign) AS sign, any_value(basis) AS basis, any_value(explains) AS explains, any_value(error) AS error
    FROM rows_ WHERE member = metric AND target = 'value' GROUP BY metric),
  parts AS (
    SELECT b.metric, u.p.input AS lever, u.p.history_shift AS history_shift, u.p.history_low AS history_low, u.p.history_high AS history_high
    FROM b, unnest(from_json(json_extract(a, '$.answer.parts'),
           '[{"member": "VARCHAR", "column": "VARCHAR", "input": "VARCHAR", "history_shift": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}]')) AS u(p)
    WHERE u.p.member = b.metric AND u.p."column" = 'value'),
  failed AS (
    SELECT b.metric, list(u.e ORDER BY u.e.code) AS errors
    FROM b, unnest(main.answer_errors(b.a)) AS u(e) WHERE u.e.member = b.metric GROUP BY b.metric),
  -- the metrics its levers name, each with its own levers judged
  named AS (
    SELECT u.l.metric AS metric, list(u.l ORDER BY u.l.lever) AS judged
    FROM sc s, unnest(s.levers) AS u(l) WHERE u.l.metric IS NOT NULL AND u.l.metric <> '' GROUP BY u.l.metric),
  per_metric AS (
    SELECT n.metric, n.judged, r.grain, r.origin,
           s.applicable AND r.applicable AND EXISTS (SELECT 1 FROM points p WHERE p.metric = n.metric) AS applicable,
           CASE WHEN NOT s.applicable THEN s.reason
                WHEN r.metric IS NULL THEN n.metric || ' is not estimated: none of its levers is judged applicable'
                WHEN NOT r.applicable THEN r.reason
                WHEN NOT EXISTS (SELECT 1 FROM points p WHERE p.metric = n.metric)
                  THEN coalesce(main.service_reason(f.errors[1].code, f.errors[1].needed, f.errors[1].given), 'the service answered no point') END AS reason,
           CASE WHEN s.applicable AND r.applicable AND NOT EXISTS (SELECT 1 FROM points p WHERE p.metric = n.metric) THEN f.errors[1].code END AS code,
           d.sign, d.basis, d.explains, d.error
    FROM named n CROSS JOIN sc s LEFT JOIN req r ON r.metric = n.metric LEFT JOIN said d ON d.metric = n.metric
    LEFT JOIN failed f ON f.metric = n.metric)
  SELECT coalesce((SELECT r FROM refusal)::VARCHAR,
                  (SELECT string_agg(DISTINCT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version'), ', ') FROM b)) AS served_by,
         split_part($subject, '.', 2) AS scenario,
         (SELECT applicable FROM sc) AS applicable, (SELECT reason FROM sc) AS reason,
         (SELECT coalesce(list({'metric': m.metric, 'grain': m.grain, 'origin': strftime(m.origin, '%Y-%m-%d'),
                                'applicable': m.applicable, 'reason': m.reason, 'code': m.code,
                                'levers': (SELECT list({'lever': l.lever, 'basis': l.basis, 'reason': l.reason,
                                                        'planned_from': (SELECT pf.planned_from FROM planned_from pf WHERE pf.metric = m.metric AND pf.lever = l.lever)}
                                                       ORDER BY l.lever) FROM unnest(m.judged) AS u(l)),
                                'sign': m.sign, 'basis': m.basis, 'explains': m.explains, 'error': m.error,
                                'points': (SELECT coalesce(list({'period': p.period, 'low': p.low, 'value': p.value, 'high': p.high, 'baseline': p.baseline,
                                                                 'effect': p.effect, 'history_value': p.history_value, 'history_low': p.history_low,
                                                                 'history_high': p.history_high} ORDER BY p.period), [])
                                           FROM points p WHERE p.metric = m.metric),
                                'parts': (SELECT coalesce(list({'lever': pt.lever, 'history_shift': pt.history_shift, 'history_low': pt.history_low,
                                                                'history_high': pt.history_high} ORDER BY pt.lever), [])
                                          FROM parts pt WHERE pt.metric = m.metric)} ORDER BY m.metric), [])
          FROM per_metric m) AS metrics
$$ RETURNS metric_scenario;

-- scenario_rows(s): the stored estimates, typed, one row per scenario and metric
CREATE OR REPLACE MACRO main.scenario_rows(s) AS TABLE
WITH stored AS (
  SELECT value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_scenario' AND value IS NOT NULL),
typed AS (
  SELECT computed_at, json_extract_string(value, '$.served_by') AS served_by, json_extract_string(value, '$.scenario') AS scenario,
         unnest(from_json(json_extract(value, '$.metrics'),
           '[{"metric": "VARCHAR", "grain": "VARCHAR", "origin": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "code": "VARCHAR",
              "levers": [{"lever": "VARCHAR", "planned_from": "VARCHAR"}], "sign": "VARCHAR", "basis": "VARCHAR", "explains": "DOUBLE", "error": "DOUBLE",
              "points": [{"period": "VARCHAR", "low": "DOUBLE", "value": "DOUBLE", "high": "DOUBLE", "baseline": "DOUBLE", "effect": "DOUBLE",
                          "history_value": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}],
              "parts": [{"lever": "VARCHAR", "history_shift": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}]}]')) AS mt
  FROM stored)
SELECT computed_at, served_by, mt.metric AS metric, struct_insert(mt, scenario := scenario) AS sc
FROM typed WHERE s IS NULL OR scenario = s;

CREATE OR REPLACE MACRO main.scenario_points(s) AS TABLE
WITH stepped AS (
  SELECT r.*, unnest(r.sc.points) AS p, unnest(generate_series(1, len(r.sc.points))) AS step
  FROM main.scenario_rows(s) r WHERE len(r.sc.points) > 0),
-- a run that failed stores no metric: it is one row for its scenario
failed AS (
  SELECT split_part(subject, '.', 2) AS scenario, error, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_scenario' AND value IS NULL AND error IS NOT NULL
    AND subject IN (SELECT asset FROM main.lineage_assets_scenario(current_schema())))
SELECT sc.scenario, metric, sc.grain, sc.origin, sc.applicable, sc.reason, sc.code, list_transform(sc.levers, lambda l: l.lever) AS levers,
       step, p.period::TIMESTAMP AS period, p.low, p.value, p.high, p.baseline, p.effect, p.history_value, p.history_low, p.history_high,
       sc.sign, sc.basis, sc.explains, sc.error AS level_error, served_by, computed_at, NULL::VARCHAR AS error
FROM stepped
UNION ALL
SELECT sc.scenario, metric, sc.grain, sc.origin, sc.applicable, sc.reason, sc.code, list_transform(sc.levers, lambda l: l.lever),
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, sc.sign, sc.basis, sc.explains, sc.error, served_by, computed_at, NULL
FROM main.scenario_rows(s) WHERE coalesce(len(sc.points), 0) = 0
UNION ALL
SELECT f.scenario, NULL, NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, f.computed_at, f.error
FROM failed f
WHERE s IS NULL OR f.scenario = s
ORDER BY scenario NULLS FIRST, metric, step NULLS FIRST;

CREATE OR REPLACE MACRO main.scenario_levers(s) AS TABLE
SELECT r.sc.scenario AS scenario, r.metric, r.sc.applicable AS applicable, r.sc.reason AS reason, r.sc.sign AS sign,
       l.l.lever AS lever, l.l.planned_from AS planned_from,
       list_extract(list_filter(r.sc.parts, lambda p: p.lever = l.l.lever), 1).history_shift AS history_shift,
       list_extract(list_filter(r.sc.parts, lambda p: p.lever = l.l.lever), 1).history_low AS history_low,
       list_extract(list_filter(r.sc.parts, lambda p: p.lever = l.l.lever), 1).history_high AS history_high,
       r.computed_at
FROM main.scenario_rows(s) r, unnest(r.sc.levers) AS l(l)
ORDER BY scenario, metric, lever;

-- The scenario world under the metric, metric_series(world := 'scenario',
-- scenario := '<name>'): the estimate's medians ahead, refused by name
-- where no scenario is named or none of that name is declared.
CREATE OR REPLACE MACRO main.world_scenario(w, s, g) AS TABLE
WITH refusal AS (
  SELECT CASE WHEN w = 'scenario' AND s IS NULL THEN error('scenario_not_named: metric_series(world := ''scenario'') names the scenario it serves, scenario := ''<name>'' — a scenario is a FACT aspect declared with x-kind scenario, annotated with a factor per period on declared levers')
              WHEN w = 'scenario' AND NOT EXISTS (SELECT 1 FROM main.scenarios() WHERE scenario = s) THEN error(
                'unknown_scenario: metric_series(scenario := ''' || s || '''): no scenario of that name is declared — a scenario is a FACT aspect declared with x-kind scenario') END AS r)
SELECT sp.metric, 'scenario' AS world, '' AS dimension, '' AS member, sp.period, sp.value,
       NULL::DOUBLE AS num, NULL::DOUBLE AS den, coalesce(a.additivity, 'none') AS additivity
FROM main.scenario_points(s) sp LEFT JOIN main.view_summary() a ON a.view = sp.metric
WHERE w = 'scenario' AND sp.applicable AND sp.value IS NOT NULL AND (g IS NULL OR g = sp.grain)
UNION ALL SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM refusal WHERE r IS NOT NULL;
