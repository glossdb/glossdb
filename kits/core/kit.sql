-- The catalog's own words, declared by the engine at every open, before
-- any kit: what the interfaces write and read on their own account. A
-- kit brings vocabulary about the data; these are about the catalog.

-- The reads the interfaces derive from the catalog, as views beside it.
-- Replaced at every open so a view follows the build, never a lake's
-- age; each open is one snapshot of the lake for it.

-- quoted_name(name): one name as a statement spells it: as it is where it
-- is a lower-case name and no reserved word, a placeholder (<...>) too,
-- else double-quoted. subject_path(subject): a stored subject as a
-- statement names it, dataset.table.column, the column all that follows
-- the second dot, each name as quoted_name spells it; a relationship
-- stays as it is. The reserved words are DuckDB's (duckdb_keywords()),
-- written out: a function's body may not read the engine's catalog.
CREATE OR REPLACE MACRO main.quoted_name(n) AS
  CASE WHEN (regexp_full_match(n, '[a-z_][a-z0-9_]*')
             AND NOT list_contains(['all', 'analyse', 'analyze', 'and', 'any', 'array', 'as', 'asc', 'asymmetric', 'both', 'case',
               'cast', 'check', 'collate', 'column', 'constraint', 'create', 'default', 'deferrable', 'desc', 'describe', 'distinct',
               'do', 'else', 'end', 'except', 'false', 'fetch', 'for', 'foreign', 'from', 'group', 'having', 'in', 'initially',
               'intersect', 'into', 'lambda', 'lateral', 'leading', 'limit', 'not', 'null', 'offset', 'on', 'only', 'or', 'order',
               'pivot', 'pivot_longer', 'pivot_wider', 'placing', 'primary', 'qualify', 'references', 'returning', 'select', 'show',
               'some', 'summarize', 'symmetric', 'table', 'then', 'to', 'trailing', 'true', 'union', 'unique', 'unpivot', 'using',
               'variadic', 'when', 'where', 'window', 'with'], n))
            OR regexp_full_match(n, '<[^<>]*>') THEN n
       ELSE '"' || replace(n, '"', '""') || '"' END;

CREATE OR REPLACE MACRO main.subject_path(s) AS
  CASE WHEN contains(s, ' -> ') THEN s
       ELSE main.quoted_name(split_part(s, '.', 1))
            || CASE WHEN contains(s, '.') THEN '.' || main.quoted_name(split_part(s, '.', 2)) ELSE '' END
            || CASE WHEN length(s) - length(replace(s, '.', '')) >= 2
                    THEN '.' || main.quoted_name(substr(s, length(split_part(s, '.', 1)) + length(split_part(s, '.', 2)) + 3))
                    ELSE '' END END;

-- The bound dataset as a relation: the schema in use when it is a
-- dataset's, no row on an unbound channel. The interfaces join it.
CREATE OR REPLACE VIEW main.current_dataset AS
  SELECT current_schema() AS dataset
  WHERE current_schema() IN (SELECT name FROM main.datasets);

-- Each annotation a person or an agent wrote, with its rank among the
-- annotations on its asset and property: 1 for the one the console shows, a
-- person's over an agent's; 2 for an agent's that a person's outranks. Unlike
-- GLOSSARY(), it withholds no value in conflict and keeps who wrote each.
CREATE OR REPLACE VIEW main.ranked_annotations AS
  SELECT dataset, subject, property, actor_kind, actor_id, body, written_at, begin_snapshot,
         row_number() OVER (PARTITION BY subject, property
           ORDER BY CASE actor_kind WHEN 'human' THEN 0 ELSE 1 END, begin_snapshot DESC) AS rank
  FROM main.glossary
  WHERE actor_kind IN ('human', 'agent');

-- The agent's current assumptions, one row each: the latest agent
-- annotation per (subject, property), its `assumptions` unnested, `idx`
-- from 0. Derived from the agent's CURRENT body, never a frozen copy, so
-- an answered question drops out once the decision is applied and its
-- confidence raised.
CREATE OR REPLACE VIEW main.agent_assumptions AS
  WITH latest AS (SELECT * FROM main.glossary WHERE actor_kind = 'agent')
  SELECT l.dataset, l.subject, l.property, t.i - 1 AS idx,
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
-- full confidence carries the decided key under the decided property.
CREATE OR REPLACE VIEW main.review_decisions AS
  WITH latest AS (SELECT * FROM main.glossary WHERE property = 'review_decision' AND actor_kind = 'human'),
  entries AS (
    SELECT l.dataset, l.subject, t.i - 1 AS idx,
           json_extract_string(t.r, '$.property') AS property,
           json_extract_string(t.r, '$.key') AS key,
           json_extract_string(t.r, '$.stance') AS stance,
           json_extract_string(t.r, '$.dimension') AS dimension,
           coalesce(json_extract_string(t.r, '$.assumption'), '') AS assumption,
           json_extract_string(t.r, '$.note') AS note,
           l.written_at
    FROM latest l, unnest(coalesce(json_extract(l.body, '$.decisions')::JSON[], []::JSON[])) WITH ORDINALITY AS t(r, i))
  SELECT e.dataset, e.subject, e.idx, e.property, e.key, e.stance, e.dimension,
         e.assumption, e.note, e.written_at,
         count(a.key) = 0 AS folded_in
  FROM entries e
  LEFT JOIN main.agent_assumptions a
    ON a.dataset = e.dataset AND a.subject = e.subject AND a.property = e.property
   AND a.key = e.key AND a.conf < 1.0
  GROUP BY ALL;

-- What is still open for a person to judge: a keyed assumption below
-- full confidence in a metric definition, in a dimension no function
-- owns (additivity, sign and grain are statistics), with no current
-- review decision on its (dataset, subject, property, key). `sibling`
-- carries a decision on the same key under another property, so the
-- review can offer it back. No ORDER BY: order where you consume.
CREATE OR REPLACE VIEW main.open_questions AS
  WITH view_properties AS (SELECT name FROM main.properties WHERE kind = 'VIEW')
  SELECT o.dataset, o.subject, o.property, o.idx, o.dimension, o.key, o.assumption, o.basis,
         o.alternative, o.conf,
         max(s.stance || ' on ' || s.property) AS sibling,
         max(s.stance) AS sibling_stance,
         max(s.note) AS sibling_note
  FROM main.agent_assumptions o
  JOIN view_properties a ON a.name = o.property
  LEFT JOIN main.review_decisions s
    ON s.dataset = o.dataset AND s.subject = o.subject AND s.key = o.key AND s.property <> o.property
   AND s.stance IN ('confirmed', 'corrected')
  WHERE o.conf < 1.0 AND o.key IS NOT NULL
    AND coalesce(o.dimension, '-') NOT IN ('additivity', 'sign', 'grain')
    AND {'dataset': o.dataset, 'subject': o.subject, 'property': o.property, 'key': o.key} NOT IN (
          SELECT {'dataset': r.dataset, 'subject': r.subject, 'property': r.property, 'key': r.key} FROM main.review_decisions r
          WHERE r.dataset IS NOT NULL AND r.subject IS NOT NULL AND r.property IS NOT NULL AND r.key IS NOT NULL)
  GROUP BY ALL;

-- Apps authored as glosses, one row per file: the property says what kind
-- of file, the subject where it goes — `app` on `<dataset>.<app>` the
-- manifest, `app_page` on `<dataset>.<app>.<page>` a page, `app_frame` a
-- query, `app_spec` a chart spec, the one ranked_annotations ranks first.
-- This is the draft; the console serves the app at its release.
CREATE OR REPLACE VIEW main.app_parts AS
  WITH winning AS (
    SELECT * FROM main.ranked_annotations
    WHERE rank = 1 AND property IN ('app', 'app_page', 'app_frame', 'app_spec')
      AND split_part(subject, '.', 1) = dataset AND split_part(subject, '.', 2) <> ''
      AND (property = 'app' OR substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) <> ''))
  SELECT dataset, split_part(subject, '.', 2) AS app,
         CASE property WHEN 'app' THEN 'app'
                     WHEN 'app_page' THEN substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.html'
                     WHEN 'app_frame' THEN 'frames/' || substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.sql'
                     ELSE 'specs/' || substr(subject, length(split_part(subject, '.', 1)) + length(split_part(subject, '.', 2)) + 3) || '.vl.json' END AS path,
         CASE property WHEN 'app_page' THEN json_extract_string(body, '$.html')
                     WHEN 'app_frame' THEN json_extract_string(body, '$.sql')
                     WHEN 'app_spec' THEN json_extract_string(body, '$.spec')
                     ELSE body::VARCHAR END AS text,
         actor_kind
  FROM winning;

-- What is released of each glossed app: one row per app that carries a
-- release, cut at `at` — the release's own time, or the earlier release
-- its body names, the one ranked_annotations ranks first.
CREATE OR REPLACE VIEW main.app_releases AS
  WITH winning AS (
    SELECT * FROM main.ranked_annotations WHERE rank = 1 AND property = 'app_release' AND split_part(subject, '.', 1) = dataset)
  SELECT dataset, split_part(subject, '.', 2) AS app,
         coalesce(json_extract_string(body, '$.at'), written_at::VARCHAR) AS at,
         json_extract_string(body, '$.note') AS note,
         actor_kind, written_at::VARCHAR AS released_at
  FROM winning;

-- Every view of the bound dataset, with its state: one row per VIEW
-- property with a definition here, served or stopped — name, title, kind
-- (the property's x-kind: relation, scalar; measure for a metric),
-- meaning (the `meaning` annotation on the view), unit (the `unit`
-- annotation on the value column of a metric or a single value; a table
-- has none), defined (a definition with sql was written), stopped (the
-- definition's stop reason, '' where it serves). The numbers are
-- view_summary() and metric_series(); join on name.
CREATE OR REPLACE VIEW main.view_definitions AS
  WITH ds AS (SELECT current_schema() AS dataset),
  properties AS (SELECT name, schema FROM main.properties WHERE kind = 'VIEW'),
  collapsed AS (
    SELECT g.property, g.body FROM main.ranked_annotations g, ds
    WHERE g.rank = 1 AND g.subject = ds.dataset AND g.property IN (SELECT name FROM properties)),
  defined AS (
    SELECT DISTINCT g.property FROM main.glossary g, ds
    WHERE g.dataset = ds.dataset AND g.subject = ds.dataset AND json_extract_string(g.body, '$.sql') IS NOT NULL),
  -- the annotations in force on the view and on its columns
  in_force AS (
    SELECT subject, property, value FROM glossql_glossary(current_schema(), NULL, false)
    WHERE property IN ('meaning', 'unit') AND value IS NOT NULL AND state IN ('current', 'stale')),
  meanings AS (
    SELECT split_part(subject, '.', 2) AS view, value->>'value' AS meaning
    FROM in_force WHERE property = 'meaning' AND len(string_split(subject, '.')) = 2),
  -- a metric's unit is its value column's: the column named value where several carry one
  units AS (
    SELECT split_part(subject, '.', 2) AS view,
           arg_min(value->>'value', CASE WHEN split_part(subject, '.', 3) = 'value' THEN 0 ELSE 1 END) AS unit
    FROM in_force WHERE property = 'unit' AND len(string_split(subject, '.')) = 3
    GROUP BY 1)
  SELECT a.name AS name,
         coalesce(json_extract_string(a.schema, '$.title'), a.name) AS title,
         coalesce(json_extract_string(a.schema, '$.x-kind'), 'measure') AS kind,
         coalesce(CASE WHEN json_extract_string(a.schema, '$.x-kind') IS DISTINCT FROM 'relation' THEN u.unit END, '') AS unit,
         coalesce(m.meaning, '') AS meaning,
         g.property IS NOT NULL AS defined,
         coalesce(json_extract_string(c.body, '$.stopped'), '') AS stopped
  FROM properties a
  LEFT JOIN defined g ON g.property = a.name
  LEFT JOIN collapsed c ON c.property = a.name
  LEFT JOIN meanings m ON m.view = a.name
  LEFT JOIN units u ON u.view = a.name
  WHERE g.property IS NOT NULL OR c.property IS NOT NULL;

-- tested_properties(): the table and column properties that exist to
-- be tested, by name: a test with a scoring function is declared on
-- the property, and a check measures it (a function returns the
-- property, or the property is a measurement). Such a property is set
-- on the assets someone chose: the expectation is annotated there, or
-- a result is stored there. It is not required on every asset a view
-- reads, as a descriptive property (meaning, role, entity) is. A
-- kit's check on a view (x-subject) and a measurement the server runs
-- for a kind of view (x-used-by) follow their own rules.
CREATE OR REPLACE MACRO main.tested_properties() AS TABLE
  SELECT a.name
  FROM main.properties a
  WHERE a.kind IN ('FACT', 'MEASUREMENT')
    AND (list_contains(a.grains, 'TABLE') OR list_contains(a.grains, 'COLUMN'))
    AND json_extract(a.schema, '$.x-subject') IS NULL
    AND json_extract(a.schema, '$.x-used-by') IS NULL
    AND a.name IN (SELECT t.property FROM main.tests t WHERE t.detector IS NOT NULL)
    AND (a.kind = 'MEASUREMENT' OR a.name IN (SELECT f.returns FROM main.functions f));

-- A load-query change a person approved for a table: the summary counts it
-- as pending until a load of that table is newer than the approval.
DECLARE PROPERTY recipe_change WITH $${
  "type": "object", "required": ["table", "sql", "reason"],
  "properties": {"table": {"type": "string"}, "sql": {"type": "string"},
                 "reason": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- What a source sends at each delivery, stated on the table loaded from
-- it: `full`, the complete state, so a row a file lacks is gone at the
-- source; `incremental`, only new and changed rows. A person's
-- annotation confirms or corrects the agent's. load_modes() (the goals
-- kit) holds each table's newest load against it.
DECLARE PROPERTY delivery WITH $${
  "description": "What the source sends at each delivery: the complete state (full), or only new and changed rows (incremental).",
  "type": "object", "required": ["value"],
  "properties": {"value": {"enum": ["full", "incremental"]}, "basis": {"type": "string"}}
}$$ AS FACT ON TABLE;

-- Review decisions: each answer a person gives in the review, the
-- claim it decides by key, confirmed or corrected; the decided property's
-- values stay agent-authored and the agent applies the decision. No test
-- on purpose: the actor kind stamps the writer.
DECLARE PROPERTY review_decision WITH $${
  "type": "object", "required": ["decisions"],
  "properties": {"decisions": {"type": "array", "items": {
    "type": "object", "required": ["property", "key", "stance"],
    "properties": {"property": {"type": "string"},
                   "dimension": {"type": "string"},
                   "key": {"type": "string"},
                   "assumption": {"type": "string"},
                   "stance": {"enum": ["confirmed", "corrected", "unclear"]},
                   "note": {"type": "string"}}}}}
}$$ AS FACT;

-- Apps as glosses: one gloss per part, the property the kind of file, the
-- subject where it goes. Grainless and without a test: a part is no claim
-- about the data.
DECLARE PROPERTY app WITH $${
  "type": "object", "required": ["title"],
  "properties": {"title": {"type": "string"}, "dataset": {"type": "string"}}
}$$ AS FACT;

DECLARE PROPERTY app_page WITH $${
  "type": "object", "required": ["html"],
  "properties": {"html": {"type": "string"}}
}$$ AS FACT;

DECLARE PROPERTY app_frame WITH $${
  "type": "object", "required": ["sql"],
  "properties": {"sql": {"type": "string"}}
}$$ AS FACT;

DECLARE PROPERTY app_spec WITH $${
  "type": "object", "required": ["spec"],
  "properties": {"spec": {"type": "string"}}
}$$ AS FACT;

DECLARE PROPERTY app_release WITH $${
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

-- The strings a CSV export writes where it has no value, for the CSV
-- reader's `nullstr`: the common spellings, a spreadsheet's error
-- cells, dashes of two or more, and the words for missing. A single
-- `-`, `.` or `*`, a number such as -999 and a date such as 1900-01-01
-- are left out: they can be real values, and the column profile shows
-- them.
CREATE OR REPLACE MACRO main.null_markers() AS
  ['', 'NULL', 'null', 'None', 'NaN', 'NA', 'N/A', 'n/a', '\N',
   '#N/A', '#NULL!', '#REF!', '#VALUE!', '#DIV/0!', '#NAME?',
   '--', '---',
   'MISSING', 'UNKNOWN', 'UNDEFINED', 'NOT SET', 'NOT PROVIDED', 'NO DATA', 'NO VALUE'];
