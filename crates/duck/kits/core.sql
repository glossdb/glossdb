-- The record's own words, declared by the engine at every open, before
-- any kit: what the doors write and read on their own account. A kit
-- brings vocabulary about the data; these are about the record.

-- The reads the doors derive from the record, as views beside it.
-- Replaced at every open so a view follows the build, never a lake's
-- age; each open is one snapshot of the lake for it.

-- The bound dataset as a relation: the schema in use when it is a
-- dataset's, no row on an unbound channel. The doors join it.
CREATE OR REPLACE VIEW ws.glossql.current_dataset AS
  SELECT current_schema() AS dataset
  WHERE current_schema() IN (SELECT name FROM ws.glossql.datasets);

-- The agent's current assumptions, one row each: the latest agent
-- gloss per slot, its `assumptions` unnested, `idx` from 0. Derived
-- from the agent's CURRENT body, never a frozen copy, so an answered
-- question drops out when the fold-in raises its confidence.
CREATE OR REPLACE VIEW ws.glossql.agent_assumptions AS
  WITH latest AS (
    SELECT * FROM (
      SELECT g.*, row_number() OVER (PARTITION BY dataset, subject, aspect ORDER BY seq DESC) AS rn
      FROM ws.glossql.glossary g WHERE actor_kind = 'agent') WHERE rn = 1)
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
CREATE OR REPLACE VIEW ws.glossql.ruling_entries AS
  WITH latest AS (
    SELECT * FROM (
      SELECT r.*, row_number() OVER (PARTITION BY dataset, subject ORDER BY seq DESC) AS rn
      FROM ws.glossql.glossary r WHERE aspect = 'ruling' AND actor_kind = 'human') WHERE rn = 1),
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
  LEFT JOIN ws.glossql.agent_assumptions a
    ON a.dataset = e.dataset AND a.subject = e.subject AND a.aspect = e.aspect
   AND a.key = e.key AND a.conf < 1.0
  GROUP BY ALL;

-- What still stands open for a human to judge: a keyed assumption
-- below full confidence on a grounding, in a dimension no function
-- owns (behavior, sign and grain are statistics), with no standing
-- ruling on its (dataset, subject, aspect, key). `sibling` carries a
-- ruling on the same key under another aspect, so the round can offer
-- it back. No ORDER BY: order where you consume.
CREATE OR REPLACE VIEW ws.glossql.open_questions AS
  WITH groundings AS (
    SELECT name FROM (
      SELECT name, kind, row_number() OVER (PARTITION BY name ORDER BY seq DESC) AS rn
      FROM ws.glossql.aspects) WHERE rn = 1 AND kind = 'QUERY')
  SELECT o.dataset, o.subject, o.aspect, o.idx, o.dimension, o.key, o.assumption, o.basis,
         o.alternative, o.conf,
         max(s.stance || ' on ' || s.aspect) AS sibling,
         max(s.stance) AS sibling_stance,
         max(s.note) AS sibling_note
  FROM ws.glossql.agent_assumptions o
  JOIN groundings a ON a.name = o.aspect
  LEFT JOIN ws.glossql.ruling_entries s
    ON s.dataset = o.dataset AND s.subject = o.subject AND s.key = o.key AND s.aspect <> o.aspect
   AND s.stance IN ('confirmed', 'corrected')
  WHERE o.conf < 1.0 AND o.key IS NOT NULL
    AND coalesce(o.dimension, '-') NOT IN ('behavior', 'sign', 'grain')
    AND NOT EXISTS (SELECT 1 FROM ws.glossql.ruling_entries r
                    WHERE r.dataset = o.dataset AND r.subject = o.subject
                      AND r.aspect = o.aspect AND r.key = o.key)
  GROUP BY ALL;

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
