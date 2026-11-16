"""Question 2: the check as SQL over stored rows, and from adjacency lists in memory. Output: bench.out."""
import os, sys, time, statistics, tracemalloc, duckdb, numpy as np
from lake import HERE

SCHEMA = open(f"{HERE}/schema.sql").read()
# a table's last load from g_load: the lake's change log is not generated at this size
SCHEMA = SCHEMA.split("-- @data")[0] + "CREATE TABLE g_load (asset VARCHAR, snapshot BIGINT);\n" \
    "CREATE VIEW g_data_changed AS SELECT asset, max(snapshot) AS changed_at FROM g_load GROUP BY ALL;" \
    + SCHEMA.split("-- @end")[1]

GEN = """
CREATE TEMP TABLE nodes AS
  SELECT 't' || i AS asset, w AS what FROM range($T) r(i), unnest(['data', 'relationships']) u(w)
  UNION ALL SELECT 't' || (i % $T) || '.c' || i, 'annotation ' || p FROM range($C) r(i), unnest(['role', 'unit', 'pii', 'doc']) u(p)
  UNION ALL SELECT 'v' || i, 'definition' FROM range($V) r(i);
INSERT INTO g_annotation SELECT 1 + hash(asset, what) % $S0, NULL, asset, substr(what, 12), 'x' FROM nodes WHERE what LIKE 'annotation%';
INSERT INTO g_definition SELECT 1 + hash(asset) % $S0, NULL, asset, 'select', [] FROM nodes WHERE what = 'definition';
INSERT INTO g_relationship SELECT 1 + hash(i) % $S0, NULL, 't' || i, 't' || hash(i) % $T FROM range($T) r(i);
INSERT INTO g_load SELECT asset, 1 + hash(asset, k) % $S0 FROM nodes, range(3) r(k) WHERE what = 'data';
CREATE TEMP TABLE nn AS SELECT row_number() OVER () - 1 AS n, * FROM nodes;
-- result i is computed at snapshot S0 + i, reads 3-10 nodes: 1 in 8 a result read by many (the first 20),
-- 1 in 8 an earlier result, else a catalog node
INSERT INTO g_result SELECT $S0 + i, NULL, 'f', 's' || i, 'v', NULL, $S0 + i - 1, $S0 + i FROM range(1, $N + 1) r(i);
INSERT INTO g_read SELECT DISTINCT $S0 + i, CASE WHEN i > 21 AND h % 8 = 0 THEN 's' || (1 + h // 8 % 20)
    WHEN i > 21 AND h % 8 = 1 THEN 's' || (1 + h // 8 % (i - 1)) ELSE n.asset END,
  CASE WHEN i > 21 AND h % 8 < 2 THEN 'result f' ELSE n.what END
  FROM (SELECT i, k, hash(i, k) AS h FROM range(1, $N + 1) r(i), range((3 + hash(i) % 8)::BIGINT) q(k)) e
  JOIN nn n ON n.n = e.h // 64 % $K;
-- after the last result: 1 in 200 annotations rewritten, 1 in 100 tables loaded
INSERT INTO g_annotation SELECT $S0 + $N + 1, NULL, asset, property, 'y' FROM g_annotation WHERE hash(asset, property) % 200 = 0;
INSERT INTO g_load SELECT asset, $S0 + $N + 2 FROM nodes WHERE what = 'data' AND hash(asset) % 100 = 0;
"""
AFTER_WRITE = """WITH RECURSIVE hit(result) AS (
  SELECT result FROM g_read WHERE asset = $1 AND what = $2
  UNION SELECT e.result FROM hit JOIN g_result q ON q.begin_snapshot = hit.result AND q.end_snapshot IS NULL
  JOIN g_read e ON e.asset = q.subject AND e.what = 'result ' || q.function)
SELECT count(*) FROM hit"""
ONE = """WITH RECURSIVE walk(result) AS (SELECT $1::BIGINT
  UNION SELECT q.begin_snapshot FROM walk JOIN g_read e ON e.result = walk.result
  JOIN g_result q ON q.subject = e.asset AND 'result ' || q.function = e.what AND q.end_snapshot IS NULL)
SELECT count(*) FROM walk w JOIN g_result r ON r.begin_snapshot = w.result JOIN g_read e ON e.result = w.result
JOIN g_changed n ON n.asset = e.asset AND n.what = e.what WHERE n.changed_at > r.read_at"""
WHOLE = "SELECT state, count(*) FROM g_check GROUP BY ALL ORDER BY ALL"


def timed(f, n=5):
    ts = []
    for _ in range(n):
        t = time.perf_counter(); out = f(); ts.append(time.perf_counter() - t)
    return statistics.median(ts) * 1000, out


def memory(c):
    """The graph: node ids, edges both ways (CSR), each node's last change, each result's read snapshot."""
    e = c.execute("SELECT e.result, e.asset || '|' || e.what AS node FROM g_read e").fetchnumpy()
    ch = c.execute("SELECT asset || '|' || what AS node, changed_at FROM g_changed").fetchnumpy()
    rs = c.execute("SELECT begin_snapshot, read_at, subject || '|result ' || function FROM g_result WHERE end_snapshot IS NULL").fetchnumpy()
    own_key = rs[list(rs)[2]]
    ids = {k: i for i, k in enumerate(np.unique(np.concatenate([e["node"], ch["node"], own_key])))}
    nid = np.fromiter((ids[k] for k in e["node"]), np.int64, len(e["node"]))
    changed = np.zeros(len(ids), np.int64); changed[[ids[k] for k in ch["node"]]] = ch["changed_at"]
    rix = {s: i for i, s in enumerate(rs["begin_snapshot"])}
    res = np.fromiter((rix[s] for s in e["result"]), np.int64, len(nid))
    read_at = np.asarray(rs["read_at"]); own = np.array([ids[k] for k in own_key])
    node_result = np.full(len(ids), -1); node_result[own] = np.arange(len(own))
    o = np.argsort(res, kind="stable"); fwd, fptr = nid[o], np.searchsorted(res[o], np.arange(len(own) + 1))
    o = np.argsort(nid, kind="stable"); rev, rptr = res[o], np.searchsorted(nid[o], np.arange(len(ids) + 1))
    return dict(ids=ids, fwd=fwd, fptr=fptr, rev=rev, rptr=rptr, changed=changed, read_at=read_at, own=own,
                node_result=node_result, res=res, nid=nid, rix=rix)


def m_after_write(g, node):
    seen, todo = set(), [g["ids"][node]]
    while todo:
        n = todo.pop()
        for r in g["rev"][g["rptr"][n]:g["rptr"][n + 1]]:
            if r not in seen:
                seen.add(r); todo.append(g["own"][r])
    return len(seen)


def m_one(g, r, seen=None):
    seen = set() if seen is None else seen; bad = 0
    for n in g["fwd"][g["fptr"][r]:g["fptr"][r + 1]]:
        bad += g["changed"][n] > g["read_at"][r]
        q = g["node_result"][n]
        if q >= 0 and q not in seen:
            seen.add(q); bad += m_one(g, q, seen)
    return bad


def m_whole(g):
    direct = np.unique(g["res"][g["changed"][g["nid"]] > g["read_at"][g["res"]]])
    up, todo = set(direct.tolist()), list(direct)
    while todo:
        n = g["own"][todo.pop()]
        for r in g["rev"][g["rptr"][n]:g["rptr"][n + 1]]:
            if r not in up:
                up.add(r); todo.append(r)
    return len(direct), len(up) - len(direct)


for N in [int(a) for a in sys.argv[1:]] or [5000, 50000, 500000]:
    T = max(N // 25, 10); p = dict(N=N, T=T, C=10 * T, V=3 * T // 2, S0=3 * N, K=2 * T + 40 * T + 3 * T // 2)
    path = f"{HERE}/run/bench_{N}.duckdb"
    for f in (path, path + ".wal"):
        if os.path.exists(f): os.remove(f)
    c = duckdb.connect(path)
    c.execute(SCHEMA)
    sql = GEN
    for k in sorted(p, key=len, reverse=True): sql = sql.replace("$" + k, str(p[k]))
    t = time.perf_counter(); c.execute(sql); gen = time.perf_counter() - t
    edges = c.execute("SELECT count(*), max(n) FROM (SELECT count(*) n FROM g_read GROUP BY asset, what)").fetchone()
    hub, typ = ("s1", "result f"), c.execute("SELECT asset, what FROM g_read WHERE what = 'data' LIMIT 1").fetchone()
    last = 3 * N + N
    print(f"\n== {N} results, {T} tables, {10 * T} columns, {3 * T // 2} views; {c.execute('SELECT count(*) FROM g_read').fetchone()[0]} edges;"
          f" most-read node read by {edges[1]}; generated in {gen:.1f}s")
    for label in ["no index", "ART index on g_read(asset, what), g_read(result), g_result(subject)"]:
        if label != "no index":
            c.execute("CREATE INDEX r1 ON g_read(asset, what); CREATE INDEX r2 ON g_read(result); CREATE INDEX r3 ON g_result(subject)")
        for name, q, a in [("i after a write to a hub result", AFTER_WRITE, list(hub)), ("i after a write to a table", AFTER_WRITE, list(typ)),
                           ("ii is one result current", ONE, [last]), ("iii whole check", WHOLE, None)]:
            ms, out = timed(lambda: c.execute(q, a).fetchall() if a else c.execute(q).fetchall(), 3)
            print(f"SQL  {label[:8]:8} {name:34} {ms:9.1f} ms  {out}")
    tracemalloc.start()
    t = time.perf_counter(); g = memory(c); build = time.perf_counter() - t
    mem = tracemalloc.get_traced_memory()[0] / 2**20; tracemalloc.stop()
    print(f"MEM  build at open {build * 1000:.0f} ms, {mem:.0f} MiB held (Python dict + numpy)")
    for name, f in [("i after a write to a hub result", lambda: m_after_write(g, "s1|result f")),
                    ("i after a write to a table", lambda: m_after_write(g, "|".join(typ))),
                    ("ii is one result current", lambda: m_one(g, g["rix"][last])), ("iii whole check", lambda: m_whole(g))]:
        ms, out = timed(f)
        print(f"MEM  {name:43} {ms:9.3f} ms  {out}")
