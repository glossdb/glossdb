//! The app interface against a real plane and a loaded table, driven
//! in-process through the router (tower oneshot, mounted at `/app`
//! exactly as serverd mounts it): pages render from the app's own
//! directory, frames stream Arrow IPC with URL params bound as plan
//! placeholders, and everything that should refuse refuses.

use std::sync::Arc;

use arrow::array::Float64Array;
use axum::Router;
use axum::body::{Body, to_bytes};
use axum::http::{Request, Response, StatusCode, header};
use glossdb_apps::engine::{Actor, ActorKind};
use glossdb_apps::engine::{Caller, Plane};
use tower::ServiceExt;

/// The server's own URI the pages are told.
const ORIGIN: &str = "https://glossql.example";

async fn open_plane(dir: &std::path::Path) -> Plane {
    Plane::open(glossdb_apps::engine::testing::golden(dir).await.unwrap())
        .await
        .unwrap()
}

async fn workspace() -> (Router, Arc<Plane>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join("ledger.csv"),
        "month,cohort,value\n2026-01-01,a,10.5\n2026-01-01,b,2.0\n2026-02-01,a,4.0\n",
    )
    .unwrap();

    let plane = Arc::new(open_plane(dir.path()).await);
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
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
        .execute(&format!(
            r#"USE perf;
               {aspects}
               GLOSS app ON board AS $${{"title": "Perf"}}$$;
               GLOSS app_page ON board.index AS $${{"html": "{{% extends \"shell.html\" %}}\n{{% import \"modules/tiles.html\" as tiles %}}\n{{% block main %}}\n<div class=\"tiles\">\n{{{{ tiles::chart(frame=\"frames/monthly\", spec=\"specs/monthly.vl.json\", title=\"Monthly\") }}}}\n</div>\n{{% endblock %}}\n"}}$$;
               GLOSS app_frame ON board.monthly AS $${{"sql": "SELECT month, sum(value) AS value FROM ledger GROUP BY month ORDER BY month"}}$$;
               GLOSS app_frame ON board.by_cohort AS $${{"sql": "SELECT month, sum(value) AS value FROM ledger WHERE cohort = $cohort GROUP BY month ORDER BY month"}}$$;
               GLOSS app_frame ON board.uncastable AS $${{"sql": "SELECT CAST(cohort AS BIGINT) AS n FROM ledger"}}$$;
               GLOSS app_frame ON board.evil AS $${{"sql": "DROP TABLE ledger"}}$$;
               GLOSS app_spec ON board.monthly AS $${{"spec": "{{\"mark\": \"bar\", \"encoding\": {{}}}}"}}$$;"#,
            aspects = shipped_app_declarations()
        ))
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

/// The core kit, whose declarations the workspace carries from its
/// first open.
const CORE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../kits/core/kit.sql"
));

/// The same aspect as the core kit declares it, cut from its text:
/// re-declared here, it is a no-op, and the tests keep one shape.
fn shipped_review_decision_declaration() -> &'static str {
    let kit = CORE;
    let start = kit
        .find("DECLARE ASPECT review_decision")
        .expect("the kit ships the review_decision aspect");
    let len = kit[start..]
        .find("AS FACT;")
        .expect("the declaration closes")
        + "AS FACT;".len();
    &kit[start..start + len]
}

/// The SHIPPED app aspects — `app`, `app_page`, `app_frame`,
/// `app_spec` — cut from the core the same way, so the interface serves the
/// parts a real workspace writes.
fn shipped_app_declarations() -> &'static str {
    let kit = CORE;
    let start = kit
        .find("DECLARE ASPECT app WITH")
        .expect("the kit ships the app aspects");
    let last = kit[start..]
        .find("DECLARE ASPECT app_release")
        .expect("the kit ships app_release");
    let len = last
        + kit[start + last..]
            .find("AS FACT;")
            .expect("the declaration closes")
        + "AS FACT;".len();
    &kit[start..start + len]
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

async fn values(response: Response<Body>) -> Vec<f64> {
    assert_eq!(
        response.headers()[header::CONTENT_TYPE],
        "application/vnd.apache.arrow.stream"
    );
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    let mut out = Vec::new();
    for batch in reader {
        let batch = batch.unwrap();
        let index = batch.schema().index_of("value").unwrap();
        let column = batch
            .column(index)
            .as_any()
            .downcast_ref::<Float64Array>()
            .unwrap()
            .clone();
        out.extend(column.iter().map(|v| v.unwrap()));
    }
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn a_manifest_orders_the_tabs() {
    let (app, plane, _dir) = workspace().await;
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
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
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
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
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
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
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "author".into(),
            },
            None,
        )
        .await
        .unwrap();
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

async fn row_count(response: Response<Body>) -> usize {
    assert_eq!(
        response.headers()[header::CONTENT_TYPE],
        "application/vnd.apache.arrow.stream"
    );
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    reader.map(|b| b.unwrap().num_rows()).sum()
}

/// Every cell of the frame, flattened to one string — for asserting a
/// rendered value is present without caring which column carries it.
async fn body_text(response: Response<Body>) -> String {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    let mut out = String::new();
    for batch in reader {
        let batch = batch.unwrap();
        for column in batch.columns() {
            for i in 0..batch.num_rows() {
                if let Ok(v) = arrow::util::display::array_value_to_string(column, i) {
                    out.push_str(&v);
                    out.push('\n');
                }
            }
        }
    }
    out
}

/// The same shapes on DuckDB, the metrics kit's way: the metric is a
/// view whose columns carry the vocabulary — the period and the value
/// glossed by role, the additivity on the value, the slice ranked — and
/// the period column profiled.
async fn seed_model_shapes(plane: &Arc<Plane>) {
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
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
    let human = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "human".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
    human
        .execute(shipped_review_decision_declaration())
        .await
        .unwrap();

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
    // Parse-only coverage lets two defect classes ship:
    // an optimizer error that only fires at plan time, and view-typed
    // columns the browser reader cannot decode. Every built-in frame
    // must execute end to end and stream classic types — against a
    // workspace carrying the shapes the frames read.
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
            let reader = arrow_ipc::reader::StreamReader::try_new(
                std::io::Cursor::new(bytes.to_vec()),
                None,
            )
            .unwrap();
            for field in reader.schema().fields() {
                assert_classic(field.data_type(), stem, field.name());
            }
            for batch in reader {
                batch.unwrap();
            }
        }
    }
    assert!(refused.is_empty(), "{}", refused.join("\n"));
}

#[tokio::test(flavor = "multi_thread")]
async fn frames_declare_their_class_and_data_frames_never_read_the_glossary() {
    // Metadata and data are not one pile: every
    // frame response carries `glossql-frame-class`, derived by the
    // session's pre-pass from what the frame's expansion actually
    // resolves — never a curated list. `catalog` frames read the
    // glossary somewhere and can change under a review decision; `data` frames
    // provably cannot, so the browser's store keeps them across
    // decisions. The class is about what a frame SERVES, not what its
    // build consumed: the cube's facts (`axes`) say what the judged
    // catalog admitted and are catalog; its cells (`slices`, `latest`,
    // `drivers`) are the data at a grain and survive a review decision on
    // screen. The trend joins the stored forecast for the range and how
    // often it held, so it is catalog-class and is read again after a decision.
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
        ("remeasure", "catalog"),
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
async fn a_second_dataset_does_not_multiply_a_views_rows() {
    // With two datasets in the
    // workspace, frames that scanned the `datasets` relation fanned
    // every joined row out — two formulas, two materializations. The
    // bound dataset rides in as `current_dataset` instead; one row per
    // face.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await; // seeds a second dataset

    let metric = get(&app, "/perf/app/console/frames/view?view=dso").await;
    assert_eq!(metric.status(), StatusCode::OK);
    let served = body_text(metric).await;
    assert_eq!(served.lines().filter(|l| l.starts_with("dso")).count(), 1);
    // The formula the seed wrote, not the empty-state prose. Counting
    // rows alone is how the face came to render nothing in every real
    // workspace: the fixture wrote a formula no skill ever taught an
    // agent to write, so the join returned a row and the value was null
    // everywhere but here.
    assert!(
        served.contains("ar[end of w] / revenue[w] * days[w]"),
        "the formula face served no formula:\n{served}"
    );
    // Unit and meaning come from the `definitions` registry, never the
    // aspect blob — a declaration cannot be superseded, and exactly
    // this field goes stale there.
    // The seed's blob carries no unit, so a face reading `x-unit` shows
    // nothing and this fails.
    assert!(
        served.contains("receivables outstanding expressed in days of revenue"),
        "the metric face served no meaning:\n{served}"
    );
    let assumptions = get(&app, "/perf/app/console/frames/assumptions?view=dso").await;
    assert_eq!(assumptions.status(), StatusCode::OK);
    assert_eq!(row_count(assumptions).await, 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_persons_newer_formula_waits_on_the_agent_until_the_definition_is_recorded_again() {
    // A person writes a formula for a metric that is newer than the
    // metric's recorded definition. The open list shows a row for the
    // agent until the agent records the definition again.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    // Seeded state: the agent's definition of dso with its formula. No
    // row of the open list says a person decided something.
    let decided = |body: &str| body.matches("\ndecided\n").count();
    let before = get(&app, "/perf/app/console/frames/next_rows").await;
    assert_eq!(before.status(), StatusCode::OK);
    assert_eq!(decided(&body_text(before).await), 0);

    // The human's answer is stored on their channel: newer than the
    // recorded dso gloss.
    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    let human = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "human".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
    human
        .execute(r#"GLOSS definitions ON perf AS $${"definitions": {"dso": {"meaning": "receivables outstanding expressed in days of revenue", "unit": "days", "owner": "Finance", "source": "KPI handbook v3", "formula": "ar[end of w] / revenue[w] * 360"}}}$$;"#)
        .await
        .unwrap();
    let after = body_text(get(&app, "/perf/app/console/frames/next_rows").await).await;
    assert_eq!(
        decided(&after),
        1,
        "the person's formula waits for the agent:\n{after}"
    );

    // The agent re-records the materialization — the wait clears.
    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(
            r#"USE perf;
               GLOSS dso ON perf AS $${"sql": "SELECT month, value FROM ledger",
                 "assumptions": [{"dimension": "definition", "assumption": "360-day year",
                                  "basis": "engineer-decided formula", "confidence": 1.0}]}$$;"#,
        )
        .await
        .unwrap();
    let cleared = body_text(get(&app, "/perf/app/console/frames/next_rows").await).await;
    assert_eq!(
        decided(&cleared),
        0,
        "recording the definition again closes the row:\n{cleared}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn the_metric_frame_serves_the_winning_value_once() {
    // With two values on `definitions` (human and
    // agent) the detail rendered the formula and the materialization
    // twice. The metric face reads the winning value only — human
    // outranking agent, exactly like the collapsed read. The
    // assumptions ledger is different: it
    // is the AGENT's working record (review decisions annotate it, and a human
    // supersede of the metric governs reads without replacing it).
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    let before = get(&app, "/perf/app/console/frames/view?view=dso").await;
    assert_eq!(before.status(), StatusCode::OK);
    assert_eq!(row_count(before).await, 1);

    // The human answers the formula, then supersedes the metric gloss
    // itself — both through their session channel.
    let human = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "human".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
    human
        .execute(
            r#"GLOSS definitions ON perf AS $${"definitions": {"dso": {"meaning": "receivables outstanding expressed in days of revenue", "unit": "days", "owner": "Finance", "source": "KPI handbook v3", "formula": "ar[end of w] / revenue[w] * 360"}}}$$;
               GLOSS dso ON perf AS $${"sql": "SELECT month, value FROM ledger",
                 "assumptions": [{"dimension": "definition", "key": "per-line",
                                  "assumption": "decided", "basis": "engineer",
                                  "confidence": 1.0}]}$$;"#,
        )
        .await
        .unwrap();

    // Still one row on the metric face, and it is the human's; the
    // assumptions ledger keeps serving the agent's working record —
    // its two disclosed assumptions — never a blend of the two bodies.
    let metric = get(&app, "/perf/app/console/frames/view?view=dso").await;
    let served = body_text(metric).await;
    assert_eq!(served.lines().filter(|l| l.starts_with("dso")).count(), 1);
    assert!(
        served.contains("ar[end of w] / revenue[w] * 360"),
        "the human's formula must outrank the agent's:\n{served}"
    );
    let assumptions = get(&app, "/perf/app/console/frames/assumptions?view=dso").await;
    assert_eq!(
        row_count(assumptions).await,
        2,
        "the ledger is the agent's record — the human supersede must not replace it"
    );
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
    let human = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "human".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
    human
        .execute(shipped_review_decision_declaration())
        .await
        .unwrap();

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
    let settled = body_text(get(&app, "/perf/app/console/frames/settled").await).await;
    assert!(
        settled.contains("/perf/app/console/p/views?view=dso\n"),
        "the link carries the dataset the app is mounted under:\n{settled}"
    );
    assert!(settled.contains("per order, not per line"), "{settled}");
    assert!(settled.contains("corrected"), "{settled}");
    let assumptions =
        body_text(get(&app, "/perf/app/console/frames/assumptions?view=dso").await).await;
    assert!(assumptions.contains("corrected"), "{assumptions}");

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
    let human = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "human".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
    human
        .execute(shipped_review_decision_declaration())
        .await
        .unwrap();

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
    let settled = body_text(get(&app, "/perf/app/console/frames/settled").await).await;
    assert!(
        settled.contains("/perf/app/console/p/views?view=dso\n"),
        "the link carries the dataset the app is mounted under:\n{settled}"
    );
    assert!(settled.contains("unclear"), "{settled}");
    assert!(settled.contains("which lines?"), "{settled}");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_tests_frame_serves_results_not_the_vocabulary() {
    // A test result is a TESTS row — a
    // detector's live result beside its test's expectation. A
    // test without a detector is an actor-kind gate; its annotated values
    // never render as tests (the old frame showed them with the
    // state column reading `current`).
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(
            r#"USE perf;
               DECLARE ASPECT meaning WITH $${"type": "object"}$$ AS FACT ON COLUMN;
               DECLARE TEST meaning_test ON meaning BY (AGENT, HUMAN);
               GLOSS meaning ON ledger.value AS $${"value": "the money"}$$;
               DECLARE FUNCTION fixed_check FOR GLOBAL AS
                 $$SELECT DISTINCT subject, 'orange' AS state, 0.42 AS score FROM annotations$$;
               DECLARE TEST dso_test ON dso DETECTOR fixed_check THRESHOLD 0.9;"#,
        )
        .await
        .unwrap();
    // The result computes at read — the detector's query answers over
    // the dso metric definition's value.

    let tests = get(&app, "/perf/app/console/frames/tests").await;
    let status = tests.status();
    if status != StatusCode::OK {
        let body = to_bytes(tests.into_body(), usize::MAX).await.unwrap();
        panic!("tests frame: {status} — {}", String::from_utf8_lossy(&body));
    }
    let tests = body_text(tests).await;
    assert_eq!(
        tests.matches("?test=dso_test\n").count(),
        1,
        "one row for the test with a scoring function, linked to its page; the test without one is not listed:\n{tests}"
    );

    // The test's own frames: how it scores (the function and the
    // threshold), then every result.
    let test = body_text(get(&app, "/perf/app/console/frames/test?test=dso_test").await).await;
    assert!(test.contains("fixed_check"), "{test}");
    assert!(test.contains("0.9"), "the threshold:\n{test}");
    let results =
        body_text(get(&app, "/perf/app/console/frames/test_results?test=dso_test").await).await;
    assert!(results.contains("the dataset\n"), "the asset:\n{results}");
    assert!(results.contains("orange\n"), "{results}");
    assert!(results.contains("0.42\n"), "the score:\n{results}");

    // A value test: the kit's detector over a value two actors
    // disagree on. Its results list every column with its
    // annotations, a person's first.
    agent
        .execute(
            r#"USE perf;
               DECLARE TEST value_test ON meaning BY (AGENT, HUMAN) DETECTOR value_entropy THRESHOLD 0.7;
               GLOSS meaning ON ledger.month AS $${"value": "the month"}$$;"#,
        )
        .await
        .unwrap();
    plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "ada".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(r#"USE perf; GLOSS meaning ON ledger.value AS $${"value": "the cash"}$$;"#)
        .await
        .unwrap();
    let values = body_text(
        get(
            &app,
            "/perf/app/console/frames/test_results?test=value_test",
        )
        .await,
    )
    .await;
    assert!(
        values.contains("ledger.value\n") && values.contains("ledger.month\n"),
        "one result per annotated column:\n{values}"
    );
    assert!(
        values.find("the cash").unwrap() < values.find("the money").unwrap(),
        "both values of the column that differs, the person's first:\n{values}"
    );
    let points = get(&app, "/perf/app/console/frames/test_points?test=value_test").await;
    assert_eq!(
        row_count(points).await,
        0,
        "a value test has no expected-range points"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn the_metric_frames_serve_the_series_its_slices_and_its_drivers() {
    // The views page end to end from the cube: nothing is
    // planted — the frames read `metric_series()` and `view_summary()`,
    // which build the cube from the metric definition and the judged results
    // the workspace carries. The measures list is the catalog, its numbers a
    // data frame joined in the browser by the metric's name; the
    // picker lists the admitted axis, a picked slice serves its
    // members, the trend carries the disclosed rival beside the chosen
    // reading, and the drivers rank member moves in SQL.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    let measures = get(&app, "/perf/app/console/frames/measures?stopped=0").await;
    assert_eq!(measures.status(), StatusCode::OK);
    let measures = body_text(measures).await;
    assert!(measures.contains("dso\n"), "{measures}");
    assert!(
        !measures.contains("cleaned\n") && !measures.contains("payables\n"),
        "three declared views, the series, the fact and the relation — the measures frame lists the series:\n{measures}"
    );

    // The views list: the relation with its link carrying the kind,
    // and neither the series nor the fact.
    let views = get(&app, "/perf/app/console/frames/views?stopped=0").await;
    assert_eq!(views.status(), StatusCode::OK);
    let views = body_text(views).await;
    assert!(views.contains("cleaned\n"), "{views}");
    assert!(views.contains("?view=cleaned&kind=relation\n"), "{views}");
    assert!(
        !views.contains("dso\n") && !views.contains("payables\n"),
        "{views}"
    );

    let latest = get(&app, "/perf/app/console/frames/latest").await;
    assert_eq!(latest.status(), StatusCode::OK);
    assert_eq!(
        row_count(latest).await,
        1,
        "the newest period of the one series; a fact has no period"
    );

    // The facts list: the fact with its one value, as of the load
    // of the table its metric definition reads, linked with its kind.
    let facts = get(&app, "/perf/app/console/frames/facts?stopped=0").await;
    assert_eq!(facts.status(), StatusCode::OK);
    let facts = body_text(facts).await;
    assert!(facts.contains("payables\n"), "{facts}");
    assert!(facts.contains("?view=payables&kind=scalar\n"), "{facts}");
    assert!(!facts.contains("dso\n"), "a series is not a fact:\n{facts}");

    // The fact's tile frame: a row for the fact, none for the series,
    // so the tile renders only where there is a number.
    let fact = get(&app, "/perf/app/console/frames/fact?view=payables").await;
    assert_eq!(fact.status(), StatusCode::OK);
    assert_eq!(row_count(fact).await, 1, "one row for the fact");
    let none = get(&app, "/perf/app/console/frames/fact?view=dso").await;
    assert_eq!(none.status(), StatusCode::OK);
    assert_eq!(row_count(none).await, 0, "a series is not a fact");

    let axes = get(&app, "/perf/app/console/frames/axes?view=dso").await;
    assert_eq!(axes.status(), StatusCode::OK);
    assert_eq!(row_count(axes).await, 1, "one fact row for the metric");

    let dims = get(
        &app,
        "/perf/app/console/frames/dims?view=dso&grain=month&span=24",
    )
    .await;
    assert_eq!(row_count(dims).await, 1, "cohort is the one admitted axis");

    let slices = get(
        &app,
        "/perf/app/console/frames/slices?view=dso&dim=cohort&grain=month&span=all",
    )
    .await;
    assert_eq!(
        row_count(slices).await,
        3,
        "two members over two months, one sparse: a member's gap stays a gap"
    );

    let trend = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=month&span=24",
    )
    .await;
    // The session engine serves the disclosed rival beside the chosen
    // reading; the DuckDB engine serves the chosen reading.
    let series = 1;
    assert_eq!(
        row_count(trend).await,
        2 * series,
        "the chosen reading{}, two months each",
        if series == 2 { " and the rival" } else { "" }
    );
    // The grain re-buckets on the server: both months fall in one
    // quarter, for the chosen reading and the rival alike.
    let quarter = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=quarter&span=24",
    )
    .await;
    assert_eq!(row_count(quarter).await, series, "one quarter");
    // The span clips the newest periods in the frame's SQL.
    let clipped = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=month&span=1",
    )
    .await;
    assert_eq!(row_count(clipped).await, series, "the newest month");

    let drivers = get(
        &app,
        "/perf/app/console/frames/drivers?view=dso&grain=month",
    )
    .await;
    assert_eq!(
        row_count(drivers).await,
        1,
        "cohort a moved between the two months; cohort b has one period"
    );

    // The axes banner is silent while the results stand at this data version.
    // On DuckDB the outlook kit's expected ranges and forecast are required from the
    // first metric definition: the banner counts them in one row, the re-measure
    // runs them, and with too short a history each stores its reasons
    // without a call.
    let preview = 1;
    let banner = get(&app, "/perf/app/console/frames/remeasure").await;
    assert_eq!(banner.status(), StatusCode::OK);
    assert_eq!(row_count(banner).await, preview, "nothing to re-measure");

    // A gloss moves the data version. The cube rebuilds at the next read with
    // the same numbers — and the results measured the data's columns,
    // which the gloss did not touch, so they still stand and the
    // banner stays silent: glossing work does not churn the catalog.
    plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(r#"USE perf; GLOSS definitions ON perf AS $${"definitions": {"dso": {"meaning": "receivables outstanding expressed in days of revenue", "unit": "days", "owner": "Finance", "source": "KPI handbook v3", "formula": "ar[end of w] / revenue[w] * days[w]"}}}$$;"#)
        .await
        .unwrap();
    let trend = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=month&span=24",
    )
    .await;
    assert_eq!(
        row_count(trend).await,
        2 * series,
        "the numbers stand after the gloss"
    );
    let banner = get(&app, "/perf/app/console/frames/remeasure").await;
    assert_eq!(
        row_count(banner).await,
        preview,
        "the results read the data, not this gloss"
    );

    // Re-measure — the console's second write, a compute act: with
    // nothing stale it stores nothing, and the response is still the
    // write event the browser's frame store hears.
    let response = app
        .clone()
        .oneshot(
            Request::post("/perf/app/console/remeasure")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    // The write names itself beside the write event: a re-measure can
    // change the cube, which a review decision cannot, so the store drops data
    // frames on the first and record frames on the second.
    assert_eq!(
        response.headers()["HX-Trigger"],
        "glossql:remeasured, glossql:written"
    );
    // The re-measure ran the expected ranges too: with no metric of seven whole
    // months it called no service and loaded its reasons, so nothing
    // stays open.
    let banner = get(&app, "/perf/app/console/frames/remeasure").await;
    assert_eq!(row_count(banner).await, 0, "the results still stand");
    let trend = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=month&span=24",
    )
    .await;
    assert_eq!(row_count(trend).await, 2 * series, "and the numbers stand");
}

/// The plan on DuckDB: a plan declared on dso over the same ledger,
/// read through the metric it plans (x-plan-of): the measures frame lists no
/// plan as a metric; the plan frame serves it period by period at its
/// own grain and at the year — two months loaded with their variance,
/// and the year loaded on those two of its twelve months, which the
/// row says, with no range read over part of a year; the trend carries
/// its cells as the plan world beside the reading.
#[tokio::test(flavor = "multi_thread")]
async fn the_plan_is_served_beside_its_metric() {
    let (app, plane, _dir) = workspace().await;
    plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(
            r#"USE perf;
               DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
               GLOSS dso ON perf AS $${"sql": "SELECT month, value, cohort FROM perf.ledger"}$$;
               GLOSS role ON dso.month AS $${"value": "timestamp"}$$;
               GLOSS role ON dso.value AS $${"value": "measure"}$$;
               GLOSS additivity ON dso.value AS $${"value": "additive"}$$;
               SELECT temporal() FROM dso.month;
               DECLARE ASPECT dso_budget WITH $${"title": "DSO budget", "x-kind": "plan", "x-plan-of": "dso"}$$ AS VIEW;
               GLOSS dso_budget ON perf AS $${"sql": "SELECT month, value * 2 AS value FROM perf.ledger"}$$;"#,
        )
        .await
        .unwrap();
    let measures = get(&app, "/perf/app/console/frames/measures?stopped=0").await;
    assert_eq!(row_count(measures).await, 1, "the plan is no metric");
    let plan = get(&app, "/perf/app/console/frames/plan?view=dso").await;
    assert_eq!(plan.status(), StatusCode::OK);
    let text = body_text(plan).await;
    assert!(text.contains("-12.5") && text.contains("2026"), "{text}");
    let plan = get(&app, "/perf/app/console/frames/plan?view=dso").await;
    assert_eq!(row_count(plan).await, 3, "two months and the year");
    let trend = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=month&span=24",
    )
    .await;
    assert_eq!(
        row_count(trend).await,
        4,
        "the reading and the plan, two months each"
    );
    let yearly = get(
        &app,
        "/perf/app/console/frames/trend?view=dso&grain=year&span=24",
    )
    .await;
    assert_eq!(
        row_count(yearly).await,
        2,
        "one year: the reading and the plan"
    );
}

/// The same list on DuckDB: no fact declared, an undated measure that
/// serves no series and says why in the axes value, and a metric whose
/// period column the server profiled with the definition, so its series
/// serves. The banner counts the preview measurements nobody ran, and
/// the console's re-measure runs them.
#[tokio::test(flavor = "multi_thread")]
async fn a_defined_metric_serves_its_series_and_a_remeasure_runs_the_preview_measurements() {
    let (app, plane, _dir) = workspace().await;
    plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(
            r#"USE perf;
               DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
               DECLARE ASPECT undated WITH $${"title": "Undated"}$$ AS VIEW;
               GLOSS dso ON perf AS $${"sql": "SELECT month, value, cohort FROM perf.ledger"}$$;
               GLOSS undated ON perf AS $${"sql": "SELECT sum(value) AS value FROM perf.ledger"}$$;
               GLOSS role ON dso.month AS $${"value": "timestamp"}$$;
               GLOSS role ON dso.value AS $${"value": "measure"}$$;
               GLOSS additivity ON dso.value AS $${"value": "additive"}$$;"#,
        )
        .await
        .unwrap();

    let facts = get(&app, "/perf/app/console/frames/facts?stopped=0").await;
    assert_eq!(facts.status(), StatusCode::OK);
    assert_eq!(row_count(facts).await, 0, "no fact declared, no fact row");
    let fact = get(&app, "/perf/app/console/frames/fact?view=dso").await;
    assert_eq!(row_count(fact).await, 0, "a series is not a fact");
    let fact = get(&app, "/perf/app/console/frames/fact?view=undated").await;
    assert_eq!(row_count(fact).await, 0, "an undeclared kind is not a fact");

    // The undated measure is listed beside the metric, though it
    // serves no series.
    let measures = get(&app, "/perf/app/console/frames/measures?stopped=0").await;
    assert_eq!(measures.status(), StatusCode::OK);
    let measures = body_text(measures).await;
    assert!(
        measures.contains("dso\n") && measures.contains("undated\n"),
        "{measures}"
    );

    // The server profiled `dso.month` after the write: the series serves.
    let latest = get(&app, "/perf/app/console/frames/latest").await;
    assert_eq!(row_count(latest).await, 1, "the one series' newest period");
    let banner = get(&app, "/perf/app/console/frames/remeasure").await;
    assert_eq!(banner.status(), StatusCode::OK);
    let banner = body_text(banner).await;
    // The outlook kit's expected ranges, forecast and estimate wait for a run.
    for function in ["metric_ranges", "metric_forecast", "metric_scenario"] {
        assert!(banner.contains(function), "{function}: {banner}");
    }
    assert!(!banner.contains("temporal"), "{banner}");
    let response = app
        .clone()
        .oneshot(
            Request::post("/perf/app/console/remeasure")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    let banner = get(&app, "/perf/app/console/frames/remeasure").await;
    assert_eq!(
        row_count(banner).await,
        0,
        "the expected ranges and the forecast stored their reasons"
    );
    let latest = get(&app, "/perf/app/console/frames/latest").await;
    assert_eq!(row_count(latest).await, 1, "the one series' newest period");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_root_lists_every_dataset_at_a_glance() {
    // The workspace root: each dataset with what loaded, what is served
    // and what waits on a person, the apps with the datasets they
    // serve, the interfaces, the connect line — every number the catalog's.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    let root = get(&app, "/").await;
    assert_eq!(root.status(), StatusCode::OK);
    let root = text(root).await;
    assert!(root.contains("app interface test"), "the purpose:\n{root}");
    // The second dataset, empty, still lists with its own way in.
    assert!(root.contains("multi-dataset guard"), "{root}");
    let links = hrefs(&root);
    let links = |path: &str| links.iter().any(|l| l == path);
    assert!(links("/second/app"), "{root}");
    // The built-in serves every dataset; a glossed app is served
    // where it was glossed and nowhere else.
    assert!(links("/perf/app/console"), "{root}");
    assert!(links("/second/app/console"), "{root}");
    assert!(links("/perf/app/board"), "{root}");
    assert!(!links("/second/app/board"), "{root}");
    // The connect line names the server as it was told it is reached,
    // whatever host the request claimed. The template escapes the
    // scheme's slashes, so the host is the tell.
    assert!(root.contains("glossql.example"), "{root}");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_export_tab_lists_tables_and_reads() {
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    // The page's curl line names this dataset's query interface.
    let page = text(get(&app, "/perf/app/console/p/export").await).await;
    assert!(page.contains("/perf/query"), "{page}");

    // The loaded table with its shape and its two files.
    let tables = body_text(get(&app, "/perf/app/console/frames/tables").await).await;
    assert!(tables.contains("ledger\n"), "{tables}");
    assert!(tables.contains("\n3\n"), "{tables}");
    assert!(tables.contains("/perf/app/export/ledger.csv\n"), "{tables}");
    assert!(
        tables.contains("/perf/app/export/ledger.parquet\n"),
        "{tables}"
    );

    // The served reads as their relations, with the definition's
    // meaning beside them, the kind as the chip, and the files.
    let reads = body_text(get(&app, "/perf/app/console/frames/reads?stopped=0").await).await;
    let relation = |name: &str| format!("\n{name}\n");
    assert!(reads.contains(&relation("dso")), "{reads}");
    assert!(reads.contains("receivables outstanding"), "{reads}");
    assert!(reads.contains("metric\n"), "{reads}");
    assert!(reads.contains("/perf/app/export/read.dso.csv\n"), "{reads}");
    assert!(reads.contains(&relation("payables")), "{reads}");

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
    let session = plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "t".into(),
            },
            Some("perf"),
        )
        .await
        .unwrap();
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

#[tokio::test(flavor = "multi_thread")]
async fn lineage_serves_tables_with_their_source_relationships_and_reads() {
    // The lineage's frames are the catalog as rows: every column of
    // every loaded table with the source it is loaded from, the
    // declared relationships, and for every view the columns its
    // served fields descend from.
    let (app, plane, dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(&format!(
            "USE perf;\n\
             DECLARE SOURCE erp2 SET (type: csv, location: '{}');\n\
             DECLARE RECIPE cohorts ON perf FROM erp2 AS $$\
               SELECT DISTINCT cohort FROM read_csv('ledger.csv')$$;\n\
             DECLARE RELATIONSHIP ledger.cohort -> cohorts.cohort;",
            dir.path().display()
        ))
        .await
        .unwrap();

    // Nodes: the two tables' columns in order, and the metric definition's
    // served fields under the metric; a metric definition with only an
    // aggregate (payables) has no field to show.
    let nodes = get(&app, "/perf/app/console/frames/lineage_nodes").await;
    assert_eq!(nodes.status(), StatusCode::OK);
    let bytes = to_bytes(nodes.into_body(), usize::MAX).await.unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    let mut rows: Vec<(String, String, String, String)> = Vec::new();
    for batch in reader {
        let batch = batch.unwrap();
        let col = |name: &str| {
            batch
                .column(batch.schema().index_of(name).unwrap())
                .as_any()
                .downcast_ref::<arrow::array::StringArray>()
                .unwrap()
                .clone()
        };
        let (node, kind, c, role) = (col("node"), col("kind"), col("col"), col("tag"));
        for i in 0..batch.num_rows() {
            rows.push((
                node.value(i).into(),
                kind.value(i).into(),
                c.value(i).into(),
                role.value(i).into(),
            ));
        }
    }
    let has = |node: &str, col: &str| rows.iter().any(|r| r.0 == node && r.2 == col);
    assert!(has("ledger", "month"), "{rows:?}");
    assert!(has("ledger", "cohort"), "{rows:?}");
    assert!(has("ledger", "value"), "{rows:?}");
    assert!(has("cohorts", "cohort"), "{rows:?}");
    assert!(
        rows.iter().any(|r| r.0 == "cohorts" && r.3 == "erp2"),
        "a table names its source:\n{rows:?}"
    );
    assert!(has("dso", "month"), "{rows:?}");
    assert!(has("dso", "cohort"), "{rows:?}");
    assert!(
        !rows.iter().any(|r| r.0 == "payables"),
        "an aggregate descends from no column:\n{rows:?}"
    );
    assert!(
        rows.iter().any(|r| r.0 == "dso" && r.1 == "view"),
        "{rows:?}"
    );
    // The format's metadata tables sit beside every loaded one in
    // information_schema; the catalog's tables are the nodes.
    assert!(
        !rows.iter().any(|r| r.0.contains('$')),
        "a metadata table leaked into the nodes:\n{rows:?}"
    );

    // The edges: the declared relationships and the view's reads.
    let edges = get(&app, "/perf/app/console/frames/lineage_edges").await;
    assert_eq!(edges.status(), StatusCode::OK);
    let bytes = to_bytes(edges.into_body(), usize::MAX).await.unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    let mut edges: Vec<(String, String, String)> = Vec::new();
    for batch in reader {
        let batch = batch.unwrap();
        let col = |name: &str| {
            batch
                .column(batch.schema().index_of(name).unwrap())
                .as_any()
                .downcast_ref::<arrow::array::StringArray>()
                .unwrap()
                .clone()
        };
        let (src, dst, kind) = (col("src"), col("dst"), col("kind"));
        for i in 0..batch.num_rows() {
            edges.push((
                src.value(i).into(),
                dst.value(i).into(),
                kind.value(i).into(),
            ));
        }
    }
    assert!(
        edges.contains(&(
            "ledger.cohort".into(),
            "cohorts.cohort".into(),
            "m2o".into()
        )),
        "{edges:?}"
    );
    assert!(
        edges.contains(&("ledger.month".into(), "dso.month".into(), "reads".into())),
        "{edges:?}"
    );
    assert!(
        edges.contains(&("ledger.value".into(), "dso.value".into(), "reads".into())),
        "{edges:?}"
    );
    assert_eq!(
        edges.iter().filter(|e| e.2 == "reads").count(),
        6,
        "the series and the relation each read three columns:\n{edges:?}"
    );
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

#[tokio::test(flavor = "multi_thread")]
async fn a_stopped_view_folds_under_the_lists() {
    // A metric definition its author stopped serves no number and no file;
    // it stays on record with the reason. The lists serve the
    // served views, and the fold under each the stopped ones —
    // the same frame, `stopped` picking the side.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(
            r#"USE perf;
               DECLARE ASPECT old_dso WITH $${"title": "Old DSO", "x-kind": "metric"}$$ AS VIEW;
               GLOSS old_dso ON perf AS $${"stopped": "superseded by dso, which reads the cohort"}$$;"#,
        )
        .await
        .unwrap();

    let served = body_text(get(&app, "/perf/app/console/frames/measures?stopped=0").await).await;
    assert!(served.contains("dso\n"), "{served}");
    assert!(
        !served.contains("old_dso"),
        "a stopped metric is not between the served:\n{served}"
    );
    let stopped = body_text(get(&app, "/perf/app/console/frames/measures?stopped=1").await).await;
    assert!(stopped.contains("old_dso\n"), "{stopped}");
    assert!(
        stopped.contains("superseded by dso, which reads the cohort\n"),
        "the author's reason in place of the axes:\n{stopped}"
    );
    assert!(
        !stopped.contains("\ndso\n"),
        "the served metric is not in the fold:\n{stopped}"
    );

    let reads = body_text(get(&app, "/perf/app/console/frames/reads?stopped=1").await).await;
    let relation = |name: &str| format!("\n{name}\n");
    assert!(reads.contains(&relation("old_dso")), "{reads}");
    assert!(!reads.contains(&relation("dso")), "{reads}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_table_view_serves_its_columns_and_the_tables_it_reads() {
    // A table view is rows, not a series: its frames list every column
    // the catalog holds under its name with the column each descends
    // from, and name the tables it reads.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;

    let fields =
        body_text(get(&app, "/perf/app/console/frames/view_fields?view=cleaned").await).await;
    assert!(
        fields.contains("month\namount\ncohort\n"),
        "every served column in the view's order:\n{fields}"
    );
    assert!(
        fields.contains("ledger.value\n"),
        "the column a renamed field descends from:\n{fields}"
    );
    let tables =
        body_text(get(&app, "/perf/app/console/frames/view_tables?view=cleaned").await).await;
    assert_eq!(tables, "ledger\n", "the one table the view reads");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_catalog_frames_serve_the_vocabulary_the_terms_the_relations_and_the_sources() {
    // The catalog's frames: the vocabulary — every declared aspect by
    // kind, the app's own apart — then the terms (every metric, view
    // and fact with its agreed meaning, and every column whose meaning
    // names a term, a person's word over an agent's), the relations to
    // query, each a link that puts the read in the page URL, the
    // tables with their columns, and the sources.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(
            r#"USE perf;
               GLOSS role ON ledger.value AS $${"value": "measure"}$$;
               GLOSS meaning ON ledger.value AS $${"value": "the money", "term": "Booked value"}$$;"#,
        )
        .await
        .unwrap();
    plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "ada".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(r#"USE perf; GLOSS meaning ON ledger.value AS $${"value": "the cash", "term": "Booked value"}$$;"#)
        .await
        .unwrap();

    // The vocabulary, by kind: a fact aspect with its enum, its grain,
    // the required assets with a value and who may annotate; a metric definition; a
    // measurement with the function that stored it; the app's own
    // folded apart.
    let facts = body_text(get(&app, "/perf/app/console/frames/vocabulary?kind=fact").await).await;
    assert!(facts.contains("role\n"), "{facts}");
    assert!(facts.contains("?aspect=role\n"), "{facts}");
    assert!(
        !facts.contains("app_frame"),
        "the app's own fold apart:\n{facts}"
    );
    let own = body_text(get(&app, "/perf/app/console/frames/vocabulary?kind=own").await).await;
    assert!(own.contains("app_frame\n"), "{own}");
    let queries = body_text(get(&app, "/perf/app/console/frames/vocabulary?kind=view").await).await;
    assert!(queries.contains("dso\n"), "{queries}");
    let measurements =
        body_text(get(&app, "/perf/app/console/frames/vocabulary?kind=measurement").await).await;
    assert!(
        measurements.contains("temporal_profile\n"),
        "{measurements}"
    );
    // The function that stored the profile: the quality kit's.
    let lands = "temporal\n";
    assert!(
        measurements.contains(lands),
        "the function that lands it:\n{measurements}"
    );

    // The terms: the views first by alphabet with the column's term
    // among them; the person's word wins and is marked, the when on
    // hover.
    let terms = body_text(get(&app, "/perf/app/console/frames/terms").await).await;
    assert!(terms.contains("Booked value\n"), "{terms}");
    assert!(
        terms.contains("the cash\n"),
        "the person's word over the agent's:\n{terms}"
    );
    assert!(!terms.contains("the money\n"), "{terms}");
    assert!(terms.contains("v-decided\n"), "{terms}");
    assert!(
        terms.contains("/perf/app/console/p/glossary?column=ledger.value\n"),
        "a term opens its column:\n{terms}"
    );
    assert!(
        terms.contains("/perf/app/console/p/views?view=cleaned&kind=relation\n"),
        "a view's page, under the dataset:\n{terms}"
    );
    assert!(!terms.contains("\nplan\n"), "a plan is no term:\n{terms}");

    let relations = get(&app, "/perf/app/console/frames/relations").await;
    assert_eq!(relations.status(), StatusCode::OK);
    let relations = body_text(relations).await;
    // Column by column: the tables first, then the views, then the
    // metrics; the fact serves no rows to browse and is listed too.
    assert!(
        relations.contains("ledger\ncleaned\ndso\n"),
        "the loaded table, the view, the metric:\n{relations}"
    );
    assert!(
        relations.contains("table\nview\n"),
        "each named by its kind:\n{relations}"
    );
    assert!(
        relations.contains("?sql=SELECT * FROM ledger LIMIT 50\n"),
        "the pick is a read in the URL:\n{relations}"
    );

    // The tables: one row per loaded table, its columns as lines, the
    // name opening the table's page.
    let columns = body_text(get(&app, "/perf/app/console/frames/columns").await).await;
    assert!(columns.contains("ledger\n"), "the loaded table:\n{columns}");
    assert!(
        columns.contains("month") && columns.contains("measure"),
        "every column of it as a line, the judged role on one:\n{columns}"
    );
    assert!(columns.contains("?table=ledger\n"), "{columns}");

    let conventions = get(&app, "/perf/app/console/frames/conventions").await;
    assert_eq!(conventions.status(), StatusCode::OK);
    let conventions = body_text(conventions).await;
    assert!(
        conventions.contains("erp\n"),
        "the recipe's source is listed:\n{conventions}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn the_frames_of_a_table_a_column_and_an_aspect_serve_their_values() {
    // A table with its entity, its columns in order with the winning
    // value on each, and its load; a column with every value on it, the
    // outranked one on record; an aspect with its declaration and every
    // value under it, the required subjects without one by name.
    let (app, plane, _dir) = workspace().await;
    seed_model_shapes(&plane).await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(
            r#"USE perf;
               GLOSS entity ON ledger AS $${"value": "one ledger line", "role": "fact", "grain": ["month", "cohort"], "time_axis": "month"}$$;
               GLOSS meaning ON ledger.value AS $${"value": "the money"}$$;"#,
        )
        .await
        .unwrap();
    plane
        .channel(
            Actor {
                kind: ActorKind::Human,
                id: "ada".into(),
            },
            None,
        )
        .await
        .unwrap()
        .execute(r#"USE perf; GLOSS meaning ON ledger.value AS $${"value": "the cash"}$$;"#)
        .await
        .unwrap();

    // The table.
    let head = body_text(get(&app, "/perf/app/console/frames/table_head?table=ledger").await).await;
    assert!(head.contains("one ledger line\n"), "{head}");
    let cols =
        body_text(get(&app, "/perf/app/console/frames/table_columns?table=ledger").await).await;
    assert!(
        cols.starts_with("month\ncohort\nvalue\n"),
        "the columns in order:\n{cols}"
    );
    assert!(
        cols.contains("the cash\n"),
        "the person's meaning wins:\n{cols}"
    );
    assert!(cols.contains("v-decided\n"), "{cols}");
    assert!(cols.contains("month\n"), "{cols}");
    assert!(cols.contains("?column=ledger.value\n"), "{cols}");
    let loads =
        body_text(get(&app, "/perf/app/console/frames/table_loads?table=ledger").await).await;
    // The load names the source.
    assert!(loads.contains("erp"), "{loads}");
    assert!(
        loads.contains("read_csv('ledger.csv')"),
        "the recipe's SQL:\n{loads}"
    );

    // The column: every value, the outranked one on record.
    let head = body_text(
        get(
            &app,
            "/perf/app/console/frames/column_head?column=ledger.value",
        )
        .await,
    )
    .await;
    assert!(head.starts_with("ledger\nvalue\n"), "{head}");
    assert!(head.contains("the cash\n"), "{head}");
    assert!(head.contains("?table=ledger\n"), "{head}");
    let values = body_text(
        get(
            &app,
            "/perf/app/console/frames/column_values?column=ledger.value",
        )
        .await,
    )
    .await;
    // Both values on the meaning, the person's first; the kit's test
    // requires the role on every column, and the unfilled role value leads
    // the list.
    let lead = "role\nmeaning\nmeaning\n";
    assert!(
        values.starts_with(lead),
        "both annotations on the meaning, the person's first:\n{values}"
    );
    assert!(values.contains("the cash\nthe money\n"), "{values}");
    assert!(values.contains("ada"), "the writer's name:\n{values}");

    // The aspect: the declaration, then every value and every
    // required subject by name.
    let head =
        body_text(get(&app, "/perf/app/console/frames/aspect_head?aspect=meaning").await).await;
    assert!(head.starts_with("meaning\n"), "{head}");
    assert!(head.contains("meaning_test"), "{head}");
    let values = body_text(
        get(
            &app,
            "/perf/app/console/frames/aspect_values?aspect=meaning",
        )
        .await,
    )
    .await;
    assert!(
        values.starts_with("ledger.value\n"),
        "annotated first, then missing by name:\n{values}"
    );
    assert!(values.contains("ledger.cohort\nledger.month\n"), "{values}");
    assert!(values.contains("the cash\n"), "{values}");
    assert!(values.contains("?column=ledger.cohort\n"), "{values}");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_tree_links_the_catalogs_objects_and_the_pages_the_bar_does_not() {
    // The console's tree: one row per entry, each with the page it
    // opens — the source, the table and its columns, and the pages
    // that have no tab in the bar.
    let (app, _plane, _dir) = workspace().await;
    let tree = body_text(get(&app, "/perf/app/console/frames/tree").await).await;
    for line in [
        "/perf/app/console/p/glossary?source=erp\n",
        "/perf/app/console/p/glossary?table=ledger\n",
        "/perf/app/console/p/glossary?column=ledger.value\n",
        "/perf/app/console/p/history\n",
        "/perf/app/console/p/lineage\n",
        "/perf/app/console/p/review#decisions\n",
        "/perf/app/console/p/query\n",
    ] {
        assert!(tree.contains(line), "{line:?} in the tree:\n{tree}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_bar_shows_the_five_functions_and_an_object_marks_its_own() {
    let (app, _plane, _dir) = workspace().await;
    let index = text(get(&app, "/perf/app/console").await).await;
    // The overview, the five functions (integration, metadata, quality,
    // governance, lineage) and the data. The history and query pages
    // are reached from the left nav.
    assert_eq!(
        hrefs(bar(&index)),
        [
            "/perf/app/console",
            "/perf/app/console/p/views",
            "/perf/app/console/p/glossary",
            "/perf/app/console/p/quality",
            "/perf/app/console/p/review",
            "/perf/app/console/p/lineage",
            "/perf/app/console/p/export",
        ],
        "{index}"
    );
    // A page marks the section that owns it.
    for (url, section) in [
        ("/perf/app/console/p/history", "/perf/app/console"),
        ("/perf/app/console/p/lineage", "/perf/app/console/p/lineage"),
        (
            "/perf/app/console/p/glossary?table=ledger",
            "/perf/app/console/p/glossary",
        ),
        (
            "/perf/app/console/p/glossary?column=ledger.value",
            "/perf/app/console/p/glossary",
        ),
        (
            "/perf/app/console/p/glossary?source=erp",
            "/perf/app/console/p/glossary",
        ),
        (
            "/perf/app/console/p/views?view=x&kind=scalar",
            "/perf/app/console/p/views",
        ),
        (
            "/perf/app/console/p/views?view=x&kind=relation",
            "/perf/app/console/p/views",
        ),
        (
            "/perf/app/console/p/views?view=x",
            "/perf/app/console/p/views",
        ),
        ("/perf/app/console/p/quality", "/perf/app/console/p/quality"),
        (
            "/perf/app/console/p/quality?test=role_test",
            "/perf/app/console/p/quality",
        ),
        ("/perf/app/console/p/query", "/perf/app/console/p/export"),
    ] {
        let page = text(get(&app, url).await).await;
        assert_eq!(current_tab(&page), section, "{url}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_source_has_its_three_tabs_and_serves_its_load_queries_and_loads() {
    let (app, _plane, _dir) = workspace().await;
    let page = text(get(&app, "/perf/app/console/p/glossary?source=erp").await).await;
    let links = hrefs(&page);
    for tab in [
        "?source=erp",
        "?source=erp&tab=used",
        "?source=erp&tab=history",
    ] {
        assert!(links.iter().any(|l| l == tab), "{tab}:\n{page}");
    }
    let recipes =
        body_text(get(&app, "/perf/app/console/frames/source_recipes?source=erp").await).await;
    assert!(
        recipes.contains("ledger\n"),
        "the source loads ledger:\n{recipes}"
    );
    let loads =
        body_text(get(&app, "/perf/app/console/frames/source_loads?source=erp").await).await;
    assert!(
        loads.contains("ledger\n"),
        "ledger was loaded from it:\n{loads}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn the_graph_serves_each_table_as_its_entity() {
    // The graph's table nodes: each table with what one row is under its
    // name, and each column with what it carries — role, additivity,
    // unit, the grain, the time axis.
    let (app, plane, _dir) = workspace().await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(
            r#"USE perf;
               GLOSS entity ON ledger AS $${"value": "one booking", "role": "fact", "grain": ["month", "cohort"], "time_axis": "month"}$$;
               GLOSS role ON ledger.value AS $${"value": "measure"}$$;
               GLOSS additivity ON ledger.value AS $${"value": "additive"}$$;
               GLOSS unit ON ledger.value AS $${"value": "EUR"}$$;"#,
        )
        .await
        .unwrap();
    let nodes = body_text(get(&app, "/perf/app/console/frames/lineage_nodes").await).await;
    for line in [
        "one booking\n",
        "measure",
        "additive",
        "EUR",
        "/perf/app/console/p/glossary?table=ledger\n",
    ] {
        assert!(nodes.contains(line), "{line:?} in the nodes:\n{nodes}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_history_lists_loads_annotations_and_declarations_newest_first() {
    let (app, plane, _dir) = workspace().await;
    let agent = plane
        .channel(
            Actor {
                kind: ActorKind::Agent,
                id: "builder".into(),
            },
            None,
        )
        .await
        .unwrap();
    agent
        .execute(r#"USE perf; GLOSS meaning ON ledger.value AS $${"value": "the money"}$$;"#)
        .await
        .unwrap();
    let all = body_text(get(&app, "/perf/app/console/frames/history?kind=&object=").await).await;
    for line in ["load\n", "annotation\n", "declaration\n", "the money\n"] {
        assert!(all.contains(line), "{line:?} in the history:\n{all}");
    }
    // The newest first: the annotation on the column was written after
    // the table's load query and its load.
    assert!(
        all.find("/perf/app/console/p/glossary?column=ledger.value\n")
            .unwrap()
            < all
                .find("/perf/app/console/p/glossary?table=ledger\n")
                .unwrap(),
        "{all}"
    );
    // Filters narrow by kind and by object; a table includes its columns.
    let loads =
        body_text(get(&app, "/perf/app/console/frames/history?kind=load&object=").await).await;
    assert!(
        loads.contains("load\n") && !loads.contains("annotation\n"),
        "{loads}"
    );
    let ledger = body_text(
        get(
            &app,
            "/perf/app/console/frames/history?kind=annotation&object=ledger",
        )
        .await,
    )
    .await;
    assert!(ledger.contains("ledger.value\n"), "{ledger}");
}
