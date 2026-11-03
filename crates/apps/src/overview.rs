//! What the workspace root reads: a few counts over the record's own
//! relations, rendered on the server. The root is not an app — no
//! frames, no params, one visit — so the rows come through the same
//! channel a frame would use and land in the template as JSON.

use crate::engine::{Actor, ActorKind};
use futures::StreamExt;
use serde_json::Value;

use crate::AppDoor;

pub(crate) const DATASETS: &str = "SELECT name, \
       coalesce(json_extract_string(settings, '$.purpose'), '') AS purpose \
     FROM datasets ORDER BY name";

/// A dataset at a glance: what has landed, what is served, what waits
/// on a person. Bound to the dataset; `current_dataset` narrows the
/// workspace-wide relations.
pub(crate) const COUNTS: &str = "WITH latest AS ( \
       SELECT i.table_name, i.rows, i.imported_at, \
              row_number() OVER (PARTITION BY i.table_name ORDER BY i.imported_at DESC, i.seq DESC) AS rn \
       FROM imports i JOIN current_dataset d ON d.dataset = i.dataset) \
     SELECT \
       (SELECT count(*) FROM latest WHERE rn = 1) AS tables, \
       (SELECT coalesce(sum(CAST(rows AS BIGINT)), 0) FROM latest WHERE rn = 1) AS rows, \
       (SELECT coalesce(max(imported_at)::VARCHAR, '') FROM latest) AS landed, \
       (SELECT count(*) FROM metric_surfaces WHERE grounded AND stopped = '') AS served, \
       (SELECT count(*) FROM metric_surfaces WHERE stopped <> '') AS stopped, \
       (SELECT count(*) FROM open_questions q \
        JOIN current_dataset d ON d.dataset = q.dataset) AS open";

/// The reader: human standing like every frame.
fn reader() -> Actor {
    Actor {
        kind: ActorKind::Human,
        id: "app:workspace".into(),
    }
}

/// One read as JSON rows — every column by name, numbers as numbers.
/// A read that fails answers with its text; the page prints it in the
/// band it was for, the way a frame error lands in its tile.
pub(crate) async fn rows(
    door: &AppDoor,
    dataset: Option<&str>,
    sql: &str,
    params: &[(&str, &str)],
) -> Result<Vec<Value>, String> {
    let session = door
        .plane
        .channel(reader(), dataset)
        .await
        .map_err(|e| e.to_string())?;
    let pairs: Vec<(String, String)> = params
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    let query = crate::query_with(&session, sql, pairs)
        .await
        .map_err(|e| e.to_string())?;
    let mut stream = query.stream;
    let mut writer = arrow_json::ArrayWriter::new(Vec::new());
    while let Some(batch) = stream.next().await {
        let batch = batch.map_err(|e| e.to_string())?;
        writer.write(&batch).map_err(|e| e.to_string())?;
    }
    writer.finish().map_err(|e| e.to_string())?;
    let bytes = writer.into_inner();
    // No batch at all leaves the writer silent rather than at `[]`.
    if bytes.is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_slice(&bytes).map_err(|e| e.to_string())
}

/// Digits grouped for reading (`412,338`), beside each named integer
/// field as `<field>_txt` — tera has no grouping filter, and the
/// template should place numbers, not format them.
pub(crate) fn grouped(rows: &mut [Value], fields: &[&str]) {
    for row in rows.iter_mut() {
        let Some(map) = row.as_object_mut() else {
            continue;
        };
        for field in fields {
            let text = map
                .get(*field)
                .and_then(Value::as_i64)
                .map(group_digits)
                .unwrap_or_default();
            map.insert(format!("{field}_txt"), Value::String(text));
        }
    }
}

fn group_digits(n: i64) -> String {
    let digits = n.unsigned_abs().to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3 + 1);
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    if n < 0 {
        out.insert(0, '-');
    }
    out
}

/// `2026-09-04T14:10:03.512Z` read as `2026-09-04 14:10`: the minute
/// is what a landing time is for on a page.
pub(crate) fn minute(rows: &mut [Value], field: &str) {
    for row in rows.iter_mut() {
        let Some(map) = row.as_object_mut() else {
            continue;
        };
        let text = map
            .get(field)
            .and_then(Value::as_str)
            .map(|s| s.chars().take(16).collect::<String>().replace('T', " "))
            .unwrap_or_default();
        map.insert(format!("{field}_txt"), Value::String(text));
    }
}
