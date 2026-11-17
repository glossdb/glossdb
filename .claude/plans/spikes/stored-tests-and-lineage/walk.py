"""The check walk over every edge against result edges only, at 500,000 (bench.py first). Output: walk.out."""
import duckdb, time, statistics, sys
c = duckdb.connect(sys.argv[1] if len(sys.argv) > 1 else "run/bench_500000.duckdb")
col = c.execute("SELECT asset FROM g_definition WHERE kind='column' AND dataset='d0' ORDER BY hash(asset) LIMIT 1").fetchone()[0]
for label, filt in [("column", f"subject = '{col}'"), ("dataset", "true")]:
    for name, src in [("all edges", "g_read"), ("result edges only", "(SELECT * FROM g_read WHERE what LIKE 'result %')")]:
        q = f"""WITH RECURSIVE roots AS (SELECT id FROM g_result WHERE end_snapshot IS NULL AND dataset = 'd0' AND {filt}),
  walk(root, id) AS (SELECT id, id FROM roots UNION SELECT w.root, q.id FROM walk w JOIN {src} e ON e.result = w.id
  JOIN g_result q ON q.subject = e.asset AND 'result ' || q.function = e.what AND q.end_snapshot IS NULL) SELECT count(*) FROM walk"""
        ts = []
        for _ in range(3):
            t = time.perf_counter(); r = c.execute(q).fetchone(); ts.append(time.perf_counter() - t)
        print(f"{label:8} {name:20} {statistics.median(ts)*1000:7.1f} ms {r}")
