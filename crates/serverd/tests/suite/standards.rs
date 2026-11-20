//! The two standard exports, read over the agent interface and
//! validated against the standards' schemas pinned in
//! `tests/fixtures/standards`: `semantic_model()` against Apache Ossie,
//! `lineage_events()` against OpenLineage's run event with the column
//! lineage facet.

use std::path::{Path, PathBuf};

use boon::{Compiler, SchemaIndex, Schemas};
use serde_json::Value;

use crate::common::{self, rows, say};

const FIN: &str = "/fin/mcp";
const RUN_EVENT: &str = "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent";
const COLUMN_LINEAGE: &str = "https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json#/$defs/ColumnLineageDatasetFacet";
const OSSIE: &str = "https://github.com/apache/ossie/core-spec/ossie-schema.json";

fn fixture(name: &str) -> Value {
    let path: PathBuf = [env!("CARGO_MANIFEST_DIR"), "tests/fixtures/standards", name]
        .iter()
        .collect();
    serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap()
}

/// The pinned schemas, each under its own `$id`: no schema is fetched.
fn schemas() -> (Schemas, SchemaIndex, SchemaIndex, SchemaIndex) {
    let mut compiler = Compiler::new();
    for name in [
        "ossie-schema.json",
        "OpenLineage.json",
        "ColumnLineageDatasetFacet.json",
    ] {
        let schema = fixture(name);
        let id = schema["$id"].as_str().unwrap().to_string();
        compiler.add_resource(&id, schema).unwrap();
    }
    let mut schemas = Schemas::new();
    let ossie = compiler.compile(OSSIE, &mut schemas).unwrap();
    let run_event = compiler.compile(RUN_EVENT, &mut schemas).unwrap();
    let column_lineage = compiler.compile(COLUMN_LINEAGE, &mut schemas).unwrap();
    (schemas, ossie, run_event, column_lineage)
}

fn json(row: &Value, column: &str) -> Value {
    match &row[column] {
        Value::String(text) => serde_json::from_str(text).unwrap(),
        value => value.clone(),
    }
}

/// A dataset with two loaded tables, a metric, a table view over both
/// and a relationship between the tables.
async fn fin(dir: &Path) -> common::Served {
    let served = common::app_on("fin").await;
    std::fs::write(
        dir.join("ledger.csv"),
        "booked,amount,fund\n2024-01-03,4,general\n2024-01-20,2,water\n2024-02-05,7,general\n",
    )
    .unwrap();
    std::fs::write(
        dir.join("funds.csv"),
        "fund,label\ngeneral,General fund\nwater,Water fund\n",
    )
    .unwrap();
    say(
        &served.0,
        FIN,
        &format!(
            "DECLARE SOURCE erp SET (type: csv, location: '{}'); \
             DECLARE RECIPE ledger ON fin FROM erp AS $$SELECT CAST(booked AS DATE) AS booked, \
             CAST(amount AS DOUBLE) AS amount, fund FROM read_csv('ledger.csv', all_varchar = true)$$; \
             DECLARE RECIPE funds ON fin FROM erp AS $$SELECT fund, label \
             FROM read_csv('funds.csv', all_varchar = true)$$;",
            dir.display()
        ),
    )
    .await;
    say(
        &served.0,
        FIN,
        r#"GLOSS entity ON fin.funds AS $${"value": "a fund", "grain": ["fund"]}$$;
           DECLARE RELATIONSHIP ledger.fund -> funds.fund;
           DECLARE PROPERTY spend WITH $${"title": "Spend"}$$ AS VIEW;
           GLOSS spend ON fin AS $${"sql": "SELECT date_trunc('month', booked)::DATE AS period, sum(amount) AS value, fund FROM fin.ledger GROUP BY ALL"}$$;
           GLOSS role ON spend.period AS $${"value": "timestamp"}$$;
           GLOSS role ON spend.value AS $${"value": "measure"}$$;
           GLOSS role ON spend.fund AS $${"value": "dimension"}$$;
           GLOSS additivity ON spend.value AS $${"value": "additive"}$$;
           GLOSS unit ON spend.value AS $${"value": "EUR"}$$;
           GLOSS meaning ON fin.spend AS $${"value": "money booked per month"}$$;
           DECLARE PROPERTY ledger_funds WITH $${"title": "Ledger with its fund", "x-kind": "relation"}$$ AS VIEW;
           GLOSS ledger_funds ON fin AS $${"sql": "SELECT l.booked, l.amount, f.label FROM fin.ledger l JOIN fin.funds f ON f.fund = l.fund"}$$;"#,
    )
    .await;
    served
}

/// `semantic_model()` is one Ossie document with zero validation
/// errors, carrying the metric, the relationship and the unit as a
/// non-portable extension; `lineage_events()` is one run event per
/// load and per view, each with zero validation errors, its column
/// lineage facet too.
#[tokio::test(flavor = "multi_thread")]
async fn the_standard_exports_validate_against_their_pinned_schemas() {
    let files = tempfile::tempdir().unwrap();
    let (app, _, _dir) = fin(files.path()).await;
    let (schemas, ossie, run_event, column_lineage) = schemas();

    let model = rows(&app, FIN, "SELECT document FROM semantic_model()").await;
    assert_eq!(model.len(), 1);
    let document = json(&model[0], "document");
    if let Err(error) = schemas.validate(&document, ossie) {
        panic!("semantic_model(): {error:#}\n{document:#}");
    }
    let spend = document["datasets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["name"] == "spend")
        .unwrap_or_else(|| panic!("{document:#}"));
    assert_eq!(spend["metrics"][0]["name"], "spend");
    let value = spend["fields"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["name"] == "value")
        .unwrap();
    assert_eq!(value["nonportable_extensions"][0]["data"]["unit"], "EUR");
    assert_eq!(document["relationships"][0]["from"], "ledger");

    let events = rows(&app, FIN, "SELECT event FROM lineage_events()").await;
    let jobs: Vec<String> = events
        .iter()
        .map(|row| {
            json(row, "event")["job"]["name"]
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect();
    for job in [
        "load.fin.ledger",
        "load.fin.funds",
        "view.fin.spend",
        "view.fin.ledger_funds",
    ] {
        assert!(jobs.contains(&job.to_string()), "{jobs:?}");
    }
    for row in &events {
        let event = json(row, "event");
        if let Err(error) = schemas.validate(&event, run_event) {
            panic!("lineage_events(): {error:#}\n{event:#}");
        }
        for output in event["outputs"].as_array().unwrap() {
            let facet = &output["facets"]["columnLineage"];
            if let Err(error) = schemas.validate(facet, column_lineage) {
                panic!("column lineage: {error:#}\n{facet:#}");
            }
        }
    }
}
