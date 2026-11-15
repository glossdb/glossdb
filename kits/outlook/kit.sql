-- The outlook kit: the worlds beside the actual — the backtest's ranges and the
-- forecast, each what the model service answers; the plan, judged against
-- them — each stored as a measurement with its provenance, and read
-- back as SQL, so that the `next` read judges from the catalog and
-- never computes over the data. Loaded after the metrics kit, whose
-- series the requests are built from. The service is named once for the instance
-- (glossql_service_url, glossql_service_token); every call goes through
-- main.service, one macro over glossql_service, so a suite holds in for
-- the service by re-declaring the macro. The service owns its topic: the
-- ranges, the PIT and why it is withheld, the backtest's result; the kit owns
-- the calendar, and sends complete periods only.
--
--   FROM glossql_kit('kits/kpi/kit.sql');
--   FROM glossql_kit('kits/quality/kit.sql');
--   FROM glossql_kit('kits/views/kit.sql');
--   FROM glossql_kit('kits/outlook/kit.sql');

CREATE OR REPLACE MACRO main.service(path, body) AS glossql_service(path, body);
-- the soft form: a refusal or an absent service comes back as {"error": "…"}, for a call the kit can stand without
CREATE OR REPLACE MACRO main.service_soft(path, body) AS glossql_service(path, body, true);

--===------------------------------------------------------------------===--
-- The series the service is sent. partial_periods(g): per metric, the
-- period at grain g (its own floor where NULL) that its data ends
-- inside, where its rows land finer than that grain: a short sum against
-- a range fitted on whole periods reads as a breach that is only the
-- calendar. complete_series(g): every applicable metric's total at
-- grain g (its floor where NULL) without that last period — metric,
-- period, value, additivity. The backtest, the forecast and the scenario
-- all read it, so they drop the same period.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.partial_periods_of(metrics_at, g) AS TABLE
WITH axes AS (
  SELECT view AS metric, period_column, coalesce(g, floor) AS at_grain
  FROM main.view_axes_of(metrics_at) WHERE applicable AND coalesce(kind, '') <> 'plan'),
edges AS (
  SELECT c."table" AS metric, any_value(a.at_grain) AS at_grain, max(TRY_CAST(c.val AS TIMESTAMP)) AS edge,
         count(DISTINCT date_trunc('day', TRY_CAST(c.val AS TIMESTAMP)))
           > count(DISTINCT date_trunc(a.at_grain, TRY_CAST(c.val AS TIMESTAMP))) AS finer
  FROM dataset_cells(current_schema(), metrics_at) c JOIN axes a ON a.metric = c."table" AND a.period_column = c."column"
  GROUP BY c."table")
SELECT metric, date_trunc(at_grain, edge) AS period FROM edges
WHERE finer AND edge::DATE < (date_trunc(at_grain, edge) + main.grain_step(at_grain) - INTERVAL 1 DAY)::DATE;

CREATE OR REPLACE MACRO main.partial_periods(g) AS TABLE FROM main.partial_periods_of('the dataset''s metrics', g);

CREATE OR REPLACE MACRO main.complete_series(g) AS TABLE
WITH s AS (
  SELECT metric, period, value, additivity, max(period) OVER (PARTITION BY metric) AS last
  FROM main.actual_series(grain := g, unclaimed := 'skip')
  WHERE dimension = '' AND world = 'actual' AND value IS NOT NULL)
SELECT s.metric, s.period, s.value, s.additivity FROM s
WHERE NOT (s.period = s.last
           AND EXISTS (SELECT 1 FROM main.partial_periods(g) p WHERE p.metric = s.metric AND p.period = s.period));

--===------------------------------------------------------------------===--
-- The levers and the scenarios. A lever is a FACT on a column of a
-- metric's view; a scenario is judged against the levers set, the metrics
-- served and their columns (both described with the scenario, below):
-- judge_levers(body, set_levers, served, columns) judges each lever the
-- scenario's body names, scenario_reason(body, levers) the scenario.
-- scenarios(): every scenario declared, judged — scenario, annotated,
-- applicable, reason, levers. read_scenarios(): the same as a function's
-- body reads it, through the read functions: the scenarios and the levers
-- annotated on the dataset, the metrics' axes. outlook_due(): per preview
-- measurement, stored (a result exists), due (none exists, or the stored
-- one is out of date by the catalog's rule, as any result) and needed
-- (outlook_measurements()).
--===------------------------------------------------------------------===--

DECLARE ASPECT lever WITH $${
  "type": "object", "required": ["value"],
  "properties": {"value": {"type": "boolean"}, "basis": {"type": "string"}}
}$$ AS FACT ON COLUMN;

CREATE OR REPLACE MACRO main.judge_levers(body, set_levers, served, columns) AS
  list_sort(list_transform(
    from_json(json_extract(body, '$.levers'), '[{"column": "VARCHAR", "factor": "JSON", "basis": "VARCHAR"}]'),
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

CREATE OR REPLACE MACRO main.scenarios() AS TABLE
WITH bodies AS (
  SELECT a.name AS scenario, g.value AS body
  FROM main.aspects a
  LEFT JOIN glossql_glossary(current_schema(), NULL, false) g ON g.aspect = a.name AND g.subject = current_schema()
  WHERE json_extract_string(a.schema, '$.x-kind') = 'scenario'),
facts AS (
  SELECT (SELECT coalesce(list(split_part(subject, '.', 2) || '.' || split_part(subject, '.', 3)), []) FROM glossql_glossary(current_schema(), 'lever', false)
          WHERE state = 'current' AND (value->>'value') = 'true') AS set_levers,
         (SELECT coalesce(list(view), []) FROM main.view_rows() WHERE applicable AND coalesce(kind, '') NOT IN ('plan', 'scalar', 'relation')) AS served,
         (SELECT coalesce(list(table_name || '.' || column_name), []) FROM glossql_columns(current_schema())) AS columns),
judged AS (
  SELECT b.scenario, b.body, coalesce(main.judge_levers(b.body, f.set_levers, f.served, f.columns), []) AS levers FROM bodies b, facts f)
SELECT scenario, body IS NOT NULL AS annotated, main.scenario_reason(body, levers) IS NULL AS applicable,
       main.scenario_reason(body, levers) AS reason, levers
FROM judged ORDER BY scenario;

CREATE OR REPLACE MACRO main.read_scenarios() AS TABLE
WITH bodies AS (
  SELECT property AS scenario, value AS body FROM annotations('x-kind scenario', 'the dataset') WHERE NOT contains(asset, '.')),
axes AS MATERIALIZED (SELECT view, kind, applicable, columns FROM main.view_axes()),
facts AS (
  SELECT (SELECT coalesce(list(split_part(asset, '.', 2) || '.' || split_part(asset, '.', 3)), []) FROM annotations('lever', 'the dataset''s metrics')
          WHERE state = 'current' AND (value->>'value') = 'true') AS set_levers,
         (SELECT coalesce(list(view), []) FROM axes WHERE applicable AND coalesce(kind, '') NOT IN ('plan', 'scalar', 'relation')) AS served,
         (SELECT coalesce(list(view || '.' || c), []) FROM axes, unnest(columns) t(c)) AS columns),
judged AS (
  SELECT b.scenario, b.body, coalesce(main.judge_levers(b.body, f.set_levers, f.served, f.columns), []) AS levers FROM bodies b, facts f)
SELECT scenario, body IS NOT NULL AS annotated, main.scenario_reason(body, levers) IS NULL AS applicable,
       main.scenario_reason(body, levers) AS reason, levers
FROM judged ORDER BY scenario;

CREATE OR REPLACE MACRO main.outlook_due() AS TABLE
WITH v AS MATERIALIZED (SELECT view, kind, stopped, applicable FROM main.view_rows()),
live AS (SELECT coalesce(current_setting('glossql_service_url'), '') <> '' AS named),
-- what the dataset needs, where a model service is named and a metric is served
has AS (
  SELECT live.named AND EXISTS (SELECT 1 FROM v WHERE stopped IS NULL AND applicable AND coalesce(kind, '') NOT IN ('scalar', 'relation', 'plan')) AS metric,
         EXISTS (SELECT 1 FROM v WHERE kind = 'plan' AND applicable) AS plan,
         EXISTS (SELECT 1 FROM main.scenarios() WHERE applicable) AS scenario
  FROM live),
needed AS (
  SELECT 'metric_ranges' AS name, metric AS needed FROM has
  UNION ALL SELECT 'metric_forecast', metric AND (plan OR scenario) FROM has
  UNION ALL SELECT 'metric_scenario', metric AND scenario FROM has),
stored AS (
  SELECT function AS name, bool_and(r.current) AS current
  FROM main.measurements m
  LEFT JOIN (SELECT aspect, current FROM glossql_glossary(current_schema(), NULL, true) WHERE actor = 'function' AND subject = current_schema()) r
    ON r.aspect = m.function
  WHERE m.dataset = current_schema() AND m.subject = current_schema() AND m.function IN ('metric_ranges', 'metric_forecast', 'metric_scenario')
  GROUP BY function)
SELECT n.name, s.name IS NOT NULL AS stored, s.name IS NULL OR NOT coalesce(s.current, true) AS due, n.needed
FROM needed n LEFT JOIN stored s USING (name);

--===------------------------------------------------------------------===--
-- The backtest. range_series(): every applicable metric's total at month
-- grain as the backtest sends it, complete months only. range_request():
-- one row per metric — additivity, the complete months, and applicable,
-- whether the backtest can take it: seven complete months at least, so
-- that one origin has the six known values the service needs.
-- range_body(): the request as the service's contract spells it, one
-- table and a specification. The red line is the test's: range_breach
-- judges the stored score against the test's threshold at read.
--===------------------------------------------------------------------===--

-- no_series_reason(metric, value_column, additivity, additivity_state,
-- grain): why complete_series() holds no period of a served metric at a
-- grain: its rows must be combined and no additivity is in force (the
-- series leaves such a metric out), or no period is complete yet.
CREATE OR REPLACE MACRO main.no_series_reason(m, value_column, additivity, additivity_state, g) AS
  CASE WHEN additivity IS NULL
       THEN CASE WHEN additivity_state = 'conflict' THEN 'the additivity on ' ELSE 'no additivity is annotated on ' END
            || current_schema() || '.' || m || '.' || value_column || ', so its rows cannot be combined by ' || g || ': '
            || main.gloss_statement('additivity', current_schema() || '.' || m || '.' || value_column, '{"value": "<additive|semi-additive|ratio|non-additive>"}')
       WHEN additivity = 'non-additive' THEN m || ' is non-additive and has several rows per ' || g || ', which cannot be combined'
       ELSE m || ' has no complete ' || g || ' yet' END;

CREATE OR REPLACE MACRO main.range_series() AS TABLE
SELECT metric, period, value, additivity FROM main.complete_series('month') ORDER BY metric, period;

CREATE OR REPLACE MACRO main.range_request() AS TABLE
WITH counted AS (SELECT metric, count(*) AS months FROM main.range_series() GROUP BY metric)
SELECT a.metric, a.additivity, coalesce(c.months, 0) AS months,
       a.applicable AND coalesce(c.months, 0) >= 7 AS applicable,
       CASE WHEN NOT a.applicable THEN a.reason
            WHEN c.metric IS NULL AND main.grain_rank(a.floor) > main.grain_rank('month')
              THEN a.metric || ' is served by ' || a.floor || ', and expected ranges are computed by month'
            WHEN c.metric IS NULL THEN main.no_series_reason(a.metric, a.value_column, a.additivity, a.additivity_state, 'month')
            WHEN c.months < 7 THEN 'a backtest needs seven complete months, and ' || a.metric || ' has ' || c.months END AS reason
FROM (SELECT * RENAME (view AS metric) FROM main.view_axes()) a LEFT JOIN counted c USING (metric)
WHERE coalesce(a.kind, '') NOT IN ('scalar', 'relation', 'plan', 'sample', 'scenario')
ORDER BY a.metric;

CREATE OR REPLACE MACRO main.range_body() AS TABLE
WITH s AS (SELECT * FROM main.range_series() WHERE metric IN (SELECT metric FROM main.range_request() WHERE applicable))
SELECT CASE WHEN count(s.metric) > 0 THEN json_object(
         'spec', json_object('targets', ['value'], 'origins', 6, 'horizon', 1,
                             'levels', [0.05, 0.1, 0.5, 0.9, 0.95], 'grain', 'month'),
         'table', json_object('member', list(s.metric ORDER BY s.metric, s.period),
                              'period', list(strftime(s.period, '%Y-%m') ORDER BY s.metric, s.period),
                              'status', list('actual' ORDER BY s.metric, s.period),
                              'value', list(s.value ORDER BY s.metric, s.period))) END AS body
FROM (SELECT 1) one LEFT JOIN s ON true;

--===------------------------------------------------------------------===--
-- metric_ranges: the backtest as a measurement on the dataset. served_by
-- names the service and its version; score, state and threshold are the
-- service's result over every metric backtested; metrics holds one row per
-- metric — applicable and reason, additivity, backtested (how many months
-- were predicted from the months before them), held_80 and held_90 (the
-- share of those months inside the 10-90 and the 5-95 range), newest (the
-- latest of them: period, pit, displacement, withheld), errors (the
-- origins the service could not predict from, in its words) and points,
-- one per backtested month: period, actual, p05 to p95, pit, withheld.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_ranges WITH $${
  "description": "Preview. The newest complete period of each metric against the range its own history predicted.",
  "type": "object",
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "grain": {"type": "string"},
    "score": {"type": ["number", "null"]},
    "state": {"type": ["string", "null"]},
    "threshold": {"type": ["number", "null"]},
    "metrics": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT ON DATASET;

DECLARE FUNCTION metric_ranges FOR GLOBAL AS $$
  WITH req AS (SELECT * FROM main.range_request()),
  b AS (SELECT body FROM main.range_body()),
  a AS (SELECT CASE WHEN body IS NOT NULL THEN main.service('/forecast', body) END AS a FROM b),
  rows_ AS (
    SELECT unnest(json_extract(a, '$.table.member')::VARCHAR[]) AS metric,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value,
           unnest(json_extract(a, '$.table.actual')::DOUBLE[]) AS actual,
           unnest(json_extract(a, '$.table.pit')::DOUBLE[]) AS pit,
           unnest(coalesce(json_extract(a, '$.table.withheld')::VARCHAR[],
                           list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::VARCHAR))) AS withheld
    FROM a WHERE a IS NOT NULL),
  points AS (
    SELECT metric, period, any_value(actual) AS actual,
           max(CASE WHEN level = 0.05 THEN value END) AS p05, max(CASE WHEN level = 0.1 THEN value END) AS p10,
           max(CASE WHEN level = 0.5 THEN value END) AS p50, max(CASE WHEN level = 0.9 THEN value END) AS p90,
           max(CASE WHEN level = 0.95 THEN value END) AS p95,
           any_value(pit) AS pit, any_value(withheld) AS withheld
    FROM rows_ WHERE period IS NOT NULL GROUP BY metric, period),
  results AS (
    SELECT v.member AS metric, v.backtested, v.held_80, v.held_90, v.newest
    FROM (SELECT unnest(from_json(json_extract(a, '$.answer.backtest.members'),
            '[{"member": "VARCHAR", "column": "VARCHAR", "backtested": "BIGINT", "held_80": "DOUBLE", "held_90": "DOUBLE", "newest": {"origin": "VARCHAR", "period": "VARCHAR", "pit": "DOUBLE", "displacement": "DOUBLE", "withheld": "VARCHAR"}}]')) AS v
          FROM a WHERE a IS NOT NULL)),
  failures AS (
    SELECT e.member AS metric, list(e.error ORDER BY e.origin) AS errors
    FROM (SELECT unnest(from_json(json_extract(a, '$.answer.errors'),
            '[{"member": "VARCHAR", "column": "VARCHAR", "origin": "VARCHAR", "error": "VARCHAR"}]')) AS e
          FROM a WHERE a IS NOT NULL)
    GROUP BY e.member),
  per_metric AS (
    SELECT r.metric, r.additivity,
           r.applicable AND EXISTS (SELECT 1 FROM points p WHERE p.metric = r.metric) AS applicable,
           CASE WHEN NOT r.applicable THEN r.reason
                WHEN NOT EXISTS (SELECT 1 FROM points p WHERE p.metric = r.metric) THEN coalesce(f.errors[1], 'the service answered no point') END AS reason,
           v.backtested, v.held_80, v.held_90, v.newest, coalesce(f.errors, []) AS errors,
           (SELECT coalesce(list({'period': p.period, 'actual': p.actual, 'p05': p.p05, 'p10': p.p10, 'p50': p.p50,
                                  'p90': p.p90, 'p95': p.p95, 'pit': p.pit, 'withheld': p.withheld} ORDER BY p.period), [])
            FROM points p WHERE p.metric = r.metric) AS points
    FROM req r LEFT JOIN results v USING (metric) LEFT JOIN failures f USING (metric))
  SELECT (SELECT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version') FROM a) AS served_by,
         'month' AS grain,
         (SELECT json_extract(a, '$.answer.backtest.score')::DOUBLE FROM a) AS score,
         (SELECT json_extract_string(a, '$.answer.backtest.state') FROM a) AS state,
         (SELECT json_extract(a, '$.answer.backtest.threshold')::DOUBLE FROM a) AS threshold,
         (SELECT coalesce(list({'metric': metric, 'applicable': applicable, 'reason': reason, 'additivity': additivity,
                                'backtested': backtested, 'held_80': held_80, 'held_90': held_90, 'newest': newest,
                                'errors': errors, 'points': points} ORDER BY metric), [])
          FROM per_metric) AS metrics
$$ RETURNS metric_ranges;

-- The breach is the service's result, judged by the test's detector over
-- the measurement's own result, so that TESTS() carries it and the checks
-- goal's next steps use it: red where the score is above the test's
-- threshold, the service's state below it, its red read as orange. A
-- backtest that predicted no month has no state and no row.
DECLARE FUNCTION range_breach FOR GLOBAL AS $$
  SELECT subject,
         CASE WHEN (body->>'score')::DOUBLE > $threshold THEN 'red' WHEN body->>'state' = 'red' THEN 'orange' ELSE body->>'state' END AS state,
         (body->>'score')::DOUBLE AS score
  FROM annotations WHERE actor_kind = 'function' AND body->>'state' IS NOT NULL
$$;

DECLARE TEST range_test ON metric_ranges DETECTOR range_breach THRESHOLD 0.98;

--===------------------------------------------------------------------===--
-- range_result(): the newest backtest's result — served_by, grain, score,
-- state, threshold, computed_at — one row, none before a backtest.
-- range_points(): the newest backtest, one row per metric and backtested
-- month — metric, applicable, reason, additivity, backtested, held_80,
-- held_90, period, actual, p05 to p95, pit, withheld, displacement
-- (|2·pit − 1|), newest (the latest backtested month, the one the result
-- scores), point_seq; a metric not backtested serves one row with its
-- reason and no numbers.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.range_result() AS TABLE
SELECT json_extract_string(value, '$.served_by') AS served_by, json_extract_string(value, '$.grain') AS grain,
       json_extract(value, '$.score')::DOUBLE AS score, json_extract_string(value, '$.state') AS state,
       json_extract(value, '$.threshold')::DOUBLE AS threshold, computed_at
FROM main.measurements
WHERE dataset = current_schema() AND function = 'metric_ranges'
ORDER BY begin_snapshot DESC LIMIT 1;

CREATE OR REPLACE MACRO main.range_points() AS TABLE
WITH newest_result AS (
  SELECT value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_ranges' ORDER BY begin_snapshot DESC LIMIT 1),
metrics AS (
  SELECT unnest(from_json(json_extract(value, '$.metrics'),
    '[{"metric": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "additivity": "VARCHAR", "backtested": "BIGINT",
       "held_80": "DOUBLE", "held_90": "DOUBLE",
       "newest": {"origin": "VARCHAR", "period": "VARCHAR", "pit": "DOUBLE", "displacement": "DOUBLE", "withheld": "VARCHAR"},
       "errors": ["VARCHAR"],
       "points": [{"period": "VARCHAR", "actual": "DOUBLE", "p05": "DOUBLE", "p10": "DOUBLE", "p50": "DOUBLE",
                   "p90": "DOUBLE", "p95": "DOUBLE", "pit": "DOUBLE", "withheld": "VARCHAR"}]}]')) AS m,
         computed_at
  FROM newest_result),
backtested AS (
  SELECT m.metric, m.applicable, m.reason, m.additivity, m.backtested, m.held_80, m.held_90, m.newest.period AS newest_period,
         unnest(m.points) AS p, computed_at
  FROM metrics WHERE cardinality(m.points) > 0)
SELECT metric, applicable, reason, additivity, backtested, held_80, held_90,
       p.period, p.actual, p.p05, p.p10, p.p50, p.p90, p.p95, p.pit, p.withheld,
       CASE WHEN p.pit IS NOT NULL THEN abs(2.0 * p.pit - 1.0) END AS displacement,
       p.period = newest_period AS newest,
       row_number() OVER (PARTITION BY metric ORDER BY p.period) AS point_seq, computed_at
FROM backtested
UNION ALL
SELECT m.metric, m.applicable, m.reason, m.additivity, m.backtested, m.held_80, m.held_90,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, computed_at
FROM metrics WHERE cardinality(m.points) = 0
ORDER BY metric, point_seq NULLS FIRST;

--===------------------------------------------------------------------===--
-- The forecast. forecast_request(): one row per metric — grain (its
-- floor), horizon (31 days, 13 weeks, 12 months, 4 quarters; an hour or a
-- minute is finer than the grains the service measured its coverage at, a
-- year has too few periods), origin (the last complete period with a
-- value: complete_series() leaves out a period the data ends inside),
-- history, the periods ahead, and for a flow the spans it asks totals
-- for: the periods left in the month (a day), the quarter (a week), the
-- quarter and the year (a month), the year (a quarter) that the first
-- period ahead falls in, where the horizon reaches the span's end; two
-- spans of one length are asked once and served under both names.
-- forecast_bodies(): one request per grain and set of totals, the history
-- as actual rows and the periods ahead as forecast rows, so the answer
-- carries their labels.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.forecast_request() AS TABLE
WITH axes AS (
  SELECT * RENAME (view AS metric) FROM main.view_axes() WHERE coalesce(kind, '') NOT IN ('scalar', 'relation', 'plan', 'scenario')),
series AS (SELECT metric, period, value FROM main.complete_series(NULL)),
hist AS (
  SELECT metric, count(*) AS n, max(period) AS origin, list({'period': period, 'value': value} ORDER BY period) AS history
  FROM series GROUP BY metric),
judged AS (
  SELECT a.metric, a.additivity, a.floor AS grain,
         CASE a.floor WHEN 'day' THEN 31 WHEN 'week' THEN 13 WHEN 'month' THEN 12 WHEN 'quarter' THEN 4 END AS horizon,
         h.n, h.origin, h.history,
         CASE WHEN NOT a.applicable THEN a.reason
              WHEN a.floor IN ('minute', 'hour') THEN 'a ' || a.floor || ' grain is finer than the grains the service measured its coverage at'
              WHEN a.floor = 'year' THEN 'a year grain has too few periods to forecast'
              WHEN h.metric IS NULL THEN main.no_series_reason(a.metric, a.value_column, a.additivity, a.additivity_state, a.floor)
              WHEN h.n < 6 THEN h.n || ' ' || a.floor || 's of history: a forecast needs 6' END AS reason
  FROM axes a LEFT JOIN hist h USING (metric)),
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
SELECT j.metric, j.additivity, j.grain, j.horizon, j.origin, j.reason, j.reason IS NULL AS applicable, j.history,
       coalesce(ah.periods[1:j.horizon], []::TIMESTAMP[]) AS ahead,
       coalesce(s.spans, []::STRUCT(span BIGINT, to_go VARCHAR)[]) AS spans
FROM judged j LEFT JOIN ahead ah USING (metric) LEFT JOIN spans s USING (metric)
ORDER BY j.metric;

CREATE OR REPLACE MACRO main.forecast_bodies() AS TABLE
WITH r AS (SELECT * FROM main.forecast_request() WHERE applicable),
rows_ AS (
  SELECT r.metric, r.grain, r.horizon, list_sort(list_distinct(list_transform(r.spans, lambda s: s.span))) AS totals,
         cell.period AS period, cell.value AS value, 'actual' AS status
  FROM r, unnest(r.history) AS hs(cell)
  UNION ALL
  SELECT r.metric, r.grain, r.horizon, list_sort(list_distinct(list_transform(r.spans, lambda s: s.span))),
         ap.p, NULL::DOUBLE, 'forecast'
  FROM r, unnest(r.ahead) AS ap(p))
SELECT grain, totals, horizon,
       json_object('spec', json_object('targets', ['value'], 'horizon', horizon, 'levels', [0.05, 0.1, 0.5, 0.9, 0.95],
                                       'grain', grain, 'totals', totals),
                   'table', json_object('member', list(metric ORDER BY metric, period),
                                        'period', list(strftime(period, '%Y-%m-%d') ORDER BY metric, period),
                                        'status', list(status ORDER BY metric, period),
                                        'value', list(value ORDER BY metric, period))) AS body
FROM rows_ GROUP BY grain, totals, horizon;

--===------------------------------------------------------------------===--
-- metric_forecast: the forecast as a measurement on the dataset, at an
-- origin: per metric its grain, origin, applicable and reason, and its
-- points — a step (one period past the origin) or a span (the total of
-- the first so many steps, to_go naming the month, the quarter or the year
-- it runs to) with its period, p05 to p95, and service_80 and service_90,
-- the service's held-out share of actuals inside the 80% and the 90% range
-- at that grain, step and span. No actual and no PIT land here: neither
-- is known at the origin; forecast_points() joins the actual at read.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_forecast WITH $${
  "description": "Preview. A forecast is stored for every metric a plan or a scenario needs.",
  "type": "object", "x-used-by": ["plan", "scenario"],
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "metrics": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT ON DATASET;

DECLARE FUNCTION metric_forecast FOR GLOBAL AS $$
  WITH req AS (SELECT * FROM main.forecast_request()),
  b AS (SELECT grain, totals, body, main.service('/forecast', body) AS a FROM main.forecast_bodies()),
  rows_ AS (
    SELECT unnest(json_extract(a, '$.table.member')::VARCHAR[]) AS metric,
           unnest(json_extract(a, '$.table.step')::BIGINT[]) AS step,
           unnest(json_extract(a, '$.table.span')::BIGINT[]) AS span,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value
    FROM b),
  points AS (
    SELECT metric, step, span, any_value(period) AS period,
           max(CASE WHEN level = 0.05 THEN value END) AS p05, max(CASE WHEN level = 0.1 THEN value END) AS p10,
           max(CASE WHEN level = 0.5 THEN value END) AS p50, max(CASE WHEN level = 0.9 THEN value END) AS p90,
           max(CASE WHEN level = 0.95 THEN value END) AS p95
    FROM rows_ GROUP BY metric, step, span),
  -- the service's held-out share per grain, step and span: every body at a grain carries it, once is enough
  coverage AS (
    SELECT b.grain, cv.c.step AS step, cv.c.span AS span, cv.c.low AS low, cv.c.high AS high, any_value(cv.c.share) AS share
    FROM b, unnest(from_json(json_extract(b.a, '$.answer.coverage'),
                   '[{"step": "BIGINT", "span": "BIGINT", "low": "DOUBLE", "high": "DOUBLE", "share": "DOUBLE"}]')) AS cv(c)
    GROUP BY ALL),
  failures AS (
    SELECT e.member AS metric, list(e.error ORDER BY e.error) AS errors
    FROM (SELECT unnest(from_json(json_extract(a, '$.answer.errors'),
            '[{"member": "VARCHAR", "column": "VARCHAR", "origin": "VARCHAR", "error": "VARCHAR"}]')) AS e FROM b)
    GROUP BY e.member),
  req_spans AS (SELECT r.metric, sp.s.span AS span, sp.s.to_go AS to_go FROM req r, unnest(r.spans) AS sp(s)),
  named AS (
    SELECT p.metric, p.step, p.span, rs.to_go, p.period, p.p05, p.p10, p.p50, p.p90, p.p95
    FROM points p LEFT JOIN req_spans rs ON rs.metric = p.metric AND rs.span = p.span),
  per_metric AS (
    SELECT r.metric, r.additivity, r.grain, r.origin,
           r.applicable AND EXISTS (SELECT 1 FROM points p WHERE p.metric = r.metric) AS applicable,
           CASE WHEN NOT r.applicable THEN r.reason
                WHEN NOT EXISTS (SELECT 1 FROM points p WHERE p.metric = r.metric) THEN coalesce(f.errors[1], 'the service answered no point for this metric') END AS reason,
           (SELECT coalesce(list({'step': n.step, 'span': n.span, 'to_go': n.to_go, 'period': n.period,
                                  'p05': n.p05, 'p10': n.p10, 'p50': n.p50, 'p90': n.p90, 'p95': n.p95,
                                  'service_80': c80.share, 'service_90': c90.share} ORDER BY n.span NULLS FIRST, n.step, n.to_go), [])
            FROM named n
            LEFT JOIN coverage c80 ON c80.grain = r.grain AND c80.step = n.step AND c80.span IS NOT DISTINCT FROM n.span AND c80.low = 0.1 AND c80.high = 0.9
            LEFT JOIN coverage c90 ON c90.grain = r.grain AND c90.step = n.step AND c90.span IS NOT DISTINCT FROM n.span AND c90.low = 0.05 AND c90.high = 0.95
            WHERE n.metric = r.metric) AS points
    FROM req r LEFT JOIN failures f USING (metric))
  SELECT (SELECT string_agg(DISTINCT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version'), ', ') FROM b) AS served_by,
         (SELECT coalesce(list({'metric': metric, 'applicable': applicable, 'reason': reason, 'additivity': additivity, 'grain': grain,
                                'origin': strftime(origin, '%Y-%m-%d'), 'points': points} ORDER BY metric), [])
          FROM per_metric) AS metrics
$$ RETURNS metric_forecast;

--===------------------------------------------------------------------===--
-- forecast_stored(): every forecast run's points as rows, from the
-- measurements alone. forecast_runs(): the same with the actual joined
-- from the actual world where it has been loaded (for a span, the sum over its
-- periods where every one has). forecast_scored(): the same, one point per
-- metric, origin, step and span — the newest run's, so that a forecast
-- run again from one origin counts once. forecast_coverage(): the
-- catalog's tally over those points — per metric and for the dataset
-- ('' the metric), per grain, step, span and to_go (a span of one length
-- under two names tallied under each) where a point's actual is loaded:
-- points loaded, inside_80, inside_90, held_80, held_90.
-- forecast_points(): the newest run, flattened — one row per metric and
-- point: seq, metric, applicable, reason, additivity, grain, origin,
-- served_by, computed_at, current (false once the forecast is due again,
-- outlook_due()), point_seq, step, span, to_go, period,
-- p05 to p95, service_80, service_90, actual, actuals (below, low, inside,
-- high, above against p05, p10, p90 and p95), held_80, held_90 and
-- held_from (how often such a range held, forecast_held()). A metric the
-- forecast found inapplicable is one row with its reason.
--===------------------------------------------------------------------===--

-- forecast_metrics(value): a stored forecast's metrics, typed
CREATE OR REPLACE MACRO main.forecast_metrics(v) AS
  from_json(json_extract(v, '$.metrics'),
    '[{"metric": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "additivity": "VARCHAR", "grain": "VARCHAR", "origin": "VARCHAR",
       "points": [{"step": "BIGINT", "span": "BIGINT", "to_go": "VARCHAR", "period": "VARCHAR", "p05": "DOUBLE", "p10": "DOUBLE",
                   "p50": "DOUBLE", "p90": "DOUBLE", "p95": "DOUBLE", "service_80": "DOUBLE", "service_90": "DOUBLE"}]}]');

CREATE OR REPLACE MACRO main.forecast_stored() AS TABLE
WITH runs AS (
  SELECT begin_snapshot AS run, value, computed_at FROM main.measurements_history
  WHERE dataset = current_schema() AND function = 'metric_forecast'),
metrics AS (
  SELECT run, computed_at, json_extract_string(value, '$.served_by') AS served_by, unnest(main.forecast_metrics(value)) AS m
  FROM runs),
pts AS (
  SELECT run, computed_at, served_by, m.metric, m.applicable, m.reason, m.additivity, m.grain, m.origin::TIMESTAMP AS origin, unnest(m.points) AS p
  FROM metrics WHERE cardinality(m.points) > 0)
SELECT run, computed_at, served_by, metric, applicable, reason, additivity, grain, origin,
       p.step AS step, p.span AS span, p.to_go AS to_go, p.period::TIMESTAMP AS period,
       p.p05 AS p05, p.p10 AS p10, p.p50 AS p50, p.p90 AS p90, p.p95 AS p95, p.service_80 AS service_80, p.service_90 AS service_90
FROM pts
UNION ALL
SELECT run, computed_at, served_by, m.metric, m.applicable, m.reason, m.additivity, m.grain, m.origin::TIMESTAMP,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM metrics WHERE cardinality(m.points) = 0;

CREATE OR REPLACE MACRO main.forecast_runs() AS TABLE
WITH actuals AS (SELECT metric, period, value FROM main.complete_series(NULL))
SELECT r.*,
       CASE WHEN r.step IS NULL THEN NULL
            WHEN r.span IS NULL THEN a.value
            ELSE (SELECT CASE WHEN count(*) = r.span THEN sum(a2.value) END FROM actuals a2
                  WHERE a2.metric = r.metric AND a2.period > r.origin AND a2.period <= r.period) END AS actual
FROM main.forecast_stored() r
LEFT JOIN actuals a ON a.metric = r.metric AND a.period = r.period AND r.span IS NULL;

CREATE OR REPLACE MACRO main.forecast_scored() AS TABLE
SELECT * FROM main.forecast_runs()
QUALIFY row_number() OVER (PARTITION BY metric, grain, origin, step, span, to_go ORDER BY run DESC) = 1;

CREATE OR REPLACE MACRO main.forecast_coverage() AS TABLE
WITH tally AS (
  SELECT metric, grain, step, span, to_go, count(actual) AS points,
         count(*) FILTER (WHERE actual BETWEEN p10 AND p90) AS inside_80,
         count(*) FILTER (WHERE actual BETWEEN p05 AND p95) AS inside_90
  FROM main.forecast_scored() WHERE applicable AND step IS NOT NULL
  GROUP BY metric, grain, step, span, to_go
  HAVING count(actual) > 0),
whole AS (
  SELECT '' AS metric, grain, step, span, to_go, sum(points) AS points, sum(inside_80) AS inside_80, sum(inside_90) AS inside_90
  FROM tally GROUP BY grain, step, span, to_go)
SELECT metric, grain, step, span, to_go, points, inside_80, inside_90,
       CASE WHEN points > 0 THEN inside_80 / points END AS held_80,
       CASE WHEN points > 0 THEN inside_90 / points END AS held_90
FROM (SELECT * FROM tally UNION ALL SELECT * FROM whole)
ORDER BY metric, grain, step, span NULLS FIRST, to_go NULLS FIRST;

-- forecast_held(): how often a range of the newest forecast held, one
-- row per metric and point (metric, grain, step, span, to_go): held_80
-- and held_90, the catalog's own share where forecast_coverage() holds
-- thirty loaded points at this grain, step and span for the metric, else
-- for the dataset, else the service's; held_from (metric, dataset,
-- service). forecast_points() and plan_points() take it at read.
CREATE OR REPLACE MACRO main.forecast_held() AS TABLE
WITH stored AS MATERIALIZED (SELECT * FROM main.forecast_stored()),
newest AS (SELECT * FROM stored WHERE run = (SELECT max(run) FROM stored) AND applicable AND step IS NOT NULL),
tally AS MATERIALIZED (SELECT * FROM main.forecast_coverage() WHERE points >= 30)
SELECT n.metric, n.grain, n.step, n.span, n.to_go,
       coalesce(tm.held_80, td.held_80, n.service_80) AS held_80,
       coalesce(tm.held_90, td.held_90, n.service_90) AS held_90,
       CASE WHEN tm.metric IS NOT NULL THEN 'metric' WHEN td.metric IS NOT NULL THEN 'dataset'
            WHEN n.service_80 IS NOT NULL THEN 'service' END AS held_from
FROM newest n
LEFT JOIN tally tm ON tm.metric = n.metric AND tm.grain = n.grain AND tm.step = n.step
                  AND tm.span IS NOT DISTINCT FROM n.span AND tm.to_go IS NOT DISTINCT FROM n.to_go
LEFT JOIN tally td ON td.metric = '' AND td.grain = n.grain AND td.step = n.step
                  AND td.span IS NOT DISTINCT FROM n.span AND td.to_go IS NOT DISTINCT FROM n.to_go;

CREATE OR REPLACE MACRO main.forecast_points() AS TABLE
WITH runs AS MATERIALIZED (SELECT * FROM main.forecast_runs()),
newest AS (SELECT max(run) AS run FROM runs),
current_ AS (SELECT NOT coalesce(bool_or(due), false) AS current FROM main.outlook_due() WHERE name = 'metric_forecast'),
rows_ AS (
  SELECT f.*, dense_rank() OVER (ORDER BY f.metric) - 1 AS seq,
         CASE WHEN f.step IS NULL THEN NULL
              ELSE row_number() OVER (PARTITION BY f.metric ORDER BY f.span NULLS FIRST, f.step, f.to_go) - 1 END AS point_seq
  FROM runs f, newest WHERE f.run = newest.run)
SELECT r.seq, r.metric, r.applicable, r.reason, r.additivity, r.grain, strftime(r.origin, '%Y-%m-%d') AS origin, r.served_by, r.computed_at,
       (SELECT current FROM current_) AS current, r.point_seq,
       r.step, r.span, r.to_go, strftime(r.period, '%Y-%m-%d') AS period, r.p05, r.p10, r.p50, r.p90, r.p95, r.service_80, r.service_90,
       r.actual,
       CASE WHEN r.actual IS NULL THEN NULL WHEN r.actual < r.p05 THEN 'below' WHEN r.actual < r.p10 THEN 'low'
            WHEN r.actual <= r.p90 THEN 'inside' WHEN r.actual <= r.p95 THEN 'high' ELSE 'above' END AS actuals,
       h.held_80, h.held_90, h.held_from
FROM rows_ r
LEFT JOIN main.forecast_held() h ON h.metric = r.metric AND h.grain = r.grain AND h.step = r.step
                                AND h.span IS NOT DISTINCT FROM r.span AND h.to_go IS NOT DISTINCT FROM r.to_go
ORDER BY r.seq, r.point_seq NULLS FIRST;

--===------------------------------------------------------------------===--
-- The scenario. A lever is a FACT on a column of a metric's view — a list
-- price, a discount rate — annotated true where someone sets it, false where
-- it was looked at and nobody does; a column with no lever annotation is no
-- lever. A scenario is the actor's own FACT aspect on the dataset, x-kind
-- scenario, its body a factor per period on declared levers: {"levers":
-- [{"column": "<metric>.<column>", "factor": {"YYYY-MM": 1.15, …},
-- "basis": "…"}]}; a period is a month or a day, one not named keeps a
-- factor of one. scenarios(): every scenario declared, judged — annotated,
-- each lever an annotated lever on a served metric's column, the factor a
-- map. scenario_request(): the scenario's reach, one row per scenario
-- and metric whose view carries one of its levers: grain (the metric's
-- floor), origin (the last complete actual, as the forecast's), history,
-- the periods ahead up to the end of the last period the scenario names,
-- and per lever its series (the mean of the column per period) and the
-- value held as planned (the last at or before the origin); applicable
-- needs 26 periods of history, a period ahead, and an input the scenario
-- moves — a lever held at nothing, or factors of one, move nothing, and
-- the service refuses a request where no input differs; fixable says the
-- reason is one the scenario's author can settle (no period ahead, every
-- factor one). lever_bodies(): one
-- forecast request per scenario, metric and lever, the lever's own
-- series as the member and the periods ahead as the horizon, at the
-- forecast's reach per grain. scenario_bodies(paths := NULL): one
-- what-if request per scenario and metric as the service's contract
-- spells it — the history as actual rows, the periods ahead twice, as
-- planned and under the scenario (planned times the period's factor),
-- every lever an input column named as the scenario names it. The
-- planned input is the lever's own forecast where paths carries one
-- ({"<scenario>|<metric>|<lever>": [{period, value}]}, its last median
-- held past its reach), else the lever's last actual value held. The
-- estimate's measurement forecasts each lever first and passes the
-- paths; a plain read of scenario_bodies() holds. No metric definition is
-- replayed over the data: the scenario world is the estimate ahead.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.scenario_request() AS TABLE
WITH lv AS (
  SELECT s.scenario, u.l.lever AS lever, u.l.metric AS metric, u.l."column" AS col, u.l.factor AS factor
  FROM main.read_scenarios() s, unnest(s.levers) AS u(l) WHERE s.applicable),
axes AS (SELECT view AS metric, floor, period_column, additivity FROM main.view_axes() WHERE applicable),
series AS (SELECT metric, period, value FROM main.complete_series(NULL)),
origins AS (SELECT metric, max(period) AS origin, count(*) AS history FROM series GROUP BY metric),
-- the lever's series: the mean of the column per period at the metric's floor
lever_rows AS (
  SELECT l.scenario, l.lever, c.rn,
         max(CASE WHEN c."column" = a.period_column THEN TRY_CAST(c.val AS TIMESTAMP) END) AS instant,
         max(CASE WHEN c."column" = l.col THEN TRY_CAST(c.val AS DOUBLE) END) AS at_row
  FROM (SELECT DISTINCT scenario, lever, metric, col FROM lv) l
  JOIN axes a ON a.metric = l.metric
  JOIN dataset_cells(current_schema(), 'the dataset''s metrics') c ON c."table" = l.metric AND c."column" IN (a.period_column, l.col)
  GROUP BY l.scenario, l.lever, c.rn),
lever_series AS (
  SELECT r.scenario, r.lever, date_trunc(a.floor, r.instant) AS period, avg(r.at_row) AS value
  FROM lever_rows r JOIN (SELECT DISTINCT scenario, lever, metric FROM lv) l USING (scenario, lever) JOIN axes a ON a.metric = l.metric
  WHERE r.instant IS NOT NULL AND r.at_row IS NOT NULL
  GROUP BY r.scenario, r.lever, date_trunc(a.floor, r.instant)),
-- the end of the last period a lever's factor names
named AS (
  SELECT l.scenario, l.lever, l.metric,
         max(CASE WHEN len(k) = 7 THEN (k || '-01')::TIMESTAMP + INTERVAL 1 MONTH ELSE k::TIMESTAMP + INTERVAL 1 DAY END) AS until
  FROM lv l, unnest(json_keys(l.factor)) AS u(k)
  GROUP BY l.scenario, l.lever, l.metric),
reach AS (
  SELECT n.scenario, n.metric, a.floor AS grain, a.additivity, o.origin, o.history, max(n.until) AS until
  FROM named n JOIN axes a USING (metric) LEFT JOIN origins o USING (metric)
  GROUP BY n.scenario, n.metric, a.floor, a.additivity, o.origin, o.history),
judged AS (
  SELECT r.*,
         CASE WHEN r.origin IS NULL THEN r.metric || ' has no complete ' || r.grain || ' in its series yet'
              WHEN r.until <= r.origin + main.grain_step(r.grain)
                THEN 'the scenario names no period after ' || strftime(r.origin, '%Y-%m-%d') || ', the last actual of ' || r.metric
              WHEN r.history < 26 THEN r.history || ' ' || r.grain || 's of history: the estimate needs 26' END AS reason
  FROM reach r),
ahead AS (
  SELECT j.scenario, j.metric, list(g.p ORDER BY g.p) AS periods
  FROM judged j, unnest(generate_series(j.origin + main.grain_step(j.grain), j.until - main.grain_step(j.grain), main.grain_step(j.grain))) AS g(p)
  WHERE j.reason IS NULL GROUP BY j.scenario, j.metric),
held AS (
  SELECT l.scenario, l.metric, l.lever, l.factor,
         (SELECT arg_max(ls.value, ls.period) FROM lever_series ls, judged j
          WHERE ls.scenario = l.scenario AND ls.lever = l.lever AND j.scenario = l.scenario AND j.metric = l.metric AND ls.period <= j.origin) AS planned,
         (SELECT coalesce(list({'period': ls.period, 'value': ls.value} ORDER BY ls.period), [])
          FROM lever_series ls WHERE ls.scenario = l.scenario AND ls.lever = l.lever) AS series
  FROM lv l),
-- a lever the scenario does not move: every factor ahead is one (a planned value of nothing is judged once the
-- planned path is known, in scenario_bodies)
moved AS (
  SELECT h.scenario, h.metric, h.lever, h.planned,
         EXISTS (
           SELECT 1 FROM ahead a, unnest(a.periods) AS u(p)
           WHERE a.scenario = h.scenario AND a.metric = h.metric
             AND coalesce(json_extract(h.factor, '$."' || strftime(u.p, '%Y-%m-%d') || '"')::DOUBLE,
                          json_extract(h.factor, '$."' || strftime(u.p, '%Y-%m') || '"')::DOUBLE, 1.0) <> 1.0) AS moves
  FROM held h),
inputs AS (
  SELECT h.scenario, h.metric,
         list({'lever': h.lever, 'factor': h.factor, 'planned': h.planned, 'series': h.series} ORDER BY h.lever) AS levers,
         string_agg(CASE WHEN NOT m.moves THEN 'every factor on ' || h.lever || ' over the periods ahead is one' END, '; ' ORDER BY h.lever) AS unmoved
  FROM held h JOIN moved m USING (scenario, metric, lever)
  GROUP BY h.scenario, h.metric)
SELECT j.scenario, j.metric, j.grain, j.additivity, j.origin, j.history,
       coalesce(j.reason, CASE WHEN i.unmoved IS NOT NULL AND NOT EXISTS (SELECT 1 FROM moved m WHERE m.scenario = j.scenario AND m.metric = j.metric AND m.moves)
                               THEN 'the scenario moves no input of ' || j.metric || ': ' || i.unmoved END) AS reason,
       coalesce(j.reason, CASE WHEN i.unmoved IS NOT NULL AND NOT EXISTS (SELECT 1 FROM moved m WHERE m.scenario = j.scenario AND m.metric = j.metric AND m.moves) THEN 'x' END) IS NULL AS applicable,
       coalesce(a.periods, []::TIMESTAMP[]) AS ahead, i.levers,
       CASE WHEN j.reason IS NOT NULL THEN j.origin IS NOT NULL AND j.until <= j.origin + main.grain_step(j.grain)
            ELSE i.unmoved IS NOT NULL AND NOT EXISTS (SELECT 1 FROM moved m WHERE m.scenario = j.scenario AND m.metric = j.metric AND m.moves) END AS fixable
FROM judged j LEFT JOIN ahead a USING (scenario, metric) JOIN inputs i USING (scenario, metric)
ORDER BY j.scenario, j.metric;

CREATE OR REPLACE MACRO main.lever_bodies() AS TABLE
WITH r AS (SELECT * FROM main.scenario_request() WHERE applicable),
lv AS (
  SELECT r.scenario, r.metric, r.grain, r.ahead, u.l.lever AS lever, u.l.series AS series,
         CASE r.grain WHEN 'day' THEN 31 WHEN 'week' THEN 13 WHEN 'month' THEN 12 WHEN 'quarter' THEN 4 ELSE 0 END AS reach
  FROM r, unnest(r.levers) AS u(l)),
rows_ AS (
  SELECT l.scenario, l.metric, l.lever, sp.s.period AS period, sp.s.value AS value, 'actual' AS status
  FROM lv l, unnest(l.series) AS sp(s)
  UNION ALL
  SELECT l.scenario, l.metric, l.lever, ap.p, NULL::DOUBLE, 'forecast'
  FROM lv l, unnest(l.ahead[1:least(len(l.ahead), l.reach)]) AS ap(p))
SELECT l.scenario, l.metric, l.lever, l.grain, least(len(l.ahead), l.reach) AS horizon,
       json_object('spec', json_object('targets', ['value'], 'horizon', least(len(l.ahead), l.reach), 'levels', [0.5], 'grain', l.grain),
                   'table', json_object('member', list(l.lever ORDER BY w.period, w.status), 'period', list(strftime(w.period, '%Y-%m-%d') ORDER BY w.period, w.status),
                                        'status', list(w.status ORDER BY w.period, w.status), 'value', list(w.value ORDER BY w.period, w.status))) AS body
FROM lv l JOIN rows_ w USING (scenario, metric, lever)
WHERE l.reach > 0 AND len(l.series) >= 6
GROUP BY l.scenario, l.metric, l.lever, l.grain, l.ahead, l.reach
ORDER BY l.scenario, l.metric, l.lever;

CREATE OR REPLACE MACRO main.scenario_bodies(paths := NULL) AS TABLE
WITH r AS (SELECT * FROM main.scenario_request() WHERE applicable),
hist AS (
  SELECT r.scenario, r.metric, s.period, 'actual' AS status, s.value, 0 AS ord
  FROM r JOIN (SELECT metric, period, value FROM main.complete_series(NULL)) s USING (metric)),
ahead AS (
  SELECT r.scenario, r.metric, u.p AS period, st.status, NULL::DOUBLE AS value, st.ord
  FROM r, unnest(r.ahead) AS u(p), (VALUES ('plan', 1), ('scenario', 2)) st(status, ord)),
rows_ AS (SELECT * FROM hist UNION ALL SELECT * FROM ahead),
inputs AS (
  SELECT r.scenario, r.metric, u.l.lever AS lever, u.l.factor AS factor, u.l.planned AS held, u.l.series AS series,
         from_json(coalesce(json_extract(paths, '$."' || r.scenario || '|' || r.metric || '|' || u.l.lever || '"'), '[]'::JSON),
                   '[{"period": "VARCHAR", "value": "DOUBLE"}]') AS path
  FROM r, unnest(r.levers) AS u(l)),
-- the planned input at a period: the lever's forecast median there, its last median past the forecast's reach, else the held value
planned AS (
  SELECT w.scenario, w.metric, i.lever, w.period, w.ord, w.status, i.factor, i.series,
         CASE WHEN i.path IS NOT NULL AND len(i.path) > 0
              THEN coalesce(list_extract(list_filter(i.path, lambda e: e.period::TIMESTAMP = w.period), 1).value, i.path[-1].value)
              ELSE i.held END AS planned
  FROM rows_ w JOIN inputs i USING (scenario, metric)),
input_cells AS (
  SELECT p.scenario, p.metric, p.lever, p.period, p.ord,
         CASE p.status WHEN 'actual' THEN list_extract(list_filter(p.series, lambda e: e.period = p.period), 1).value
                       WHEN 'plan' THEN p.planned
                       ELSE p.planned * coalesce(json_extract(p.factor, '$."' || strftime(p.period, '%Y-%m-%d') || '"')::DOUBLE,
                                                 json_extract(p.factor, '$."' || strftime(p.period, '%Y-%m') || '"')::DOUBLE, 1.0) END AS value
  FROM planned p),
-- an input the scenario moves: some period ahead where its value under the scenario differs from the planned one
moves AS (
  SELECT scenario, metric, lever,
         bool_or(scenario_value IS DISTINCT FROM plan_value AND scenario_value IS NOT NULL) AS moves,
         any_value(plan_value) AS planned_at_first
  FROM (SELECT scenario, metric, lever, period,
               max(CASE WHEN ord = 1 THEN value END) AS plan_value, max(CASE WHEN ord = 2 THEN value END) AS scenario_value
        FROM input_cells WHERE ord > 0 GROUP BY scenario, metric, lever, period)
  GROUP BY scenario, metric, lever),
unmoved AS (
  SELECT scenario, metric,
         string_agg(lever || ' is at ' || coalesce(planned_at_first::VARCHAR, 'nothing') || ' as planned over the periods ahead, and a factor on nothing is nothing', '; ' ORDER BY lever) AS reason
  FROM moves WHERE NOT moves GROUP BY scenario, metric
  HAVING NOT bool_or(moves)),
base AS (
  SELECT w.scenario, w.metric,
         json_object('member', list(w.metric ORDER BY w.period, w.ord), 'period', list(strftime(w.period, '%Y-%m-%d') ORDER BY w.period, w.ord),
                     'status', list(w.status ORDER BY w.period, w.ord), 'value', list(w.value ORDER BY w.period, w.ord)) AS cols
  FROM rows_ w GROUP BY w.scenario, w.metric),
levered AS (
  SELECT scenario, metric, json_group_object(lever, vals) AS cols
  FROM (SELECT scenario, metric, lever, list(value ORDER BY period, ord) AS vals FROM input_cells GROUP BY scenario, metric, lever)
  GROUP BY scenario, metric)
SELECT r.scenario, r.metric, r.grain,
       CASE WHEN u.reason IS NULL THEN json_object('spec', json_object('targets', ['value'], 'levels', [0.1, 0.5, 0.9]),
                                                   'table', json_merge_patch(b.cols, l.cols)) END AS body,
       u.reason AS unmoved
FROM r JOIN base b USING (scenario, metric) JOIN levered l USING (scenario, metric)
LEFT JOIN (SELECT scenario, metric, reason FROM unmoved
           WHERE NOT EXISTS (SELECT 1 FROM moves m WHERE m.scenario = unmoved.scenario AND m.metric = unmoved.metric AND m.moves)) u USING (scenario, metric)
ORDER BY r.scenario, r.metric;

--===------------------------------------------------------------------===--
-- metric_scenario: the estimate as a measurement on the dataset, over
-- every scenario annotated: per scenario its judgement and levers, per
-- metric reached its grain, origin, the service's sign, confidence and
-- basis, explains and error, the points ahead (period, low, value, high
-- at the 10, 50 and 90 levels; baseline, the same estimate's median with
-- every lever as planned; the history's own reading with its 90%
-- interval) and the parts (per lever, what it alone does by the
-- history). Due again once what it read is out of date: the scenarios,
-- the levers, the metrics' data and definitions. scenario_points(s): the newest estimate, one
-- row per scenario (or every one, NULL), metric and period ahead, with
-- baseline and effect (value minus baseline: what the scenario changes)
-- and how often such a range held, the forecast service's share at that
-- grain and step; a metric not estimated is one row with its reason.
-- scenario_levers(s): the parts.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_scenario WITH $${
  "description": "Preview. An estimate is stored for every declared scenario.",
  "type": "object", "x-used-by": ["scenario"],
  "properties": {
    "served_by": {"type": ["string", "null"]},
    "scenarios": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT ON DATASET;

DECLARE FUNCTION metric_scenario FOR GLOBAL AS $$
  WITH sc AS (SELECT * FROM main.read_scenarios()),
  req AS (SELECT * FROM main.scenario_request()),
  -- each lever's own forecast, soft: a refusal holds the lever instead
  lf AS (SELECT lb.scenario, lb.metric, lb.lever, main.service_soft('/forecast', lb.body) AS fa FROM main.lever_bodies() lb),
  medians AS (
    SELECT scenario, metric, lever,
           unnest(json_extract(fa, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(fa, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(fa, '$.table.value')::DOUBLE[]) AS value
    FROM lf WHERE json_extract_string(fa, '$.error') IS NULL),
  paths AS (
    SELECT scenario, metric, lever, list({'period': period, 'value': value} ORDER BY period) AS path
    FROM medians WHERE level = 0.5 AND period IS NOT NULL AND value IS NOT NULL GROUP BY scenario, metric, lever),
  planned_json AS (SELECT json_group_object(scenario || '|' || metric || '|' || lever, path) AS j FROM paths),
  planned_from AS (
    SELECT r.scenario, r.metric, u.l.lever AS lever,
           CASE WHEN p.lever IS NOT NULL THEN 'forecast'
                WHEN lf.lever IS NULL THEN 'held: the lever is not forecast at this grain, or has too short a history'
                ELSE 'held: ' || coalesce(json_extract_string(lf.fa, '$.error'), 'the forecast answered no median') END AS planned_from
    FROM req r, unnest(r.levers) AS u(l)
    LEFT JOIN lf ON lf.scenario = r.scenario AND lf.metric = r.metric AND lf.lever = u.l.lever
    LEFT JOIN paths p ON p.scenario = r.scenario AND p.metric = r.metric AND p.lever = u.l.lever),
  -- a body exists only where an input moves; a NULL body makes no call
  b AS (SELECT scenario, metric, grain, unmoved, CASE WHEN body IS NOT NULL THEN main.service('/whatif', body) END AS a
        FROM main.scenario_bodies(paths := (SELECT j FROM planned_json))),
  rows_ AS (
    SELECT b.scenario, b.metric,
           unnest(json_extract(a, '$.table.member')::VARCHAR[]) AS member,
           unnest(json_extract(a, '$.table.period')::VARCHAR[]) AS period,
           unnest(json_extract(a, '$.table.status')::VARCHAR[]) AS status,
           unnest(coalesce(json_extract(a, '$.table.column')::VARCHAR[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: 'value'))) AS target,
           unnest(json_extract(a, '$.table.level')::DOUBLE[]) AS level,
           unnest(json_extract(a, '$.table.value')::DOUBLE[]) AS value,
           unnest(coalesce(json_extract(a, '$.table.history_value')::DOUBLE[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::DOUBLE))) AS history_value,
           unnest(coalesce(json_extract(a, '$.table.history_low')::DOUBLE[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::DOUBLE))) AS history_low,
           unnest(coalesce(json_extract(a, '$.table.history_high')::DOUBLE[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::DOUBLE))) AS history_high,
           unnest(coalesce(json_extract(a, '$.table.sign')::VARCHAR[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::VARCHAR))) AS sign,
           unnest(coalesce(json_extract(a, '$.table.confidence')::VARCHAR[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::VARCHAR))) AS confidence,
           unnest(coalesce(json_extract(a, '$.table.basis')::VARCHAR[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::VARCHAR))) AS basis,
           unnest(coalesce(json_extract(a, '$.table.explains')::DOUBLE[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::DOUBLE))) AS explains,
           unnest(coalesce(json_extract(a, '$.table.error')::DOUBLE[], list_transform(json_extract(a, '$.table.member')::VARCHAR[], lambda x: NULL::DOUBLE))) AS error
    FROM b WHERE a IS NOT NULL),
  -- the service answers each period ahead twice: under the scenario, and with every lever as planned (the baseline)
  points AS (
    SELECT scenario, metric, period,
           max(CASE WHEN status = 'scenario' AND level = 0.1 THEN value END) AS low,
           max(CASE WHEN status = 'scenario' AND level = 0.5 THEN value END) AS value,
           max(CASE WHEN status = 'scenario' AND level = 0.9 THEN value END) AS high,
           max(CASE WHEN status = 'plan' AND level = 0.5 THEN value END) AS baseline,
           any_value(history_value) FILTER (WHERE status = 'scenario') AS history_value,
           any_value(history_low) FILTER (WHERE status = 'scenario') AS history_low,
           any_value(history_high) FILTER (WHERE status = 'scenario') AS history_high
    FROM rows_ WHERE member = metric AND status IN ('scenario', 'plan') AND target = 'value' AND period IS NOT NULL
    GROUP BY scenario, metric, period
    HAVING count(*) FILTER (WHERE status = 'scenario') > 0),
  said AS (
    SELECT scenario, metric, any_value(sign) AS sign, any_value(confidence) AS confidence, any_value(basis) AS basis,
           any_value(explains) AS explains, any_value(error) AS error
    FROM rows_ WHERE member = metric AND target = 'value' GROUP BY scenario, metric),
  parts AS (
    SELECT b.scenario, b.metric, u.p.input AS lever, u.p.history_shift AS history_shift, u.p.history_low AS history_low, u.p.history_high AS history_high
    FROM b, unnest(from_json(json_extract(a, '$.answer.parts'),
           '[{"member": "VARCHAR", "column": "VARCHAR", "input": "VARCHAR", "history_shift": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}]')) AS u(p)
    WHERE u.p.member = b.metric AND coalesce(u.p."column", 'value') = 'value'),
  failures AS (
    SELECT b.scenario, b.metric, list(u.e.error ORDER BY u.e.error) AS errors
    FROM b, unnest(from_json(json_extract(a, '$.answer.errors'), '[{"member": "VARCHAR", "column": "VARCHAR", "error": "VARCHAR"}]')) AS u(e)
    WHERE u.e.member = b.metric GROUP BY b.scenario, b.metric),
  per_metric AS (
    SELECT r.scenario, r.metric, r.grain, r.origin,
           r.applicable AND bd.unmoved IS NULL AND EXISTS (SELECT 1 FROM points p WHERE p.scenario = r.scenario AND p.metric = r.metric) AS applicable,
           CASE WHEN NOT r.applicable THEN r.reason
                WHEN bd.unmoved IS NOT NULL THEN 'the scenario moves no input of ' || r.metric || ': ' || bd.unmoved
                WHEN NOT EXISTS (SELECT 1 FROM points p WHERE p.scenario = r.scenario AND p.metric = r.metric)
                  THEN coalesce(f.errors[1], 'the service answered no point') END AS reason,
           coalesce(NOT r.applicable AND r.fixable, false) AS fixable,
           (SELECT coalesce(list({'lever': pf.lever, 'planned_from': pf.planned_from} ORDER BY pf.lever), [])
            FROM planned_from pf WHERE pf.scenario = r.scenario AND pf.metric = r.metric) AS levers,
           s.sign, s.confidence, s.basis, s.explains, s.error,
           (SELECT coalesce(list({'period': p.period, 'low': p.low, 'value': p.value, 'high': p.high, 'baseline': p.baseline, 'history_value': p.history_value,
                                  'history_low': p.history_low, 'history_high': p.history_high} ORDER BY p.period), [])
            FROM points p WHERE p.scenario = r.scenario AND p.metric = r.metric) AS points,
           (SELECT coalesce(list({'lever': pt.lever, 'history_shift': pt.history_shift, 'history_low': pt.history_low, 'history_high': pt.history_high} ORDER BY pt.lever), [])
            FROM parts pt WHERE pt.scenario = r.scenario AND pt.metric = r.metric) AS parts
    FROM req r LEFT JOIN said s ON s.scenario = r.scenario AND s.metric = r.metric
    LEFT JOIN failures f ON f.scenario = r.scenario AND f.metric = r.metric
    LEFT JOIN b bd ON bd.scenario = r.scenario AND bd.metric = r.metric),
  per_scenario AS (
    SELECT sc.scenario, sc.applicable, sc.reason,
           list_transform(sc.levers, lambda l: {'lever': l.lever, 'basis': l.basis, 'reason': l.reason}) AS levers,
           (SELECT coalesce(list({'metric': m.metric, 'grain': m.grain, 'origin': strftime(m.origin, '%Y-%m-%d'), 'applicable': m.applicable, 'reason': m.reason,
                                  'fixable': m.fixable, 'levers': m.levers, 'sign': m.sign, 'confidence': m.confidence, 'basis': m.basis, 'explains': m.explains, 'error': m.error,
                                  'points': m.points, 'parts': m.parts} ORDER BY m.metric), [])
            FROM per_metric m WHERE m.scenario = sc.scenario) AS metrics
    FROM sc)
  SELECT (SELECT string_agg(DISTINCT json_extract_string(a, '$.answer.service') || ' ' || json_extract_string(a, '$.answer.version'), ', ') FROM b) AS served_by,
         (SELECT coalesce(list({'scenario': scenario, 'applicable': applicable, 'reason': reason, 'levers': levers, 'metrics': metrics} ORDER BY scenario), [])
          FROM per_scenario) AS scenarios
$$ RETURNS metric_scenario;

CREATE OR REPLACE MACRO main.scenario_points(s) AS TABLE
WITH newest AS (
  SELECT value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_scenario' ORDER BY begin_snapshot DESC LIMIT 1),
scn AS (
  SELECT computed_at, json_extract_string(value, '$.served_by') AS served_by,
         unnest(from_json(json_extract(value, '$.scenarios'),
           '[{"scenario": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR",
              "metrics": [{"metric": "VARCHAR", "grain": "VARCHAR", "origin": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR",
                           "levers": [{"lever": "VARCHAR", "planned_from": "VARCHAR"}], "sign": "VARCHAR", "confidence": "VARCHAR", "basis": "VARCHAR", "explains": "DOUBLE", "error": "DOUBLE",
                           "points": [{"period": "VARCHAR", "low": "DOUBLE", "value": "DOUBLE", "high": "DOUBLE", "baseline": "DOUBLE",
                                       "history_value": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}]}]}]')) AS sc
  FROM newest),
mets AS (
  SELECT computed_at, served_by, sc.scenario, sc.applicable AS scenario_applicable, sc.reason AS scenario_reason, unnest(sc.metrics) AS m
  FROM scn WHERE s IS NULL OR sc.scenario = s),
stepped AS (
  SELECT computed_at, served_by, scenario, m.metric, m.grain, m.origin, m.applicable, m.reason, m.levers, m.sign, m.confidence, m.basis, m.explains, m.error,
         unnest(m.points) AS p, unnest(generate_series(1, cardinality(m.points)::BIGINT)) AS step
  FROM mets WHERE cardinality(m.points) > 0),
-- how often such a range held: the service's share at that grain and step, from the newest forecast run (the catalog's own
-- tally reads the series, which reads the worlds, which read this)
held AS (
  SELECT r.metric, r.grain, r.step, r.service_80 AS held_80, CASE WHEN r.service_80 IS NOT NULL THEN 'service' END AS held_from
  FROM main.forecast_stored() r JOIN (SELECT max(run) AS run FROM main.forecast_stored()) n ON n.run = r.run
  WHERE r.applicable AND r.span IS NULL AND r.step IS NOT NULL)
SELECT s.scenario, s.metric, s.grain, s.origin, s.applicable, s.reason, list_transform(s.levers, lambda l: l.lever) AS levers, 'estimated' AS pass, s.step::BIGINT AS step,
       s.p.period::TIMESTAMP AS period, s.p.low AS low, s.p.value AS value, s.p.high AS high,
       s.p.baseline AS baseline, s.p.value - s.p.baseline AS effect,
       s.p.history_value AS history_value, s.p.history_low AS history_low, s.p.history_high AS history_high,
       h.held_80, h.held_from, s.sign, s.confidence, s.basis, s.explains, s.error, s.served_by, s.computed_at
FROM stepped s LEFT JOIN held h ON h.metric = s.metric AND h.grain = s.grain AND h.step = s.step
UNION ALL
SELECT scenario, m.metric, m.grain, m.origin, m.applicable, m.reason, list_transform(m.levers, lambda l: l.lever), 'estimated', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, m.sign, m.confidence, m.basis, m.explains, m.error, served_by, computed_at
FROM mets WHERE coalesce(cardinality(m.points), 0) = 0
ORDER BY scenario, metric, step NULLS FIRST;

CREATE OR REPLACE MACRO main.scenario_levers(s) AS TABLE
WITH newest AS (
  SELECT value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_scenario' ORDER BY begin_snapshot DESC LIMIT 1),
scn AS (
  SELECT computed_at, unnest(from_json(json_extract(value, '$.scenarios'),
           '[{"scenario": "VARCHAR", "metrics": [{"metric": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "sign": "VARCHAR", "basis": "VARCHAR",
              "levers": [{"lever": "VARCHAR", "planned_from": "VARCHAR"}],
              "parts": [{"lever": "VARCHAR", "history_shift": "DOUBLE", "history_low": "DOUBLE", "history_high": "DOUBLE"}]}]}]')) AS sc
  FROM newest),
mets AS (SELECT computed_at, sc.scenario, unnest(sc.metrics) AS m FROM scn WHERE s IS NULL OR sc.scenario = s),
levers AS (SELECT computed_at, scenario, m, unnest(m.levers) AS l FROM mets WHERE cardinality(m.levers) > 0),
parts AS (SELECT scenario, m.metric AS metric, unnest(m.parts) AS p FROM mets WHERE cardinality(m.parts) > 0)
SELECT l.scenario, l.m.metric AS metric, l.m.applicable AS applicable, l.m.reason AS reason, l.m.sign AS sign, l.m.basis AS basis,
       l.l.lever AS lever, l.l.planned_from AS planned_from, p.p.history_shift AS history_shift, p.p.history_low AS history_low, p.p.history_high AS history_high, l.computed_at
FROM levers l LEFT JOIN parts p ON p.scenario = l.scenario AND p.metric = l.m.metric AND p.p.lever = l.l.lever
ORDER BY l.scenario, metric, lever;

--===------------------------------------------------------------------===--
-- The plan. plan_rows(): every applicable plan's rows through the metric
-- it plans — plan, metric, additivity, covers, instant, value, and grain,
-- the plan's own: the grain its rows are booked against where the
-- declaration says so, else the rows' measured grain. plan_grains(): one row per
-- plan with it. plan_cells(at_grain): the
-- plan world's cells per plan at a grain, or at its own where NULL — a
-- flow sums, a stock keeps the last level, anything else averages; a plan
-- coarser than the asked grain serves nothing. world_cells(): the plan
-- world (named plan, refused by name where it is no plan or nothing
-- serves it), the forecast world (the newest forecast's medians at its
-- grain) and the scenario world (named scenario: the newest estimate's
-- medians ahead) under the metric, for metric_series(world := …).
--===------------------------------------------------------------------===--

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

CREATE OR REPLACE MACRO main.plan_rows() AS TABLE FROM main.plan_rows_of('the dataset', 'the dataset''s metrics');

CREATE OR REPLACE MACRO main.plan_grains_of(plans_at, metrics_at) AS TABLE
SELECT DISTINCT plan, metric, additivity, grain FROM main.plan_rows_of(plans_at, metrics_at);

CREATE OR REPLACE MACRO main.plan_grains() AS TABLE FROM main.plan_grains_of('the dataset', 'the dataset''s metrics');

CREATE OR REPLACE MACRO main.plan_cells(at_grain) AS TABLE
SELECT r.plan, r.metric, coalesce(at_grain, r.grain) AS grain, date_trunc(coalesce(at_grain, r.grain), r.instant) AS period,
       CASE r.additivity WHEN 'semi-additive' THEN arg_max(r.value, r.instant) WHEN 'additive' THEN sum(r.value) ELSE avg(r.value) END AS value,
       coalesce(r.additivity, 'none') AS additivity
FROM main.plan_rows() r
WHERE r.instant IS NOT NULL AND r.value IS NOT NULL
  AND (at_grain IS NULL OR main.grain_rank(at_grain) >= main.grain_rank(r.grain))
GROUP BY r.plan, r.metric, coalesce(at_grain, r.grain), date_trunc(coalesce(at_grain, r.grain), r.instant), r.additivity;

CREATE OR REPLACE MACRO main.world_cells(w, p, s, g) AS TABLE
WITH named AS (
  SELECT a.view AS plan, a.applicable, a.reason FROM main.view_rows() a WHERE a.kind = 'plan' AND a.view = p),
refusal AS (
  SELECT CASE WHEN w NOT IN ('actual', 'plan', 'forecast', 'scenario') THEN error('unknown_world: metric_series(world := ''' || w || '''): the worlds are actual, plan, forecast and scenario')
              WHEN w = 'scenario' AND s IS NULL THEN error('scenario_not_named: metric_series(world := ''scenario'') names the scenario it serves, scenario := ''<name>'' — a scenario is a FACT aspect declared with x-kind scenario, annotated with a factor per period on declared levers')
              WHEN w = 'scenario' AND NOT EXISTS (SELECT 1 FROM main.scenarios() WHERE scenario = s) THEN error(
                'unknown_scenario: metric_series(scenario := ''' || s || '''): no scenario of that name is declared — a scenario is a FACT aspect declared with x-kind scenario')
              WHEN w = 'plan' AND p IS NULL THEN error('plan_not_named: metric_series(world := ''plan'') names the plan it serves, plan := ''<name>'' — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>')
              WHEN w = 'plan' AND NOT EXISTS (SELECT 1 FROM named) THEN error(
                CASE WHEN NOT EXISTS (SELECT 1 FROM main.aspects WHERE name = p)
                     THEN 'unknown_plan: metric_series(plan := ''' || p || '''): no aspect of that name is declared — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>'
                     ELSE 'not_a_plan: metric_series(plan := ''' || p || '''): ' || p || ' is no plan — a plan is a VIEW aspect declared with x-kind plan and x-plan-of <metric>' END)
              WHEN w = 'plan' AND EXISTS (SELECT 1 FROM named WHERE NOT applicable) THEN error(
                'plan_not_served: metric_series(plan := ''' || p || '''): ' || (SELECT reason FROM named))
         END AS r),
plan_world AS (
  SELECT c.metric, 'plan' AS world, '' AS dimension, '' AS member, c.period, c.value, NULL::DOUBLE AS num, NULL::DOUBLE AS den, c.additivity
  FROM main.plan_cells(g) c WHERE w = 'plan' AND c.plan = p),
newest AS (SELECT max(run) AS run FROM main.forecast_stored()),
forecast_world AS (
  SELECT f.metric, 'forecast' AS world, '' AS dimension, '' AS member, f.period, f.p50 AS value,
         NULL::DOUBLE AS num, NULL::DOUBLE AS den, coalesce(f.additivity, 'none') AS additivity
  FROM main.forecast_stored() f JOIN newest n ON n.run = f.run
  WHERE w = 'forecast' AND f.applicable AND f.span IS NULL AND f.period IS NOT NULL AND (g IS NULL OR g = f.grain)),
scenario_world AS (
  SELECT sp.metric, 'scenario' AS world, '' AS dimension, '' AS member, sp.period, sp.value,
         NULL::DOUBLE AS num, NULL::DOUBLE AS den, coalesce(a.additivity, 'none') AS additivity
  FROM main.scenario_points(s) sp LEFT JOIN main.view_rows() a ON a.view = sp.metric
  WHERE w = 'scenario' AND sp.applicable AND sp.value IS NOT NULL AND (g IS NULL OR g = sp.grain))
SELECT * FROM plan_world
UNION ALL SELECT * FROM forecast_world
UNION ALL SELECT * FROM scenario_world
UNION ALL SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM refusal WHERE r IS NOT NULL;

--===------------------------------------------------------------------===--
-- plan_points(): every served plan against the actual and the forecast,
-- one row per plan and period at the plan's own grain and, where that is
-- finer, at the year — plan, metric, grain, period, label, value (the
-- plan's cell), actual (the actual world's cell at that grain where the
-- period has begun; for the current period, to date), variance (actual
-- minus plan, on a complete period), low, expected, high (the newest
-- forecast's 80% range and median: the step's at the metric's own grain;
-- at a coarser grain, for a flow the actual of the complete periods plus
-- the total that runs to the period's end, for a stock the range of the
-- last period of the metric's grain inside it), planned (complete: the
-- period is over and the actuals cover every period of it; not_covered:
-- begun, and the actuals served do not reach back to its start or hold
-- no value for it, so no actual and no variance; inside, below, above:
-- where the plan lies against the range; partial: begun and the rows
-- cover part of the period, no range; open: begun, no range covers the
-- rest; ahead: not begun), covers (on the year row of a plan whose rows
-- cover part of the year: how much), held_80 and held_from (how often
-- the range a row is held against held, forecast_held()), origin (the
-- forecast's). A period is complete once the metric's last complete
-- period reaches its end (complete_series()). Computed at read;
-- metric_plan stores it per plan, without held_80 and held_from: the
-- catalog's share reads every stored forecast, and a body reads only the
-- places it names. plan_points_of(plans_at, metrics_at) is the same over
-- the plans and the metrics of the places it names, with the key of the
-- forecast point a row is held against (forecast_grain, forecast_step,
-- forecast_span, forecast_to_go) in place of the share: metric_plan
-- reads its own plan, 'itself', and 'its metric'.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.plan_points_of(plans_at, metrics_at) AS TABLE
WITH prow AS MATERIALIZED (SELECT * FROM main.plan_rows_of(plans_at, metrics_at)),
g AS (
  SELECT pg.plan, pg.metric, pg.additivity, pg.grain, m.floor AS metric_floor
  FROM (SELECT DISTINCT plan, metric, additivity, grain FROM prow) pg
  JOIN main.view_axes_of(metrics_at) m ON m.view = pg.metric WHERE m.applicable),
floor_cells AS MATERIALIZED (
  SELECT metric, period, value, num, den, additivity FROM main.actual_series_of(metrics_at, unclaimed := 'skip')
  WHERE dimension = '' AND world = 'actual'),
-- edge: the last period with a value; origin: the last complete one, the period before where the data ends inside the
-- edge's; first_actual: where the served actuals begin (the series serves a window of periods, not the whole history)
edges AS (SELECT metric, max(period) AS edge, min(period) AS first_actual FROM floor_cells WHERE value IS NOT NULL GROUP BY metric),
origins AS (
  SELECT e.metric, e.edge, e.first_actual,
         CASE WHEN EXISTS (SELECT 1 FROM main.partial_periods_of(metrics_at, NULL) pp WHERE pp.metric = e.metric AND pp.period = e.edge)
              THEN e.edge - main.grain_step(m.floor) ELSE e.edge END AS origin
  FROM edges e JOIN main.view_axes_of(metrics_at) m ON m.view = e.metric),
cells AS (
  -- the plan's cells at its own grain and at the year
  SELECT r.plan, r.metric, gr.step_grain AS grain, date_trunc(gr.step_grain, r.instant) AS period,
         CASE r.additivity WHEN 'semi-additive' THEN arg_max(r.value, r.instant) WHEN 'additive' THEN sum(r.value) ELSE avg(r.value) END AS value
  FROM prow r, unnest(CASE WHEN r.grain = 'year' THEN ['year'] ELSE [r.grain, 'year'] END) AS gr(step_grain)
  WHERE r.instant IS NOT NULL AND r.value IS NOT NULL
  GROUP BY r.plan, r.metric, gr.step_grain, date_trunc(gr.step_grain, r.instant), r.additivity),
own AS (SELECT c.* FROM cells c JOIN g USING (plan) WHERE c.grain = g.grain),
rows_ AS (SELECT * FROM cells),
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
  FROM floor_cells f JOIN (SELECT DISTINCT metric, grain FROM rows_) r USING (metric) LEFT JOIN origins o ON o.metric = f.metric
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
  FROM rows_ r JOIN g USING (plan)
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
-- the stored forecast's ranges
fp AS MATERIALIZED (
  SELECT u.m.metric AS metric, u.m.grain AS grain, u.m.origin::TIMESTAMP AS origin, p.p.step AS step, p.p.span AS span, p.p.to_go AS to_go,
         p.p.period::TIMESTAMP AS period, p.p.p10 AS p10, p.p.p50 AS p50, p.p.p90 AS p90
  FROM results('metric_forecast', 'its dataset') f, unnest(main.forecast_metrics(f.value)) u(m), unnest(u.m.points) p(p)
  WHERE f.value IS NOT NULL AND u.m.applicable AND p.p.step IS NOT NULL),
-- the range a row is held against: the step's at the metric's own grain; at a coarser grain, for a stock the range of the
-- last period of the metric's grain inside it, for a flow that has begun the total that runs to the period's end
candidates AS (
  SELECT v.plan, v.grain, v.period, f.p10, f.p50, f.p90, f.grain AS forecast_grain, f.step, f.span, f.to_go, f.origin,
         row_number() OVER (PARTITION BY v.plan, v.grain, v.period ORDER BY f.span NULLS FIRST, f.step) AS rn
  FROM result v JOIN fp f ON f.metric = v.metric
  WHERE NOT v.complete AND NOT v.part AND NOT v.uncovered
    AND ((v.grain = v.metric_floor AND f.span IS NULL AND f.period = v.period)
      OR (v.grain <> v.metric_floor AND v.additivity = 'semi-additive' AND f.span IS NULL AND f.period = v.last_inside)
      OR (v.grain <> v.metric_floor AND v.additivity = 'additive' AND v.has_begun AND v.actual IS NOT NULL
          AND f.span IS NOT NULL AND f.to_go = v.grain AND f.period >= v.period AND f.period < v.period_end))),
ranged AS (
  SELECT v.*, c.p10, c.p50, c.p90, c.forecast_grain, c.step AS forecast_step, c.span AS forecast_span, c.to_go AS forecast_to_go,
         c.origin AS forecast_origin,
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
       CASE WHEN complete OR part THEN NULL ELSE strftime(forecast_origin, '%Y-%m-%d') END AS origin,
       CASE WHEN complete OR part THEN NULL ELSE forecast_grain END AS forecast_grain,
       CASE WHEN complete OR part THEN NULL ELSE forecast_step END AS forecast_step,
       CASE WHEN complete OR part THEN NULL ELSE forecast_span END AS forecast_span,
       CASE WHEN complete OR part THEN NULL ELSE forecast_to_go END AS forecast_to_go
FROM ranged
ORDER BY plan, CASE grain WHEN 'year' THEN 0 ELSE 1 END, period;

CREATE OR REPLACE MACRO main.plan_points() AS TABLE
SELECT p.plan, p.metric, p.grain, p.period, p.label, p.value, p.actual, p.variance, p.low, p.expected, p.high, p.planned, p.covers,
       h.held_80, h.held_from, p.origin
FROM main.plan_points_of('the dataset', 'the dataset''s metrics') p
LEFT JOIN main.forecast_held() h ON h.metric = p.metric AND h.grain = p.forecast_grain AND h.step = p.forecast_step
                                AND h.span IS NOT DISTINCT FROM p.forecast_span AND h.to_go IS NOT DISTINCT FROM p.forecast_to_go
ORDER BY p.plan, CASE p.grain WHEN 'year' THEN 0 ELSE 1 END, p.period;

--===------------------------------------------------------------------===--
-- metric_plan: the plan judged, as a measurement on the plan — the rows
-- plan_points() serves for it as of the data, without held_80 and
-- held_from, with the origin of the forecast they were judged against. Refused on a view that is not a plan,
-- or a plan that is not served, by name. Wanted on the plan's row until one
-- exists; due again once what it read is out of date, the forecast among it.
-- plan_stored(): the newest judgement per plan from the measurements
-- alone, one row per point, the read an arm of the `next` read takes;
-- plan_points() stays the live read.
--===------------------------------------------------------------------===--

DECLARE ASPECT metric_plan WITH $${
  "description": "Preview. Each plan against the forecast of the metric it plans.",
  "type": "object", "x-used-by": ["plan"],
  "properties": {
    "plan": {"type": "string"},
    "metric": {"type": ["string", "null"]},
    "grain": {"type": ["string", "null"]},
    "forecast_origin": {"type": ["string", "null"]},
    "points": {"type": "array", "items": {"type": "object"}}
  }
}$$ AS MEASUREMENT ON TABLE;

DECLARE FUNCTION metric_plan FOR GLOBAL AS $$
  WITH named AS (SELECT kind, applicable, reason FROM main.plan_axes_of('itself', 'its metric') WHERE view = split_part($subject, '.', 2)),
  refusal AS (
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM named WHERE kind = 'plan')
                THEN error('not_a_plan: ' || $subject || ' is not a plan: metric_plan() compares a plan, a VIEW aspect declared with x-kind plan and x-plan-of <metric>, with the actual and the forecast')
                WHEN EXISTS (SELECT 1 FROM named WHERE NOT applicable)
                THEN error('plan_not_served: ' || $subject || ' is a plan that is not served: ' || (SELECT reason FROM named)) END AS r),
  pts AS (SELECT * FROM main.plan_points_of('itself', 'its metric') WHERE plan = split_part($subject, '.', 2)),
  own AS (SELECT metric, grain FROM main.plan_grains_of('itself', 'its metric') WHERE plan = split_part($subject, '.', 2))
  SELECT coalesce((SELECT r FROM refusal)::VARCHAR, split_part($subject, '.', 2)) AS plan,
         (SELECT any_value(metric) FROM own) AS metric,
         (SELECT any_value(grain) FROM own) AS grain,
         (SELECT any_value(origin) FROM pts WHERE origin IS NOT NULL) AS forecast_origin,
         (SELECT coalesce(list({'grain': grain, 'period': strftime(period, '%Y-%m-%d'), 'label': label, 'value': value,
                                'actual': actual, 'variance': variance, 'low': low, 'expected': expected, 'high': high,
                                'planned': planned, 'covers': covers}
                               ORDER BY CASE grain WHEN 'year' THEN 0 ELSE 1 END, period), [])
          FROM pts) AS points
$$ RETURNS metric_plan;

-- The gap is read by the test's detector over the judgement's own
-- result: red where a ranged period lies below or above the forecast's
-- range, the score the share of ranged periods that do, so that TESTS()
-- carries it and the summary counts it.
DECLARE FUNCTION plan_gap FOR GLOBAL AS $$
  SELECT subject,
         CASE WHEN outside > 0 THEN 'red' ELSE 'green' END AS state,
         CASE WHEN ranged > 0 THEN outside / ranged ELSE 0.0 END AS score
  FROM (SELECT subject,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above'))), 0)::DOUBLE AS outside,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above', 'inside'))), 0)::DOUBLE AS ranged
        FROM (SELECT subject,
                     list_transform(from_json(json_extract(body, '$.points'), '[{"planned": "VARCHAR"}]'), lambda p: p.planned) AS planned
              FROM annotations WHERE actor_kind = 'function'))
$$;

DECLARE TEST plan_test ON metric_plan DETECTOR plan_gap;

CREATE OR REPLACE MACRO main.plan_stored() AS TABLE
WITH newest AS (
  SELECT subject, value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_plan'
  QUALIFY row_number() OVER (PARTITION BY subject ORDER BY begin_snapshot DESC) = 1),
judged AS (
  SELECT json_extract_string(value, '$.plan') AS plan, json_extract_string(value, '$.metric') AS metric,
         json_extract_string(value, '$.grain') AS plan_grain, json_extract_string(value, '$.forecast_origin') AS forecast_origin, computed_at,
         from_json(json_extract(value, '$.points'),
           '[{"grain": "VARCHAR", "period": "VARCHAR", "label": "VARCHAR", "value": "DOUBLE", "actual": "DOUBLE", "variance": "DOUBLE",
              "low": "DOUBLE", "expected": "DOUBLE", "high": "DOUBLE", "planned": "VARCHAR", "covers": "VARCHAR"}]') AS points
  FROM newest),
pts AS (
  SELECT plan, metric, plan_grain, forecast_origin, computed_at, unnest(points) AS p
  FROM judged WHERE cardinality(points) > 0)
SELECT plan, metric, plan_grain, forecast_origin, computed_at,
       p.grain AS grain, p.period::TIMESTAMP AS period, p.label, p.value, p.actual, p.variance, p.low, p.expected, p.high,
       p.planned, p.covers
FROM pts
UNION ALL
SELECT plan, metric, plan_grain, forecast_origin, computed_at,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM judged WHERE coalesce(cardinality(points), 0) = 0
ORDER BY plan, CASE grain WHEN 'year' THEN 0 ELSE 1 END, period;

--===------------------------------------------------------------------===--
-- outlook_measurements(): the preview measurements the bound dataset
-- needs, where a model service is named and a metric serves a series
-- (a metric still blocked, with no grain yet, needs none) — name,
-- stored, due (outlook_due()): the expected ranges; the forecast once a
-- plan is served or a scenario can be estimated, since the plan is held
-- against its ranges and the scenario reads how often they held; the
-- scenario estimate once a scenario can be estimated. `next` lists the
-- ones that are due.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.outlook_measurements() AS TABLE
SELECT name, stored, due FROM main.outlook_due() WHERE needed;

--===------------------------------------------------------------------===--
-- outlook_findings(): what the preview features leave open on the bound
-- dataset, as rows for `next`: step (test or integrate), asset, state,
-- open (the finding), for_view, statement (the fix), test (the test the
-- finding belongs to). A value outside its expected range, a plan
-- outside the forecast's range, a plan not compared yet or whose
-- comparison is out of date, a plan without a
-- definition, a scenario that cannot be estimated for a reason its
-- author can settle. A reason nobody can settle (too little history) is
-- no row. A finding a person was asked about or decided on is closed.
-- Served only where a model service is named.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.outlook_findings() AS TABLE
WITH ds AS (SELECT current_schema() AS d),
live AS (SELECT coalesce(current_setting('glossql_service_url'), '') <> '' AS named),
asked AS (
  SELECT aspect, key FROM main.review_decisions r, ds WHERE r.dataset = ds.d
  UNION SELECT aspect, key FROM main.open_questions q, ds WHERE q.dataset = ds.d),
views AS MATERIALIZED (SELECT view, kind, stopped, applicable FROM main.view_rows()),
plans AS (
  SELECT a.name AS plan, json_extract_string(a.schema, '$.x-plan-of') AS metric, x.applicable, x.stopped
  FROM (SELECT name, kind, schema FROM main.aspects QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1) a
  LEFT JOIN views x ON x.view = a.name
  WHERE a.kind = 'VIEW' AND json_extract_string(a.schema, '$.x-kind') = 'plan'),
compared AS (
  SELECT subject, json_extract_string(value, '$.plan') AS plan
  FROM main.measurements WHERE dataset = current_schema() AND function = 'metric_plan'
  QUALIFY row_number() OVER (PARTITION BY subject ORDER BY begin_snapshot DESC) = 1),
-- the catalog's stale rule on each stored comparison
held AS (
  SELECT subject, bool_and(current) AS current FROM glossql_glossary(current_schema(), NULL, true)
  WHERE actor = 'function' AND aspect = 'metric_plan' GROUP BY subject),
-- the newest estimate's scenarios and the metrics they reach
estimate AS (
  SELECT value, computed_at FROM main.measurements
  WHERE dataset = current_schema() AND function = 'metric_scenario'
  ORDER BY begin_snapshot DESC LIMIT 1),
estimated AS (
  SELECT sc.scenario AS scenario, unnest(sc.metrics) AS m, computed_at
  FROM (SELECT unnest(from_json(json_extract(value, '$.scenarios'),
          '[{"scenario": "VARCHAR", "metrics": [{"metric": "VARCHAR", "applicable": "BOOLEAN", "reason": "VARCHAR", "fixable": "BOOLEAN"}]}]')) AS sc,
               computed_at
        FROM estimate)),
-- a scenario's annotation as it stands, to edit and send
scenario_bodies AS (
  SELECT w.aspect AS scenario, w.body::VARCHAR AS body, w.written_at FROM main.glossary w, ds
  WHERE w.dataset = ds.d AND w.subject = ds.d
  QUALIFY row_number() OVER (PARTITION BY w.aspect ORDER BY w.begin_snapshot DESC) = 1)
SELECT 'test' AS step, ds.d || '.' || p.metric AS asset, 'red' AS state,
       'range_test (preview): ' || p.metric || ' is ' || CAST(round(p.actual, 2) AS VARCHAR) || ' at ' || p.period
         || ', outside its expected range of ' || CAST(round(p.p05, 2) AS VARCHAR) || ' to ' || CAST(round(p.p95, 2) AS VARCHAR) AS open,
       p.metric AS for_view,
       '-- a defect in the data is fixed in the load or the definition. A real shift is for a person: add it to "assumptions" as {"dimension": "definition", "key": "range-' || p.period
         || '", "assumption": "<the shift at ' || p.period || ', in the business''s words>", "basis": "<what it rests on>", "confidence": 0.7}. Then record the definition again:' || chr(10)
         || main.view_redefine(ds.d, p.metric) AS statement,
       'range_test' AS test
FROM main.range_points() p, ds, live
WHERE live.named AND p.newest AND p.displacement > 0.9
  AND EXISTS (SELECT 1 FROM glossql_tests(current_schema(), 'metric_ranges') t WHERE t.test = 'range_test' AND t.state = 'red')
  AND NOT EXISTS (SELECT 1 FROM asked a WHERE a.aspect = p.metric AND a.key = 'range-' || p.period)
UNION ALL
SELECT 'test', ds.d || '.' || g.plan, 'red',
       'plan_test (preview): ' || g.plan || ' is ' || CAST(round(g.value, 2) AS VARCHAR) || ' at ' || g.label || ', ' || g.planned
         || ' the forecast''s range for ' || g.metric || ' of ' || CAST(round(g.low, 2) AS VARCHAR) || ' to ' || CAST(round(g.high, 2) AS VARCHAR),
       g.metric,
       '-- add the gap to "assumptions" of the plan as {"dimension": "definition", "key": "plan-' || g.label
         || '", "assumption": "<the gap at ' || g.label || ' and what closes it, in the business''s words>", "basis": "<what it rests on>", "confidence": 0.7}. Then record the plan again:' || chr(10)
         || main.view_redefine(ds.d, g.plan),
       'plan_test'
FROM main.plan_stored() g, ds, live
WHERE live.named AND g.grain = 'year' AND g.planned IN ('below', 'above')
  AND NOT EXISTS (SELECT 1 FROM asked a WHERE a.aspect = g.plan AND a.key = 'plan-' || g.label)
UNION ALL
SELECT 'test', ds.d || '.' || p.plan, 'not_run',
       'plan_test (preview): ' || p.plan || CASE WHEN c.plan IS NULL THEN ' is not compared with the actual and the forecast yet'
                                                ELSE ' was compared before the forecast or the plan changed' END,
       p.metric, 'SELECT metric_plan() FROM ' || ds.d || '.' || p.plan || ';', 'plan_test'
FROM plans p LEFT JOIN compared c USING (plan) LEFT JOIN held h ON h.subject = c.subject, ds, live
WHERE live.named AND p.applicable AND (c.plan IS NULL OR NOT coalesce(h.current, true))
UNION ALL
SELECT 'integrate', ds.d || '.' || p.plan, 'missing',
       p.plan || ' (preview) plans ' || p.metric || ' and has no definition', p.metric,
       main.gloss_statement(p.plan, ds.d, '{"sql": "SELECT <date column> AS <the metric''s period column>, <planned value> AS <the metric''s value column> FROM <budget table>"}'),
       NULL
FROM plans p LEFT JOIN main.view_definitions s ON s.name = p.plan, ds, live
WHERE live.named AND p.stopped IS NULL AND coalesce(s.stopped, '') = '' AND NOT coalesce(s.defined, false)
  -- an aspect is the workspace's: a plan is this dataset's where the metric it plans is
  AND EXISTS (SELECT 1 FROM views m WHERE m.view = p.metric)
UNION ALL
-- a scenario annotated on this dataset that the catalog cannot read as one: a lever that is none, a factor that is no map
SELECT 'test', ds.d, 'not_run',
       'scenario_test (preview): ' || s.scenario || ' cannot be estimated: ' || s.reason, '',
       main.gloss_statement(s.scenario, ds.d, coalesce(b.body,
         '{"levers": [{"column": "<metric>.<column>", "factor": {"<YYYY-MM>": <factor>}, "basis": "<what the scenario assumes>"}]}'))
         || CASE WHEN s.reason LIKE '%not annotated as a lever%'
                 THEN chr(10) || '-- a lever is a column someone sets: ' || main.gloss_statement('lever', '<metric>.<column>', '{"value": true, "basis": "<who sets it>"}') ELSE '' END,
       'scenario_test'
FROM main.scenarios() s LEFT JOIN scenario_bodies b USING (scenario), ds, live
WHERE live.named AND s.annotated AND NOT s.applicable
UNION ALL
-- a scenario estimated for no period of a metric, for a reason its author can settle; once the scenario is
-- annotated again the estimate is due, and the finding is the old annotation's
SELECT 'test', ds.d || '.' || e.m.metric, 'not_run',
       'scenario_test (preview): ' || e.scenario || ' is not estimated for ' || e.m.metric || ': ' || e.m.reason, e.m.metric,
       '-- change the periods or the factors so that the scenario moves a lever in a period after the last complete one, then run the estimate again:' || chr(10)
         || main.gloss_statement(e.scenario, ds.d, coalesce(b.body, '<the scenario>')) || chr(10)
         || 'SELECT metric_scenario() FROM ' || ds.d || ';',
       'scenario_test'
FROM estimated e LEFT JOIN scenario_bodies b ON b.scenario = e.scenario, ds, live
WHERE live.named AND NOT e.m.applicable AND coalesce(e.m.fixable, false)
  AND (b.written_at IS NULL OR b.written_at <= e.computed_at);

--===------------------------------------------------------------------===--
-- preview_tests(): the preview features' tests as rows of view_tests(),
-- one per metric and test — view, test, aspect, subject, state, current,
-- score, evidence, run. state: red where the metric's newest value lies
-- outside its expected range or the plan outside the forecast's; orange
-- where the newest value lies outside its range and the test reads the
-- service's red as orange (range_breach); green
-- where the result holds a point for the metric; not_run where no
-- result is stored yet, or one could be after a fix the evidence names;
-- not_applicable where the result holds no point for the metric and
-- nothing can be done about it (the evidence's reason says why). A
-- plan's test shows under the metric it plans, the plan its subject.
-- current is false once the measurement is due again. evidence carries
-- applicable, reason, and finding and fix where outlook_findings() holds
-- one. run is empty: a preview measurement calls the model service, and
-- the server runs none by itself; `next` names the ones that are due.
-- forecast_test and scenario_test are this read's alone: a test on a
-- measurement names a detector, and their state needs none.
-- Served where a model service is named or a result is stored.
--===------------------------------------------------------------------===--

CREATE OR REPLACE MACRO main.preview_tests() AS TABLE
WITH ds AS (SELECT current_schema() AS d),
live AS (SELECT coalesce(current_setting('glossql_service_url'), '') <> '' AS named),
due AS MATERIALIZED (SELECT * FROM main.outlook_due()),
declared AS (
  SELECT name AS test, aspect FROM main.tests
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY begin_snapshot DESC) = 1),
tests AS (
  SELECT test, aspect FROM declared WHERE aspect IN ('metric_ranges', 'metric_plan')
  UNION ALL VALUES ('forecast_test', 'metric_forecast'), ('scenario_test', 'metric_scenario')),
results AS MATERIALIZED (
  SELECT subject, test, state, score FROM glossql_tests(current_schema(), NULL) WHERE test IN (SELECT test FROM tests)),
summary AS MATERIALIZED (SELECT view, kind, plan_of, stopped, applicable FROM main.view_summary()),
metrics AS (SELECT view AS metric FROM summary WHERE stopped IS NULL AND coalesce(kind, '') NOT IN ('scalar', 'relation', 'plan', 'sample')),
open_ AS MATERIALIZED (SELECT asset, test, state, open, statement FROM main.outlook_findings() WHERE test IS NOT NULL),
-- one finding per asset and test, a red one first
findings AS (
  SELECT asset, test, arg_min(open, CASE state WHEN 'red' THEN 0 ELSE 1 END) AS finding,
         arg_min(statement, CASE state WHEN 'red' THEN 0 ELSE 1 END) AS fix
  FROM open_ GROUP BY asset, test),
-- a measurement on the dataset shows where it is stored, or where the dataset needs it
shown AS (SELECT name, stored, due FROM due WHERE stored OR needed),
ranged AS (
  SELECT metric, any_value(applicable) AS applicable, any_value(reason) AS reason,
         max(CASE WHEN newest THEN displacement END) AS displacement
  FROM main.range_points() GROUP BY metric),
forecasted AS (
  SELECT metric, bool_or(applicable) AS applicable, any_value(reason) AS reason
  FROM main.forecast_stored() WHERE run = (SELECT max(run) FROM main.forecast_stored()) GROUP BY metric),
estimated AS (
  SELECT metric, bool_or(applicable) AS applicable,
         string_agg(DISTINCT CASE WHEN NOT applicable THEN scenario || ': ' || reason END, '; ') AS reason
  FROM main.scenario_points(NULL) GROUP BY metric),
reached AS (
  SELECT DISTINCT u.l.metric AS metric FROM main.scenarios() s, unnest(s.levers) AS u(l) WHERE s.applicable),
plans AS (SELECT view AS plan, plan_of AS metric, applicable FROM summary WHERE kind = 'plan' AND stopped IS NULL),
rows_ AS (
  -- the expected ranges
  SELECT m.metric AS view, t.test, t.aspect, ds.d || '.' || m.metric AS subject,
         CASE WHEN NOT w.stored OR r.metric IS NULL THEN 'not_run'
              WHEN NOT r.applicable OR x.state IS NULL THEN 'not_applicable'
              WHEN f.finding IS NOT NULL THEN 'red'
              WHEN x.state = 'orange' AND r.displacement > 0.9 THEN 'orange'
              ELSE 'green' END AS state,
         NOT w.due AS current, r.displacement AS score,
         r.applicable, r.reason, f.finding,
         coalesce(f.fix, CASE WHEN w.due THEN 'SELECT metric_ranges() FROM ' || ds.d || ';' END) AS fix
  FROM metrics m CROSS JOIN ds JOIN tests t ON t.aspect = 'metric_ranges' JOIN shown w ON w.name = 'metric_ranges'
  LEFT JOIN ranged r ON r.metric = m.metric
  LEFT JOIN results x ON x.subject = ds.d AND x.test = t.test
  LEFT JOIN findings f ON f.asset = ds.d || '.' || m.metric AND f.test = t.test
  UNION ALL
  -- the forecast
  SELECT m.metric, t.test, t.aspect, ds.d || '.' || m.metric,
         CASE WHEN NOT w.stored OR r.metric IS NULL THEN 'not_run'
              WHEN NOT r.applicable THEN 'not_applicable'
              ELSE 'green' END,
         NOT w.due, NULL::DOUBLE, r.applicable, r.reason, NULL::VARCHAR,
         CASE WHEN w.due THEN 'SELECT metric_forecast() FROM ' || ds.d || ';' END
  FROM metrics m CROSS JOIN ds JOIN tests t ON t.aspect = 'metric_forecast' JOIN shown w ON w.name = 'metric_forecast'
  LEFT JOIN forecasted r ON r.metric = m.metric
  UNION ALL
  -- the scenario estimate, on the metrics a scenario reaches
  SELECT m.metric, t.test, t.aspect, ds.d || '.' || m.metric,
         CASE WHEN NOT w.stored OR r.metric IS NULL OR f.finding IS NOT NULL THEN 'not_run'
              WHEN NOT r.applicable THEN 'not_applicable'
              ELSE 'green' END,
         NOT w.due, NULL::DOUBLE, r.applicable, r.reason, f.finding,
         coalesce(f.fix, CASE WHEN w.due THEN 'SELECT metric_scenario() FROM ' || ds.d || ';' END)
  FROM (SELECT metric FROM reached UNION SELECT metric FROM estimated) m CROSS JOIN ds
  JOIN tests t ON t.aspect = 'metric_scenario' JOIN shown w ON w.name = 'metric_scenario'
  LEFT JOIN estimated r ON r.metric = m.metric
  LEFT JOIN findings f ON f.asset = ds.d || '.' || m.metric AND f.test = t.test
  UNION ALL
  -- the plan against the actual and the forecast, under the metric it plans
  SELECT p.metric, t.test, t.aspect, ds.d || '.' || p.plan,
         coalesce(x.state, 'not_run'),
         x.state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM open_ o
                                             WHERE o.asset = ds.d || '.' || p.plan AND o.test = t.test AND o.state = 'not_run'),
         x.score, p.applicable, NULL::VARCHAR,
         CASE WHEN x.state = 'red' THEN f.finding END, f.fix
  FROM plans p CROSS JOIN ds CROSS JOIN live JOIN tests t ON t.aspect = 'metric_plan'
  LEFT JOIN results x ON x.subject = ds.d || '.' || p.plan AND x.test = t.test
  LEFT JOIN findings f ON f.asset = ds.d || '.' || p.plan AND f.test = t.test
  WHERE x.state IS NOT NULL OR (live.named AND p.applicable))
SELECT view, test, aspect, subject, state, current, score,
       json_object('applicable', applicable, 'reason', reason, 'finding', finding, 'fix', fix) AS evidence, '' AS run
FROM rows_;
