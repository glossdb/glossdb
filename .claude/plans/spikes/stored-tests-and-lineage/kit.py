"""The kits' declarations the spike runs on: four real detectors copied from the kits, the tests
that name them, and stand-ins for a view's lineage (planning), a kit's scenario edges, a column
profile and a view's grain check. Each function is a declaration with the subjects it is
expected on; the Python body stands in for the function's SQL."""
import json, time
from store import declare, q

PLAN_MS = 1.0  # the stand-in for planning one view: the real one is about 1 ms per view

# copied from gloss/kits/kpi/kit.sql:88-100
VALUE_ENTROPY = """
  WITH s AS (
    SELECT subject,
           CASE WHEN count(*) <= 1 THEN 0.0
                ELSE (count(DISTINCT body->>'value') - 1.0) / (count(*) - 1.0)
           END AS score
    FROM annotations GROUP BY subject)
  SELECT subject,
         CASE WHEN score = 0.0 THEN 'green'
              WHEN score <= coalesce($threshold, 1.0) THEN 'yellow'
              ELSE 'red' END AS state,
         score
  FROM s"""
# copied from gloss/kits/quality/kit.sql:948-961
RATE_TOLERANCE = """
  WITH s AS (
    SELECT subject,
           max(try_cast(body->>'breach_rate' AS DOUBLE)) FILTER (WHERE actor_kind = 'function') AS rate,
           coalesce(max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'human'),
                    max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'agent')) AS tolerance
    FROM annotations GROUP BY subject)
  SELECT subject,
         CASE WHEN rate IS NULL THEN 'yellow'
              WHEN rate <= coalesce(tolerance, $threshold, 0.0) THEN 'green'
              ELSE 'red' END AS state,
         CASE WHEN rate IS NULL OR rate <= coalesce(tolerance, $threshold, 0.0) THEN 0.0
              ELSE least(greatest(rate, 0.0), 1.0) END AS score
  FROM s"""
# copied from glossql/kits/outlook/kit.sql:211-221
RANGE_STATE = """
  WITH s AS (
    SELECT subject,
           max(body->>'state') FILTER (WHERE actor_kind = 'function') AS state,
           max(try_cast(body->>'score' AS DOUBLE)) FILTER (WHERE actor_kind = 'function') AS score,
           coalesce(max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'human'),
                    max(try_cast(body->>'tolerance' AS DOUBLE)) FILTER (WHERE actor_kind = 'agent')) AS tolerance
    FROM annotations GROUP BY subject)
  SELECT subject, CASE WHEN score <= tolerance THEN 'green' ELSE state END AS state, score
  FROM s WHERE state IS NOT NULL"""
# copied from glossql/kits/plan/kit.sql:372-382
PLAN_GAP = """
  SELECT subject,
         CASE WHEN failed THEN 'yellow' WHEN outside > 0 THEN 'red' ELSE 'green' END AS state,
         CASE WHEN ranged > 0 THEN outside / ranged ELSE 0.0 END AS score
  FROM (SELECT subject, failed,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above'))), 0)::DOUBLE AS outside,
               coalesce(len(list_filter(planned, lambda s: s IN ('below', 'above', 'inside'))), 0)::DOUBLE AS ranged
        FROM (SELECT subject, json_extract_string(body, '$.forecast_error') IS NOT NULL AS failed,
                     list_transform(from_json(json_extract(body, '$.points'), '[{"planned": "VARCHAR"}]'), lambda p: p.planned) AS planned
              FROM annotations WHERE actor_kind = 'function'))"""
# not from a kit: a detector that judges a subject against the others (its share of the
# largest number of values any subject holds). Narrowed to one subject it answers otherwise
RANK_SHARE = """
  SELECT subject, CASE WHEN share < 0.5 THEN 'yellow' ELSE 'green' END AS state, share AS score
  FROM (SELECT subject, count(*) / max(count(*)) OVER () AS share FROM annotations GROUP BY subject)"""

DETECTORS = {"value_entropy": VALUE_ENTROPY, "rate_tolerance": RATE_TOLERANCE, "range_state": RANGE_STATE,
             "plan_gap": PLAN_GAP, "rank_share": RANK_SHARE}

VIEWS = "SELECT dataset, asset AS subject FROM g_definition WHERE kind = 'view' AND end_snapshot IS NULL"
SCENARIOS = ("SELECT g.dataset, g.dataset || '.' || g.property AS subject FROM g_annotation g JOIN g_declaration d"
             " ON d.asset = g.property AND d.kind = 'property' AND d.end_snapshot IS NULL"
             " AND d.body::JSON->>'x-kind' = 'scenario' WHERE g.end_snapshot IS NULL AND g.asset = g.dataset")
COLUMNS = "SELECT dataset, asset AS subject FROM g_columns WHERE relation NOT IN (SELECT asset FROM g_definition WHERE kind = 'view')"
CHECKED = ("SELECT g.dataset, g.asset AS subject FROM g_annotation g JOIN g_definition d ON d.asset = g.asset"
           " AND d.kind = 'view' AND d.end_snapshot IS NULL WHERE g.property = 'grain_check' AND g.end_snapshot IS NULL")


def declare_kits(c, detectors=("value_entropy", "rate_tolerance")):
    for d in detectors:
        declare(c, d, "function", {"detector": DETECTORS[d]})
    declare(c, "lineage", "function", {"subjects": VIEWS})
    declare(c, "column_profile", "function", {"subjects": COLUMNS, "returns": "column_profile"})
    declare(c, "grain_check", "function", {"subjects": CHECKED, "returns": "grain_check", "after": ["lineage"]})
    declare(c, "edges_scenario", "function", {"subjects": SCENARIOS})
    for p in ["role", "unit", "additivity"]:
        declare(c, f"{p}_test", "test", {"property": p, "detector": "value_entropy", "threshold": 0.7, "grain": "column"})
    declare(c, "grain_test", "test", {"property": "grain_check", "detector": "rate_tolerance", "threshold": 0.0, "grain": "view"})


def view_defs(c):
    return {a: (list(r), list(j)) for a, r, j in c.execute(
        "SELECT asset, reads, joins FROM g_definition WHERE kind = 'view' AND end_snapshot IS NULL").fetchall()}


def lineage(c, views):
    """A view's lineage: the relations and columns it reads, through views, as edges. Reads its
    definition and the definition of each relation on the way. Planning stands in at PLAN_MS."""
    defs = view_defs(c)
    tables = {r for (r,) in c.execute("SELECT DISTINCT relation FROM g_columns").fetchall()}
    out = []
    for v in views:
        time.sleep(PLAN_MS / 1000)
        reads, edges, error = [(v, "definition")], set(), None

        def walk(x, seen):
            nonlocal error
            r, j = defs[x]
            for a in r:
                rel = ".".join(a.split(".")[:2])
                if rel in defs and rel not in seen:
                    reads.append((rel, "definition"))
                    walk(rel, seen | {rel})
                elif rel in tables:
                    reads.append((rel, "definition"))
                elif rel not in defs:
                    error = f"{rel} does not exist"
                edges.add((v, a, "reads"))
            for p in j:
                for side in p.split("="):
                    edges.add((v, side, "reads"))
        walk(v, {v})
        edges = sorted(edges)
        value = None if error else json.dumps([list(e) for e in edges], separators=(",", ":"))
        out.append((v, value, error, sorted(set(reads)), [] if error else edges))
    return out


def edges_scenario(c, subjects):
    """A kit's function: a scenario's levers as edges (sets) to the columns it names. Reads the
    annotation that declares the scenario."""
    out = []
    for s in subjects:
        ds, prop = s.split(".", 1)
        body = c.execute("SELECT body FROM g_annotation WHERE asset = ? AND property = ? AND end_snapshot IS NULL"
                         " ORDER BY actor = 'human' DESC LIMIT 1", [ds, prop]).fetchone()
        levers = sorted(l["column"] for l in json.loads(body[0]).get("levers", [])) if body else []
        out.append((s, json.dumps(levers), None, [(ds, "annotation " + prop)], [(s, l, "sets") for l in levers]))
    return out


def column_profile(c, subjects, lake=True):
    out = []
    for s in subjects:
        ds, t, col = s.split(".", 2)
        if lake:
            n = c.execute(f'SELECT count(DISTINCT "{col}") FROM lake.{ds}.{t}').fetchone()[0]
        else:
            n = hash(s) % 100
        out.append((s, json.dumps({"distinct": n}), None,
                    [(f"{ds}.{t}", "data"), (s, "definition"), ("column_profile", "declaration")], []))
    return out


def grain_check(c, subjects):
    """A view's check: reads the view's stored lineage (which tables to read) and their data."""
    out = []
    for v in subjects:
        lin = c.execute("SELECT value FROM g_result WHERE function = 'lineage' AND subject = ? AND end_snapshot IS NULL", [v]).fetchone()
        tables = sorted({".".join(e[1].split(".")[:2]) for e in json.loads(lin[0] or "[]")}) if lin else []
        out.append((v, json.dumps({"breach_rate": 0.0}), None,
                    [(v, "result lineage"), ("grain_check", "declaration")] + [(t, "data") for t in tables], []))
    return out


def functions(lake=True):
    return {"lineage": lineage, "edges_scenario": edges_scenario, "grain_check": grain_check,
            "column_profile": (lambda c, s: column_profile(c, s, lake))}
