"""A DuckLake lake with the catalog of schema.sql, and the writes on it."""
import os, shutil, duckdb

HERE = os.path.dirname(os.path.abspath(__file__))
HEAD = "SELECT max(snapshot_id) FROM ducklake_snapshot"


def q(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def open_lake(path, options=""):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    c = duckdb.connect()
    c.execute(f"ATTACH 'ducklake:{path}/meta.duckdb' AS lake (DATA_PATH '{path}/data/' {options})")
    c.execute("USE __ducklake_metadata_lake")
    c.execute(open(f"{HERE}/schema.sql").read())
    return c


def conn(c):  # a second connection to the same instance
    c2 = c.cursor()
    c2.execute("USE __ducklake_metadata_lake")
    return c2


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


def annotate(c, asset, prop, body):
    return write(c, f"UPDATE g_annotation SET end_snapshot = $s WHERE asset = {q(asset)}"
                    f" AND property = {q(prop)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_annotation VALUES ($s, NULL, {q(asset)}, {q(prop)}, {q(body)})")


def define(c, view, reads):
    return write(c, f"UPDATE g_definition SET end_snapshot = $s WHERE asset = {q(view)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_definition VALUES ($s, NULL, {q(view)}, 'select …', {reads!r}::VARCHAR[])")


def relate(c, a, b):
    return write(c, f"INSERT INTO g_relationship VALUES ($s, NULL, {q(a)}, {q(b)})")


def load(c, sql):
    """A load, committed by DuckLake itself."""
    c.execute(sql)
    return c.execute(HEAD).fetchone()[0]


def read(c, value_sql):
    """A computation: what it returns, or its error, and the snapshot it read at."""
    c.execute("BEGIN")
    at = c.execute(HEAD).fetchone()[0]
    try:
        v, e = str(c.execute(value_sql).fetchone()[0]), None
        c.execute("COMMIT")
    except duckdb.Error as x:
        v, e = None, str(x).split("\n")[0]
        c.execute("ROLLBACK")
    return v, e, at


def store(c, fn, subject, reads, v, e, read_at):
    """The result, with the nodes it read. Same (value, error) as before: changed_at is kept."""
    prev = c.execute("SELECT value, error, changed_at FROM g_result WHERE function = ? AND subject = ?"
                     " AND end_snapshot IS NULL", [fn, subject]).fetchone()
    changed = prev[2] if prev and (prev[0], prev[1]) == (v, e) else "$s"
    return write(c, f"UPDATE g_result SET end_snapshot = $s WHERE function = {q(fn)} AND subject = {q(subject)}"
                    " AND end_snapshot IS NULL",
                 f"INSERT INTO g_result VALUES ($s, NULL, {q(fn)}, {q(subject)}, {q(v)}, {q(e)}, {read_at}, {changed})",
                 *[f"INSERT INTO g_read VALUES ($s, {q(a)}, {q(w)})" for a, w in reads])


def compute(c, fn, subject, reads, value_sql):
    return store(c, fn, subject, reads, *read(c, value_sql))


def show(c, title, sql="SELECT function, subject, read_at, changed_at, state, changed FROM g_check"):
    print(f"\n-- {title}")
    cur = c.execute(sql)
    names = [d[0] for d in cur.description]
    print(" | ".join(names))
    for row in cur.fetchall():
        print(" | ".join("" if x is None else str(x) for x in row))


def declare(c, asset, kind, body, unless_same=False):
    """A declaration of any kind. unless_same: no write when the current row has this body."""
    if unless_same and c.execute("SELECT 1 FROM g_declaration WHERE asset = ? AND body = ? AND end_snapshot IS NULL",
                                 [asset, body]).fetchone():
        return None
    return write(c, f"UPDATE g_declaration SET end_snapshot = $s WHERE asset = {q(asset)} AND end_snapshot IS NULL",
                 f"INSERT INTO g_declaration VALUES ($s, NULL, {q(asset)}, {q(kind)}, {q(body)})")
