//! The routes on the DuckDB engine: `next` answers from the record, one
//! act per goal, read through the bound agent door; a goal's act is a
//! statement the record filled, and the `next://` page carries the
//! forms.

use std::sync::Arc;

use axum::Router;
use axum::body::{Body, to_bytes};
use axum::http::{Request, Response, StatusCode, header};
use glossdb_serverd::{Access, DoorConfig, router};
use serde_json::{Value, json};
use tower::ServiceExt;

use crate::common;

async fn app() -> (Router, tempfile::TempDir) {
    let (dir, plane) = common::scratch_plane().await;
    let plane = Arc::new(
        plane.with_pages(
            glossdb_serverd::skills::door_pages()
                .expect("the language's documents beside the extension's kits"),
        ),
    );
    (
        router(plane, DoorConfig::default(), Access::Gated(common::login())),
        dir,
    )
}

fn meta() -> Value {
    json!({
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "routes-test", "version": "0"}
    })
}

fn call(id: u64, statements: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
           "params": {"_meta": meta(), "name": "glossql", "arguments": {"statements": statements}}})
}

async fn mcp_on(app: Router, path: &str, payload: Value) -> Response<Body> {
    let method = payload["method"].as_str().unwrap().to_string();
    let mut request = Request::post(path)
        .header(header::HOST, "127.0.0.1")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header(header::AUTHORIZATION, common::bearer("dev-agent"))
        .header("mcp-protocol-version", "2026-07-28")
        .header("mcp-method", method);
    if let Some(name) = payload["params"]["name"]
        .as_str()
        .or_else(|| payload["params"]["uri"].as_str())
    {
        request = request.header("mcp-name", name.to_string());
    }
    app.oneshot(request.body(Body::from(payload.to_string())).unwrap())
        .await
        .unwrap()
}

async fn expect_ok(response: Response<Body>) -> Value {
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let text = String::from_utf8_lossy(&bytes);
    assert_eq!(status, StatusCode::OK, "{text}");
    serde_json::from_str(&text).unwrap()
}

/// Statements on the dataset's door; the outcomes, and a panic on a refusal.
async fn say(app: &Router, statements: &str) -> Value {
    let body = expect_ok(mcp_on(app.clone(), "/fin/mcp", call(1, statements)).await).await;
    assert_ne!(
        body["result"]["isError"],
        json!(true),
        "`{statements}`: {body}"
    );
    let text = body["result"]["content"][0]["text"].as_str().unwrap();
    serde_json::from_str(text).unwrap()
}

/// A refused statement's text on the dataset's door.
async fn refused(app: &Router, statements: &str) -> String {
    let body = expect_ok(mcp_on(app.clone(), "/fin/mcp", call(1, statements)).await).await;
    assert_eq!(
        body["result"]["isError"],
        json!(true),
        "`{statements}` was not refused: {body}"
    );
    body["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

/// The rows of one read on the dataset's door.
async fn rows(app: &Router, sql: &str) -> Vec<Value> {
    let outcomes = say(app, sql).await;
    outcomes[0]["rows"].as_array().cloned().unwrap_or_default()
}

/// One goal's row of `next`, by surface.
async fn goal(app: &Router, surface: &str) -> Value {
    let all = rows(app, "SELECT * FROM next ORDER BY goal").await;
    all.into_iter()
        .find(|r| r["surface"] == json!(surface))
        .unwrap_or_else(|| panic!("no {surface} goal"))
}

fn text(row: &Value, key: &str) -> String {
    row[key].as_str().unwrap_or_default().to_string()
}

/// A workspace with the dataset `fin` and a daily ledger landed.
async fn fin() -> (Router, tempfile::TempDir) {
    let (app, dir) = app().await;
    let body = expect_ok(
        mcp_on(
            app.clone(),
            "/mcp",
            call(0, "DECLARE DATASET fin SET (purpose: 'the routes');"),
        )
        .await,
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    say(
        &app,
        "CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked, \
         (i % 7 + 1)::DOUBLE AS amount, ['general', 'water', 'parks'][i % 3 + 1] AS fund \
         FROM range(120) r(i)",
    )
    .await;
    (app, dir)
}

#[tokio::test(flavor = "multi_thread")]
async fn a_fresh_dataset_routes_every_goal() {
    let (app, _dir) = fin().await;
    let all = rows(&app, "SELECT * FROM next ORDER BY goal").await;
    let surfaces: Vec<String> = all.iter().map(|r| text(r, "surface")).collect();
    assert_eq!(
        surfaces,
        [
            "structure",
            "metrics",
            "slices",
            "bands",
            "checks",
            "app",
            "plan",
            "rulings"
        ],
        "{all:?}"
    );
    let state = |surface: &str| {
        all.iter()
            .find(|r| r["surface"] == json!(surface))
            .map(|r| text(r, "state"))
            .unwrap_or_default()
    };
    // The table came by SQL, not by a recipe: the structure goal still
    // asks for the source the files come from.
    assert_eq!(state("structure"), "next");
    assert_eq!(
        text(&goal(&app, "structure").await, "act"),
        "DECLARE SOURCE"
    );
    let metrics = goal(&app, "metrics").await;
    assert_eq!(text(&metrics, "state"), "next");
    assert_eq!(text(&metrics, "say"), "declare the first concept");
    assert_eq!(state("slices"), "blocked");
    assert_eq!(state("app"), "blocked");
    assert_eq!(state("rulings"), "done");
    // The bands and plan goals are the futures kit's: blocked while no
    // metric is applicable.
    for surface in ["bands", "plan"] {
        let row = goal(&app, surface).await;
        assert_eq!(text(&row, "state"), "blocked", "{row}");
        assert_eq!(text(&row, "why"), "no applicable metric stands", "{row}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_metric_walks_from_its_claim_to_its_behaviour() {
    let (app, _dir) = fin().await;

    // Declared and claimed by nobody: the claim is the act.
    say(
        &app,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS QUERY;"#,
    )
    .await;
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "say"), "claim spend for fin", "{row}");
    assert!(
        text(&row, "statement").starts_with("GLOSS definitions ON fin"),
        "{row}"
    );

    // Claimed and not grounded: the grounding, or a stop.
    say(&app, r#"GLOSS definitions ON fin AS $${"definitions": {"spend": {"unit": "EUR", "meaning": "what was booked"}}}$$;"#).await;
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "say"), "ground spend, or stop it", "{row}");
    assert!(text(&row, "statement").contains("\"stopped\""), "{row}");

    // Grounded: the write answers with the metric's row, and the
    // view's columns owe their roles.
    let outcomes = say(
        &app,
        r#"GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
    )
    .await;
    let written = &outcomes[0]["rows"][0];
    assert_eq!(written["metric"], json!("spend"), "{outcomes}");
    assert_eq!(written["applicable"], json!(false), "{outcomes}");
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "say"), "gloss the columns of spend", "{row}");
    assert!(
        text(&row, "statement").contains("GLOSS role ON fin.spend.period"),
        "{row}"
    );
    assert_eq!(text(&goal(&app, "slices").await, "state"), "blocked");

    // The roles stand and no cadence does: the profile is the act.
    say(
        &app,
        r#"GLOSS role ON spend.period AS $${"value": "timestamp"}$$;
           GLOSS role ON spend.value AS $${"value": "measure"}$$;
           GLOSS role ON spend.fund AS $${"value": "dimension"}$$;"#,
    )
    .await;
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "say"), "profile period of spend", "{row}");
    assert_eq!(
        text(&row, "statement"),
        "SELECT temporal() FROM fin.spend.period",
        "{row}"
    );

    // Profiled: the metric is applicable, and the behaviour is the act —
    // the view serves a row per fund in each period, so the series
    // refuses to combine them until it is said; the slice wants its rank.
    say(&app, "SELECT temporal() FROM fin.spend.period;").await;
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "say"), "say how spend combines", "{row}");
    assert!(
        text(&row, "statement").contains("GLOSS behavior ON fin.spend.value"),
        "{row}"
    );
    let refusal = refused(
        &app,
        "SELECT period, value FROM metric_series() WHERE metric = 'spend'",
    )
    .await;
    assert!(
        refusal.contains("no behaviour stands on fin.spend.value"),
        "{refusal}"
    );
    assert!(
        refusal.contains("GLOSS behavior ON fin.spend.value"),
        "{refusal}"
    );
    let slices = goal(&app, "slices").await;
    assert_eq!(text(&slices, "say"), "rank fund on spend", "{slices}");
    assert_eq!(
        text(&goal(&app, "app").await, "say"),
        "write the first page over 1 metric"
    );

    // Said: the series serves at its floor and coarser, the metrics
    // goal is done, the slices goal once the rank stands.
    say(
        &app,
        r#"GLOSS behavior ON spend.value AS $${"value": "flow"}$$;"#,
    )
    .await;
    let cells = rows(&app, "SELECT period, value FROM metric_series() WHERE metric = 'spend' AND dimension = '' ORDER BY period").await;
    assert_eq!(cells.len(), 4, "{cells:?}");
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "state"), "done", "{row}");
    assert!(text(&row, "why").contains("served or stopped"), "{row}");
    let quarters = rows(&app, "SELECT period, value FROM metric_series(grain := 'quarter') WHERE metric = 'spend' AND dimension = '' ORDER BY period").await;
    assert_eq!(quarters.len(), 2, "{quarters:?}");
    say(
        &app,
        r#"GLOSS dimension ON spend.fund AS $${"value": "primary"}$$;"#,
    )
    .await;
    assert_eq!(text(&goal(&app, "slices").await, "state"), "done");

    // A stop ends the view and holds no goal.
    say(
        &app,
        r#"GLOSS spend ON fin AS $${"stopped": "the ledger is not booked before 2024"}$$;"#,
    )
    .await;
    let row = goal(&app, "metrics").await;
    assert_eq!(text(&row, "state"), "done", "{row}");
    assert_eq!(text(&goal(&app, "app").await, "state"), "blocked");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_next_page_carries_the_forms() {
    let (app, _dir) = fin().await;
    say(
        &app,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS QUERY;"#,
    )
    .await;
    let body = expect_ok(
        mcp_on(
            app.clone(),
            "/fin/mcp",
            json!({"jsonrpc": "2.0", "id": 5, "method": "resources/read",
                   "params": {"_meta": meta(), "uri": "next://fin/metrics"}}),
        )
        .await,
    )
    .await;
    let page = body["result"]["contents"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("{body}"));
    assert!(page.starts_with("# next on fin"), "{page}");
    assert!(page.contains("## metrics: next"), "{page}");
    assert!(page.contains("claim spend for fin"), "{page}");
    assert!(page.contains("GLOSS definitions ON fin"), "{page}");
    assert!(!page.contains("```glossql\n\n```"), "no empty form: {page}");

    // Every result on the dataset's door closes with the line.
    let body = expect_ok(mcp_on(app.clone(), "/fin/mcp", call(6, "SELECT 1 AS one")).await).await;
    let window = body["result"]["content"][1]["text"].as_str().unwrap();
    assert!(window.contains("next:"), "{window}");
    assert!(
        window.contains("metrics → claim spend for fin (next://fin/metrics)"),
        "{window}"
    );
}
