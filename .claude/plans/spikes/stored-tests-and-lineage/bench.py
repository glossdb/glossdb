"""Question 7: generated catalogs at three sizes, every result computed and stored; then one
write of each kind, what is due, what is computed, and the reads over stored rows.
Output: bench.out. Usage: bench.py [N ...] (default 5000 50000 500000)."""
import sys, time, statistics, json
from store import *
import kit
from kit import declare_kits, functions, DETECTORS

FN = functions(lake=False)
ROLES = ["measure", "dimension", "timestamp", "key"]

GEN = """
-- tables, columns, views; every catalog row begins at a snapshot in 1..$S0
INSERT INTO g_definition SELECT 1 + hash(t) % 100, NULL, ds, ds || '.t' || t, 'table', ds || '.t' || t, 'table', [], []
  FROM (SELECT 'd' || (i % $D) AS ds, i // $D AS t FROM range($T) r(i));
INSERT INTO g_definition SELECT 1 + hash(t, j) % 100, NULL, ds, ds || '.t' || t || '.c' || j, 'column', ds || '.t' || t, 'INTEGER', [], []
  FROM (SELECT 'd' || (i % $D) AS ds, i // $D AS t FROM range($T) r(i)), range(10) q(j);
INSERT INTO g_load SELECT ds, ds || '.t' || t, 1 + hash(t, 'load') % $S0 FROM (SELECT 'd' || (i % $D) AS ds, i // $D AS t FROM range($T) r(i));
-- view v of a dataset reads table v % TD, a second table on even v, a third on every fifth
CREATE TEMP TABLE vw AS SELECT ds, ds || '.v' || v AS view, list_distinct([a, b, c]) AS tabs, a, b FROM (
  SELECT 'd' || (i % $D) AS ds, i // $D AS v, ds || '.t' || (v % $TD) AS a,
         CASE WHEN v % 2 = 0 THEN ds || '.t' || ((v * 7 + 3) % $TD) END AS b,
         CASE WHEN v % 5 = 0 THEN ds || '.t' || ((v * 13 + 5) % $TD) END AS c FROM range($V) r(i));
UPDATE vw SET tabs = list_filter(tabs, lambda x: x IS NOT NULL);
INSERT INTO g_definition SELECT 1 + hash(view) % 100, NULL, ds, view, 'view', view, 'select ...',
  list_concat([a || '.c0', a || '.c1', a || '.c2'], CASE WHEN b IS NOT NULL THEN [b || '.c2'] ELSE [] END),
  CASE WHEN b IS NOT NULL THEN [a || '.c3=' || b || '.c0'] ELSE [] END FROM vw;
-- annotations: on every table column role, unit, additivity, meaning (an agent's); a person's role
-- on one column in ten, half of them otherwise; on every view grain_check (a tolerance), and on its
-- four columns role, on its value column additivity
INSERT INTO g_annotation SELECT 1 + hash(asset, p) % ($S0 - 100) + 100, NULL, dataset, asset, p, 'agent',
  json_object('value', CASE p WHEN 'role' THEN ['measure', 'dimension', 'timestamp', 'key'][(1 + hash(asset) % 4)::BIGINT]
                               WHEN 'unit' THEN 'EUR' WHEN 'additivity' THEN 'additive' ELSE 'text' END)::VARCHAR
  FROM g_definition, unnest(['role', 'unit', 'additivity', 'meaning']) u(p) WHERE kind = 'column';
INSERT INTO g_annotation SELECT 100 + hash(asset, 'h') % ($S0 - 100), NULL, dataset, asset, 'role', 'human',
  json_object('value', CASE WHEN hash(asset) % 20 = 0 THEN 'other' ELSE ['measure', 'dimension', 'timestamp', 'key'][(1 + hash(asset) % 4)::BIGINT] END)::VARCHAR
  FROM g_definition WHERE kind = 'column' AND hash(asset) % 10 = 0;
INSERT INTO g_annotation SELECT 100 + hash(view, 'g') % ($S0 - 100), NULL, ds, view, 'grain_check', 'agent', '{"tolerance": 0.0}' FROM vw;
INSERT INTO g_annotation SELECT 100 + hash(view, c) % ($S0 - 100), NULL, ds, view || '.' || c, 'role', 'agent', json_object('value', r)::VARCHAR
  FROM vw, (VALUES ('period', 'timestamp'), ('amount', 'measure'), ('dim1', 'dimension'), ('dim2', 'dimension')) u(c, r);
INSERT INTO g_annotation SELECT 100 + hash(view, 'a') % ($S0 - 100), NULL, ds, view || '.amount', 'additivity', 'agent', '{"value": "additive"}' FROM vw;
"""

RESULTS = """
-- every result computed at $S1, having read at $S0: column profiles, lineage, grain checks
CREATE TEMP TABLE gen AS
SELECT dataset, 'column_profile' AS function, asset AS subject, json_object('distinct', hash(asset) % 100)::VARCHAR AS value
  FROM g_definition WHERE kind = 'column'
UNION ALL SELECT ds, 'lineage', view, to_json(list_transform(list_sort(list_distinct(list_concat([a || '.c0', a || '.c1', a || '.c2'],
  CASE WHEN b IS NOT NULL THEN [b || '.c2', a || '.c3', b || '.c0'] ELSE [] END))), lambda x: [view, x, 'reads']))::VARCHAR FROM vw
UNION ALL SELECT ds, 'grain_check', view, '{"breach_rate": 0.0}' FROM vw;
INSERT INTO g_result SELECT row_number() OVER () + $B, $S1, NULL, dataset, function, subject, value, NULL, $S0, $S0 FROM gen;
INSERT INTO g_read SELECT id, split_part(subject, '.', 1) || '.' || split_part(subject, '.', 2), 'data' FROM g_result WHERE function = 'column_profile'
UNION ALL SELECT id, subject, 'definition' FROM g_result WHERE function = 'column_profile'
UNION ALL SELECT id, 'column_profile', 'declaration' FROM g_result WHERE function = 'column_profile'
UNION ALL SELECT id, subject, 'definition' FROM g_result WHERE function = 'lineage'
UNION ALL SELECT r.id, unnest(v.tabs), 'definition' FROM g_result r JOIN vw v ON v.view = r.subject WHERE r.function = 'lineage'
UNION ALL SELECT id, subject, 'result lineage' FROM g_result WHERE function = 'grain_check'
UNION ALL SELECT r.id, unnest(v.tabs), 'data' FROM g_result r JOIN vw v ON v.view = r.subject WHERE r.function = 'grain_check'
UNION ALL SELECT id, 'grain_check', 'declaration' FROM g_result WHERE function = 'grain_check';
INSERT INTO g_edge SELECT r.id, e[1], e[2], e[3] FROM g_result r, unnest(from_json(r.value, '[["VARCHAR"]]')) u(e) WHERE r.function = 'lineage';
"""


def gen_tests(c, S0, S1):
    """Every test's results, computed by its detector over the whole of the generated values."""
    decl = declarations(c)
    for name, (kind, body) in decl.items():
        if kind != "test":
            continue
        script = decl[body["detector"]][1]["detector"].replace("$threshold", str(body["threshold"]))
        p = body["property"]
        c.execute(f"""INSERT INTO g_result SELECT (SELECT max(id) FROM g_result) + row_number() OVER (), {S1}, NULL,
            split_part(q.subject, '.', 1), '{name}', q.subject, json_object('state', q.state, 'score', q.score::DOUBLE)::VARCHAR, NULL, {S0}, {S0}
            FROM (WITH annotations AS (SELECT subject, aspect, actor_kind, body, true AS current FROM g_values('{p}'))
                  SELECT * FROM ({script}) AS q) q""")
        c.execute(f"""INSERT INTO g_read SELECT id, subject, 'annotation {p}' FROM g_result WHERE function = '{name}'
            UNION ALL SELECT id, CASE WHEN split_part(subject, '.', 2) LIKE 't%' AND len(string_split(subject, '.')) = 3 THEN subject
                                      ELSE split_part(subject, '.', 1) || '.' || split_part(subject, '.', 2) END, 'definition'
                      FROM g_result WHERE function = '{name}'
            UNION ALL SELECT id, '{name}', 'declaration' FROM g_result WHERE function = '{name}'
            UNION ALL SELECT id, '{body["detector"]}', 'declaration' FROM g_result WHERE function = '{name}'
            UNION ALL SELECT r.id, r.subject, 'result ' || f.asset FROM g_result r JOIN g_declaration f ON f.kind = 'function'
                      AND f.body::JSON->>'returns' = '{p}' WHERE r.function = '{name}'""")


def timed(f, n=3):
    ts, out = [], None
    for i in range(n):
        t = time.perf_counter(); out = f(i); ts.append(time.perf_counter() - t)
    return statistics.median(ts) * 1000, out


def ms(x):
    return f"{x:8.1f} ms"


SIZES = {5000: 1, 50000: 4, 500000: 10}
for N in [int(a) for a in sys.argv[1:]] or [5000, 50000, 500000]:
    D = SIZES.get(N, 1); T = max(N // 52, 10); TD = T // D; V = 3 * T // 2; S0 = 10_000
    c = open_file(f"{HERE}/run/bench_{N}.duckdb")
    t0 = time.perf_counter()
    declare_kits(c)  # snapshots 1..n; the generated rows begin below S0
    p = dict(D=D, T=T, TD=TD, V=V, S0=S0, S1=S0 + 1, B=0)
    sql = GEN + RESULTS
    for k in sorted(p, key=len, reverse=True):
        sql = sql.replace("$" + k, str(p[k]))
    c.execute(sql)
    gen_tests(c, S0, S0 + 1)
    c.execute(f"INSERT INTO ducklake_snapshot VALUES ({S0 + 1}, now(), 0, 0, 0)")
    gen = time.perf_counter() - t0
    n_res, n_read, n_edge, n_ann = [c.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in ("g_result", "g_read", "g_edge", "g_annotation")]
    mix = c.execute("SELECT function, count(*) FROM g_result GROUP BY ALL ORDER BY 2 DESC").fetchall()
    print(f"\n== {N}: {n_res} results ({', '.join(f'{f} {k}' for f, k in mix)}); {D} datasets, {T} tables, {T * 10} columns, "
          f"{V} views; {n_ann} annotations; {n_read} edges read; {n_edge} lineage edges; generated in {gen:.1f}s")
    print("whole due now:", c.execute(f"SELECT why, count(*) FROM ({due_sql(declarations(c))}) GROUP BY ALL").fetchall() or "nothing")
    ds = "d0"
    cols = [r[0] for r in c.execute(f"SELECT asset FROM g_definition WHERE kind = 'column' AND dataset = '{ds}' ORDER BY hash(asset) LIMIT 9").fetchall()]
    rows = []

    def after_write(label, write_fn):
        """A write, then what is due from the nodes it wrote, then computing it; median of 3."""
        dec, comp, what = [], [], None
        for i in range(3):
            s = write_fn(i)
            t = time.perf_counter(); d = due(c, ds, s - 1); dec.append(time.perf_counter() - t)
            t = time.perf_counter(); done = bring_current(c, FN, ds, s - 1); comp.append(time.perf_counter() - t)
            what = (len(d), done)
        rows.append((label, statistics.median(dec) * 1000, statistics.median(comp) * 1000, what))

    after_write("an annotation (role) on a table column", lambda i: annotate(c, cols[i], "role", '{"value": "key"}'))
    after_write("an annotation with no test (meaning) on a column", lambda i: annotate(c, cols[3 + i], "meaning", '{"value": "x"}'))
    tab3 = [r[0] for r in c.execute(f"SELECT t FROM (SELECT unnest(tabs) AS t FROM vw WHERE ds = '{ds}') GROUP BY t HAVING count(*) >= 3 ORDER BY t LIMIT 3").fetchall()]
    after_write("a table that three views read: a column added", lambda i: write(c,
        f"INSERT INTO g_definition VALUES ($s, NULL, '{ds}', '{tab3[i]}.cx', 'column', '{tab3[i]}', 'INTEGER', [], [])"))
    after_write("a new view on two tables", lambda i: define(c, f"{ds}.new{i}", [f"{ds}.t{i}.c0", f"{ds}.t{i + 1}.c1"], [f"{ds}.t{i}.c3={ds}.t{i + 1}.c0"]))
    vv = [r[0] for r in c.execute(f"SELECT view FROM vw WHERE ds = '{ds}' AND b IS NULL ORDER BY view LIMIT 3").fetchall()]
    after_write("a view defined again, reading one more table", lambda i: define(c, vv[i], [f"{vv[i].replace('.v', '.t')}.c0", f"{ds}.t1.c1", f"{ds}.t2.c2"]))
    after_write("a test declared again (unit_test, threshold)", lambda i: declare(c, "unit_test", "test",
        {"property": "unit", "detector": "value_entropy", "threshold": 0.5 + i / 10, "grain": "column"}))
    print(f"{'write':52} {'decide':>11} {'compute+store':>14}  due / computed (function, results, retired, values changed)")
    for label, a, b, what in rows:
        print(f"{label:52} {ms(a)} {ms(b):>14}  {what[0]} / {what[1]}")

    # the narrowed check against the whole one, after a write nobody computed after
    s = annotate(c, cols[6], "role", '{"value": "measure"}'); write(c, f"INSERT INTO g_load VALUES ('{ds}', '{ds}.t3', $s)")
    whole = c.execute(f"SELECT id, CASE state WHEN 'possibly out of date' THEN 'possibly' ELSE state END FROM g_check WHERE dataset = '{ds}' AND state <> 'current' ORDER BY 1").fetchall()
    narrow = c.execute(f"SELECT id, state FROM g_check_of('{ds}', NULL) ORDER BY 1").fetchall()
    print(f"after a write and a load nobody computed after: the whole check and the narrowed one agree: {whole == narrow} ({len(whole)} not current)")
    decl = declarations(c)
    reads = [
        ("the whole due, every dataset (check + expected)", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM ({due_sql(decl)}) t").fetchone()),
        ("the whole due, one dataset", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM ({due_sql(decl, ds)}) t").fetchone()),
        ("the whole check alone (g_check)", lambda i: c.execute("SELECT count(*), sum(hash(t)) % 1000 FROM g_check t").fetchone()),
        ("deciding after a write: the nodes written and their readers (g_after)", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_after({s - 1}) t").fetchone()),
        ("deciding after a write: what is expected and missing, one dataset", lambda i: c.execute(f"SELECT count(*) FROM ({expected_sql(decl, ds)}) e WHERE NOT EXISTS (SELECT 1 FROM g_result r WHERE r.end_snapshot IS NULL AND r.function = e.function AND r.subject = e.subject)").fetchone()),
        ("TESTS() of a dataset, with current marks", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_tests('{ds}', NULL) t").fetchone()),
        ("TESTS() of one column", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_tests('{ds}', '{cols[i]}') t").fetchone()),
        ("GLOSSARY() collapsed, a dataset", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_collapsed('{ds}', NULL) t").fetchone()),
        ("GLOSSARY() collapsed, a table", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_collapsed('{ds}', '{ds}.t{i}') t").fetchone()),
        ("GLOSSARY() collapsed, a column", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_collapsed('{ds}', '{cols[i]}') t").fetchone()),
        ("the stale mark alone, a dataset's annotations", lambda i: c.execute(f"""SELECT count(*) FILTER (WHERE a.begin_snapshot < d.changed_at)
            FROM g_annotation a LEFT JOIN g_columns k ON k.asset = a.asset LEFT JOIN (SELECT * FROM g_def_changed WHERE dataset = '{ds}') d
            ON d.node = coalesce(k.asset, split_part(a.asset, '.', 1) || '.' || split_part(a.asset, '.', 2))
            WHERE a.dataset = '{ds}' AND a.end_snapshot IS NULL""").fetchone()),
        ("view_summary stand-in, a dataset", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_view_summary('{ds}') t").fetchone()),
        ("view_tests stand-in, a dataset", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_view_tests('{ds}') t").fetchone()),
        ("lineage(dataset) from stored edges", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_lineage('{ds}') t").fetchone()),
        ("a view's sources (its place) from stored edges", lambda i: c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_lineage('{ds}') t WHERE src = '{ds}.v{i}'").fetchone()),
    ]
    # today's pattern, as a stand-in: after any write the dataset's detectors run whole and the collapse is computed whole
    def today(i):
        n = 0
        for name, (kind, body) in decl.items():
            if kind == "test":
                n += len(run_detector(c, name, body, decl, ds=ds))
        return n, c.execute(f"SELECT count(*), sum(hash(t)) % 1000 FROM g_collapsed('{ds}', NULL) t").fetchone()[0]
    reads.append(("stand-in of today: every detector of a dataset whole + its collapse", today))
    reads.append(("one result per (dataset, test): role_test's detector whole", lambda i: len(run_detector(c, "role_test", decl["role_test"][1], decl, ds=ds))))
    reads.append(("lineage of every view of a dataset planned whole (stand-in)", lambda i: (time.sleep(kit.PLAN_MS / 1000 * V / D), V // D)[1]))
    print(f"{'read':64} {'median of 3':>11}  rows")
    for label, f in reads:
        t, out = timed(f)
        print(f"{label:64} {ms(t)}  {out}")
    c.close()
