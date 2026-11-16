"""Question 1: the cases a-h on a real DuckLake lake. Output: cases.out."""
from lake import *

c = open_lake(f"{HERE}/run/q1")
for t in ["orders(id INT, customer_id INT, amount INT)", "customers(id INT, name VARCHAR)", "items(order_id INT, sku VARCHAR)"]:
    load(c, f"CREATE TABLE lake.main.{t}")
load(c, "INSERT INTO lake.main.orders VALUES (1, 1, 10), (2, 2, 30)")
load(c, "INSERT INTO lake.main.customers VALUES (1, 'a'), (2, 'b')")
annotate(c, "main.orders.amount", "unit", "EUR")
define(c, "main.sales", ["main.orders", "main.customers"])
ORD, CUS = ("main.orders", "data"), ("main.customers", "data")
UNIT = ("main.orders.amount", "annotation unit")
compute(c, "profile", "main.orders.amount", [ORD, UNIT], "SELECT sum(amount) || ' ' || "
        "(SELECT body FROM g_annotation WHERE property = 'unit' AND end_snapshot IS NULL) FROM lake.main.orders")
compute(c, "profile", "main.customers", [CUS], "SELECT count(*) FROM lake.main.customers")
compute(c, "total", "main.orders", [ORD], "SELECT max(amount) FROM lake.main.orders")
compute(c, "share", "main.sales", [("main.orders", "result total")],
        "SELECT (SELECT value FROM g_result WHERE function = 'total' AND end_snapshot IS NULL)")
compute(c, "summary", "main.orders.amount", [("main.orders.amount", "result profile")], "SELECT 'ok'")
# d: "the relationships of this view": the walk (its definition, then each table it reads) and the set
# of relationships of each table; and the same read recorded by its end nodes alone
place = [("main.sales", "definition"), ("main.orders", "relationships"), ("main.customers", "relationships")]
compute(c, "coherence", "main.sales", place, "SELECT 0")
compute(c, "coherence_ends_only", "main.sales", place[1:], "SELECT 0")
show(c, "start: every result current")

annotate(c, "main.customers.id", "role", "key")
show(c, "a1: annotation on a node no result read (customers.id role)")
s = annotate(c, "main.orders.amount", "unit", "USD")
show(c, f"a2: annotation read by profile(orders.amount) changed at {s}")

compute(c, "profile", "main.orders.amount", [ORD, UNIT], "SELECT sum(amount) || ' ' || "
        "(SELECT body FROM g_annotation WHERE property = 'unit' AND end_snapshot IS NULL) FROM lake.main.orders")
s = load(c, "INSERT INTO lake.main.customers VALUES (3, 'c')")
show(c, f"b: customers loaded at {s} (profile(orders.amount) recomputed before; it read orders)")
compute(c, "profile", "main.customers", [CUS], "SELECT count(*) FROM lake.main.customers")
compute(c, "summary", "main.orders.amount", [("main.orders.amount", "result profile")], "SELECT 'ok'")

s = load(c, "INSERT INTO lake.main.orders VALUES (3, 1, 5)")
show(c, f"c1: orders loaded at {s}, max(amount) unchanged; total not yet computed again")
compute(c, "total", "main.orders", [ORD], "SELECT max(amount) FROM lake.main.orders")
compute(c, "profile", "main.orders.amount", [ORD, UNIT], "SELECT sum(amount) || ' ' || "
        "(SELECT body FROM g_annotation WHERE property = 'unit' AND end_snapshot IS NULL) FROM lake.main.orders")
compute(c, "summary", "main.orders.amount", [("main.orders.amount", "result profile")], "SELECT 'ok'")
show(c, "c2: total computed again, same value: share current")
load(c, "INSERT INTO lake.main.orders VALUES (4, 2, 99)")
compute(c, "total", "main.orders", [ORD], "SELECT max(amount) FROM lake.main.orders")
show(c, "c3: orders loaded with a new max, total computed again with another value")
for f, sql in [("profile", "SELECT sum(amount) || ' USD' FROM lake.main.orders"), ("summary", "SELECT 'ok'")]:
    compute(c, f, "main.orders.amount", [ORD, UNIT] if f == "profile" else [("main.orders.amount", "result profile")], sql)
compute(c, "share", "main.sales", [("main.orders", "result total")], "SELECT 99")

s = relate(c, "main.items.order_id", "main.items")
show(c, f"d1: relationship declared at {s} on a table the view does not read")
s = relate(c, "main.orders", "main.customers")
show(c, f"d2: relationship orders -> customers declared at {s}")
show(c, "d2: what was added since coherence read, from the rows alone",
     "SELECT g.* FROM g_relationship g, g_result r WHERE r.function = 'coherence' AND r.end_snapshot IS NULL"
     " AND (g.begin_snapshot > r.read_at OR g.end_snapshot > r.read_at)")
compute(c, "coherence", "main.sales", place, "SELECT 1")
compute(c, "coherence_ends_only", "main.sales", place[1:], "SELECT 1")
s = define(c, "main.sales", ["main.orders", "main.customers", "main.items"])
show(c, f"d3: view redefined at {s} to read items too (items had a relationship already)")

s0 = annotate(c, "main.orders.amount", "unit", "EUR")
s1 = annotate(c, "main.orders.amount", "unit", "USD")
show(c, f"e1: unit changed at {s0} and changed back at {s1}")
compute(c, "profile", "main.orders.amount", [ORD, UNIT], "SELECT sum(amount) || ' ' || "
        "(SELECT body FROM g_annotation WHERE property = 'unit' AND end_snapshot IS NULL) FROM lake.main.orders")
show(c, "e2: profile computed again (same value): summary current again without being computed")
s = annotate(c, "main.orders.amount", "unit", "USD")
show(c, f"e3: unit written again at {s} with the body it has (a re-declaration that changes nothing)")

# g: two connections
c2 = conn(c)
c.execute("BEGIN")
h = c.execute(HEAD).fetchone()[0]
c.execute("INSERT INTO ducklake_snapshot SELECT ?, now(), schema_version, next_catalog_id, next_file_id"
          " FROM ducklake_snapshot WHERE snapshot_id = ?", [h + 1, h])
sb = annotate(c2, "main.customers", "owner", "b")
try:
    c.execute("COMMIT")
    print(f"\n-- g1: both writers committed snapshot {h + 1}: WRONG")
except duckdb.Error as x:
    print(f"\n-- g1: A took {h + 1} in an open transaction, B committed {sb}; A's commit: {str(x).splitlines()[0][:110]}")
v, e, at = read(c, "SELECT count(*) FROM lake.main.customers")      # A computes at `at`
annotate(c2, "main.customers", "owner", "c")                         # B writes after A read
load(c2, "INSERT INTO lake.main.customers VALUES (4, 'd')")          # B loads after A read
store(c, "count_read_at", "main.customers", [CUS], v, e, at)          # A stores: read_at = its read
s = c.execute(HEAD).fetchone()[0]
store(c, "count_commit_at", "main.customers", [CUS], v, e, s + 1)     # A stores: read_at = its commit
show(c, f"g2: A read at {at}, B loaded customers after; A stored the value computed at {at}")

compute(c, "fx", "main.orders", [ORD], "SELECT error('service down')")
compute(c, "uses_fx", "main.sales", [("main.orders", "result fx")], "SELECT 'fx failed'")
compute(c, "fx", "main.orders", [ORD], "SELECT error('service down')")
show(c, "h1: fx failed, computed again, failed the same way: uses_fx current")
compute(c, "fx", "main.orders", [ORD], "SELECT 1")
show(c, "h2: fx computed again and succeeded: uses_fx out of date")

# f: a lake whose small loads are inlined; flush, compaction, deletion, expiry
c = open_lake(f"{HERE}/run/f", ", DATA_INLINING_ROW_LIMIT 10")
log = []
log.append(("create", load(c, "CREATE TABLE lake.main.t (i INT)")))
log.append(("insert 3 rows (inlined)", load(c, "INSERT INTO lake.main.t VALUES (1), (2), (3)")))
log.append(("a result reads t here", write(c)))
log.append(("flush inlined data", load(c, "CALL ducklake_flush_inlined_data('lake')")))
log.append(("insert 1000 rows", load(c, "INSERT INTO lake.main.t SELECT range FROM range(1000)")))
log.append(("insert 1000 rows", load(c, "INSERT INTO lake.main.t SELECT range FROM range(1000)")))
log.append(("a result reads t here", write(c)))
log.append(("merge adjacent files", load(c, "CALL ducklake_merge_adjacent_files('lake')")))
log.append(("a result reads t here", write(c)))
log.append(("delete every row", load(c, "DELETE FROM lake.main.t")))
log.append(("an unrelated catalog write", write(c)))
print("\n-- f1: the writes\n" + "\n".join(f"{s} {w}" for w, s in log))
show(c, "f1: change log", "SELECT snapshot_id, changes FROM ducklake_snapshots('lake') ORDER BY 1")
show(c, "f1: data files", "SELECT data_file_id, begin_snapshot, end_snapshot, record_count FROM ducklake_data_file")
show(c, "f1: when t changed, before expiry", "SELECT * FROM g_changed WHERE what = 'data'")
load(c, "CALL ducklake_expire_snapshots('lake', older_than => now())")
load(c, "CALL ducklake_cleanup_old_files('lake', cleanup_all => true)")
show(c, "f2: change log after expiry", "SELECT snapshot_id, changes FROM ducklake_snapshots('lake') ORDER BY 1")
show(c, "f2: data files after expiry", "SELECT data_file_id, begin_snapshot, end_snapshot, record_count FROM ducklake_data_file")
show(c, "f2: when t changed, after expiry", "SELECT * FROM g_changed WHERE what = 'data'")
show(c, "f2: t's rows now", "SELECT count(*) FROM lake.main.t")

# q5: an add-on the core knows nothing about. Its function, its scenarios and the model service's
# version it observed are rows of g_declaration; its results are rows of g_result with edges in g_read
c = open_lake(f"{HERE}/run/q5")
load(c, "CREATE TABLE lake.main.orders (id INT, amount INT)")
load(c, "INSERT INTO lake.main.orders VALUES (1, 10), (2, 30)")
declare(c, "profile", "function", "core: sum(amount)")
declare(c, "scenario_forecast", "function", "add-on: ask the model service")
declare(c, "model_service", "service version", "1.3")
declare(c, "main.scenario_a", "scenario", "main.orders.amount +5%")
ADDON = [("scenario_forecast", "declaration"), ("model_service", "declaration"), ORD]
compute(c, "profile", "main.orders", [ORD, ("profile", "declaration")], "SELECT sum(amount) FROM lake.main.orders")
compute(c, "scenario_forecast", "main.scenario_a", ADDON + [("main.scenario_a", "declaration")], "SELECT 42")
compute(c, "scenario_count", "scenario", [("scenario", "declarations")], "SELECT 1")
show(c, "q5 start: a core result, an add-on result on a scenario, a result that reads every scenario")
s = declare(c, "main.scenario_b", "scenario", "main.orders.amount -5%")
show(c, f"q5b: a second scenario declared at {s}")
compute(c, "scenario_forecast", "main.scenario_b", ADDON + [("main.scenario_b", "declaration")], "SELECT 40")
compute(c, "scenario_count", "scenario", [("scenario", "declarations")], "SELECT 2")
print(f"\n-- q5d: the add-on observes the service again, version 1.3: written? {declare(c, 'model_service', 'service version', '1.3', unless_same=True)}")
s = declare(c, "model_service", "service version", "1.4", unless_same=True)
show(c, f"q5d: the add-on observes version 1.4, written at {s}")
s = write(c, "UPDATE g_declaration SET end_snapshot = $s WHERE end_snapshot IS NULL AND (kind IN ('scenario', 'service version')"
             " OR asset = 'scenario_forecast')")
show(c, f"q5c: the add-on removed at {s}: its declarations end")
