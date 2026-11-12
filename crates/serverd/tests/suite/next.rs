//! `next`, the work list of a dataset, read through the agent
//! interface: what is open, each row labelled with its kind of work
//! (the `step` column: integrate, describe, test, review), with its
//! asset, its state and the statement that opens the work. The tests
//! check kind, asset and state, and that a row's statement names the
//! asset and the property of the fixture.

use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::Response;
use glossdb_serverd::{Access, InterfaceConfig, router};
use serde_json::{Value, json};

use crate::common::{self, expect_ok, meta};

async fn app() -> (Router, tempfile::TempDir) {
    let (dir, plane) = common::scratch_plane().await;
    let plane = Arc::new(
        plane.with_pages(
            glossdb_serverd::skills::served_pages()
                .expect("the language's documents beside the extension's kits"),
        ),
    );
    (
        router(
            plane,
            InterfaceConfig::default(),
            Access::Gated(common::login()),
        ),
        dir,
    )
}

fn call(id: u64, statements: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
           "params": {"_meta": meta(), "name": "glossql", "arguments": {"statements": statements}}})
}

async fn mcp_on(app: Router, path: &str, payload: Value) -> Response<Body> {
    common::mcp_on(app, path, "127.0.0.1", payload).await
}

/// Statements on the dataset's interface; the outcomes, and a panic on a refusal.
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

/// A refused statement's text on the dataset's interface.
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

/// The rows of one read on the dataset's interface.
async fn rows(app: &Router, sql: &str) -> Vec<Value> {
    let outcomes = say(app, sql).await;
    outcomes[0]["rows"].as_array().cloned().unwrap_or_default()
}

/// The rows of `next` under "test", in the list's order.
async fn open_tests(app: &Router) -> Vec<Value> {
    rows(app, "SELECT * FROM next WHERE step = 'test'").await
}

fn text(row: &Value, key: &str) -> String {
    row[key].as_str().unwrap_or_default().to_string()
}

/// A workspace with the dataset `fin` and a daily ledger loaded.
async fn fin() -> (Router, tempfile::TempDir) {
    let (app, dir) = app().await;
    let body = expect_ok(
        mcp_on(
            app.clone(),
            "/mcp",
            call(0, "DECLARE DATASET fin SET (purpose: 'the next steps');"),
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
async fn a_dataset_without_a_view_has_one_open_row_and_a_table_or_single_value_closes_it() {
    let (app, _dir) = fin().await;
    let all = rows(&app, "SELECT * FROM next").await;
    // A table is there and no view: one row of kind "integrate", with
    // the statements that define one. Nothing is asked about a table no
    // view reads, and the preview rows stay out while no model
    // service is named.
    let open: Vec<(String, String)> = all
        .iter()
        .map(|r| (text(r, "step"), text(r, "state")))
        .collect();
    assert_eq!(open, [("integrate".into(), "missing".into())], "{all:?}");
    assert!(!text(&all[0], "statement").is_empty(), "{all:?}");

    // A view is a metric, a single value or a table. Only a metric needs
    // a series; the other two leave nothing to integrate.
    say(
        &app,
        r#"DECLARE ASPECT ledger_clean WITH $${"title": "Ledger, cleaned", "x-kind": "relation"}$$ AS VIEW;
           GLOSS ledger_clean ON fin AS $${"sql": "SELECT booked, amount, upper(fund) AS fund FROM fin.ledger"}$$;
           DECLARE ASPECT ledger_rows WITH $${"title": "Ledger rows", "x-kind": "scalar"}$$ AS VIEW;
           GLOSS ledger_rows ON fin AS $${"sql": "SELECT count(*) AS value FROM fin.ledger"}$$;"#,
    )
    .await;
    let integrate = rows(&app, "SELECT * FROM next WHERE step = 'integrate'").await;
    assert!(integrate.is_empty(), "{integrate:?}");
    // A table and a single value have no series: their summary rows
    // carry neither `applicable` nor a period column, a floor or a window.
    let summary = rows(
        &app,
        "SELECT * FROM view_summary() WHERE view IN ('ledger_clean', 'ledger_rows')",
    )
    .await;
    assert_eq!(summary.len(), 2, "{summary:?}");
    for row in &summary {
        for field in [
            "applicable",
            "reason",
            "period_column",
            "floor",
            "window_periods",
        ] {
            assert!(row.get(field).is_none_or(Value::is_null), "{field}: {row}");
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_test_declared_on_a_table_view_opens_a_row_while_it_is_red() {
    let (app, _dir) = fin().await;
    // A table view with a test of the team's own: the property holds
    // the expectation, annotated on the view, and the check returns the
    // same property. The check measures the share of rows outside the
    // code table; one fund in three is outside it, so the test is red
    // and the list carries a row of kind "test" for the view. The
    // table's own columns are asked to be described, as a table is
    // handed over with them.
    say(
        &app,
        r#"DECLARE ASPECT ledger_clean WITH $${"title": "Ledger, cleaned", "x-kind": "relation"}$$ AS VIEW;
           GLOSS ledger_clean ON fin AS $${"sql": "SELECT booked, amount, fund FROM fin.ledger"}$$;
           DECLARE ASPECT fund_coded WITH $${"type": "object", "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"}, "basis": {"type": "string"}, "breach_rate": {"type": "number"}, "rows": {"type": "integer"}}}$$ AS FACT ON TABLE;
           DECLARE FUNCTION fund_coded_check FOR fin AS $$SELECT count(*) FILTER (WHERE fund NOT IN ('general', 'water')) / greatest(count(*), 1)::DOUBLE AS breach_rate, count(*) AS rows FROM fin.ledger_clean$$ RETURNS fund_coded;
           DECLARE TEST fund_coded_test ON fund_coded BY (AGENT, HUMAN) DETECTOR rate_tolerance;
           GLOSS fund_coded ON ledger_clean AS $${"outcome": "each fund is in the code table", "tolerance": 0.0, "basis": "the code table lists every fund"}$$;
           SELECT fund_coded_check() FROM ledger_clean;"#,
    )
    .await;
    let open = open_tests(&app).await;
    let row = open
        .iter()
        .find(|r| text(r, "asset") == "fin.ledger_clean")
        .unwrap_or_else(|| panic!("no test row for the table view: {open:?}"));
    assert_eq!(text(row, "state"), "red", "{row}");
    assert_eq!(text(row, "for_view"), "ledger_clean", "{row}");
    assert!(
        text(row, "statement").contains("fund_coded_check()"),
        "{row}"
    );
    // The rate is accepted where the expectation is: an annotation on
    // the view, which a person can write with a reason.
    assert!(
        text(row, "statement").contains("GLOSS fund_coded ON fin.ledger_clean AS"),
        "{row}"
    );
    // The expectation is set on the view. The list asks for it on no
    // other asset the view reads.
    let asked = rows(
        &app,
        "SELECT asset, statement FROM next WHERE step = 'describe' AND contains(statement, 'fund_coded')",
    )
    .await;
    assert!(asked.is_empty(), "{asked:?}");
    let described = rows(
        &app,
        "SELECT * FROM next WHERE step = 'describe' AND asset = 'fin.ledger_clean'",
    )
    .await;
    assert!(
        described
            .iter()
            .any(|r| text(r, "statement").contains("fin.ledger_clean.fund")),
        "{described:?}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_metric_walks_its_tests_from_the_definition_to_green() {
    let (app, _dir) = fin().await;

    // Defined: the write answers with the metric's row, the server runs
    // the built-in tests, and the additivity test says the columns owe
    // their roles. One table scanned: nothing to fan out, no join to check.
    let outcomes = say(
        &app,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
    )
    .await;
    let written = &outcomes[1]["rows"][0];
    assert_eq!(written["view"], json!("spend"), "{outcomes}");
    assert_eq!(written["applicable"], json!(false), "{outcomes}");
    let tests = rows(
        &app,
        "SELECT test, state FROM view_tests() WHERE view = 'spend' ORDER BY test",
    )
    .await;
    let states: Vec<(String, String)> = tests
        .iter()
        .map(|r| (text(r, "test"), text(r, "state")))
        .collect();
    assert_eq!(
        states,
        [
            ("fan_out_test".into(), "green".into()),
            ("measure_additivity_test".into(), "yellow".into()),
            ("orphan_test".into(), "green".into()),
            ("validity_test".into(), "green".into()),
        ],
        "{tests:?}"
    );
    let open = open_tests(&app).await;
    assert_eq!(open.len(), 1, "{open:?}");
    assert_eq!(text(&open[0], "asset"), "fin.spend", "{open:?}");
    assert_eq!(text(&open[0], "state"), "yellow", "{open:?}");
    assert!(
        text(&open[0], "statement").contains("GLOSS role ON fin.spend.period"),
        "{open:?}"
    );

    // The roles are annotated and the period is profiled: the server
    // ran the tests again after each call, and the additivity is open.
    say(
        &app,
        r#"GLOSS role ON spend.period AS $${"value": "timestamp"}$$;
           GLOSS role ON spend.value AS $${"value": "measure"}$$;
           GLOSS role ON spend.fund AS $${"value": "dimension"}$$;
           SELECT temporal() FROM fin.spend.period;"#,
    )
    .await;
    let open = open_tests(&app).await;
    assert_eq!(open.len(), 1, "{open:?}");
    assert_eq!(text(&open[0], "state"), "red", "{open:?}");
    assert!(
        text(&open[0], "statement").contains("GLOSS additivity ON fin.spend.value"),
        "{open:?}"
    );
    let refusal = refused(
        &app,
        "SELECT period, value FROM metric_series() WHERE metric = 'spend'",
    )
    .await;
    assert!(refusal.contains("fin.spend.value"), "{refusal}");

    // Annotated: every test is green and nothing is open under
    // "test"; the series serves at its finest grain and coarser.
    say(
        &app,
        r#"GLOSS additivity ON spend.value AS $${"value": "additive"}$$;"#,
    )
    .await;
    let open = open_tests(&app).await;
    assert!(open.is_empty(), "{open:?}");
    let cells = rows(&app, "SELECT period, value FROM metric_series() WHERE metric = 'spend' AND dimension = '' ORDER BY period").await;
    assert_eq!(cells.len(), 4, "{cells:?}");

    // A stopped metric is no longer served, and the list says that no
    // metric is defined.
    say(
        &app,
        r#"GLOSS spend ON fin AS $${"stopped": "the ledger is not booked before 2024"}$$;"#,
    )
    .await;
    let integrate = rows(
        &app,
        "SELECT asset, state FROM next WHERE step = 'integrate'",
    )
    .await;
    assert_eq!(integrate.len(), 1, "{integrate:?}");
    assert_eq!(text(&integrate[0], "asset"), "fin", "{integrate:?}");
    assert_eq!(text(&integrate[0], "state"), "missing", "{integrate:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_next_page_carries_the_test_and_its_statement() {
    let (app, _dir) = fin().await;
    say(
        &app,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
    )
    .await;
    let body = expect_ok(
        mcp_on(
            app.clone(),
            "/fin/mcp",
            json!({"jsonrpc": "2.0", "id": 5, "method": "resources/read",
                   "params": {"_meta": meta(), "uri": "next://fin/test"}}),
        )
        .await,
    )
    .await;
    let page = body["result"]["contents"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("{body}"));
    assert!(page.contains("fin.spend"), "{page}");
    assert!(page.contains("yellow"), "{page}");
    assert!(page.contains("measure_additivity_test"), "{page}");
    assert!(page.contains("GLOSS role ON fin.spend.period"), "{page}");

    // Every result on the dataset's interface closes with the link to
    // the page of the first open row's kind of work.
    let body = expect_ok(mcp_on(app.clone(), "/fin/mcp", call(6, "SELECT 1 AS one")).await).await;
    let window = body["result"]["content"][1]["text"].as_str().unwrap();
    assert!(window.contains("next://fin/describe"), "{window}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_definition_that_names_its_columns_is_served_in_one_statement() {
    let (app, _dir) = fin().await;
    // The definition says which column is the time, which the measure
    // and how it adds up, and which slice it: the server writes the
    // column annotations, profiles the time column and runs the tests.
    let outcomes = say(
        &app,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;"#,
    )
    .await;
    let written = &outcomes[1]["rows"][0];
    assert_eq!(written["applicable"], json!(true), "{outcomes}");
    assert_eq!(written["additivity"], json!("additive"), "{outcomes}");
    let open = open_tests(&app).await;
    assert!(open.is_empty(), "{open:?}");
    // What is left is the description of the table the metric reads:
    // the row hands over one statement per missing property, and names
    // no column the metric does not read.
    let describe = rows(
        &app,
        "SELECT state, statement FROM next WHERE step = 'describe' AND asset = 'fin.ledger'",
    )
    .await;
    assert_eq!(describe.len(), 1, "{describe:?}");
    assert_eq!(text(&describe[0], "state"), "missing", "{describe:?}");
    let statement = text(&describe[0], "statement");
    assert!(
        statement.contains("GLOSS meaning ON fin.ledger.amount"),
        "{statement}"
    );
    let cells = rows(&app, "SELECT period, value FROM metric_series() WHERE metric = 'spend' AND dimension = '' ORDER BY period").await;
    assert_eq!(cells.len(), 4, "{cells:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_ratio_marked_additive_is_red_and_so_is_the_metric_that_sums_it() {
    let (app, _dir) = fin().await;
    // What an earlier session left: a daily rate marked additive, and a
    // monthly metric that sums the daily rates. Both are wrong numbers;
    // the additivity test reads how each value is computed.
    say(
        &app,
        r#"DECLARE ASPECT amount_per_booking WITH $${"title": "Amount per booking"}$$ AS VIEW;
           GLOSS amount_per_booking ON fin AS $${"sql": "SELECT booked::DATE AS period, sum(amount) AS num, count(*) AS den, sum(amount) / count(*) AS value FROM fin.ledger GROUP BY 1", "time": "period", "measure": {"column": "value", "additivity": "additive"}}$$;
           DECLARE ASPECT amount_per_booking_month WITH $${"title": "Amount per booking, monthly"}$$ AS VIEW;
           GLOSS amount_per_booking_month ON fin AS $${"sql": "SELECT date_trunc('month', period)::DATE AS period, sum(value) AS value FROM fin.amount_per_booking GROUP BY 1", "time": "period", "measure": {"column": "value", "additivity": "additive"}}$$;"#,
    )
    .await;
    // Both are red rows of kind "test", with the fix the test itself returns:
    // the metric's current definition, to edit and record.
    let open = rows(
        &app,
        "SELECT asset, state, statement FROM next WHERE step = 'test' ORDER BY asset",
    )
    .await;
    let assets: Vec<String> = open.iter().map(|r| text(r, "asset")).collect();
    assert_eq!(
        assets,
        ["fin.amount_per_booking", "fin.amount_per_booking_month"],
        "{open:?}"
    );
    for row in &open {
        assert_eq!(text(row, "state"), "red", "{row}");
    }
    let fix = text(&open[0], "statement");
    assert!(
        fix.contains("GLOSS amount_per_booking ON fin AS $${\"sql\""),
        "{fix}"
    );
    // Marked a ratio with its two halves, the daily metric is done.
    say(
        &app,
        r#"GLOSS amount_per_booking ON fin AS $${"sql": "SELECT booked::DATE AS period, sum(amount) AS num, count(*) AS den, sum(amount) / count(*) AS value FROM fin.ledger GROUP BY 1", "time": "period", "measure": {"column": "value", "additivity": "ratio", "numerator": "num", "denominator": "den"}}$$;"#,
    )
    .await;
    let open = open_tests(&app).await;
    let assets: Vec<String> = open.iter().map(|r| text(r, "asset")).collect();
    assert_eq!(assets, ["fin.amount_per_booking_month"], "{open:?}");
}

/// The rows of `next` under "describe" for the bookings table.
async fn bookings_rows(app: &Router) -> Vec<Value> {
    rows(
        app,
        "SELECT state, cause FROM next WHERE step = 'describe' AND asset = 'fin.bookings' ORDER BY state",
    )
    .await
}

#[tokio::test(flavor = "multi_thread")]
async fn a_changed_load_is_named_with_what_it_changed() {
    // After the layer is built, a load query that derives a column
    // differently makes its description outdated. The row under
    // "describe" gives the cause: the row counts of the two loads and
    // the columns whose profile moved. The server profiles the columns
    // a metric reads itself.
    let (app, dir) = fin().await;
    let file = dir.path().join("bookings.csv");
    let head =
        "booked,amount,fund\n2024-01-01,10,general\n2024-01-02,20,water\n2024-02-01,30,parks\n";
    std::fs::write(&file, head).unwrap();
    let load = "DECLARE RECIPE bookings ON fin FROM erp AS $$SELECT CAST(booked AS DATE) AS booked, \
                CAST(amount AS DOUBLE) AS amount, fund FROM read_csv('bookings.csv')$$;";
    say(
        &app,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); {load}",
            dir.path().display()
        ),
    )
    .await;
    say(
        &app,
        r#"DECLARE ASPECT booked_amount WITH $${"title": "Booked amount"}$$ AS VIEW;
           GLOSS booked_amount ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, fund, sum(amount) AS value FROM fin.bookings GROUP BY 1, 2", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;
           GLOSS meaning ON fin.bookings.fund AS $${"value": "the fund a booking is charged to"}$$;"#,
    )
    .await;
    let before = bookings_rows(&app).await;
    assert!(
        before.iter().all(|r| text(r, "state") != "stale"),
        "{before:?}"
    );
    // One booking more, on a fund not seen before, and the fund now
    // derived in upper case.
    std::fs::write(&file, format!("{head}2024-03-01,40,roads\n")).unwrap();
    say(
        &app,
        &load.replace(", fund FROM", ", upper(fund) AS fund FROM"),
    )
    .await;
    let after = bookings_rows(&app).await;
    let stale = after
        .iter()
        .find(|r| text(r, "state") == "stale")
        .unwrap_or_else(|| panic!("no outdated description: {after:?}"));
    // The cause names the column whose profile moved; the two loads it
    // compares are the catalog's, three rows and then four.
    let cause = text(stale, "cause");
    assert!(cause.contains("fund"), "{cause}");
    let loads = rows(
        &app,
        "SELECT rows FROM imports WHERE table_name = 'bookings' ORDER BY seq",
    )
    .await;
    let counts: Vec<&Value> = loads.iter().map(|r| &r["rows"]).collect();
    assert_eq!(counts, [&json!(3), &json!(4)], "{loads:?}");
}

/// The `next:` line under a result counts the rows `next` lists. A call
/// that defines a metric and reads `next` gets the same rows in the
/// read and in the line: the server runs the metric's tests before the
/// read, not after it.
#[tokio::test(flavor = "multi_thread")]
async fn the_next_line_counts_the_rows_the_same_call_lists() {
    let (app, _dir) = fin().await;
    let body = expect_ok(
        mcp_on(
            app.clone(),
            "/fin/mcp",
            call(
                1,
                r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
                   GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;
                   SELECT step, who FROM next"#,
            ),
        )
        .await,
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    let outcomes: Value =
        serde_json::from_str(body["result"]["content"][0]["text"].as_str().unwrap()).unwrap();
    let listed = outcomes[2]["rows"].as_array().unwrap();
    let window = body["result"]["content"][1]["text"].as_str().unwrap();
    let line = window
        .lines()
        .find_map(|l| l.strip_prefix("next:"))
        .unwrap_or_else(|| panic!("{window}"));
    for step in ["integrate", "describe", "test", "review"] {
        let counted: usize = line
            .split('\u{b7}')
            .find_map(|part| part.trim().strip_prefix(step)?.trim().parse().ok())
            .unwrap_or(0);
        let rows = listed
            .iter()
            .filter(|r| text(r, "step") == step && text(r, "who") != "person")
            .count();
        assert_eq!(counted, rows, "{step}: {window} against {listed:?}");
    }
    // the metric's own tests ran before the read: none of them is listed
    assert_eq!(
        listed.iter().filter(|r| text(r, "step") == "test").count(),
        0,
        "{listed:?}"
    );
}
