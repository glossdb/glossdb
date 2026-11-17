//! The app interface against a real plane and a loaded table, driven
//! in-process through the router (tower oneshot, mounted at `/app`
//! exactly as serverd mounts it): pages render from the app's own
//! directory, frames stream Arrow IPC with URL params bound as plan
//! placeholders, and everything that should refuse refuses.

use std::sync::Arc;

use axum::Router;
use axum::body::{Body, to_bytes};
use axum::http::{Request, Response, StatusCode, header};
use glossdb_apps::engine::{Actor, ActorKind};
use glossdb_apps::engine::{Caller, Plane, Session};
use tower::ServiceExt;

/// The server's own URI the pages are told.
const ORIGIN: &str = "https://glossql.example";

/// A workspace with the dataset `perf`, a ledger loaded from a CSV, and
/// the app `board` glossed on it, behind the app interface.
async fn workspace() -> (Router, Arc<Plane>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join("ledger.csv"),
        "month,cohort,value\n2026-01-01,a,10.5\n2026-01-01,b,2.0\n2026-02-01,a,4.0\n",
    )
    .unwrap();

    let config = glossdb_apps::engine::testing::golden(dir.path())
        .await
        .unwrap();
    let plane = Arc::new(Plane::open(config).await.unwrap());
    let session = builder(&plane).await;
    session
        .execute(&format!(
            "DECLARE DATASET perf SET (purpose: 'app interface test');\n\
             USE perf;\n\
             DECLARE SOURCE erp SET (type: csv, location: '{}');\n\
             DECLARE RECIPE ledger ON perf FROM erp AS $$\
               SELECT CAST(month AS DATE) AS month, cohort, \
                      CAST(value AS DOUBLE) AS value \
               FROM read_csv('ledger.csv')$$;",
            dir.path().display()
        ))
        .await
        .unwrap();

    // The app, authored as glosses — the only way an app is written:
    // one part per gloss under the four shipped aspects. Its name is
    // its own: an `<app>.<part>` subject whose first segment names the
    // dataset would read as dataset-qualified (SPEC.md §3).
    session
        .execute(
            r#"USE perf;
               GLOSS app ON board AS $${"title": "Perf"}$$;
               GLOSS app_page ON board.index AS $${"html": "{% extends \"shell.html\" %}\n{% import \"modules/tiles.html\" as tiles %}\n{% block main %}\n<div class=\"tiles\">\n{{ tiles::chart(frame=\"frames/monthly\", spec=\"specs/monthly.vl.json\", title=\"Monthly\") }}\n</div>\n{% endblock %}\n"}$$;
               GLOSS app_frame ON board.monthly AS $${"sql": "SELECT month, sum(value) AS value FROM ledger GROUP BY month ORDER BY month"}$$;
               GLOSS app_frame ON board.by_cohort AS $${"sql": "SELECT month, sum(value) AS value FROM ledger WHERE cohort = $cohort GROUP BY month ORDER BY month"}$$;
               GLOSS app_frame ON board.uncastable AS $${"sql": "SELECT CAST(cohort AS BIGINT) AS n FROM ledger"}$$;
               GLOSS app_frame ON board.evil AS $${"sql": "DROP TABLE ledger"}$$;
               GLOSS app_spec ON board.monthly AS $${"spec": "{\"mark\": \"bar\", \"encoding\": {}}"}$$;"#,
        )
        .await
        .unwrap();

    // In the binary the gate sits above this interface and leaves the
    // verified caller in the request; here the layer holds in for it,
    // as a human actor, as the gate stamps on a human interface.
    let router = Router::new()
        .merge(glossdb_apps::root_router(Arc::clone(&plane), ORIGIN))
        .nest(
            "/{dataset}/app",
            glossdb_apps::router(Arc::clone(&plane), ORIGIN),
        )
        .nest("/assets", glossdb_apps::assets_router())
        .layer(axum::Extension(Caller(Actor {
            kind: ActorKind::Human,
            id: "ada".into(),
        })));
    (router, plane, dir)
}

async fn get(app: &Router, uri: &str) -> Response<Body> {
    app.clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap()
}

async fn text(response: Response<Body>) -> String {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

/// Every link of `html`, in the page's order.
fn hrefs(html: &str) -> Vec<String> {
    html.split("href=\"")
        .skip(1)
        .filter_map(|rest| rest.split('"').next())
        .map(str::to_string)
        .collect()
}

/// The bar's page links: the navigation the shell labels `pages`.
fn bar(page: &str) -> &str {
    let labelled = page
        .find("aria-label=\"pages\"")
        .unwrap_or_else(|| panic!("the page has no bar:\n{page}"));
    let end = labelled + page[labelled..].find("</nav>").unwrap();
    &page[labelled..end]
}

/// The link the bar marks as the current page.
fn current_tab(page: &str) -> String {
    let marked: Vec<&str> = bar(page)
        .split("<a")
        .filter(|link| link.contains("aria-current=\"page\""))
        .collect();
    assert_eq!(marked.len(), 1, "one tab is current: {marked:?}");
    hrefs(marked[0]).remove(0)
}

/// A channel on the workspace as `kind` `id`, bound to `dataset` if given.
async fn channel(plane: &Plane, kind: ActorKind, id: &str, dataset: Option<&str>) -> Arc<Session> {
    plane
        .channel(
            Actor {
                kind,
                id: id.into(),
            },
            dataset,
        )
        .await
        .unwrap()
}

/// The agent the workspace was built by, unbound.
async fn builder(plane: &Plane) -> Arc<Session> {
    channel(plane, ActorKind::Agent, "builder", None).await
}

/// A frame as the browser reads it: its schema, and each row's cells as
/// they display, under their columns.
struct Frame {
    schema: arrow::datatypes::SchemaRef,
    rows: Vec<Vec<String>>,
}

impl Frame {
    fn read(bytes: &[u8]) -> Frame {
        let reader =
            arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes), None).unwrap();
        let schema = reader.schema();
        let mut rows = Vec::new();
        for batch in reader {
            let batch = batch.unwrap();
            for i in 0..batch.num_rows() {
                rows.push(
                    batch
                        .columns()
                        .iter()
                        .map(|c| arrow::util::display::array_value_to_string(c, i).unwrap())
                        .collect(),
                );
            }
        }
        Frame { schema, rows }
    }

    fn len(&self) -> usize {
        self.rows.len()
    }

    /// Every cell of `column`, in the frame's row order.
    fn col(&self, column: &str) -> Vec<&str> {
        let index = self
            .schema
            .index_of(column)
            .unwrap_or_else(|_| panic!("no column {column} in {:?}", self.schema));
        self.rows.iter().map(|r| r[index].as_str()).collect()
    }

    /// The cell of `column` in the row whose `key` cell is `value`.
    fn cell(&self, key: &str, value: &str, column: &str) -> &str {
        let at = self
            .col(key)
            .iter()
            .position(|v| *v == value)
            .unwrap_or_else(|| panic!("no row with {key} = {value}: {:?}", self.rows));
        self.col(column)[at]
    }
}

/// The frame a response streams, after insisting it is one.
async fn frame(response: Response<Body>) -> Frame {
    let status = response.status();
    let kind = response.headers().get(header::CONTENT_TYPE).cloned();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(
        status,
        StatusCode::OK,
        "{}",
        String::from_utf8_lossy(&bytes)
    );
    assert_eq!(
        kind.as_ref().and_then(|k| k.to_str().ok()),
        Some("application/vnd.apache.arrow.stream")
    );
    Frame::read(&bytes)
}

/// The frame's `value` column as numbers.
async fn values(response: Response<Body>) -> Vec<f64> {
    let frame = frame(response).await;
    frame
        .col("value")
        .iter()
        .map(|v| v.parse().unwrap())
        .collect()
}

async fn row_count(response: Response<Body>) -> usize {
    frame(response).await.len()
}

#[tokio::test(flavor = "multi_thread")]
async fn a_manifest_orders_the_tabs() {
    let (app, plane, _dir) = workspace().await;
    let session = builder(&plane).await;
    let page = r#"{% extends \"shell.html\" %}{% block main %}x{% endblock %}"#;
    session
        .execute(&format!(
            r#"USE perf;
               GLOSS app ON two AS $${{"title": "Two", "pages": [{{"name": "later", "title": "Later"}}, {{"name": "index", "title": "First"}}]}}$$;
               GLOSS app_page ON two.index AS $${{"html": "{page}"}}$$;
               GLOSS app_page ON two.later AS $${{"html": "{page}"}}$$;
               GLOSS app_page ON bare.index AS $${{"html": "{page}"}}$$;
               GLOSS app_page ON bare.zed AS $${{"html": "{page}"}}$$;
               GLOSS app_page ON bare.alpha AS $${{"html": "{page}"}}$$;"#
        ))
        .await
        .unwrap();

    // The manifest's order.
    let two = text(get(&app, "/perf/app/two").await).await;
    assert_eq!(
        hrefs(bar(&two)),
        ["/perf/app/two/p/later", "/perf/app/two"],
        "{two}"
    );

    // No manifest: index first, then by name; the open page is marked.
    let bare = text(get(&app, "/perf/app/bare/p/zed").await).await;
    assert_eq!(
        hrefs(bar(&bare)),
        [
            "/perf/app/bare",
            "/perf/app/bare/p/alpha",
            "/perf/app/bare/p/zed"
        ],
        "{bare}"
    );
    assert_eq!(current_tab(&bare), "/perf/app/bare/p/zed");
}

#[tokio::test(flavor = "multi_thread")]
async fn pages_render_and_frames_stream() {
    let (app, _plane, _dir) = workspace().await;

    // The dataset's page is the console, and the URL says so.
    let home = get(&app, "/perf/app").await;
    assert_eq!(home.status(), StatusCode::SEE_OTHER);
    assert_eq!(home.headers()[header::LOCATION], "/perf/app/console");
    // A console page is a live view of the catalog and is never
    // cached; its picker lists the glossed app by the path that opens it.
    let console = get(&app, "/perf/app/console/p/export").await;
    assert_eq!(
        console
            .headers()
            .get(header::CACHE_CONTROL)
            .and_then(|v| v.to_str().ok()),
        Some("no-store")
    );
    let console = text(console).await;
    assert!(
        console.contains("\"/perf/app/board\""),
        "the picker lists the app:\n{console}"
    );

    // The glossed page renders through the shell and the tile macros
    // and names the frame its author placed.
    let page = get(&app, "/perf/app/board").await;
    let status = page.status();
    let page = text(page).await;
    assert_eq!(status, StatusCode::OK, "{page}");
    assert!(page.contains("frames/monthly"), "{page}");
    // A frame streams IPC: two months, summed.
    let frame = get(&app, "/perf/app/board/frames/monthly").await;
    assert_eq!(frame.status(), StatusCode::OK);
    assert_eq!(values(frame).await, vec![12.5, 4.0]);

    // URL params bind as plan placeholders — cohort a only.
    let filtered = get(&app, "/perf/app/board/frames/by_cohort?cohort=a").await;
    assert_eq!(filtered.status(), StatusCode::OK);
    assert_eq!(values(filtered).await, vec![10.5, 4.0]);

    // An unbound placeholder is the read telling the author what the
    // URL required it.
    let unbound = get(&app, "/perf/app/board/frames/by_cohort").await;
    assert_eq!(unbound.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let unbound = text(unbound).await;
    assert!(unbound.contains("cohort"), "{unbound}");

    // A frame that plans and then fails on its first batch is refused
    // with the engine's reason, as the JSON its tile renders — never a
    // 200 over a stream that breaks.
    let uncastable = get(&app, "/perf/app/board/frames/uncastable").await;
    assert_eq!(uncastable.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let uncastable = text(uncastable).await;
    assert!(uncastable.contains("\"error\""), "{uncastable}");

    // The spec serves as authored.
    let spec = get(&app, "/perf/app/board/specs/monthly.vl.json").await;
    assert_eq!(spec.status(), StatusCode::OK);
    assert!(text(spec).await.contains("\"mark\""));
}

/// The interface serves an app at its release: a part glossed after the
/// release serves under `?draft` and not at the plain URL, a release
/// naming an earlier one's time serves that cut, and an app nobody
/// released serves its draft.
#[tokio::test(flavor = "multi_thread")]
async fn a_release_gates_what_is_served() {
    let (app, plane, _dir) = workspace().await;
    let session = channel(&plane, ActorKind::Agent, "builder", Some("perf")).await;
    let doubled = r#"GLOSS app_frame ON board.monthly AS $${"sql": "SELECT month, sum(value) * 2 AS value FROM ledger GROUP BY month ORDER BY month"}$$;"#;

    // No release: the draft serves at the plain URL.
    let frame = get(&app, "/perf/app/board/frames/monthly").await;
    assert_eq!(values(frame).await, vec![12.5, 4.0]);

    // Released, then edited: the plain URL keeps the release and
    // `?draft` shows the edit.
    session
        .execute(r#"GLOSS app_release ON board AS $${"note": "first cut"}$$;"#)
        .await
        .unwrap();
    session.execute(doubled).await.unwrap();
    let frame = get(&app, "/perf/app/board/frames/monthly").await;
    assert_eq!(values(frame).await, vec![12.5, 4.0]);
    let frame = get(&app, "/perf/app/board/frames/monthly?draft").await;
    assert_eq!(values(frame).await, vec![25.0, 8.0]);

    // A second release serves the edit; one naming the first's time
    // returns to it, and `app_releases` says which stands.
    session
        .execute(r#"GLOSS app_release ON board AS $${"note": "second cut"}$$;"#)
        .await
        .unwrap();
    let frame = get(&app, "/perf/app/board/frames/monthly").await;
    assert_eq!(values(frame).await, vec![25.0, 8.0]);
    let first = session
        .execute("SELECT min(written_at) FROM glossary_history WHERE aspect = 'app_release';")
        .await
        .unwrap();
    let glossdb_apps::engine::Outcome::Rows { batches, .. } = &first[0] else {
        panic!("a read answers rows")
    };
    let first_at = arrow::util::display::array_value_to_string(batches[0].column(0), 0).unwrap();
    session
        .execute(&format!(
            r#"GLOSS app_release ON board AS $${{"at": "{first_at}", "note": "back"}}$$;"#
        ))
        .await
        .unwrap();
    let frame = get(&app, "/perf/app/board/frames/monthly").await;
    assert_eq!(values(frame).await, vec![12.5, 4.0]);
    let released = session
        .execute("SELECT app, note, \"at\" FROM app_releases;")
        .await
        .unwrap();
    let glossdb_apps::engine::Outcome::Rows { batches, .. } = &released[0] else {
        panic!("a read answers rows")
    };
    let cell =
        |i: usize| arrow::util::display::array_value_to_string(batches[0].column(i), 0).unwrap();
    assert_eq!(
        (cell(0), cell(1), cell(2)),
        ("board".to_string(), "back".to_string(), first_at)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn unknown_paths_and_write_frames_are_refused() {
    let (app, _plane, _dir) = workspace().await;

    // Frames read; a write in a frame file is not one query.
    let evil = get(&app, "/perf/app/board/frames/evil").await;
    assert_eq!(evil.status(), StatusCode::UNPROCESSABLE_ENTITY);

    // Unknown app, unknown frame, unknown page.
    assert_eq!(
        get(&app, "/perf/app/nope").await.status(),
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(&app, "/perf/app/board/frames/nope").await.status(),
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(&app, "/perf/app/board/p/nope").await.status(),
        StatusCode::NOT_FOUND
    );

    // A frame name is one flat segment; nothing walks.
    let escape = get(&app, "/perf/app/board/frames/..%2Findex").await;
    assert_eq!(escape.status(), StatusCode::NOT_FOUND);
}

/// A page body is markup. The interface serves every page under a policy
/// that runs the shell's own assets and nothing the page carries, so
/// a script an author glosses — an agent's, rendered with the human
/// viewer's actor on the query and decide interfaces — is served as text
/// the browser does not run.
#[tokio::test(flavor = "multi_thread")]
async fn a_page_body_is_markup_not_script() {
    let (app, plane, _dir) = workspace().await;
    let session = builder(&plane).await;
    let planted = "<script>fetch('/perf/query', {method: 'POST', body: 'DROP TABLE ledger'})\
                   </script><button onclick='alert(1)'>x</button>";
    session
        .execute(&format!(
            r#"USE perf;
               GLOSS app ON planted AS $${{"title": "Planted"}}$$;
               GLOSS app_page ON planted.index AS $${{"html": "{{% extends \"shell.html\" %}}{{% block main %}}{planted}{{% endblock %}}"}}$$;"#
        ))
        .await
        .unwrap();

    let page = get(&app, "/perf/app/planted").await;
    assert_eq!(page.status(), StatusCode::OK);
    let policy = page.headers()[header::CONTENT_SECURITY_POLICY]
        .to_str()
        .unwrap()
        .to_string();
    assert_eq!(policy, glossdb_apps::CONTENT_SECURITY_POLICY);
    // What the policy must say, whatever else it comes to say: script
    // from this origin's files alone, no eval, no object, no moved
    // base, no form posting elsewhere.
    let script = policy
        .split(';')
        .map(str::trim)
        .find(|d| d.starts_with("script-src"))
        .unwrap();
    assert_eq!(script, "script-src 'self'", "{policy}");
    for directive in ["object-src 'none'", "base-uri 'none'", "form-action 'self'"] {
        assert!(policy.contains(directive), "{policy}");
    }
    assert!(!policy.contains("unsafe-eval"), "{policy}");
    // The markup serves as authored; the policy is what stops it.
    let body = text(page).await;
    assert!(body.contains(planted), "{body}");

    // The workspace root and the built-in carry the same policy.
    for uri in ["/", "/perf/app/console"] {
        let response = get(&app, uri).await;
        assert_eq!(
            response.headers()[header::CONTENT_SECURITY_POLICY],
            glossdb_apps::CONTENT_SECURITY_POLICY,
            "{uri}"
        );
    }
}

/// Every page renders and passes the shell's own policy: every script
/// a rendered page loads is one of the interface's assets by `src` and
/// served as such, nothing is inline, no element carries a handler
/// attribute, no URL is `javascript:`, and htmx is told not to
/// evaluate — over the workspace root, the built-in's every page in
/// each of its states, and a glossed app's.
#[tokio::test(flavor = "multi_thread")]
async fn every_page_renders_and_passes_the_shells_policy() {
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    for uri in [
        "/",
        "/perf/app/console",
        "/perf/app/console/p/history",
        "/perf/app/console/p/history?kind=load",
        "/perf/app/console/p/lineage",
        "/perf/app/console/p/glossary",
        "/perf/app/console/p/glossary?table=ledger",
        "/perf/app/console/p/glossary?table=ledger&tab=history",
        "/perf/app/console/p/glossary?column=ledger.value",
        "/perf/app/console/p/glossary?aspect=meaning",
        "/perf/app/console/p/glossary?source=erp",
        "/perf/app/console/p/glossary?source=erp&tab=used",
        "/perf/app/console/p/views",
        "/perf/app/console/p/views?view=dso",
        "/perf/app/console/p/views?view=dso&tab=measurements",
        "/perf/app/console/p/views?view=dso&dim=cohort",
        "/perf/app/console/p/views?view=cleaned&kind=relation",
        "/perf/app/console/p/views?view=payables&kind=scalar",
        "/perf/app/console/p/quality",
        "/perf/app/console/p/quality?test=role_test",
        "/perf/app/console/p/quality?test=range_test&kind=range",
        "/perf/app/console/p/review",
        "/perf/app/console/p/export",
        "/perf/app/console/p/query",
        "/perf/app/board",
    ] {
        let response = get(&app, uri).await;
        assert_eq!(response.status(), StatusCode::OK, "{uri}");
        let html = text(response).await;
        for (at, _) in html.match_indices("<script") {
            let end = at + html[at..].find('>').unwrap();
            let tag = &html[at..end];
            let src = tag
                .split("src=\"")
                .nth(1)
                .and_then(|s| s.split('"').next())
                .unwrap_or_else(|| panic!("{uri}: a script with no src: {tag}"));
            assert!(src.starts_with("/assets/"), "{uri}: {tag}");
            let asset = get(&app, src).await;
            assert_eq!(asset.status(), StatusCode::OK, "{uri}: {src}");
            let rest = &html[end + 1..];
            let inline = &rest[..rest.find("</script>").unwrap()];
            assert!(
                inline.trim().is_empty(),
                "{uri}: an inline script: {inline}"
            );
        }
        for (at, _) in html.match_indices(" on") {
            let after = &html[at + 3..];
            let name: String = after
                .chars()
                .take_while(char::is_ascii_alphabetic)
                .collect();
            assert!(
                name.is_empty() || !after[name.len()..].starts_with('='),
                "{uri}: a handler attribute: on{name}="
            );
        }
        assert!(!html.contains("javascript:"), "{uri}");
        if uri != "/" {
            assert!(html.contains("\"allowEval\":false"), "{uri}");
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_glossed_part_may_not_take_a_builtin_name() {
    let (app, plane, _dir) = workspace().await;

    // Add an app, don't fork the built-in: a part carries no manifest
    // requirement, so one frame under the built-in's name would resolve
    // the whole app to that single file and 404 every page the console
    // ships.
    let session = channel(&plane, ActorKind::Agent, "author", None).await;
    session
        .execute(
            r#"USE perf;
               GLOSS app_frame ON console.mine AS $${"sql": "SELECT 1 AS v"}$$;"#,
        )
        .await
        .unwrap();

    let page = get(&app, "/perf/app/console").await;
    assert_eq!(page.status(), StatusCode::INTERNAL_SERVER_ERROR);

    // The same part under its own name serves — including without a
    // manifest, which names no dataset — the URL binds it.
    session
        .execute(r#"GLOSS app_frame ON cash.mine AS $${"sql": "SELECT 1 AS v"}$$;"#)
        .await
        .unwrap();
    assert_eq!(
        get(&app, "/perf/app/cash/frames/mine").await.status(),
        StatusCode::OK
    );
}

/// The same shapes on DuckDB, the metrics kit's way: the metric is a
/// view whose columns carry the vocabulary — the period and the value
/// glossed by role, the additivity on the value, the slice ranked — and
/// the period column profiled.
async fn seed_model_shapes(plane: &Arc<Plane>) {
    let agent = builder(plane).await;
    agent
        .execute(
            r#"USE perf;
               DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
               DECLARE ASPECT payables WITH $${"title": "Outstanding payables", "x-kind": "scalar"}$$ AS VIEW;
               DECLARE ASPECT cleaned WITH $${"title": "Cleaned ledger", "x-kind": "relation"}$$ AS VIEW;
               GLOSS dso ON perf AS $${"sql": "SELECT month, value, cohort FROM perf.ledger",
                 "assumptions": [
                   {"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.7,
                    "alternative": "doubled", "alternative_sql": "SELECT month, value * 2 AS value FROM ledger"},
                   {"dimension": "grain", "key": "grain-preserving", "assumption": "grain-preserving", "basis": "measured", "confidence": 1.0}
                 ]}$$;
               GLOSS payables ON perf AS $${"sql": "SELECT sum(value) AS value FROM perf.ledger"}$$;
               GLOSS cleaned ON perf AS $${"sql": "SELECT month, value AS amount, cohort FROM perf.ledger WHERE value IS NOT NULL"}$$;
               GLOSS definitions ON perf AS $${"definitions": {"dso": {
                 "meaning": "receivables outstanding expressed in days of revenue",
                 "unit": "days", "owner": "Finance", "source": "KPI handbook v3",
                 "formula": "ar[end of w] / revenue[w] * days[w]"}}}$$;
               GLOSS role ON dso.month AS $${"value": "timestamp"}$$;
               GLOSS role ON dso.value AS $${"value": "measure"}$$;
               GLOSS additivity ON dso.value AS $${"value": "additive"}$$;
               GLOSS role ON dso.cohort AS $${"value": "dimension"}$$;
               GLOSS dimension ON dso.cohort AS $${"value": "primary"}$$;
               DECLARE DATASET second SET (purpose: 'multi-dataset guard');
               USE perf;
               SELECT temporal() FROM dso.month;"#,
        )
        .await
        .unwrap();
}

fn assert_classic(dt: &arrow::datatypes::DataType, frame: &str, field: &str) {
    use arrow::datatypes::DataType;
    match dt {
        // The browser's arrow reader speaks only classic types — a view
        // type in a frame schema renders as `Unrecognized type` in every
        // tile bound to it (glossql-apps: cast view types back).
        DataType::Utf8View | DataType::BinaryView => {
            panic!("frame {frame} field {field} carries view type {dt}")
        }
        DataType::List(f) | DataType::LargeList(f) | DataType::FixedSizeList(f, _) => {
            assert_classic(f.data_type(), frame, field)
        }
        DataType::Struct(fields) => {
            for f in fields {
                assert_classic(f.data_type(), frame, field)
            }
        }
        _ => {}
    }
}

/// A review decision is a human act, signed with the caller's own name. This is
/// a human interface: the gate stamps the human actor kind on whoever reaches it,
/// and the catalog takes the token's subject — nothing anonymous holds
/// in for the person.
#[tokio::test(flavor = "multi_thread")]
async fn a_review_decision_is_signed_with_the_callers_own_name() {
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let human = channel(&plane, ActorKind::Human, "human", Some("perf")).await;

    let accepted = app
        .oneshot(
            Request::post("/perf/app/console/decide")
                .header(
                    axum::http::header::CONTENT_TYPE,
                    "application/x-www-form-urlencoded",
                )
                .body(Body::from(
                    "subject=perf&aspect=dso&key=per-line&stance=confirmed",
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(accepted.status(), StatusCode::NO_CONTENT);
    // Signed with the name the gate carried in (`workspace()` holds
    // in for it with `ada`), not with a stand-in.
    let signed = human
        .execute("SELECT actor_id FROM glossary WHERE aspect = 'review_decision' AND actor_kind = 'human';")
        .await
        .unwrap();
    let glossdb_apps::engine::Outcome::Rows { batches, .. } = signed.last().unwrap() else {
        panic!("expected rows");
    };
    let batch = batches.iter().find(|b| b.num_rows() > 0).unwrap();
    assert_eq!(
        arrow::util::display::array_value_to_string(batch.column(0), 0).unwrap(),
        "ada"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn every_builtin_frame_executes_and_serves_classic_types() {
    // Every built-in frame executes end to end — an optimizer error
    // fires only at plan time — and streams classic types, which the
    // browser's reader decodes; on a workspace carrying the shapes the
    // frames read.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    // Every refusal at once, so one run says what the port still lacks.
    let mut refused = Vec::new();
    for builtin in glossdb_apps::BUILTINS {
        for (path, _) in builtin.files {
            let Some(stem) = path
                .strip_prefix("frames/")
                .and_then(|p| p.strip_suffix(".sql"))
            else {
                continue;
            };
            // Extra params are ignored by frames that bind none of them.
            let uri = format!(
                "/perf/app/{}/frames/{stem}?view=dso&subject=ledger&dim=region&grain=month&span=24&test=none&stopped=0&table=ledger&column=ledger.value&aspect=meaning&kind=fact&source=none&object=ledger",
                builtin.name
            );
            let response = get(&app, &uri).await;
            let status = response.status();
            let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
            if status != StatusCode::OK {
                refused.push(format!(
                    "frame {}/{stem} refused: {}",
                    builtin.name,
                    String::from_utf8_lossy(&bytes)
                ));
                continue;
            }
            for field in Frame::read(&bytes).schema.fields() {
                assert_classic(field.data_type(), stem, field.name());
            }
        }
    }
    assert!(refused.is_empty(), "{}", refused.join("\n"));
}

#[tokio::test(flavor = "multi_thread")]
async fn frames_declare_their_class_and_data_frames_never_read_the_glossary() {
    // Every frame response carries `glossql-frame-class`, derived from
    // what the frame's expansion resolves. A `catalog` frame reads the
    // glossary and can change under a review decision; a `data` frame
    // cannot, so the browser's store keeps it across decisions. The
    // class is about what a frame serves: a metric's row (`axes`) is
    // catalog, its cells (`slices`, `latest`, `drivers`) are data, and
    // the trend, which joins the stored forecast, is catalog.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    for (frame, expected) in [
        ("open", "catalog"),
        ("settled", "catalog"),
        ("next_rows", "catalog"),
        ("functions", "catalog"),
        ("assumptions", "catalog"),
        ("measures", "catalog"),
        ("views", "catalog"),
        ("columns", "catalog"),
        ("conventions", "catalog"),
        ("terms", "catalog"),
        ("vocabulary", "catalog"),
        ("joins", "catalog"),
        ("table_head", "catalog"),
        ("table_columns", "catalog"),
        ("table_identities", "catalog"),
        ("table_loads", "catalog"),
        ("column_head", "catalog"),
        ("column_values", "catalog"),
        ("aspect_head", "catalog"),
        ("aspect_values", "catalog"),
        ("findings", "catalog"),
        ("breaches", "catalog"),
        ("measured", "catalog"),
        ("relations", "catalog"),
        ("view_fields", "catalog"),
        ("tests", "catalog"),
        ("test", "catalog"),
        ("test_results", "catalog"),
        ("axes", "catalog"),
        ("view", "catalog"),
        ("trend", "catalog"),
        ("plan", "catalog"),
        ("slices", "data"),
        ("dims", "data"),
        ("drivers", "data"),
        ("latest", "data"),
    ] {
        let response = get(
            &app,
            &format!(
                "/perf/app/console/frames/{frame}?view=dso&subject=ledger&dim=region&grain=month&span=24&test=none&stopped=0&table=ledger&column=ledger.value&aspect=meaning&kind=fact&source=none"
            ),
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK, "{frame}");
        assert_eq!(
            response
                .headers()
                .get("glossql-frame-class")
                .and_then(|v| v.to_str().ok()),
            Some(expected),
            "frame `{frame}`"
        );
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_console_takes_a_review_decision_and_refuses_a_stale_one() {
    // The interface's one write. A human who
    // steps away has no way back into the catalog at all: the MCP review
    // can only ask while they are watching, and an agent may never
    // speak for them. The console is already the page of open
    // questions, so answering there is the gesture it was drawn for.
    //
    // Only the claim's identity is posted. The prose the review decision records
    // is re-derived from `open_questions` — so a tab left open across a
    // applying the decision is refused rather than believed, and a browser can never
    // put words in the workspace's mouth.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let post = |form: &'static str| {
        let app = app.clone();
        async move {
            app.oneshot(
                Request::post("/perf/app/console/decide")
                    .header(
                        axum::http::header::CONTENT_TYPE,
                        "application/x-www-form-urlencoded",
                    )
                    .body(Body::from(form))
                    .unwrap(),
            )
            .await
            .unwrap()
        }
    };

    assert_eq!(
        row_count(get(&app, "/perf/app/console/frames/open").await).await,
        1
    );

    // A correction with the human's own words. The answer is the write
    // event, not a navigation: 204 with the trigger header the store
    // and every component listen for.
    let response =
        post("subject=perf&aspect=dso&key=per-line&stance=corrected&note=per+order,+not+per+line")
            .await;
    assert_eq!(response.status(), StatusCode::NO_CONTENT, "{:?}", response);
    assert_eq!(
        response
            .headers()
            .get("HX-Trigger")
            .and_then(|v| v.to_str().ok()),
        Some("glossql:written")
    );
    assert!(
        response.headers().get(header::LOCATION).is_none(),
        "the answer is an event, there is nowhere to follow it to"
    );

    // The question closes, the review decision holds in the human's
    // words, and the view's assumptions show it beside the assumption.
    assert_eq!(
        row_count(get(&app, "/perf/app/console/frames/open").await).await,
        0,
        "the decision closes its question"
    );
    let settled = frame(get(&app, "/perf/app/console/frames/settled").await).await;
    // the link carries the dataset the app is mounted under
    assert_eq!(settled.col("link"), ["/perf/app/console/p/views?view=dso"]);
    assert_eq!(settled.col("stance"), ["corrected"]);
    assert!(settled.col("note")[0].contains("per order, not per line"));
    let assumptions = frame(get(&app, "/perf/app/console/frames/assumptions?view=dso").await).await;
    assert_ne!(assumptions.cell("what", "per line", "decision"), "");
    assert_eq!(assumptions.cell("what", "grain-preserving", "decision"), "");

    // The same post again: the question no longer derives, so the interface
    // refuses instead of writing a second review decision from a stale page —
    // and the refusal carries the trigger too, so the stale tab's
    // panels re-derive to the current state on their own.
    let response = post("subject=perf&aspect=dso&key=per-line&stance=confirmed").await;
    assert_eq!(response.status(), StatusCode::CONFLICT);
    assert_eq!(
        response
            .headers()
            .get("HX-Trigger")
            .and_then(|v| v.to_str().ok()),
        Some("glossql:written")
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unclear_review_decision_closes_the_question_without_taking_a_side() {
    // The third stance: the human refuses the
    // QUESTION, not the claim. Without it a sloppily worded question
    // can only be deferred, which re-asks the same words
    // forever. `unclear` is stored like any review decision — this key closes, what
    // confused the reader rides as the note — and what the agent owes
    // is a reformulation under a NEW key (whose clearer wording derives
    // its own question), never an applied decision.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let response = app
        .clone()
        .oneshot(
            Request::post("/perf/app/console/decide")
                .header(
                    axum::http::header::CONTENT_TYPE,
                    "application/x-www-form-urlencoded",
                )
                .body(Body::from(
                    "subject=perf&aspect=dso&key=per-line&stance=unclear&note=which+lines%3F",
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT, "{response:?}");

    // The question closes — the refusal holds this key, and only a
    // re-record with a clearer assumption asks again.
    assert_eq!(
        row_count(get(&app, "/perf/app/console/frames/open").await).await,
        0
    );
    let settled = frame(get(&app, "/perf/app/console/frames/settled").await).await;
    assert_eq!(settled.col("link"), ["/perf/app/console/p/views?view=dso"]);
    assert_eq!(settled.col("stance"), ["unclear"]);
    assert!(settled.col("note")[0].contains("which lines?"));
}

#[tokio::test(flavor = "multi_thread")]
async fn the_export_tab_lists_tables_and_reads() {
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    // The page's curl line names this dataset's query interface.
    let page = text(get(&app, "/perf/app/console/p/export").await).await;
    assert!(page.contains("/perf/query"), "{page}");

    // The loaded table with its shape and its two files.
    let tables = frame(get(&app, "/perf/app/console/frames/tables").await).await;
    assert_eq!(tables.col("name"), ["ledger"]);
    assert_eq!(tables.col("rows"), ["3"]);
    assert_eq!(tables.col("csv"), ["/perf/app/export/ledger.csv"]);
    assert_eq!(tables.col("parquet"), ["/perf/app/export/ledger.parquet"]);

    // The served reads as their relations, with the definition's
    // meaning beside them, the kind as the chip, and the files.
    let reads = frame(get(&app, "/perf/app/console/frames/reads?stopped=0").await).await;
    assert!(reads.col("read").contains(&"payables"));
    assert_eq!(
        reads.cell("read", "dso", "what"),
        "receivables outstanding expressed in days of revenue"
    );
    assert_eq!(reads.cell("read", "dso", "chip"), "metric");
    assert_eq!(
        reads.cell("read", "dso", "csv"),
        "/perf/app/export/read.dso.csv"
    );

    // A dataset with nothing loaded serves empty frames, and its page
    // renders.
    assert_eq!(
        row_count(get(&app, "/second/app/console/frames/tables").await).await,
        0
    );
    assert_eq!(
        get(&app, "/second/app/console/p/export").await.status(),
        StatusCode::OK
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_table_downloads_as_csv_and_parquet() {
    let (app, plane, dir) = workspace().await;

    let csv = get(&app, "/perf/app/export/ledger.csv").await;
    assert_eq!(csv.status(), StatusCode::OK);
    assert_eq!(
        csv.headers()[header::CONTENT_TYPE],
        "text/csv; charset=utf-8"
    );
    assert_eq!(
        csv.headers()[header::CONTENT_DISPOSITION],
        "attachment; filename=\"ledger.csv\""
    );
    let body = text(csv).await;
    let mut lines = body.lines();
    assert_eq!(lines.next(), Some("month,cohort,value"), "{body}");
    assert_eq!(lines.count(), 3, "{body}");
    assert!(body.contains("2026-01-01,a,10.5"), "{body}");

    let parquet = get(&app, "/perf/app/export/ledger.parquet").await;
    assert_eq!(parquet.status(), StatusCode::OK);
    assert_eq!(
        parquet.headers()[header::CONTENT_TYPE],
        "application/vnd.apache.parquet"
    );
    assert_eq!(
        parquet.headers()[header::CONTENT_DISPOSITION],
        "attachment; filename=\"ledger.parquet\""
    );
    let bytes = to_bytes(parquet.into_body(), usize::MAX).await.unwrap();
    // The engine's types survive the file: the cast date and double,
    // read back by the engine itself.
    let file = dir.path().join("ledger-export.parquet");
    std::fs::write(&file, &bytes).unwrap();
    let session = channel(&plane, ActorKind::Human, "t", Some("perf")).await;
    let (schema, batches) = session
        .batches_with_schema(
            &format!("SELECT * FROM read_parquet('{}')", file.display()),
            &[],
        )
        .await
        .unwrap();
    assert_eq!(
        schema.field_with_name("month").unwrap().data_type(),
        &arrow::datatypes::DataType::Date32
    );
    assert_eq!(
        schema.field_with_name("value").unwrap().data_type(),
        &arrow::datatypes::DataType::Float64
    );
    let rows: usize = batches.iter().map(|b| b.num_rows()).sum();
    assert_eq!(rows, 3);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_served_metric_downloads_its_relation() {
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    let csv = get(&app, "/perf/app/export/read.dso.csv").await;
    assert_eq!(csv.status(), StatusCode::OK);
    let body = text(csv).await;
    let mut lines = body.lines();
    assert_eq!(lines.next(), Some("month,value,cohort"), "{body}");
    assert_eq!(lines.count(), 3, "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_download_refuses_what_it_should() {
    let (app, _plane, _dir) = workspace().await;

    // An unknown dataset names the ones there are.
    let missing = get(&app, "/nope/app/export/ledger.csv").await;
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
    assert!(text(missing).await.contains("perf"));

    // A format that is not one of the two.
    let xlsx = get(&app, "/perf/app/export/ledger.xlsx").await;
    assert_eq!(xlsx.status(), StatusCode::NOT_FOUND);

    // No format at all.
    let bare = get(&app, "/perf/app/export/ledger").await;
    assert_eq!(bare.status(), StatusCode::NOT_FOUND);

    // A name that is not an identifier never reaches the planner.
    let walk = get(&app, "/perf/app/export/..%2Fledger.csv").await;
    assert_eq!(walk.status(), StatusCode::NOT_FOUND);
    let spliced = get(
        &app,
        "/perf/app/export/ledger%3B%20DROP%20TABLE%20ledger.csv",
    )
    .await;
    assert_eq!(spliced.status(), StatusCode::NOT_FOUND);

    // A table or a metric the dataset does not hold is the engine's
    // refusal, with its text.
    let table = get(&app, "/perf/app/export/nothing.csv").await;
    assert_eq!(table.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert!(text(table).await.contains("nothing"));
    let metric = get(&app, "/perf/app/export/read.nothing.parquet").await;
    assert_eq!(metric.status(), StatusCode::UNPROCESSABLE_ENTITY);

    // The table is still there.
    let csv = get(&app, "/perf/app/export/ledger.csv").await;
    assert_eq!(csv.status(), StatusCode::OK);
}

/// An asset revalidates by its tag: the first load carries the bytes
/// and a validator, and a load that sends the validator back is
/// answered with no body. A tag the server does not hold is a full
/// answer again.
#[tokio::test]
async fn an_unchanged_asset_revalidates_without_its_body() {
    let assets = glossdb_apps::assets_router();
    let first = get(&assets, "/app.css").await;
    assert_eq!(first.status(), StatusCode::OK);
    assert_eq!(first.headers()[header::CACHE_CONTROL], "no-cache");
    let tag = first.headers()[header::ETAG].clone();
    assert!(!text(first).await.is_empty());

    let conditional = |sent: axum::http::HeaderValue| {
        let assets = assets.clone();
        async move {
            assets
                .oneshot(
                    Request::get("/app.css")
                        .header(header::IF_NONE_MATCH, sent)
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap()
        }
    };
    let again = conditional(tag.clone()).await;
    assert_eq!(again.status(), StatusCode::NOT_MODIFIED);
    assert_eq!(again.headers()[header::ETAG], tag);
    assert!(text(again).await.is_empty());

    let stale = conditional("\"0000000000000000\"".parse().unwrap()).await;
    assert_eq!(stale.status(), StatusCode::OK);
}

/// Every tile the reference page and the apps skill name is a script
/// the shell loads and an asset the interface serves. The prose is the
/// author's contract; a tile it names that the browser never defines
/// renders as nothing, silently.
#[tokio::test(flavor = "multi_thread")]
async fn every_documented_tile_is_shipped() {
    const SHELL: &str = include_str!("../../templates/shell.html");
    const REFERENCE: &str = include_str!("../../../../docs/reference/apps.md");
    const SKILL: &str = include_str!("../../../../skills/glossql-apps/SKILL.md");

    let mut tiles: Vec<String> = [REFERENCE, SKILL]
        .iter()
        .flat_map(|page| page.split("gl-").skip(1))
        .map(|rest| {
            rest.chars()
                .take_while(|c| c.is_ascii_lowercase())
                .collect()
        })
        .filter(|name: &String| !name.is_empty())
        .collect();
    tiles.sort();
    tiles.dedup();
    assert!(tiles.len() >= 5, "{tiles:?}");

    let assets = Router::new().nest("/assets", glossdb_apps::assets_router());
    for tile in tiles {
        let script = format!("/assets/gl-{tile}.js");
        assert!(SHELL.contains(&script), "the shell loads no {script}");
        let served = get(&assets, &script).await;
        assert_eq!(served.status(), StatusCode::OK, "{script}");
        assert!(
            text(served)
                .await
                .contains(&format!("customElements.define('gl-{tile}'")),
            "{script} defines no element"
        );
    }
}

/// A person walks the console of a small workspace: the dataset's
/// page, a loaded table's page and a view's page each answer 200, and
/// every frame a page names serves under the page's own params.
#[tokio::test(flavor = "multi_thread")]
async fn a_person_walks_the_dataset_a_table_and_a_view() {
    let (app, plane, _dir) = workspace().await;
    builder(&plane)
        .await
        .execute(
            r#"USE perf;
               DECLARE ASPECT cohorts WITH $${"title": "Cohorts", "x-kind": "relation"}$$ AS VIEW;
               GLOSS cohorts ON perf AS $${"sql": "SELECT month, cohort, value FROM perf.ledger"}$$;"#,
        )
        .await
        .unwrap();
    for (page, params) in [
        ("index", ""),
        ("glossary", "table=ledger"),
        ("views", "view=cohorts"),
    ] {
        let uri = format!("/perf/app/console/p/{page}?{params}");
        let response = get(&app, &uri).await;
        assert_eq!(response.status(), StatusCode::OK, "{uri}");
        let html = text(response).await;
        let mut frames: Vec<&str> = html
            .split("frame=\"frames/")
            .skip(1)
            .filter_map(|rest| rest.split('"').next())
            .collect();
        frames.sort();
        frames.dedup();
        assert!(!frames.is_empty(), "{uri} names no frame");
        for named in frames {
            let named = named.replace("&amp;", "&");
            let (name, own) = named.split_once('?').unwrap_or((&named, ""));
            let params = [params, own]
                .into_iter()
                .filter(|p| !p.is_empty())
                .collect::<Vec<_>>()
                .join("&");
            let frame = format!("/perf/app/console/frames/{name}?{params}");
            let response = get(&app, &frame).await;
            let status = response.status();
            assert_eq!(
                status,
                StatusCode::OK,
                "{uri}: {frame}: {}",
                text(response).await
            );
        }
    }
}
