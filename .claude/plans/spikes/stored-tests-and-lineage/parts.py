"""Questions 3 and 5 apart: the collapse and TESTS() with and without the current marks (the
check walk), on the catalogs bench.py left in run/. Output: parts.out."""
import time, statistics, duckdb
from store import HERE

READS = open(f"{HERE}/reads.sql").read()
NOMARK = (READS.replace("fk AS (SELECT * FROM g_check_of(ds, subj) WHERE id IN (SELECT id FROM picked)),",
                        "fk AS (SELECT NULL::BIGINT AS id, NULL::VARCHAR AS state WHERE false),")
          .replace("LEFT JOIN g_check_of(ds, subj) k ON k.id = r.id", "LEFT JOIN (SELECT NULL::BIGINT AS id, NULL::VARCHAR AS state WHERE false) k ON k.id = r.id")
          .replace("MACRO g_", "MACRO n_").replace("FROM g_collapsed(", "FROM n_collapsed(").replace("FROM g_tests(", "FROM n_tests("))
assert NOMARK.count("WHERE false") == 2
for N in [5000, 50000, 500000]:
    c = duckdb.connect(f"{HERE}/run/bench_{N}.duckdb")
    c.execute(NOMARK)
    col = c.execute("SELECT asset FROM g_definition WHERE kind = 'column' AND dataset = 'd0' ORDER BY hash(asset) LIMIT 1").fetchone()[0]
    print(f"\n== {N}")
    for what, arg in [("a dataset", "NULL"), ("a table", "'d0.t3'"), ("a column", f"'{col}'")]:
        for read in ["collapsed", "tests"]:
            line = []
            for m in ["g", "n"]:
                ts = []
                for _ in range(3):
                    t = time.perf_counter()
                    r = c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM {m}_{read}('d0', {arg}) t").fetchone()
                    ts.append(time.perf_counter() - t)
                line.append(f"{statistics.median(ts) * 1000:6.1f} ms {r[0]:>6} rows")
            print(f"{read:9} {what:9}  with the marks: {line[0]}   without: {line[1]}")
    c.close()

# a kit's edges read from annotation bodies at each call, as lineage_edges_scenario does today
# (glossql/kits/outlook/kit.sql:555): 100 / 1,000 / 10,000 scenarios of 5 levers each
c = duckdb.connect()
print("\n== a scenario's edges unnested from its annotation's body at each read")
for n in [100, 1000, 10000]:
    c.execute(f"""CREATE OR REPLACE TABLE ann AS SELECT 'd0' AS dataset, 'd0' AS asset, 'scenario_' || i AS property, 'agent' AS actor,
        json_object('levers', [json_object('column', 'd0.t' || ((i * 7 + k) % 1000) || '.c1') FOR k IN range(5)])::VARCHAR AS body
        FROM range({n}) r(i)""")
    ts = []
    for _ in range(3):
        t = time.perf_counter()
        r = c.execute("""SELECT count(*), sum(hash(t)) % 1000 FROM (SELECT dataset || '.' || property AS "from", l.lever->>'column' AS "to"
            FROM ann, unnest(coalesce(from_json(body::JSON->'levers', '["JSON"]'), [])) l(lever) WHERE asset = dataset) t""").fetchone()
        ts.append(time.perf_counter() - t)
    print(f"{n:6} scenarios: {statistics.median(ts) * 1000:6.1f} ms, {r[0]} edges")
