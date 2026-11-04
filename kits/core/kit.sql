-- The record's own words, declared by the engine at every open, before
-- any kit: what the doors write and read on their own account. A kit
-- brings vocabulary about the data; these are about the record.

-- The reads the doors derive from the record, as views beside it.
-- Replaced at every open so a view follows the build, never a lake's
-- age; each open is one snapshot of the lake for it.

-- The bound dataset as a relation: the schema in use when it is a
-- dataset's, no row on an unbound channel. The doors join it.
CREATE OR REPLACE VIEW ws.main.current_dataset AS
  SELECT current_schema() AS dataset
  WHERE current_schema() IN (SELECT name FROM ws.main.datasets);

-- The agent's current assumptions, one row each: the latest agent
-- gloss per slot, its `assumptions` unnested, `idx` from 0. Derived
-- from the agent's CURRENT body, never a frozen copy, so an answered
-- question drops out when the fold-in raises its confidence.
CREATE OR REPLACE VIEW ws.main.agent_assumptions AS
  WITH latest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, aspect ORDER BY seq DESC) AS rn
      FROM ws.main.glossary g WHERE actor_kind = 'agent') WHERE rn = 1)
  SELECT l.dataset, l.subject, l.aspect, t.i - 1 AS idx,
         json_extract_string(t.a, '$.dimension') AS dimension,
         json_extract_string(t.a, '$.key') AS key,
         json_extract_string(t.a, '$.assumption') AS assumption,
         json_extract_string(t.a, '$.basis') AS basis,
         json_extract_string(t.a, '$.alternative') AS alternative,
         json_extract(t.a, '$.confidence')::DOUBLE AS conf,
         l.body
  FROM latest l, unnest(coalesce(json_extract(l.body, '$.assumptions')::JSON[], []::JSON[])) WITH ORDINALITY AS t(a, i);

-- The human's standing rulings, one row per entry of the latest ruling
-- body on a subject; `folded_in` once no agent assumption below full
-- confidence carries the ruled key under the ruled aspect.
CREATE OR REPLACE VIEW ws.main.ruling_entries AS
  WITH latest AS (
    SELECT * FROM (
      SELECT r.*, row_number() OVER (PARTITION BY dataset, subject ORDER BY seq DESC) AS rn
      FROM ws.main.glossary r WHERE aspect = 'ruling' AND actor_kind = 'human') WHERE rn = 1),
  entries AS (
    SELECT l.dataset, l.subject, t.i - 1 AS idx,
           json_extract_string(t.r, '$.aspect') AS aspect,
           json_extract_string(t.r, '$.key') AS key,
           json_extract_string(t.r, '$.stance') AS stance,
           json_extract_string(t.r, '$.dimension') AS dimension,
           coalesce(json_extract_string(t.r, '$.assumption'), '') AS assumption,
           json_extract_string(t.r, '$.note') AS note,
           l.written_at
    FROM latest l, unnest(coalesce(json_extract(l.body, '$.rulings')::JSON[], []::JSON[])) WITH ORDINALITY AS t(r, i))
  SELECT e.dataset, e.subject, e.idx, e.aspect, e.key, e.stance, e.dimension,
         e.assumption, e.note, e.written_at,
         count(a.key) = 0 AS folded_in
  FROM entries e
  LEFT JOIN ws.main.agent_assumptions a
    ON a.dataset = e.dataset AND a.subject = e.subject AND a.aspect = e.aspect
   AND a.key = e.key AND a.conf < 1.0
  GROUP BY ALL;

-- What still stands open for a human to judge: a keyed assumption
-- below full confidence on a grounding, in a dimension no function
-- owns (behavior, sign and grain are statistics), with no standing
-- ruling on its (dataset, subject, aspect, key). `sibling` carries a
-- ruling on the same key under another aspect, so the round can offer
-- it back. No ORDER BY: order where you consume.
CREATE OR REPLACE VIEW ws.main.open_questions AS
  WITH groundings AS (
    SELECT name FROM (
      SELECT name, kind, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM ws.main.aspects) WHERE rn = 1 AND kind = 'QUERY')
  SELECT o.dataset, o.subject, o.aspect, o.idx, o.dimension, o.key, o.assumption, o.basis,
         o.alternative, o.conf,
         max(s.stance || ' on ' || s.aspect) AS sibling,
         max(s.stance) AS sibling_stance,
         max(s.note) AS sibling_note
  FROM ws.main.agent_assumptions o
  JOIN groundings a ON a.name = o.aspect
  LEFT JOIN ws.main.ruling_entries s
    ON s.dataset = o.dataset AND s.subject = o.subject AND s.key = o.key AND s.aspect <> o.aspect
   AND s.stance IN ('confirmed', 'corrected')
  WHERE o.conf < 1.0 AND o.key IS NOT NULL
    AND coalesce(o.dimension, '-') NOT IN ('behavior', 'sign', 'grain')
    AND NOT EXISTS (SELECT 1 FROM ws.main.ruling_entries r
                    WHERE r.dataset = o.dataset AND r.subject = o.subject
                      AND r.aspect = o.aspect AND r.key = o.key)
  GROUP BY ALL;

-- Apps authored as glosses, one row per file: the aspect says what kind
-- of file, the subject where it goes — `app` on `<dataset>.<app>` the
-- manifest, `app_page` on `<dataset>.<app>.<page>` a page, `app_frame` a
-- query, `app_spec` a chart spec. Two collapses: the newest writing per
-- (dataset, subject, aspect, actor kind), then the human's over the
-- agent's. This is the draft; the door serves the app at its release.
CREATE OR REPLACE VIEW ws.main.app_parts AS
  WITH newest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, aspect, actor_kind ORDER BY seq DESC) AS rn
      FROM ws.main.glossary g
      WHERE aspect IN ('app', 'app_page', 'app_frame', 'app_spec')
        AND split_part(subject, '.', 1) = dataset AND split_part(subject, '.', 2) <> ''
        AND (aspect = 'app' OR split_part(subject, '.', 3) <> '')) WHERE rn = 1),
  winning AS (
    SELECT * FROM newest
    QUALIFY row_number() OVER (PARTITION BY dataset, subject, aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT dataset, split_part(subject, '.', 2) AS app,
         CASE aspect WHEN 'app' THEN 'app'
                     WHEN 'app_page' THEN split_part(subject, '.', 3) || '.html'
                     WHEN 'app_frame' THEN 'frames/' || split_part(subject, '.', 3) || '.sql'
                     ELSE 'specs/' || split_part(subject, '.', 3) || '.vl.json' END AS path,
         CASE aspect WHEN 'app_page' THEN json_extract_string(body, '$.html')
                     WHEN 'app_frame' THEN json_extract_string(body, '$.sql')
                     WHEN 'app_spec' THEN json_extract_string(body, '$.spec')
                     ELSE body::VARCHAR END AS text,
         actor_kind
  FROM winning;

-- What is released of each glossed app: one row per app that carries a
-- release, cut at `at` — the release's own time, or the earlier release
-- its body names. The same two collapses as app_parts.
CREATE OR REPLACE VIEW ws.main.app_releases AS
  WITH newest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, actor_kind ORDER BY seq DESC) AS rn
      FROM ws.main.glossary g
      WHERE aspect = 'app_release' AND split_part(subject, '.', 1) = dataset) WHERE rn = 1),
  winning AS (
    SELECT * FROM newest
    QUALIFY row_number() OVER (PARTITION BY dataset, subject ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT dataset, split_part(subject, '.', 2) AS app,
         coalesce(json_extract_string(body, '$.at'), written_at::VARCHAR) AS at,
         json_extract_string(body, '$.note') AS note,
         actor_kind, written_at::VARCHAR AS released_at
  FROM winning;

-- Every metric the bound dataset claims, with where it stands: one row
-- per QUERY aspect a grounding stands on here, served or stopped, or
-- whose definitions entry names it — name, title, kind (the aspect's
-- x-kind), unit and meaning from the definitions handbook, grounded
-- (a grounding with sql was written), stopped (the collapsed
-- grounding's own text, '' where it serves). The numbers are
-- metric_axes() and metric_series(); join on name.
CREATE OR REPLACE VIEW ws.main.metric_surfaces AS
  WITH ds AS (SELECT current_schema() AS dataset),
  aspects AS (
    SELECT name, schema FROM (
      SELECT name, kind, schema, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM ws.main.aspects) WHERE rn = 1 AND kind = 'QUERY'),
  slots AS (
    SELECT aspect, body, actor_kind FROM (
      SELECT g.aspect, g.body, g.actor_kind, row_number() OVER (PARTITION BY g.aspect, g.actor_kind ORDER BY g.seq DESC) AS rn
      FROM ws.main.glossary g, ds
      WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.actor_kind IN ('human', 'agent')
        AND g.aspect IN (SELECT name FROM aspects)) WHERE rn = 1),
  collapsed AS (
    SELECT aspect, body FROM slots
    QUALIFY row_number() OVER (PARTITION BY aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1),
  grounded AS (
    SELECT DISTINCT g.aspect FROM ws.main.glossary g, ds
    WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND json_extract_string(g.body, '$.sql') IS NOT NULL),
  registry AS (
    SELECT aspect, body FROM (
      SELECT g.aspect, g.body, g.actor_kind, row_number() OVER (PARTITION BY g.aspect, g.actor_kind ORDER BY g.seq DESC) AS rn
      FROM ws.main.glossary g, ds
      WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND g.aspect IN ('definitions', 'formulas')) WHERE rn = 1
    QUALIFY row_number() OVER (PARTITION BY aspect ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END) = 1)
  SELECT a.name AS name,
         coalesce(json_extract_string(a.schema, '$.title'), a.name) AS title,
         coalesce(json_extract_string(a.schema, '$.x-kind'), '') AS kind,
         coalesce(json_extract_string(d.body, '$.definitions.' || a.name || '.unit'), '') AS unit,
         coalesce(json_extract_string(d.body, '$.definitions.' || a.name || '.meaning'), '') AS meaning,
         coalesce(json_extract_string(f.body, '$.formulas.' || a.name), 'a base concept — grounded as an extract, no formula') AS formula,
         g.aspect IS NOT NULL AS grounded,
         coalesce(json_extract_string(c.body, '$.stopped'), '') AS stopped
  FROM aspects a
  LEFT JOIN grounded g ON g.aspect = a.name
  LEFT JOIN collapsed c ON c.aspect = a.name
  LEFT JOIN registry d ON d.aspect = 'definitions'
  LEFT JOIN registry f ON f.aspect = 'formulas'
  WHERE g.aspect IS NOT NULL OR c.aspect IS NOT NULL
     OR json_extract(d.body, '$.definitions.' || a.name) IS NOT NULL
     OR json_extract(f.body, '$.formulas.' || a.name) IS NOT NULL;

-- What this workspace can be extended through, and where it stands on
-- each: `stands` counts what exists, `open` what is unfinished on the
-- surface, `how` the statement that extends it. Every count spans the
-- workspace: the orienting read, run from a channel bound to nothing.
CREATE OR REPLACE VIEW ws.main.workspace_next AS
  WITH asked AS (SELECT count(*) AS n, count(DISTINCT aspect) AS metrics FROM ws.main.open_questions),
  ruled AS (SELECT count(*) AS n, count(*) FILTER (WHERE NOT folded_in) AS owed FROM ws.main.ruling_entries),
  apps AS (SELECT count(*) AS n FROM (SELECT DISTINCT dataset, app FROM ws.main.app_parts)),
  newest_aspects AS (
    SELECT name, kind, schema FROM (
      SELECT name, kind, schema, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM ws.main.aspects) WHERE rn = 1),
  counts AS (
    SELECT (SELECT count(*) FROM ws.main.sources) AS n_sources,
           (SELECT count(*) FROM (SELECT DISTINCT dataset, table_name FROM ws.main.imports)) AS n_tables,
           (SELECT count(*) FROM (SELECT DISTINCT dataset, table_name FROM ws.main.imports WHERE coalesce(dropped_rows_count, 0) > 0)) AS open_tables,
           (SELECT count(*) FROM ws.main.relationships) AS n_relationships,
           (SELECT count(*) FROM newest_aspects) AS n_aspects,
           (SELECT count(*) FROM ws.main.glossary) AS n_claims,
           (SELECT n FROM asked) AS open_claims,
           (SELECT count(DISTINCT name) FROM ws.main.functions) AS n_functions,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'QUERY'
              AND coalesce(json_extract_string(schema, '$.x-kind'), '') NOT IN ('sample', 'plan')) AS n_metrics,
           (SELECT metrics FROM asked) AS open_metrics,
           (SELECT count(DISTINCT name) FROM ws.main.witnesses) AS n_validations,
           (SELECT count(*) FROM (SELECT DISTINCT aspect FROM ws.main.witnesses) w
            WHERE NOT EXISTS (SELECT 1 FROM ws.main.glossary g WHERE g.aspect = w.aspect)
              AND NOT EXISTS (SELECT 1 FROM ws.main.measurements m WHERE m.aspect = w.aspect)) AS open_validations,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'FACT' AND json_extract_string(schema, '$.x-kind') = 'scenario') AS n_scenarios,
           (SELECT count(*) FROM newest_aspects a WHERE a.kind = 'FACT' AND json_extract_string(a.schema, '$.x-kind') = 'scenario'
              AND NOT EXISTS (SELECT 1 FROM ws.main.glossary g WHERE g.aspect = a.name)) AS open_scenarios,
           (SELECT count(*) FROM newest_aspects WHERE kind = 'QUERY' AND json_extract_string(schema, '$.x-kind') = 'plan') AS n_plans,
           (SELECT count(*) FROM newest_aspects a WHERE a.kind = 'QUERY' AND json_extract_string(a.schema, '$.x-kind') = 'plan'
              AND NOT EXISTS (SELECT 1 FROM ws.main.glossary g WHERE g.aspect = a.name)) AS open_plans,
           (SELECT n FROM ruled) AS n_rulings,
           (SELECT owed FROM ruled) AS open_rulings,
           (SELECT n FROM apps) AS n_apps)
  SELECT s.surface, s.how,
         CASE s.surface WHEN 'sources' THEN c.n_sources WHEN 'tables' THEN c.n_tables
           WHEN 'relationships' THEN c.n_relationships WHEN 'aspects' THEN c.n_aspects
           WHEN 'claims' THEN c.n_claims WHEN 'functions' THEN c.n_functions
           WHEN 'metrics' THEN c.n_metrics WHEN 'validations' THEN c.n_validations
           WHEN 'scenarios' THEN c.n_scenarios WHEN 'plans' THEN c.n_plans
           WHEN 'rulings' THEN c.n_rulings ELSE c.n_apps END AS stands,
         CASE s.surface WHEN 'tables' THEN c.open_tables WHEN 'claims' THEN c.open_claims
           WHEN 'metrics' THEN c.open_metrics WHEN 'validations' THEN c.open_validations
           WHEN 'scenarios' THEN c.open_scenarios WHEN 'plans' THEN c.open_plans
           WHEN 'rulings' THEN c.open_rulings ELSE 0 END AS open
  FROM counts c
  CROSS JOIN (VALUES
    ('sources', 'DECLARE SOURCE, then PROBE it — rehearse with LIMIT 0 to see every column before authoring a recipe'),
    ('tables', 'author a recipe and extract it — typing is the recipe''s work, this is not ETL'),
    ('relationships', 'DECLARE RELATIONSHIP between two endpoints — detect_relationships proposes, you judge'),
    ('aspects', 'DECLARE ASPECT to add vocabulary — AS FACT, MEASUREMENT or QUERY, grained with ON'),
    ('claims', 'GLOSS a subject with an aspect — the write verb; a human writing outranks the agent slot at every read'),
    ('functions', 'run one as a measurement, or DECLARE FUNCTION your own — statistics are the functions'' work, never a human question'),
    ('metrics', 'GLOSS a QUERY aspect with its SQL and its assumptions — its name then serves it as a view, and its columns carry role, behavior and dimension'),
    ('validations', 'GLOSS the expectation on a FACT aspect, DECLARE FUNCTION the check that RETURNS it, DECLARE WITNESS with a DETECTOR banding them — ATTEST() serves the verdicts'),
    ('scenarios', 'DECLARE ASPECT ... AS FACT with x-kind scenario, GLOSS its levers — the futures kit serves it'),
    ('plans', 'DECLARE ASPECT ... AS QUERY with x-kind plan and x-plan-of the metric it plans, GLOSS its SQL over the landed budget table — the futures kit serves the plan world'),
    ('rulings', 'a human rules a disclosed assumption; the agent owes the re-record that folds it in'),
    ('apps', 'GLOSS app, app_page, app_frame, app_spec — one gloss per part, so a surface is written like anything else')
  ) AS s(surface, how);

-- A recipe change a human approved for a table: the brief counts it as
-- pending until a landing of that table is newer than the approval.
DECLARE ASPECT recipe_change WITH $${
  "type": "object", "required": ["table", "sql", "reason"],
  "properties": {"table": {"type": "string"}, "sql": {"type": "string"},
                 "reason": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- The ruling channel: each human judgment the question round lands, the
-- claim it rules by key, confirmed or corrected; the ruled aspect's
-- slots stay agent-authored and the agent owes the fold-in. Witness-free
-- on purpose: the actor kind stamps the writer.
DECLARE ASPECT ruling WITH $${
  "type": "object", "required": ["rulings"],
  "properties": {"rulings": {"type": "array", "items": {
    "type": "object", "required": ["aspect", "key", "stance"],
    "properties": {"aspect": {"type": "string"},
                   "dimension": {"type": "string"},
                   "key": {"type": "string"},
                   "assumption": {"type": "string"},
                   "stance": {"enum": ["confirmed", "corrected", "unclear"]},
                   "note": {"type": "string"}}}}}
}$$ AS FACT;

-- Apps as glosses: one gloss per part, the aspect the kind of file, the
-- subject where it goes. Grainless and witness-free: a part is no claim
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
