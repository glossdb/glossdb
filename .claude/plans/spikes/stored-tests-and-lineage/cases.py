"""The cases on a real DuckLake lake: what one write puts out of date, what is computed, what the
reads serve. Output: cases.out."""
import json
from store import *
from kit import declare_kits, functions, DETECTORS

FN = functions(lake=True)


def show(c, title, sql):
    print(f"\n-- {title}")
    cur = c.execute(sql)
    print(" | ".join(d[0] for d in cur.description))
    for row in cur.fetchall():
        print(" | ".join("" if x is None else str(x) for x in row))


def step(c, title, since):
    """After a write at `since`+: what is due (from the nodes written alone), then computed."""
    d = due(c, "main", since)
    print(f"\n== {title}\ndue after the write: " + ("; ".join(f"{f}({s}) {w}" for f, _, s, w in d) or "nothing"))
    whole = due(c, "main")
    if sorted(whole) != sorted(d):
        print("   the whole check says otherwise: " + "; ".join(f"{f}({s}) {w}" for f, _, s, w in whole))
    done = bring_current(c, FN, "main", since)
    print("computed (function, results, retired, values changed): " + (", ".join(map(str, done)) or "nothing"))
    rest = due(c, "main")
    print("due after computing: " + ("; ".join(f"{f}({s}) {w}" for f, _, s, w in rest) or "nothing"))


c = open_lake(f"{HERE}/run/cases")
for t in ["orders(id INT, customer_id INT, amount INT, ordered_at DATE)", "customers(id INT, name VARCHAR, region VARCHAR)",
          "items(order_id INT, sku VARCHAR, qty INT)"]:
    load(c, f"CREATE TABLE lake.main.{t}")
load(c, "INSERT INTO lake.main.orders VALUES (1, 1, 10, '2026-01-01'), (2, 2, 30, '2026-02-01')")
load(c, "INSERT INTO lake.main.customers VALUES (1, 'a', 'north'), (2, 'b', 'south')")
load(c, "INSERT INTO lake.main.items VALUES (1, 'x', 2)")
declare_kits(c)
define(c, "main.sales", ["main.orders.amount", "main.orders.ordered_at", "main.customers.region"],
       ["main.orders.customer_id=main.customers.id"])
define(c, "main.big_orders", ["main.orders.amount"])
define(c, "main.sales_by_region", ["main.sales.region", "main.sales.amount"])
for col, role in [("amount", "measure"), ("ordered_at", "timestamp"), ("region", "dimension")]:
    annotate(c, f"main.sales.{col}", "role", json.dumps({"value": role}))
annotate(c, "main.sales.amount", "additivity", json.dumps({"value": "additive"}))
annotate(c, "main.orders.amount", "unit", json.dumps({"value": "EUR"}))
annotate(c, "main.orders", "role", json.dumps({"value": "fact"}))
annotate(c, "main.sales", "grain_check", json.dumps({"tolerance": 0.0}))
s = head(c)
step(c, "start: every result computed once", 0)
show(c, "the results", "SELECT function, subject, value, error, read_at, changed_at FROM g_result WHERE end_snapshot IS NULL ORDER BY 1, 2")

s = annotate(c, "main.sales.amount", "role", json.dumps({"value": "dimension"}))
step(c, f"A1: an agent changes role on main.sales.amount at {s}", s - 1)
s = annotate(c, "main.sales.amount", "role", json.dumps({"value": "measure"}), actor="human")
step(c, f"A2: a person annotates role on main.sales.amount otherwise, at {s}", s - 1)
show(c, "A2: the collapsed read of main.sales (a read over stored rows)", "SELECT * FROM g_collapsed('main', 'main.sales') ORDER BY 1, 2")

s = annotate(c, "main.customers.name", "unit", json.dumps({"value": "none"}))
step(c, f"B: an annotation on a column no view reads, a property with a test, at {s}", s - 1)

s = define(c, "main.top_customers", ["main.customers.name"])
step(c, f"C1: a new view defined at {s}", s - 1)
s = define(c, "main.sales", ["main.orders.amount", "main.orders.ordered_at", "main.customers.region", "main.items.qty"],
           ["main.orders.customer_id=main.customers.id", "main.orders.id=main.items.order_id"])
step(c, f"C2: main.sales defined again at {s}, reading items too (sales_by_region reads sales)", s - 1)

s = load(c, "ALTER TABLE lake.main.orders ADD COLUMN note VARCHAR")
step(c, f"D: orders altered at {s}: a column added, which no view reads (three views read orders)", s - 1)
show(c, "D: the lineage results after D: read_at moved, changed_at kept",
     "SELECT function, subject, read_at, changed_at FROM g_result WHERE function IN ('lineage', 'grain_check') AND end_snapshot IS NULL ORDER BY 1")
show(c, "D: the stale mark: an annotation on main.orders began before its definition changed",
     "SELECT subject, aspect, state FROM g_collapsed('main', 'main.orders') WHERE state <> 'missing' ORDER BY 1, 2")

s = load(c, "ALTER TABLE lake.main.orders ALTER amount TYPE BIGINT")
step(c, f"E: orders.amount retyped at {s}", s - 1)
show(c, "E: the stale mark on orders.amount", "SELECT subject, aspect, state FROM g_collapsed('main', 'main.orders.amount') WHERE state <> 'missing'")

s = load(c, "INSERT INTO lake.main.orders VALUES (3, 1, 5, '2026-03-01', NULL)")
step(c, f"F: orders loaded at {s}", s - 1)

declare(c, "scenario_a", "property", {"x-kind": "scenario"})
declare(c, "scenario_b", "property", {"x-kind": "scenario"})
s = annotate(c, "main", "scenario_a", json.dumps({"levers": [{"column": "main.orders.amount"}]}))
step(c, f"G1: a scenario annotated on the dataset at {s}", s - 1)
s = annotate(c, "main", "scenario_b", json.dumps({"levers": [{"column": "main.customers.region"}]}))
step(c, f"G2: a second scenario at {s}", s - 1)
s = annotate(c, "main", "scenario_a", json.dumps({"levers": [{"column": "main.orders.amount"}, {"column": "main.items.qty"}]}))
step(c, f"G3: scenario_a's levers changed at {s}", s - 1)
show(c, "G: the lineage of main, edges held by results (a read over rows)",
     "SELECT * FROM g_lineage('main') WHERE kind <> 'contains' ORDER BY ALL")

s = declare(c, "role_test", "test", {"property": "role", "detector": "value_entropy", "threshold": 0.9, "grain": "column"})
step(c, f"I: role_test declared again with another threshold at {s}", s - 1)

s = declare(c, "unit_test", "test", {"property": "unit", "detector": "no_such_detector", "threshold": 0.7, "grain": "column"})
step(c, f"J1: unit_test names a detector nobody declared, at {s}", s - 1)
show(c, "J1: TESTS() on unit", "SELECT subject, test, state, error, current FROM g_tests('main', NULL) WHERE aspect = 'unit'")
s = declare(c, "no_such_detector", "function", {"detector": DETECTORS["value_entropy"]})
step(c, f"J2: the detector declared at {s}", s - 1)

# K: a load by another tool: nobody computes after it
c2 = c.cursor(); c2.execute("USE __ducklake_metadata_lake")
s = load(c2, "INSERT INTO lake.main.orders VALUES (4, 2, 7, '2026-04-01', NULL)")
show(c, f"K: orders loaded at {s} by another tool, nothing computed after it: TESTS() serves the stored rows, marked",
     "SELECT subject, test, state, current, result_state FROM g_tests('main', NULL) ORDER BY 1, 2")
step(c, "K: the next write through the server brings them current", s - 1)

s = write(c, "UPDATE g_definition SET end_snapshot = $s WHERE asset = 'main.big_orders' AND end_snapshot IS NULL")
step(c, f"L: main.big_orders removed at {s}", s - 1)
show(c, "the view summary and the view tests stand-ins over stored rows", "SELECT * FROM g_view_summary('main') ORDER BY 1")
show(c, "", "SELECT view, test, subject, state, current FROM g_view_tests('main')")

# H: a detector at the grain of one subject: whole, per subject, and as one batch of subjects
print("\n== H: each detector over a dataset's values, whole against narrowed to subjects")
h = duckdb.connect()
h.execute("""CREATE TABLE vals AS SELECT * FROM (VALUES
 ('m.a', 'agent', '{"value": "additive", "tolerance": 0.1}'), ('m.a', 'human', '{"value": "stock", "tolerance": 0.3}'),
 ('m.a', 'function', '{"breach_rate": 0.2, "state": "red", "score": 0.25, "points": [{"planned": "above"}, {"planned": "inside"}]}'),
 ('m.b', 'agent', '{"value": "additive", "tolerance": 0.0}'),
 ('m.b', 'function', '{"breach_rate": 0.0, "state": "green", "score": 0.0, "points": [{"planned": "inside"}]}'),
 ('m.c', 'agent', '{"value": "ratio"}'), ('m.c', 'human', '{"value": "ratio"}'), ('m.c', 'agent', '{"value": "ratio"}'),
 ('m.d', 'function', '{"forecast_error": "no data", "points": []}')) v(subject, actor_kind, body)""")
for name, det in DETECTORS.items():
    det = det.replace("$threshold", "0.7")
    run = lambda where: sorted(h.execute(f"WITH annotations AS (SELECT subject, 'p' AS aspect, actor_kind, body::JSON AS body, true AS current"
                                          f" FROM vals WHERE {where}) SELECT * FROM ({det}) q").fetchall())
    whole = run("true")
    one = sorted(r for s in ["m.a", "m.b", "m.c", "m.d"] for r in run(f"subject = '{s}'"))
    batch = run("subject IN ('m.a', 'm.c')")
    tree = h.execute("SELECT json_serialize_sql(?)", [f"SELECT * FROM ({det}) q"]).fetchone()[0]
    print(f"{name}: whole = per subject: {whole == one}; batch of two = whole on them: "
          f"{batch == [r for r in whole if r[0] in ('m.a', 'm.c')]}; a window in the body: {'WINDOW' in tree}")
    if whole != one:
        print(f"   whole: {whole}\n   per subject: {one}")
