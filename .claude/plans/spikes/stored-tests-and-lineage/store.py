"""The writes on the catalog of schema.sql, and who computes what is due.

A function, a test and a kit's function are declarations (g_declaration). A declaration of
kind 'function' names the subjects it is expected on (body.subjects, SQL over the catalog) and
the functions whose results it reads (body.after): that is all the core knows of it. A test
is expected on every subject holding a value of its property. bring_current() computes what
is due, in the order of `after`, one write per function per round."""
import os, shutil, json, time, duckdb

HERE = os.path.dirname(os.path.abspath(__file__))
HEAD = "SELECT max(snapshot_id) FROM ducklake_snapshot"
SCHEMA = open(f"{HERE}/schema.sql").read()
NO_LAKE = """CREATE TABLE IF NOT EXISTS ducklake_snapshot (snapshot_id BIGINT PRIMARY KEY, snapshot_time TIMESTAMPTZ,
  schema_version BIGINT, next_catalog_id BIGINT, next_file_id BIGINT);
CREATE TABLE IF NOT EXISTS ducklake_snapshot_changes (snapshot_id BIGINT, changes_made VARCHAR, author VARCHAR,
  commit_message VARCHAR, commit_extra_info VARCHAR);
CREATE TABLE IF NOT EXISTS g_load (dataset VARCHAR, asset VARCHAR, snapshot BIGINT);
CREATE OR REPLACE VIEW g_lake_changed AS SELECT dataset, asset, 'data' AS what, max(snapshot) AS changed_at
  FROM g_load GROUP BY ALL;
CREATE OR REPLACE VIEW g_columns AS SELECT dataset, asset, relation, body AS type FROM g_definition
  WHERE kind = 'column' AND end_snapshot IS NULL;
"""
READS = open(f"{HERE}/reads.sql").read()


def q(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def open_lake(path, options=""):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    c = duckdb.connect()
    c.execute(f"ATTACH 'ducklake:{path}/meta.duckdb' AS lake (DATA_PATH '{path}/data/' {options})")
    c.execute("USE __ducklake_metadata_lake")
    c.execute(SCHEMA)
    c.execute(READS)
    return c


def open_file(path):
    """A catalog in a DuckDB file with no lake: a table's loads and columns are rows of its own."""
    for f in (path, path + ".wal"):
        if os.path.exists(f):
            os.remove(f)
    c = duckdb.connect(path)
    c.execute(SCHEMA.split("-- @lake")[0] + NO_LAKE + SCHEMA.split("-- @end")[1])
    c.execute("INSERT INTO ducklake_snapshot VALUES (0, now(), 0, 0, 0)")
    c.execute(READS)
    return c


def write(c, *stmts):
    """One catalog write, at the lake's next snapshot id, as DuckLake takes it."""
    c.execute("BEGIN")
    s = c.execute(HEAD).fetchone()[0] + 1
    c.execute("INSERT INTO ducklake_snapshot SELECT ?, now(), schema_version, next_catalog_id,"
              " next_file_id FROM ducklake_snapshot WHERE snapshot_id = ?", [s, s - 1])
    c.execute("INSERT INTO ducklake_snapshot_changes VALUES (?, '', 'catalog', NULL, NULL)", [s])
    for st in stmts:
        c.execute(st.replace("$s", str(s)))
    c.execute("COMMIT")
    return s


def head(c):
    return c.execute(HEAD).fetchone()[0]


def annotate(c, asset, prop, body, actor="agent"):
    ds = asset.split(".")[0]
    return write(c, f"UPDATE g_annotation SET end_snapshot = $s WHERE asset = {q(asset)} AND property = {q(prop)}"
                    f" AND actor = {q(actor)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_annotation VALUES ($s, NULL, {q(ds)}, {q(asset)}, {q(prop)}, {q(actor)}, {q(body)})")


def define(c, view, reads, joins=(), body="select ..."):
    ds = view.split(".")[0]
    return write(c, f"UPDATE g_definition SET end_snapshot = $s WHERE asset = {q(view)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_definition VALUES ($s, NULL, {q(ds)}, {q(view)}, 'view', {q(view)}, {q(body)},"
                 f" {list(reads)!r}::VARCHAR[], {list(joins)!r}::VARCHAR[])")


def declare(c, asset, kind, body, unless_same=False):
    body = body if isinstance(body, str) else json.dumps(body)
    if unless_same and c.execute("SELECT 1 FROM g_declaration WHERE asset = ? AND body = ? AND end_snapshot IS NULL",
                                 [asset, body]).fetchone():
        return None
    return write(c, f"UPDATE g_declaration SET end_snapshot = $s WHERE asset = {q(asset)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_declaration VALUES ($s, NULL, {q(asset)}, {q(kind)}, {q(body)})")


def load(c, sql):
    c.execute(sql)
    return head(c)


# ---- the declarations, as the computation reads them ----------------------------------------

def declarations(c):
    """Every declared function and test: name -> (kind, body)."""
    return {a: (k, json.loads(b)) for a, k, b in c.execute(
        "SELECT asset, kind, body FROM g_declaration WHERE end_snapshot IS NULL AND kind IN ('function', 'test')").fetchall()}


def expected_sql(decl, ds=None):
    """(function, dataset, subject) every result that should exist: a function's declared subjects,
    a test's subjects holding a value of its property. Built from the declarations alone."""
    parts = []
    for name, (kind, body) in decl.items():
        if kind == "test":
            parts.append(f"SELECT DISTINCT {q(name)} AS function, dataset, subject FROM g_values({q(body['property'])})")
        elif body.get("subjects"):
            parts.append(f"SELECT {q(name)} AS function, dataset, subject FROM ({body['subjects']})")
    sql = " UNION ALL ".join(parts) or "SELECT NULL AS function, NULL AS dataset, NULL AS subject WHERE false"
    return f"SELECT * FROM ({sql})" + (f" WHERE dataset = {q(ds)}" if ds else "")


def order(decl):
    """The functions in the order their results are read: a test after the functions that return
    its property, a function after those it names in `after`."""
    def after(n):
        k, b = decl[n]
        if k == "test":
            return [f for f, (k2, b2) in decl.items() if k2 == "function" and b2.get("returns") == b["property"]]
        return [f for f in b.get("after", []) if f in decl]
    done, out = set(), []

    def visit(n):
        if n not in done:
            done.add(n)
            for m in after(n):
                visit(m)
            out.append(n)
    for n in sorted(decl):
        visit(n)
    return out


# ---- what is due ------------------------------------------------------------------------------

def due_sql(decl, ds=None, since=None):
    """The results due: missing (expected, none stored), out of date (a node it read changed after
    it read), possibly out of date (a result it read is out of date: waits), retired (stored, no
    longer expected). since: only the nodes written after that snapshot are looked at (the server
    knows what it wrote); else every node (the whole check)."""
    scope = f"AND dataset = {q(ds)}" if ds else ""
    if since is None:
        stale = f"SELECT id, state FROM g_check WHERE state IN ('out of date', 'possibly out of date', 'not declared') {scope}"
    else:
        stale = f"""SELECT * FROM g_after({since})"""
    funcs = ", ".join(q(n) for n in decl) or "NULL"
    return f"""WITH exp AS ({expected_sql(decl, ds)}),
cur AS (SELECT id, dataset, function, subject FROM g_result WHERE end_snapshot IS NULL {scope}),
chk AS ({stale})
SELECT e.function, e.dataset, e.subject, 'missing' AS why FROM exp e
WHERE NOT EXISTS (SELECT 1 FROM cur r WHERE r.function = e.function AND r.subject = e.subject)
UNION ALL SELECT r.function, r.dataset, r.subject, k.state FROM cur r JOIN chk k ON k.id = r.id
UNION ALL SELECT r.function, r.dataset, r.subject, 'retired' FROM cur r
WHERE r.function IN ({funcs}) AND NOT EXISTS (SELECT 1 FROM exp e WHERE e.function = r.function AND e.subject = r.subject)"""


def due(c, ds=None, since=None):
    return c.execute(due_sql(declarations(c), ds, since) + " ORDER BY ALL").fetchall()


# ---- computing ---------------------------------------------------------------------------------

def run_detector(c, test, body, decl, subjects=None, ds=None):
    """A test's detector over its property's values: of the subjects in the temp table `subjects`
    (one query for the batch), or of a whole dataset. -> [(subject, state, score)]"""
    det = decl.get(body["detector"])
    if det is None:
        raise ValueError(f"detector {body['detector']} is not a declared function")
    script = det[1]["detector"].replace("$threshold", "NULL" if body.get("threshold") is None else str(body["threshold"]))
    where = "subject IN (SELECT subject FROM due_subjects)" if subjects is not None else f"dataset = {q(ds)}"
    return c.execute(f"""SELECT q.subject::VARCHAR, q.state::VARCHAR, q.score::DOUBLE,
        json_object('state', q.state, 'score', q.score::DOUBLE)::VARCHAR FROM (
        WITH annotations AS (SELECT subject, aspect, actor_kind, body, true AS current FROM g_values({q(body['property'])})
                             WHERE {where}) SELECT * FROM ({script}) AS q) q""").fetchall()


def compute_test(c, name, body, decl, subjects):
    """A test's result on each subject: (subject, value, error, reads, edges). One detector run for
    the batch; each subject's result reads its own values, its definition, the test and detector."""
    c.execute("CREATE OR REPLACE TEMP TABLE due_subjects (subject VARCHAR)")
    insert(c, "due_subjects", [(s,) for s in subjects])
    try:
        rows, error = {r[0]: r[3] for r in run_detector(c, name, body, decl, subjects)}, None
    except (duckdb.Error, ValueError) as x:
        rows, error = {}, str(x).split("\n")[0]
    returns = [f for f, (k, b) in decl.items() if k == "function" and b.get("returns") == body["property"]]
    had = {s: fs for s, fs in c.execute(
        "SELECT subject, list(DISTINCT function) FROM g_result WHERE end_snapshot IS NULL AND subject IN "
        "(SELECT subject FROM due_subjects) AND function IN (SELECT unnest(?::VARCHAR[])) GROUP BY ALL", [returns]).fetchall()}
    nodes = dict(c.execute("SELECT subject, g_def_node(subject) FROM due_subjects").fetchall())
    out = []
    for s in subjects:
        reads = [(s, "annotation " + body["property"]), (name, "declaration"), (body["detector"], "declaration")]
        reads += [(s, "result " + f) for f in had.get(s, [])]
        if nodes.get(s):
            reads.append((nodes[s], "definition"))
        v = None if error else rows.get(s)
        out.append((s, v, error, reads, []))
    return out


def insert(c, table, rows, chunk=20000):
    for i in range(0, len(rows), chunk):
        c.execute(f"INSERT INTO {table} VALUES " + ", ".join("(" + ", ".join(str(x) if isinstance(x, int) else q(x)
                                                                         for x in r) + ")" for r in rows[i:i + chunk]))


def store_many(c, function, rows, read_at, retire=()):
    """One write: each row a result of `function`, with the nodes it read and the edges it holds.
    The same (value, error) as the current result keeps its changed_at (early cutoff)."""
    c.execute("CREATE OR REPLACE TEMP TABLE nw (k INT, dataset VARCHAR, subject VARCHAR, value VARCHAR, error VARCHAR)")
    c.execute("CREATE OR REPLACE TEMP TABLE nr (k INT, asset VARCHAR, what VARCHAR)")
    c.execute("CREATE OR REPLACE TEMP TABLE ne (k INT, src VARCHAR, dst VARCHAR, kind VARCHAR)")
    insert(c, "nw", [(k, s.split(".")[0], s, v, e) for k, (s, v, e, _, _) in enumerate(rows)])
    insert(c, "nr", [(k, a, w) for k, r in enumerate(rows) for a, w in r[3]])
    insert(c, "ne", [(k, *x) for k, r in enumerate(rows) for x in r[4]])
    c.execute("CREATE OR REPLACE TEMP TABLE nret (subject VARCHAR)")
    insert(c, "nret", [(s,) for s in retire])
    f = q(function)
    return write(c,
        "CREATE OR REPLACE TEMP TABLE base AS SELECT coalesce(max(id), 0) + 1 AS b FROM g_result",
        f"INSERT INTO g_result SELECT (SELECT b FROM base) + n.k, $s, NULL, n.dataset, {f}, n.subject, n.value, n.error, {read_at},"
        " CASE WHEN p.id IS NOT NULL AND p.value IS NOT DISTINCT FROM n.value AND p.error IS NOT DISTINCT FROM n.error"
        f" THEN p.changed_at ELSE $s END FROM nw n LEFT JOIN g_result p ON p.function = {f} AND p.subject = n.subject"
        " AND p.end_snapshot IS NULL",
        f"UPDATE g_result SET end_snapshot = $s WHERE function = {f} AND end_snapshot IS NULL AND begin_snapshot < $s"
        " AND (subject IN (SELECT subject FROM nw) OR subject IN (SELECT subject FROM nret))",
        "INSERT INTO g_read SELECT (SELECT b FROM base) + k, asset, what FROM nr",
        "INSERT INTO g_edge SELECT (SELECT b FROM base) + k, src, dst, kind FROM ne")


def bring_current(c, functions, ds=None, since=None, rounds=4, log=None):
    """The server after a write: compute what is due, function by function in the order of
    `after`, until nothing is due but what waits. functions: name -> python body for the
    declared functions that are not tests. Returns [(function, computed, retired, values changed)]."""
    done = []
    for _ in range(rounds):
        decl = declarations(c)
        rows = c.execute(due_sql(decl, ds, since)).fetchall()
        todo = {}
        for f, d, s, why in rows:
            if why != "possibly out of date":
                todo.setdefault(f, {"compute": set(), "retire": set()})["retire" if why in ("retired", "not declared") else "compute"].add(s)
        if not todo:
            break
        for f in [n for n in order(decl) if n in todo] + [n for n in todo if n not in decl]:
            subjects = sorted(todo[f]["compute"] - todo[f]["retire"])
            at = head(c)
            if f in decl and decl[f][0] == "test":
                out = compute_test(c, f, decl[f][1], decl, subjects)
            elif f in functions:
                out = functions[f](c, subjects)
            else:
                out = []
            s = store_many(c, f, out, at, sorted(todo[f]["retire"]))
            moved = c.execute("SELECT count(*) FROM g_result WHERE function = ? AND begin_snapshot = ? AND changed_at = ?", [f, s, s]).fetchone()[0]
            done.append((f, len(out), len(todo[f]["retire"]), moved))
    if log is not None:
        log.extend(done)
    return done
