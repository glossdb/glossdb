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
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
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
/// and the completeness test turns red with no statement either.
#[tokio::test(flavor = "multi_thread")]
async fn the_server_runs_a_table_views_tests_after_each_write() {
    let (app, _, _dir) = fin().await;
    say(
        &app,
        FIN,
        r#"CREATE TABLE fin.funds AS SELECT unnest(['general', 'water']) AS fund, 'a fund' AS label;
           DECLARE ASPECT ledger_funds WITH $${"title": "Ledger with its fund", "x-kind": "relation"}$$ AS VIEW;
           GLOSS ledger_funds ON fin AS $${"sql": "SELECT l.booked, l.amount, f.label FROM fin.ledger l JOIN fin.funds f ON f.fund = l.fund"}$$;"#,
    )
    .await;
    let computed = async |function: &str| {
        rows(
            &app,
            FIN,
            &format!(
                "SELECT subject FROM measurements WHERE function = '{function}' ORDER BY subject"
            ),
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
        "SELECT test, state FROM view_tests() WHERE view = 'ledger_funds' ORDER BY test",
    )
    .await;
    let states: Vec<(String, String)> = tests
        .iter()
        .map(|r| (text(r, "test"), text(r, "state")))
        .collect();
    assert_eq!(
        states,
        [
            ("completeness_test".to_string(), "green".to_string()),
            ("join_test".to_string(), "green".to_string()),
            ("orphan_test".to_string(), "red".to_string())
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
        "SELECT state, current, evidence->'columns'->0->>'column' AS col, evidence->'columns'->0->>'cause' AS cause \
         FROM view_tests() WHERE view = 'ledger_funds' AND test = 'completeness_test'",
    )
    .await;
    assert_eq!(emptied.len(), 1, "{emptied:?}");
    assert_eq!(text(&emptied[0], "state"), "red");
    assert_eq!(emptied[0]["current"].as_bool(), Some(true));
    assert_eq!(text(&emptied[0], "col"), "label");
    assert_eq!(text(&emptied[0], "cause"), "load");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_next_page_carries_the_test_and_its_statement() {
    let (app, _, _dir) = fin().await;
    say(&app, FIN,
        r#"DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;"#,
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

#[tokio::test(flavor = "multi_thread")]
async fn a_definition_that_names_its_columns_is_served_in_one_statement() {
    let (app, _, _dir) = fin().await;
    // The definition says which column is the time, which the measure
    // and how it adds up, and which slice it: the server writes the
    // column annotations, profiles the time column and runs the tests.
    let outcomes = say(&app, FIN,
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

/// The server reconciles a target table view with a contract after
/// each load, with no statement by the agent: the rows its branch
/// reads and serves. A view without a contract gets no reconciliation.
#[tokio::test(flavor = "multi_thread")]
async fn the_server_reconciles_a_contracted_view_after_each_load() {
    let (app, _, dir) = fin().await;
    let file = dir.path().join("stock.csv");
    std::fs::write(&file, "item,qty,status\nA,1,D\nB,2,K\n").unwrap();
    say(
        &app,
        FIN,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); \
             DECLARE RECIPE stock ON fin FROM erp AS $$SELECT item, CAST(qty AS DOUBLE) AS qty, status \
             FROM read_csv('stock.csv', all_varchar = true)$$;",
            dir.path().display()
        ),
    )
    .await;
    say(
        &app,
        FIN,
        r#"DECLARE ASPECT free_stock WITH $${"title": "Free stock", "x-kind": "relation"}$$ AS VIEW;
           GLOSS free_stock ON fin AS $${"sql": "SELECT s.item, s.qty FROM fin.stock s WHERE s.status = 'D'"}$$;
           DECLARE ASPECT all_stock WITH $${"title": "All stock", "x-kind": "relation"}$$ AS VIEW;
           GLOSS all_stock ON fin AS $${"sql": "SELECT s.item, s.qty FROM fin.stock s"}$$;
           GLOSS contract ON fin.free_stock.item AS $${"type": "VARCHAR", "required": true}$$;"#,
    )
    .await;
    let reconciled = async || {
        rows(
            &app,
            FIN,
            "SELECT subject, (value->'rows'->0->>'read')::INT AS read, \
             (value->'rows'->0->>'reached')::INT AS reached \
             FROM measurements WHERE function = 'reconciliation' ORDER BY subject",
        )
        .await
    };
    let first = reconciled().await;
    assert_eq!(first.len(), 1, "{first:?}");
    assert_eq!(text(&first[0], "subject"), "fin.free_stock");
    assert_eq!(
        (&first[0]["read"], &first[0]["reached"]),
        (&json!(2), &json!(1))
    );

    std::fs::write(&file, "item,qty,status\nA,1,D\nB,2,K\nC,3,D\n").unwrap();
    say(&app, FIN, "IMPORT stock;").await;
    let after = reconciled().await;
    assert_eq!(after.len(), 1, "{after:?}");
    assert_eq!(
        (&after[0]["read"], &after[0]["reached"]),
        (&json!(3), &json!(2))
    );
    let due = rows(&app, FIN, "SELECT run FROM results_due()").await;
    assert!(due.is_empty(), "{due:?}");
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
        r#"DECLARE ASPECT booked_rows WITH $${"title": "Booked rows", "x-kind": "relation"}$$ AS VIEW;
           GLOSS booked_rows ON fin AS $${"sql": "SELECT booked, amount FROM fin.bookings"}$$;"#,
    )
    .await;
    let lineage = async || {
        rows(
            &app,
            FIN,
            "SELECT begin_snapshot, changed_at FROM measurements \
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

/// The rows of `next` under "describe" for the bookings table.
async fn bookings_rows(app: &Router) -> Vec<Value> {
    rows(
        app,
        FIN,
        "SELECT state, cause FROM next WHERE kind = 'describe' AND asset = 'fin.bookings' ORDER BY state",
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
    say(&app, FIN,
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
        FIN,
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
        FIN,
        "SELECT rows FROM imports_history WHERE table_name = 'bookings' ORDER BY begin_snapshot",
    )
    .await;
    let counts: Vec<&Value> = loads.iter().map(|r| &r["rows"]).collect();
    assert_eq!(counts, [&json!(3), &json!(4)], "{loads:?}");
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
           DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;
           SELECT level, kind, who FROM next"#,
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    let outcomes = common::outcomes(&body);
    let listed = outcomes[3]["rows"].as_array().unwrap();
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

/// The plan, the harmonise and the outlook kits are pull-ins: a server
/// that leaves out all three, or the outlook kit alone, serves `next`,
/// `view_tests()`, `column_mapping()` and the console, the preview tiles
/// and frames empty, and for a dataset with no stored preview or plan
/// result it serves the same `next`, the same tests and the same column
/// mapping as a server with all of them.
#[tokio::test(flavor = "multi_thread")]
async fn a_server_without_the_plan_the_harmonise_or_the_outlook_kit_serves_next_the_tests_and_the_console()
 {
    let build = r#"CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked,
                     (i % 7 + 1)::DOUBLE AS amount, ['general', 'water', 'parks'][i % 3 + 1] AS fund FROM range(120) r(i);
                   DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
                   GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}, "dimensions": ["fund"]}$$;
                   DECLARE ASPECT spend_budget WITH $${"title": "Spend budget", "x-kind": "plan", "x-plan-of": "spend"}$$ AS VIEW;
                   GLOSS spend_budget ON fin AS $${"sql": "SELECT period, value * 1.1 AS value FROM fin.spend"}$$;"#;
    let next = "SELECT level, kind, asset, state, who, open, statement FROM next";
    let tests = "SELECT view, test, subject, state, current, run FROM view_tests() ORDER BY ALL";
    let (with, _, _with_dir) = common::app_on("fin").await;
    say(&with, FIN, build).await;
    let (neither, _, _neither_dir) =
        common::app_on_without("fin", &["plan", "harmonise", "outlook"]).await;
    say(&neither, FIN, build).await;
    let (plan_alone, _, _plan_dir) = common::app_on_without("fin", &["outlook"]).await;
    say(&plan_alone, FIN, build).await;
    let served_next = rows(&with, FIN, next).await;
    let served_tests = rows(&with, FIN, tests).await;
    assert!(!served_tests.is_empty());
    let mapping = "SELECT view, target_column, branch, source_table, source_column FROM column_mapping() ORDER BY ALL";
    let served_mapping = rows(&with, FIN, mapping).await;
    assert!(!served_mapping.is_empty());
    for app in [&neither, &plan_alone] {
        assert_eq!(rows(app, FIN, next).await, served_next);
        assert_eq!(rows(app, FIN, tests).await, served_tests);
        assert_eq!(rows(app, FIN, mapping).await, served_mapping);
        let closing = window(&tool(app, FIN, "SELECT 1 AS one").await);
        assert!(closing.contains("next: must 0"), "{closing}");
        for page in [
            "/fin/app/console",
            "/fin/app/console/p/quality",
            "/fin/app/console/p/views?view=spend&tab=measurements",
            "/fin/app/console/frames/next_rows",
            "/fin/app/console/frames/functions",
            "/fin/app/console/frames/front",
            "/fin/app/console/frames/view_tests",
            "/fin/app/console/frames/trend?view=spend&grain=month&span=24",
            "/fin/app/console/frames/breaches",
            "/fin/app/console/frames/test_points?test=range_test",
            "/fin/app/console/frames/corridor?view=spend",
            "/fin/app/console/frames/movers?view=spend",
            "/fin/app/console/frames/plan?view=spend",
        ] {
            let response = common::get(app, page).await;
            assert_eq!(response.status(), axum::http::StatusCode::OK, "{page}");
        }
    }
    // the plan against the actual where the plan kit is loaded, nothing
    // where it is not
    let plan = "SELECT plan FROM plan_points()";
    assert!(rows(&plan_alone, FIN, plan).await.len() > 1);
    assert!(rows(&neither, FIN, plan).await.is_empty());
}

/// The interface keeps a dataset's `next` rows while the lake's snapshot
/// holds. A write that did not come through the interface takes a
/// snapshot too, so the rows the next call serves are read again.
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
            r#"DECLARE ASPECT ledger_rows WITH $${"title": "Ledger rows", "x-kind": "scalar"}$$ AS VIEW;
               GLOSS ledger_rows ON fin AS $${"sql": "SELECT count(*) AS value FROM fin.ledger"}$$;"#,
        )
        .await
        .expect("the view is defined");
    let after = tool(&app, FIN, "SELECT 1 AS x").await;
    assert!(!next_line(&after).contains("integrate"), "{after}");
}
