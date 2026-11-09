-- The catalog's own words, declared by the engine at every open, before
-- any kit: what the interfaces write and read on their own account. A
-- kit brings vocabulary about the data; these are about the catalog.

-- The reads the interfaces derive from the catalog, as views beside it.
-- Replaced at every open so a view follows the build, never a lake's
-- age; each open is one snapshot of the lake for it.

-- The bound dataset as a relation: the schema in use when it is a
-- dataset's, no row on an unbound channel. The interfaces join it.
CREATE OR REPLACE VIEW main.current_dataset AS
  SELECT current_schema() AS dataset
  WHERE current_schema() IN (SELECT name FROM main.datasets);

-- The agent's current assumptions, one row each: the latest agent
-- annotation per (subject, aspect), its `assumptions` unnested, `idx`
-- from 0. Derived from the agent's CURRENT body, never a frozen copy, so
-- an answered question drops out once the decision is applied and its
-- confidence raised.
CREATE OR REPLACE VIEW main.agent_assumptions AS
  WITH latest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, aspect ORDER BY seq DESC) AS rn
      FROM main.glossary g WHERE actor_kind = 'agent') WHERE rn = 1)
  SELECT l.dataset, l.subject, l.aspect, t.i - 1 AS idx,
         json_extract_string(t.a, '$.dimension') AS dimension,
         json_extract_string(t.a, '$.key') AS key,
         json_extract_string(t.a, '$.assumption') AS assumption,
         json_extract_string(t.a, '$.basis') AS basis,
         json_extract_string(t.a, '$.alternative') AS alternative,
         json_extract(t.a, '$.confidence')::DOUBLE AS conf,
         l.body
  FROM latest l, unnest(coalesce(json_extract(l.body, '$.assumptions')::JSON[], []::JSON[])) WITH ORDINALITY AS t(a, i);

-- A person's current review decisions, one row per entry of the latest
-- `review_decision` body on a subject; `folded_in` once no agent assumption below
-- full confidence carries the decided key under the decided aspect.
CREATE OR REPLACE VIEW main.review_decisions AS
  WITH latest AS (
    SELECT * FROM (
      SELECT r.*, row_number() OVER (PARTITION BY dataset, subject ORDER BY seq DESC) AS rn
      FROM main.glossary r WHERE aspect = 'review_decision' AND actor_kind = 'human') WHERE rn = 1),
  entries AS (
    SELECT l.dataset, l.subject, t.i - 1 AS idx,
           json_extract_string(t.r, '$.aspect') AS aspect,
           json_extract_string(t.r, '$.key') AS key,
           json_extract_string(t.r, '$.stance') AS stance,
           json_extract_string(t.r, '$.dimension') AS dimension,
           coalesce(json_extract_string(t.r, '$.assumption'), '') AS assumption,
           json_extract_string(t.r, '$.note') AS note,
           l.written_at
    FROM latest l, unnest(coalesce(json_extract(l.body, '$.decisions')::JSON[], []::JSON[])) WITH ORDINALITY AS t(r, i))
  SELECT e.dataset, e.subject, e.idx, e.aspect, e.key, e.stance, e.dimension,
         e.assumption, e.note, e.written_at,
         count(a.key) = 0 AS folded_in
  FROM entries e
  LEFT JOIN main.agent_assumptions a
    ON a.dataset = e.dataset AND a.subject = e.subject AND a.aspect = e.aspect
   AND a.key = e.key AND a.conf < 1.0
  GROUP BY ALL;

-- What is still open for a person to judge: a keyed assumption below
-- full confidence in a metric definition, in a dimension no function
-- owns (behavior, sign and grain are statistics), with no current
-- review decision on its (dataset, subject, aspect, key). `sibling`
-- carries a decision on the same key under another aspect, so the
-- review can offer it back. No ORDER BY: order where you consume.
CREATE OR REPLACE VIEW main.open_questions AS
  WITH groundings AS (
    SELECT name FROM (
      SELECT name, kind, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM main.aspects) WHERE rn = 1 AND kind = 'VIEW')
  SELECT o.dataset, o.subject, o.aspect, o.idx, o.dimension, o.key, o.assumption, o.basis,
         o.alternative, o.conf,
         max(s.stance || ' on ' || s.aspect) AS sibling,
         max(s.stance) AS sibling_stance,
         max(s.note) AS sibling_note
  FROM main.agent_assumptions o
  JOIN groundings a ON a.name = o.aspect
  LEFT JOIN main.review_decisions s
    ON s.dataset = o.dataset AND s.subject = o.subject AND s.key = o.key AND s.aspect <> o.aspect
   AND s.stance IN ('confirmed', 'corrected')
  WHERE o.conf < 1.0 AND o.key IS NOT NULL
    AND coalesce(o.dimension, '-') NOT IN ('behavior', 'sign', 'grain')
    AND NOT EXISTS (SELECT 1 FROM main.review_decisions r
                    WHERE r.dataset = o.dataset AND r.subject = o.subject
                      AND r.aspect = o.aspect AND r.key = o.key)
  GROUP BY ALL;

-- Apps authored as glosses, one row per file: the aspect says what kind
-- of file, the subject where it goes — `app` on `<dataset>.<app>` the
-- manifest, `app_page` on `<dataset>.<app>.<page>` a page, `app_frame` a
-- query, `app_spec` a chart spec. Two collapses: the newest writing per
-- (dataset, subject, aspect, actor kind), then the human's over the
-- agent's. This is the draft; the console serves the app at its release.
CREATE OR REPLACE VIEW main.app_parts AS
  WITH newest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, aspect, actor_kind ORDER BY seq DESC) AS rn
      FROM main.glossary g
      WHERE aspect IN ('app', 'app_page', 'app_frame', 'app_spec')
        AND split_part(subject, '.', 1) = dataset AND split_part(subject, '.', 2) <> ''
        AND (aspect = 'app' OR substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) <> '')) WHERE rn = 1),
  winning AS (
    SELECT * FROM newest
    QUALIFY row_number() OVER (PARTITION BY dataset, subject, aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT dataset, split_part(subject, '.', 2) AS app,
         CASE aspect WHEN 'app' THEN 'app'
                     WHEN 'app_page' THEN substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.html'
                     WHEN 'app_frame' THEN 'frames/' || substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.sql'
                     ELSE 'specs/' || substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.vl.json' END AS path,
         CASE aspect WHEN 'app_page' THEN json_extract_string(body, '$.html')
                     WHEN 'app_frame' THEN json_extract_string(body, '$.sql')
                     WHEN 'app_spec' THEN json_extract_string(body, '$.spec')
                     ELSE body::VARCHAR END AS text,
         actor_kind
  FROM winning;

-- What is released of each glossed app: one row per app that carries a
-- release, cut at `at` — the release's own time, or the earlier release
-- its body names. The same two collapses as app_parts.
CREATE OR REPLACE VIEW main.app_releases AS
  WITH newest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, actor_kind ORDER BY seq DESC) AS rn
      FROM main.glossary g
      WHERE aspect = 'app_release' AND split_part(subject, '.', 1) = dataset) WHERE rn = 1),
  winning AS (
    SELECT * FROM newest
    QUALIFY row_number() OVER (PARTITION BY dataset, subject ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT dataset, split_part(subject, '.', 2) AS app,
         coalesce(json_extract_string(body, '$.at'), written_at::VARCHAR) AS at,
         json_extract_string(body, '$.note') AS note,
         actor_kind, written_at::VARCHAR AS released_at
  FROM winning;

-- Every metric the bound dataset claims, with its state: one row per
-- VIEW aspect with a metric definition here, served or stopped, or
-- whose definitions entry names it — name, title, kind (the aspect's
-- x-kind), unit and meaning from the definitions handbook, grounded
-- (a definition with sql was written), stopped (the collapsed
-- definition's own text, '' where it serves). The numbers are
-- metric_axes() and metric_series(); join on name.
CREATE OR REPLACE VIEW main.metric_surfaces AS
  WITH ds AS (SELECT current_schema() AS dataset),
  aspects AS (
    SELECT name, schema FROM (
      SELECT name, kind, schema, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM main.aspects) WHERE rn = 1 AND kind = 'VIEW'),
  slots AS (
    SELECT aspect, body, actor_kind FROM (
      SELECT g.aspect, g.body, g.actor_kind, row_number() OVER (PARTITION BY g.aspect, g.actor_kind ORDER BY g.seq DESC) AS rn
      FROM main.glossary g, ds
      WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.actor_kind IN ('human', 'agent')
        AND g.aspect IN (SELECT name FROM aspects)) WHERE rn = 1),
  collapsed AS (
    SELECT aspect, body FROM slots
    QUALIFY row_number() OVER (PARTITION BY aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1),
  grounded AS (
    SELECT DISTINCT g.aspect FROM main.glossary g, ds
    WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND json_extract_string(g.body, '$.sql') IS NOT NULL),
  registry AS (
    SELECT aspect, body FROM (
      SELECT g.aspect, g.body, g.actor_kind, row_number() OVER (PARTITION BY g.aspect, g.actor_kind ORDER BY g.seq DESC) AS rn
      FROM main.glossary g, ds
      WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.aspect = 'definitions') WHERE rn = 1
    QUALIFY row_number() OVER (PARTITION BY aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT a.name AS name,
         coalesce(json_extract_string(a.schema, '$.title'), a.name) AS title,
         coalesce(json_extract_string(a.schema, '$.x-kind'), '') AS kind,
         coalesce(json_extract_string(d.body, '$.definitions.' || a.name || '.unit'), '') AS unit,
         coalesce(json_extract_string(d.body, '$.definitions.' || a.name || '.meaning'), '') AS meaning,
         coalesce(json_extract_string(d.body, '$.definitions.' || a.name || '.formula'), 'a base concept — grounded as an extract, no formula') AS formula,
         g.aspect IS NOT NULL AS grounded,
         coalesce(json_extract_string(c.body, '$.stopped'), '') AS stopped
  FROM aspects a
  LEFT JOIN grounded g ON g.aspect = a.name
  LEFT JOIN collapsed c ON c.aspect = a.name
  LEFT JOIN registry d ON d.aspect = 'definitions'
  WHERE g.aspect IS NOT NULL OR c.aspect IS NOT NULL
     OR json_extract(d.body, '$.definitions.' || a.name) IS NOT NULL;

-- What this workspace can be extended through, and its state on
-- each: `existing` counts what exists, `open` what is unfinished on the
-- surface and the agent can finish, `waiting` what waits for a person,
-- `how` the statement that extends it. Every count spans the
-- workspace: the orienting read, run from a channel bound to nothing.
CREATE OR REPLACE VIEW main.workspace_next AS
  WITH asked AS (SELECT count(*) AS n, count(DISTINCT aspect) AS metrics FROM main.open_questions),
  ruled AS (SELECT count(*) AS n, count(*) FILTER (WHERE NOT folded_in) AS unapplied FROM main.review_decisions),
  apps AS (SELECT count(*) AS n FROM (SELECT DISTINCT dataset, app FROM main.app_parts)),
  newest_aspects AS (
    SELECT name, kind, grains, condition, schema FROM (
      SELECT name, kind, grains, condition, schema, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM main.aspects) WHERE rn = 1),
  -- A test is open while its property is in use and has no value. A
  -- table or column property is in use on what the metrics read: each
  -- loaded table a metric's view descends from when the property takes
  -- tables, else each such column, where a WHEN holds on that asset;
  -- each asset without a value is open. Every other property counts
  -- once, in use when something that exists needs it: a measurement
  -- marked `x-used-by`, once a property of one of those x-kinds is
  -- declared; a WHEN on another property's value, once an asset carries
  -- that value; a WHEN on a column type, once such a column exists; a
  -- relationship property, once a key is declared; anything else,
  -- always.
  tested AS (
    SELECT DISTINCT a.name, a.kind, a.grains, a.condition, a.schema,
           json_extract(a.schema, '$.x-used-by') IS NULL
             AND (list_contains(a.grains, 'TABLE') OR list_contains(a.grains, 'COLUMN')) AS on_assets
    FROM (SELECT DISTINCT aspect FROM main.tests) t
    JOIN newest_aspects a ON a.name = t.aspect),
  metric_reads AS (
    SELECT DISTINCT split_part(path, '.', 1) AS dataset, split_part(path, '.', 2) AS table_name,
           split_part(path, '.', 3) AS column_name
    FROM (SELECT unnest(regexp_extract_all(l.derivation, '([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*):', 1)) AS path
          FROM glossql_views_lineage(NULL) l
          JOIN newest_aspects m ON m.name = l.view AND m.kind = 'VIEW'
            AND coalesce(json_extract_string(m.schema, '$.x-kind'), '') NOT IN ('sample', 'plan'))),
  assets AS (
    SELECT DISTINCT a.name, a.condition, r.dataset, r.table_name,
           CASE WHEN list_contains(a.grains, 'TABLE') THEN NULL ELSE r.column_name END AS column_name
    FROM tested a, metric_reads r WHERE a.on_assets),
  open_assets AS (
    SELECT s.name FROM assets s
    WHERE (json_extract_string(s.condition, '$.aspect') IS NULL OR EXISTS (
            SELECT 1 FROM main.glossary g
            WHERE g.dataset = s.dataset AND g.subject = concat_ws('.', s.dataset, s.table_name, s.column_name)
              AND g.aspect = json_extract_string(s.condition, '$.aspect')
              AND json_extract_string(g.body, '$.value') = json_extract_string(s.condition, '$.value')))
      AND (json_extract(s.condition, '$.type') IS NULL OR EXISTS (
            SELECT 1 FROM duckdb_columns() c
            WHERE c.database_name = current_database() AND c.schema_name = s.dataset
              AND c.table_name = s.table_name AND c.column_name = s.column_name
              AND list_contains(from_json(json_extract(s.condition, '$.type'), '["VARCHAR"]'), c.data_type)))
      AND NOT EXISTS (
            SELECT 1 FROM main.glossary g
            WHERE g.dataset = s.dataset AND g.subject = concat_ws('.', s.dataset, s.table_name, s.column_name)
              AND g.aspect = s.name)
      AND NOT EXISTS (
            SELECT 1 FROM main.measurements m
            WHERE m.dataset = s.dataset AND m.subject = concat_ws('.', s.dataset, s.table_name, s.column_name)
              AND m.aspect = s.name)),
  in_use AS (
    SELECT a.name,
      CASE
        WHEN json_extract(a.schema, '$.x-used-by') IS NOT NULL THEN EXISTS (
          SELECT 1 FROM newest_aspects u
          WHERE list_contains(from_json(json_extract(a.schema, '$.x-used-by'), '["VARCHAR"]'),
                              json_extract_string(u.schema, '$.x-kind')))
        WHEN json_extract_string(a.condition, '$.aspect') IS NOT NULL THEN EXISTS (
          SELECT 1 FROM main.glossary g
          WHERE g.aspect = json_extract_string(a.condition, '$.aspect')
            AND json_extract_string(g.body, '$.value') = json_extract_string(a.condition, '$.value'))
        WHEN json_extract(a.condition, '$.type') IS NOT NULL THEN EXISTS (
          SELECT 1 FROM duckdb_columns() c
          WHERE c.database_name = current_database()
            AND list_contains(from_json(json_extract(a.condition, '$.type'), '["VARCHAR"]'), c.data_type))
        WHEN a.grains = ['RELATIONSHIP'] THEN EXISTS (SELECT 1 FROM main.relationships)
        ELSE true
      END AS used
    FROM tested a WHERE NOT a.on_assets),
  counts AS (
    SELECT (SELECT count(*) FROM main.sources) AS n_sources,
           (SELECT count(*) FROM (SELECT DISTINCT dataset, table_name FROM main.imports)) AS n_tables,
           (SELECT count(*) FROM (SELECT DISTINCT dataset, table_name FROM main.imports WHERE coalesce(dropped_rows_count, 0) > 0)) AS open_tables,
           (SELECT count(*) FROM main.relationships) AS n_relationships,
           (SELECT count(*) FROM newest_aspects) AS n_aspects,
           (SELECT count(*) FROM main.glossary) AS n_claims,
           0 AS open_claims,
           (SELECT count(DISTINCT name) FROM main.functions) AS n_functions,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'VIEW'
              AND coalesce(json_extract_string(schema, '$.x-kind'), '') NOT IN ('sample', 'plan')) AS n_metrics,
           (SELECT count(*) FROM newest_aspects a WHERE a.kind = 'VIEW'
              AND coalesce(json_extract_string(a.schema, '$.x-kind'), '') NOT IN ('sample', 'plan')
              AND NOT EXISTS (SELECT 1 FROM main.glossary g WHERE g.aspect = a.name)) AS open_metrics,
           (SELECT count(DISTINCT name) FROM main.tests) AS n_validations,
           (SELECT count(*) FROM in_use u WHERE u.used
              AND NOT EXISTS (SELECT 1 FROM main.glossary g WHERE g.aspect = u.name)
              AND NOT EXISTS (SELECT 1 FROM main.measurements m WHERE m.aspect = u.name))
             + (SELECT count(*) FROM open_assets) AS open_validations,
           (SELECT n FROM asked) AS waiting,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'FACT' AND json_extract_string(schema, '$.x-kind') = 'scenario') AS n_scenarios,
           (SELECT count(*) FROM newest_aspects a WHERE a.kind = 'FACT' AND json_extract_string(a.schema, '$.x-kind') = 'scenario'
              AND NOT EXISTS (SELECT 1 FROM main.glossary g WHERE g.aspect = a.name)) AS open_scenarios,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'VIEW' AND json_extract_string(schema, '$.x-kind') = 'plan') AS n_plans,
           (SELECT count(*) FROM newest_aspects a WHERE a.kind = 'VIEW' AND json_extract_string(a.schema, '$.x-kind') = 'plan'
              AND NOT EXISTS (SELECT 1 FROM main.glossary g WHERE g.aspect = a.name)) AS open_plans,
           (SELECT n FROM ruled) AS n_decisions,
           (SELECT unapplied FROM ruled) AS open_decisions,
           (SELECT n FROM apps) AS n_apps)
  SELECT s.surface, s.how,
         CASE s.surface WHEN 'sources' THEN c.n_sources WHEN 'tables' THEN c.n_tables
           WHEN 'relationships' THEN c.n_relationships WHEN 'aspects' THEN c.n_aspects
           WHEN 'claims' THEN c.n_claims WHEN 'functions' THEN c.n_functions
           WHEN 'metrics' THEN c.n_metrics WHEN 'validations' THEN c.n_validations
           WHEN 'scenarios' THEN c.n_scenarios WHEN 'plans' THEN c.n_plans
           WHEN 'review' THEN c.n_decisions ELSE c.n_apps END AS existing,
         CASE s.surface WHEN 'tables' THEN c.open_tables WHEN 'claims' THEN c.open_claims
           WHEN 'metrics' THEN c.open_metrics WHEN 'validations' THEN c.open_validations
           WHEN 'scenarios' THEN c.open_scenarios WHEN 'plans' THEN c.open_plans
           WHEN 'review' THEN c.open_decisions ELSE 0 END AS open,
         CASE s.surface WHEN 'review' THEN c.waiting ELSE 0 END AS waiting
  FROM counts c
  CROSS JOIN (VALUES
    ('sources', 'DECLARE SOURCE, then PREVIEW it — rehearse with LIMIT 0 to see every column before authoring a recipe'),
    ('tables', 'write a load query (recipe) and load it — typing is the load query''s work, this is not ETL'),
    ('relationships', 'DECLARE RELATIONSHIP between two endpoints — detect_relationships proposes, you judge'),
    ('aspects', 'DECLARE ASPECT to add vocabulary — AS FACT, MEASUREMENT or VIEW, grained with ON'),
    ('claims', 'GLOSS an asset with an aspect — the write verb; a person''s annotation outranks the agent''s at every read'),
    ('functions', 'run one as a measurement, or DECLARE FUNCTION your own — statistics are the functions'' work, never a human question'),
    ('metrics', 'GLOSS a VIEW aspect with its SQL and its assumptions — its name then serves it as a view, and its columns carry role, behavior and dimension'),
    ('validations', 'GLOSS the expectation on a FACT aspect, DECLARE FUNCTION the check that RETURNS it, DECLARE TEST with a DETECTOR scoring them — TESTS() serves the test results'),
    ('scenarios', 'DECLARE ASPECT ... AS FACT with x-kind scenario, GLOSS its levers — the outlook kit serves it'),
    ('plans', 'DECLARE ASPECT ... AS VIEW with x-kind plan and x-plan-of the metric it plans, GLOSS its SQL over the loaded budget table — the outlook kit serves the plan world'),
    ('review', 'a person decides on a disclosed assumption; the agent then records the definition again with the decision applied — `waiting` counts the questions waiting for a person, which the agent cannot close'),
    ('apps', 'GLOSS app, app_page, app_frame, app_spec — one gloss per part, so a surface is written like anything else')
  ) AS s(surface, how);

-- A load-query change a person approved for a table: the brief counts it
-- as pending until a load of that table is newer than the approval.
DECLARE ASPECT recipe_change WITH $${
  "type": "object", "required": ["table", "sql", "reason"],
  "properties": {"table": {"type": "string"}, "sql": {"type": "string"},
                 "reason": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- Review decisions: each answer a person gives in the review, the
-- claim it decides by key, confirmed or corrected; the decided aspect's
-- values stay agent-authored and the agent applies the decision. No test
-- on purpose: the actor kind stamps the writer.
DECLARE ASPECT review_decision WITH $${
  "type": "object", "required": ["decisions"],
  "properties": {"decisions": {"type": "array", "items": {
    "type": "object", "required": ["aspect", "key", "stance"],
    "properties": {"aspect": {"type": "string"},
                   "dimension": {"type": "string"},
                   "key": {"type": "string"},
                   "assumption": {"type": "string"},
                   "stance": {"enum": ["confirmed", "corrected", "unclear"]},
                   "note": {"type": "string"}}}}}
}$$ AS FACT;

-- Apps as glosses: one gloss per part, the aspect the kind of file, the
-- subject where it goes. Grainless and without a test: a part is no claim
-- about the data.
DECLARE ASPECT app WITH $${
  "type": "object", "required": ["title"],
  "properties": {"title": {"type": "string"}, "dataset": {"type": "string"}}
}$$ AS FACT;

DECLARE ASPECT app_page WITH $${
  "type": "object", "required": ["html"],
  "properties": {"html": {"type": "string"}}
}$$ AS FACT;

DECLARE ASPECT app_frame WITH $${
  "type": "object", "required": ["sql"],
  "properties": {"sql": {"type": "string"}}
}$$ AS FACT;

DECLARE ASPECT app_spec WITH $${
  "type": "object", "required": ["spec"],
  "properties": {"spec": {"type": "string"}}
}$$ AS FACT;

DECLARE ASPECT app_release WITH $${
  "type": "object",
  "properties": {"note": {"type": "string"}, "at": {"type": "string"}}
}$$ AS FACT;

-- How the console and the apps print a number: grouped thousands from
-- 1,000 up, three significant digits below, plain decimals under 0.001.
CREATE OR REPLACE MACRO main.fmt_number(x) AS
  CASE WHEN x IS NULL THEN NULL
       WHEN abs(x::DOUBLE) >= 999.5 THEN format('{:,.0f}', x::DOUBLE)
       WHEN x::DOUBLE = 0 OR abs(x::DOUBLE) >= 0.001 THEN format('{:.3g}', x::DOUBLE)
       ELSE rtrim(rtrim(format('{:.9f}', x::DOUBLE), '0'), '.') END;

-- A change in percent, signed: +12.3%, -0.04%.
CREATE OR REPLACE MACRO main.fmt_change(p) AS
  CASE WHEN p IS NULL THEN NULL
       WHEN p::DOUBLE < 0 THEN '-' || main.fmt_number(abs(p::DOUBLE)) || '%'
       ELSE '+' || main.fmt_number(p::DOUBLE) || '%' END;
