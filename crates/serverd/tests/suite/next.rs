//! `next`, the work list of a dataset, read through the agent
//! interface: what is open, each row with its level (must, should,
//! could) and its kind of work (integrate, describe, test, review),
//! with its asset, its state and the statement that opens the work.
//! The tests check level, kind, asset and state, and that a row's
//! statement names the asset and the property of the fixture.

use axum::Router;
use serde_json::{Value, json};

use crate::common::{self, rows, say, tool, window};

const FIN: &str = "/fin/mcp";

/// The rows of `next` under "test", in the list's order.
async fn open_tests(app: &Router) -> Vec<Value> {
    rows(app, FIN, "SELECT * FROM next WHERE kind = 'test'").await
}

fn text(row: &Value, key: &str) -> String {
    row[key].as_str().unwrap_or_default().to_string()
}

/// A workspace with the dataset `fin` and a daily ledger loaded.
async fn fin() -> common::Served {
    let served = common::app_on("fin").await;
    say(
        &served.0,
        FIN,
        "CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked, \
         (i % 7 + 1)::DOUBLE AS amount, ['general', 'water', 'parks'][i % 3 + 1] AS fund \
         FROM range(120) r(i)",
    )
    .await;
    served
}

/// The server runs a metric's tests after each write: the definition
/// is tested before anyone asks, and so is each annotation after it,
/// until nothing is open and the series serves.
#[tokio::test(flavor = "multi_thread")]
async fn the_server_runs_a_metrics_tests_after_each_write() {
    let (app, _, _dir) = fin().await;
    let states = async || {
        let tests = rows(
            &app,
            FIN,
            "SELECT test, state FROM view_tests() WHERE view = 'spend' ORDER BY test",
        )
        .await;
        tests
            .iter()
            .map(|r| (text(r, "test"), text(r, "state")))
            .collect::<Vec<_>>()
    };
    let state = |states: &[(String, String)], test: &str| {
        states
            .iter()
            .find(|(t, _)| t == test)
            .map(|(_, s)| s.clone())
            .unwrap_or_else(|| panic!("no {test}: {states:?}"))
    };

    say(
        &app,
        FIN,
        r#"GLOSS spend ON fin AS $${"kind": "metric", "sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
    )
    .await;
    let defined = states().await;
    for test in ["join_test", "orphan_test"] {
        assert_eq!(state(&defined, test), "green", "{defined:?}");
    }
    assert_eq!(state(&defined, "measure_additivity_test"), "yellow");

    say(
        &app,
        FIN,
        r#"GLOSS role ON spend.period AS $${"value": "timestamp"}$$;
           GLOSS role ON spend.value AS $${"value": "measure"}$$;
           GLOSS role ON spend.fund AS $${"value": "dimension"}$$;
           SELECT temporal() FROM fin.spend.period;"#,
    )
    .await;
    assert_eq!(state(&states().await, "measure_additivity_test"), "red");

    say(
        &app,
        FIN,
        r#"GLOSS additivity ON spend.value AS $${"value": "additive"}$$;"#,
    )
    .await;
    assert!(open_tests(&app).await.is_empty());
    let cells = rows(
        &app,
        FIN,
        "SELECT period, value FROM metric_series() WHERE metric = 'spend' AND dimension = '' ORDER BY period",
    )
    .await;
    assert_eq!(cells.len(), 4, "{cells:?}");
}

/// The server runs a table view's tests after each write, as a
/// metric's: its join columns are profiled and the relationship it
/// joins over is checked with no statement by the agent, and a key
/// without a parent turns the orphan test red under "test" in `next`;
/// the funds loaded again with no label empty a column the view serves,
/// and the completeness test on that column turns red with no statement
/// either, the other columns green.
#[tokio::test(flavor = "multi_thread")]
async fn the_server_runs_a_table_views_tests_after_each_write() {
    let (app, _, _dir) = fin().await;
    say(
        &app,
        FIN,
        r#"CREATE TABLE fin.funds AS SELECT unnest(['general', 'water']) AS fund, 'a fund' AS label;
           GLOSS ledger_funds ON fin AS $${"kind": "table", "sql": "SELECT l.booked, l.amount, f.label FROM fin.ledger l JOIN fin.funds f ON f.fund = l.fund"}$$;"#,
    )
    .await;
    let computed = async |function: &str| {
        rows(
            &app,
            FIN,
            &format!("SELECT subject FROM results WHERE function = '{function}' ORDER BY subject"),
        )
        .await
        .iter()
        .map(|r| text(r, "subject"))
        .collect::<Vec<_>>()
    };
    let profiled = computed("column_profile").await;
    for column in ["fin.funds.fund", "fin.ledger.fund"] {
        assert!(profiled.contains(&column.to_string()), "{profiled:?}");
    }

    say(&app, FIN, "DECLARE RELATIONSHIP ledger.fund -> funds.fund;").await;
    assert_eq!(
        computed("relationship_coherence").await,
        ["fin.ledger.fund -> fin.funds.fund"]
    );
    let tests = rows(
        &app,
        FIN,
        "SELECT test, subject, state FROM view_tests() WHERE view = 'ledger_funds' ORDER BY test, subject",
    )
    .await;
    let states: Vec<(String, String, String)> = tests
        .iter()
        .map(|r| (text(r, "test"), text(r, "subject"), text(r, "state")))
        .collect();
    let row = |test: &str, subject: &str, state: &str| {
        (test.to_string(), subject.to_string(), state.to_string())
    };
    assert_eq!(
        states,
        [
            row("completeness_test", "fin.ledger_funds.amount", "green"),
            row("completeness_test", "fin.ledger_funds.booked", "green"),
            row("completeness_test", "fin.ledger_funds.label", "green"),
            row("join_test", "fin.ledger_funds", "green"),
            row("orphan_test", "fin.ledger_funds", "red"),
            row("relationship_test", "fin.ledger_funds", "green"),
        ]
    );
    let open = open_tests(&app).await;
    assert_eq!(open.len(), 1, "{open:?}");
    assert_eq!(text(&open[0], "asset"), "fin.ledger_funds");
    assert_eq!(text(&open[0], "state"), "red");

    say(
        &app,
        FIN,
        "CREATE OR REPLACE TABLE fin.funds AS SELECT unnest(['general', 'water']) AS fund, NULL::VARCHAR AS label;",
    )
    .await;
    let emptied = rows(
        &app,
        FIN,
        "SELECT subject, state, current, evidence->>'emptied_by' AS emptied_by \
         FROM view_tests() WHERE view = 'ledger_funds' AND test = 'completeness_test' AND state <> 'green'",
    )
    .await;
    assert_eq!(emptied.len(), 1, "{emptied:?}");
    assert_eq!(text(&emptied[0], "subject"), "fin.ledger_funds.label");
    assert_eq!(text(&emptied[0], "state"), "red");
    assert_eq!(emptied[0]["current"].as_bool(), Some(true));
    assert_eq!(text(&emptied[0], "emptied_by"), "load");
}

/// A definition recorded again that empties a column the view serves
/// turns that column's completeness test red, and the statement `next`
/// hands over for it runs as handed: the comments above it and the
/// commented accept after it are no statement of their own.
#[tokio::test(flavor = "multi_thread")]
async fn the_statement_next_hands_over_runs_with_its_comments() {
    let (app, _, _dir) = fin().await;
    say(
        &app,
        FIN,
        r#"CREATE TABLE fin.funds AS SELECT unnest(['general', 'water']) AS fund, 'a fund' AS label;
           GLOSS ledger_funds ON fin AS $${"kind": "table", "sql": "SELECT l.booked, l.amount, f.label FROM fin.ledger l JOIN fin.funds f ON f.fund = l.fund"}$$;"#,
    )
    .await;
    say(
        &app,
        FIN,
        r#"GLOSS ledger_funds ON fin AS $${"kind": "table", "sql": "SELECT l.booked, l.amount, CAST(NULL AS VARCHAR) AS label FROM fin.ledger l JOIN fin.funds f ON f.fund = l.fund"}$$;"#,
    )
    .await;
    let red = rows(
        &app,
        FIN,
        "SELECT asset, level, statement FROM next WHERE kind = 'test' AND starts_with(open, 'completeness_test')",
    )
    .await;
    assert_eq!(red.len(), 1, "{red:?}");
    assert_eq!(text(&red[0], "asset"), "fin.ledger_funds.label");
    assert_eq!(text(&red[0], "level"), "must");
    let handed = text(&red[0], "statement");
    assert!(handed.starts_with("--"), "{handed}");
    say(&app, FIN, &handed).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn the_next_page_carries_the_test_and_its_statement() {
    let (app, _, _dir) = fin().await;
    say(&app, FIN,
        r#"GLOSS spend ON fin AS $${"kind": "metric", "sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
    )
    .await;
    let body = common::rpc(
        &app,
        FIN,
        "resources/read",
        json!({"uri": "next://fin/test"}),
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
    // the page of the kind of work of the first row it must or should
    // work on: the additivity test that waits for its annotations.
    let closing = window(&tool(&app, FIN, "SELECT 1 AS one").await);
    assert!(closing.contains("next://fin/test"), "{closing}");
}

/// One statement keeps a query with its reason: the server writes the
/// definition's `meaning` and `tags` as annotations on the view, by the
/// definition's actor, and the search read finds the view by a tag. A
/// comment before the statement changes none of it.
#[tokio::test(flavor = "multi_thread")]
async fn a_definitions_meaning_and_tags_are_annotations_on_its_view() {
    let (app, _, _dir) = fin().await;
    say(&app, FIN,
        concat!("-- the funds\n", r#"GLOSS funds_seen ON fin AS $${"sql": "SELECT DISTINCT fund FROM fin.ledger", "meaning": "the funds the ledger books to", "tags": ["fund", "budget line"]}$$;"#),
    )
    .await;
    let said = rows(
        &app,
        FIN,
        "SELECT property, actor_kind, body->'value' AS value FROM main.glossary \
         WHERE subject = 'fin.funds_seen' ORDER BY property",
    )
    .await;
    assert_eq!(said.len(), 2, "{said:?}");
    assert_eq!(text(&said[0], "property"), "meaning", "{said:?}");
    assert_eq!(text(&said[1], "property"), "tags", "{said:?}");
    assert!(
        said.iter().all(|r| text(r, "actor_kind") == "agent"),
        "{said:?}"
    );
    let found = rows(&app, FIN, "SELECT asset, kind FROM find('budget')").await;
    assert_eq!(found.len(), 1, "{found:?}");
    assert_eq!(text(&found[0], "asset"), "fin.funds_seen", "{found:?}");
    assert_eq!(found[0]["kind"], Value::Null, "{found:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_definition_that_names_its_columns_is_served_in_one_statement() {
    let (app, _, _dir) = fin().await;
    // The definition says which column is the time, which the measure
    // and how it adds up, and which slice it: the server writes the
    // column annotations, profiles the time column and runs the tests.
    let outcomes = say(&app, FIN,
        r#"GLOSS spend ON fin AS $${"kind": "metric", "sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;"#,
    )
    .await;
    let written = &outcomes[0]["rows"][0];
    assert_eq!(written["applicable"], json!(true), "{outcomes}");
    assert_eq!(written["additivity"], json!("additive"), "{outcomes}");
    let open = open_tests(&app).await;
    assert!(open.is_empty(), "{open:?}");
    // What is left is the description of the table the metric reads:
    // the row hands over one statement per missing property, and names
    // no column the metric does not read.
    let describe = rows(
        &app,
        FIN,
        "SELECT state, statement FROM next WHERE kind = 'describe' AND asset = 'fin.ledger'",
    )
    .await;
    assert_eq!(describe.len(), 1, "{describe:?}");
    assert_eq!(text(&describe[0], "state"), "missing", "{describe:?}");
    let statement = text(&describe[0], "statement");
    assert!(
        statement.contains("GLOSS meaning ON fin.ledger.amount"),
        "{statement}"
    );
    let cells = rows(&app, FIN, "SELECT period, value FROM metric_series() WHERE metric = 'spend' AND dimension = '' ORDER BY period").await;
    assert_eq!(cells.len(), 4, "{cells:?}");
}

/// The server holds a target view with a contract against its source
/// after each load, with no statement by the agent: a source row the
/// view's join drops turns `reconciliation_test` red, a must of `next`
/// whose statements run; a row its condition leaves out does not; once
/// a load of the mapping table brings the row, nothing is open.
#[tokio::test(flavor = "multi_thread")]
async fn the_server_reconciles_a_contracted_view_after_each_load() {
    let (app, _, dir) = fin().await;
    std::fs::write(
        dir.path().join("stock.csv"),
        "item,qty,status\nA,1,D\nA,2,D\nB,2,D\nA,5,K\n",
    )
    .unwrap();
    std::fs::write(dir.path().join("items.csv"), "local,global\nA,P1\n").unwrap();
    say(
        &app,
        FIN,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); \
             DECLARE RECIPE stock ON fin FROM erp AS $$SELECT item, CAST(qty AS DOUBLE) AS qty, status \
             FROM read_csv('stock.csv', all_varchar = true)$$; \
             DECLARE RECIPE items ON fin FROM erp AS $$SELECT * FROM read_csv('items.csv', all_varchar = true)$$;",
            dir.path().display()
        ),
    )
    .await;
    say(
        &app,
        FIN,
        r#"GLOSS free_stock ON fin AS $${"kind": "table", "sql": "SELECT i.global AS item, sum(s.qty) AS qty FROM fin.stock s JOIN fin.items i ON i.local = s.item WHERE s.status = 'D' GROUP BY ALL"}$$;
           GLOSS entity ON fin.free_stock AS $${"value": "the stock of one item", "grain": ["item"]}$$;
           GLOSS contract ON fin.free_stock.item AS $${"type": "VARCHAR", "required": true}$$;"#,
    )
    .await;
    let open = async || {
        rows(
            &app,
            FIN,
            "SELECT level, statement FROM next WHERE asset = 'fin.free_stock' AND open LIKE 'reconciliation_test%'",
        )
        .await
    };
    let red = open().await;
    assert_eq!(red.len(), 1, "{red:?}");
    assert_eq!(text(&red[0], "level"), "must");
    let missing = rows(
        &app,
        FIN,
        "SELECT sum((r->>'missing_rows')::BIGINT) AS missing, sum((r->>'excluded_rows')::BIGINT) AS excluded \
         FROM results, unnest(from_json(value->'rows', '[\"JSON\"]')) t(r) \
         WHERE function = 'reconciliation' AND subject = 'fin.free_stock'",
    )
    .await;
    assert_eq!(missing[0]["missing"], 1, "{missing:?}");
    assert_eq!(missing[0]["excluded"], 1, "{missing:?}");
    let handed: Vec<String> = text(&red[0], "statement")
        .lines()
        .filter(|line| !line.starts_with("--") && !line.contains('<'))
        .map(str::to_string)
        .collect();
    assert!(!handed.is_empty(), "{red:?}");
    for statement in handed {
        say(&app, FIN, &statement).await;
    }

    std::fs::write(dir.path().join("items.csv"), "local,global\nA,P1\nB,P2\n").unwrap();
    say(&app, FIN, "IMPORT items;").await;
    let green = open().await;
    assert!(green.is_empty(), "{green:?}");
}

/// A view's lineage is a stored result the server brings current: a
/// load whose query adds a column to the table a view reads puts the
/// view's lineage out of date, and the server computes it again after
/// the write. It has the same value, so it keeps the snapshot it changed
/// at, and nothing that read it is out of date.
#[tokio::test(flavor = "multi_thread")]
async fn a_load_that_adds_a_column_brings_the_lineage_of_the_view_over_it_current() {
    let (app, _, dir) = fin().await;
    std::fs::write(
        dir.path().join("bookings.csv"),
        "booked,amount\n2024-01-01,10\n2024-01-02,20\n",
    )
    .unwrap();
    let load = "DECLARE RECIPE bookings ON fin FROM erp AS $$SELECT CAST(booked AS DATE) AS booked, \
                CAST(amount AS DOUBLE) AS amount FROM read_csv('bookings.csv')$$;";
    say(
        &app,
        FIN,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); {load}",
            dir.path().display()
        ),
    )
    .await;
    say(&app, FIN,
        r#"GLOSS booked_rows ON fin AS $${"kind": "table", "sql": "SELECT booked, amount FROM fin.bookings"}$$;"#,
    )
    .await;
    let lineage = async || {
        rows(
            &app,
            FIN,
            "SELECT begin_snapshot, changed_at FROM results \
             WHERE function = 'lineage' AND subject = 'fin.booked_rows'",
        )
        .await
    };
    let before = lineage().await;
    assert_eq!(before.len(), 1, "{before:?}");
    say(
        &app,
        FIN,
        &load.replace(" AS amount FROM", " AS amount, 'erp' AS origin FROM"),
    )
    .await;
    let after = lineage().await;
    assert_eq!(after.len(), 1, "{after:?}");
    assert_ne!(after[0]["begin_snapshot"], before[0]["begin_snapshot"]);
    assert_eq!(after[0]["changed_at"], before[0]["changed_at"]);
    let outdated = rows(
        &app,
        FIN,
        "SELECT function, subject, asset, what FROM glossql_outdated() WHERE subject LIKE 'fin.booked_rows%'",
    )
    .await;
    assert!(outdated.is_empty(), "{outdated:?}");
}

/// A load that derives a column otherwise makes the annotations on its
/// table outdated. The row under "describe" names the read that says
/// what the load changed, in a comment above its statement, and that
/// read runs: it lists the table, three rows before and four after.
#[tokio::test(flavor = "multi_thread")]
async fn an_outdated_annotation_names_the_read_of_what_the_load_changed() {
    let (app, _, dir) = fin().await;
    let file = dir.path().join("bookings.csv");
    let head =
        "booked,amount,fund\n2024-01-01,10,general\n2024-01-02,20,water\n2024-02-01,30,parks\n";
    std::fs::write(&file, head).unwrap();
    let load = "DECLARE RECIPE bookings ON fin FROM erp AS $$SELECT CAST(booked AS DATE) AS booked, \
                CAST(amount AS DOUBLE) AS amount, fund FROM read_csv('bookings.csv')$$;";
    say(
        &app,
        FIN,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); {load}",
            dir.path().display()
        ),
    )
    .await;
    say(
        &app,
        FIN,
        r#"GLOSS meaning ON fin.bookings.fund AS $${"value": "the fund a booking is charged to"}$$;"#,
    )
    .await;
    std::fs::write(&file, format!("{head}2024-03-01,40,roads\n")).unwrap();
    say(
        &app,
        FIN,
        &load.replace(", fund FROM", ", upper(fund) AS fund FROM"),
    )
    .await;
    let stale = rows(
        &app,
        FIN,
        "SELECT statement FROM next WHERE asset = 'fin.bookings' AND state = 'stale'",
    )
    .await;
    assert_eq!(stale.len(), 1, "{stale:?}");
    let statement = text(&stale[0], "statement");
    let read = statement
        .lines()
        .find(|line| line.starts_with("--") && line.contains("load_changes()"))
        .and_then(|line| line.split_once(": "))
        .map(|(_, read)| read.to_string())
        .unwrap_or_else(|| panic!("{statement}"));
    let changed = rows(&app, FIN, &read).await;
    assert_eq!(changed.len(), 1, "{changed:?}");
    assert_eq!(text(&changed[0], "table_name"), "fin.bookings");
    say(&app, FIN, &statement).await;
    let closed = rows(
        &app,
        FIN,
        "SELECT state FROM next WHERE asset = 'fin.bookings' AND state = 'stale'",
    )
    .await;
    assert!(closed.is_empty(), "{closed:?}");
}

/// The `next:` line under a result counts the rows `next` lists that
/// must and should be done, per kind of work; what could be done is not
/// counted. A call that defines a metric and reads `next` gets the same
/// rows in the read and in the line: the server runs the metric's tests
/// before the read, not after it.
#[tokio::test(flavor = "multi_thread")]
async fn the_next_line_counts_the_rows_the_same_call_lists() {
    let (app, _, _dir) = fin().await;
    let body = tool(
        &app,
        FIN,
        r#"CREATE TABLE fin.funds AS SELECT 'general' AS fund;
           GLOSS spend ON fin AS $${"kind": "metric", "sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;
           SELECT level, kind, who FROM next"#,
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    let outcomes = common::outcomes(&body);
    let listed = outcomes[2]["rows"].as_array().unwrap();
    let window = window(&body);
    let line = window
        .lines()
        .find_map(|l| l.strip_prefix("next:"))
        .unwrap_or_else(|| panic!("{window}"));
    for level in ["must", "should"] {
        let part = line
            .split('\u{b7}')
            .find_map(|part| part.trim().strip_prefix(level))
            .unwrap_or_else(|| panic!("no {level} in {window}"));
        for kind in ["integrate", "describe", "test", "review"] {
            let counted: usize = part
                .split(',')
                .find_map(|p| p.trim().strip_prefix(kind)?.trim().parse().ok())
                .unwrap_or(0);
            let rows = listed
                .iter()
                .filter(|r| {
                    text(r, "level") == level
                        && text(r, "kind") == kind
                        && text(r, "who") != "person"
                })
                .count();
            assert_eq!(counted, rows, "{level} {kind}: {window} against {listed:?}");
        }
    }
    // the table no view reads is described on request: listed, not counted
    assert!(
        listed.iter().any(|r| text(r, "level") == "could"),
        "{listed:?}"
    );
    assert!(line.contains("must 0"), "{window}");
    // the metric's own tests ran before the read: none of them is listed
    assert_eq!(
        listed.iter().filter(|r| text(r, "kind") == "test").count(),
        0,
        "{listed:?}"
    );
}

/// The harmonise kit is an add-on: a server that leaves it out serves
/// `next`, `view_tests()`, `column_mapping()` and the console, and the
/// same `next`, tests and column mapping as a server with it.
#[tokio::test(flavor = "multi_thread")]
async fn a_server_without_the_harmonise_kit_serves_next_the_tests_and_the_console() {
    let build = r#"CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked,
                     (i % 7 + 1)::DOUBLE AS amount, ['general', 'water', 'parks'][i % 3 + 1] AS fund FROM range(120) r(i);
                   GLOSS spend ON fin AS $${"kind": "metric", "sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;"#;
    let next = "SELECT level, kind, asset, state, who, open, statement FROM next";
    let tests = "SELECT view, test, subject, state, current, run FROM view_tests() ORDER BY ALL";
    let (with, _, _with_dir) = common::app_on("fin").await;
    say(&with, FIN, build).await;
    let (neither, _, _neither_dir) = common::app_on_without("fin", &["harmonise"]).await;
    say(&neither, FIN, build).await;
    let served_next = rows(&with, FIN, next).await;
    let served_tests = rows(&with, FIN, tests).await;
    assert!(!served_tests.is_empty());
    let mapping = "SELECT view, target_column, branch, source_table, source_column FROM column_mapping() ORDER BY ALL";
    let served_mapping = rows(&with, FIN, mapping).await;
    assert!(!served_mapping.is_empty());
    for app in [&neither] {
        assert_eq!(rows(app, FIN, next).await, served_next);
        assert_eq!(rows(app, FIN, tests).await, served_tests);
        assert_eq!(rows(app, FIN, mapping).await, served_mapping);
        let closing = window(&tool(app, FIN, "SELECT 1 AS one").await);
        assert!(closing.contains("next: must 0"), "{closing}");
        for page in [
            "/fin/app/console",
            "/fin/app/console/p/quality",
            "/fin/app/console/p/views?view=spend&tab=results",
            "/fin/app/console/frames/next_rows",
            "/fin/app/console/frames/functions",
            "/fin/app/console/frames/front",
            "/fin/app/console/frames/view_tests",
            "/fin/app/console/frames/trend?view=spend&grain=month&span=24",
        ] {
            let response = common::get(app, page).await;
            assert_eq!(response.status(), axum::http::StatusCode::OK, "{page}");
        }
    }
}

/// A write that did not come through the interface shows in the `next`
/// rows the next call serves: they are read on every call.
#[tokio::test(flavor = "multi_thread")]
async fn the_next_rows_follow_a_write_made_beside_the_interface() {
    let (app, plane, _dir) = common::app_on("fin").await;
    say(&app, FIN, "CREATE TABLE fin.ledger AS SELECT 1 AS amount").await;
    let next_line = |body: &Value| -> String {
        window(body)
            .lines()
            .find(|l| l.starts_with("next:"))
            .unwrap_or_else(|| panic!("{body}"))
            .to_string()
    };
    // twice the same call, nothing written between: the same line
    let first = tool(&app, FIN, "SELECT 1 AS x").await;
    let again = tool(&app, FIN, "SELECT 1 AS x").await;
    assert!(next_line(&first).contains("integrate 1"), "{first}");
    assert_eq!(next_line(&first), next_line(&again));
    // a view defined on the engine's own channel, beside the interface
    let session = plane
        .channel(common::human(), Some("fin"))
        .await
        .expect("a channel on fin");
    session
        .execute(
            r#"GLOSS ledger_rows ON fin AS $${"kind": "value", "sql": "SELECT count(*) AS value FROM fin.ledger"}$$;"#,
        )
        .await
        .expect("the view is defined");
    let after = tool(&app, FIN, "SELECT 1 AS x").await;
    assert!(!next_line(&after).contains("integrate"), "{after}");
}
