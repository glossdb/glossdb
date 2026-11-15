//! The lines on every result: where the call left the agent, on its
//! last outcome (`status:`), and, where the call is on a dataset, what
//! is open on it (`next:`): what must and what should be done, a count
//! per kind of work, and the first of them (`first:`) with a link into
//! `next://` and the `next` read. What could be done is not counted. A call
//! that reads `metric_series()` adds `window:`. The lines are context:
//! the skills say how, the catalog says what is open, and the agent
//! decides.

use serde_json::Value;

/// The `status:` line: refused, with the refusal's first line, or
/// done — and for a view's definition what its summary row said.
pub fn situation(refusal: Option<&str>, outcome: Option<&Value>) -> String {
    if let Some(text) = refusal {
        let first = text.lines().next().unwrap_or(text);
        return format!("status: refused — {first}");
    }
    // a definition's summary row, never another read that names a view:
    // a metric's row says whether a series is served (`applicable`), a
    // table's and a single value's row has no such field
    let Some(fact) = outcome.filter(|o| {
        o.get("view").is_some()
            && (o.get("applicable").is_some() || o.get("profile_current").is_some())
    }) else {
        return "status: done".to_string();
    };
    let list = |field: &str| -> String {
        fact.get(field)
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default()
    };
    let view = fact.get("view").and_then(Value::as_str).unwrap_or("");
    let kind = fact.get("kind").and_then(Value::as_str).unwrap_or("");
    let reason = fact.get("reason").and_then(Value::as_str).unwrap_or("");
    let first = reason.split(". ").next().unwrap_or(reason);
    let mut line = format!("status: done — {view}: ");
    if matches!(kind, "relation" | "scalar") {
        // A table and a single value have no series to wait for: the
        // view can be read once it is defined. A reason is there only
        // where it is stopped or its definition serves no view.
        if !first.is_empty() {
            line.push_str(first);
        } else if kind == "relation" {
            line.push_str(&format!("defined as a table; read it FROM {view}"));
        } else {
            line.push_str(&format!(
                "defined as a single value; read it FROM {view} or with fact_values()"
            ));
        }
    } else if fact.get("applicable") == Some(&Value::Bool(true)) {
        // served, and by which columns it slices; then only what is
        // left to say: a served column with no role, a profile not run
        let dims = list("dims");
        line.push_str("served");
        if !dims.is_empty() {
            line.push_str(&format!(", sliced by {dims}"));
        }
        let without_role = list("columns_without_role");
        if !without_role.is_empty() {
            line.push_str(&format!("; columns without a role: {without_role}"));
        }
        let to_run = list("measurements_to_run");
        if !to_run.is_empty() {
            line.push_str(&format!("; still to run: {to_run}"));
        }
    } else {
        line.push_str(&format!("no series yet — {first}"));
    }
    line
}

/// The `window:` line, on a call that reads `metric_series()`: the
/// read serves each metric's newest periods and not its history, which
/// its rows alone do not show.
pub fn series_window(statements: &str) -> Option<&'static str> {
    statements
        .to_ascii_lowercase()
        .contains("metric_series(")
        .then_some(
            "window: metric_series() serves the newest periods of each metric, not its whole \
             history. view_summary() has the count per metric as window_periods; time_grains \
             \"windows\" on the period column sets it.",
        )
}

fn field(row: &Value, name: &str) -> String {
    row.get(name)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

/// The kinds of work a row of `next` is labelled with (its `kind`
/// column). They are labels, not stages: the list is ordered by level,
/// and this order is only the order of the counts.
const KINDS: [&str; 4] = ["integrate", "describe", "test", "review"];

/// The levels the `next:` line counts, in the list's order. `could` is
/// read on request and not counted.
const COUNTED: [&str; 2] = ["must", "should"];

/// The `next:` line: per level, must then should, how many rows are
/// open for the agent per kind of work; `must 0` says the work on the
/// dataset is complete. Then the first of them (the view orders by
/// level), with the link to the page of its kind. What waits for a
/// person closes the line and never counts as the agent's.
pub fn next_line(dataset: &str, rows: &[Value]) -> String {
    let counted: Vec<&Value> = rows
        .iter()
        .filter(|r| COUNTED.contains(&field(r, "level").as_str()))
        .collect();
    let mine: Vec<&Value> = counted
        .iter()
        .copied()
        .filter(|r| field(r, "who") != "person")
        .collect();
    let waiting = counted.len() - mine.len();
    let mut parts: Vec<String> = COUNTED
        .iter()
        .map(|level| {
            let kinds: Vec<String> = KINDS
                .iter()
                .filter_map(|kind| {
                    let n = mine
                        .iter()
                        .filter(|r| field(r, "level") == *level && field(r, "kind") == *kind)
                        .count();
                    (n > 0).then(|| format!("{kind} {n}"))
                })
                .collect();
            if kinds.is_empty() {
                format!("{level} 0")
            } else {
                format!("{level} {}", kinds.join(", "))
            }
        })
        .collect();
    if waiting > 0 {
        parts.push(format!("waiting for a person {waiting}"));
    }
    let mut line = format!("next: {}", parts.join(" · "));
    if let Some(first) = mine.first() {
        let kind = field(first, "kind");
        line.push_str(&format!(
            "\nfirst: {} {kind} {} ({}): {} (next://{dataset}/{kind})",
            field(first, "level"),
            field(first, "asset"),
            field(first, "state"),
            field(first, "open")
        ));
    }
    line
}

/// The `next://<dataset>[/<kind>]` page: every open row in the list's
/// own order (by level), labelled with its level and its kind of work,
/// with its cause and the statement that opens the work.
pub fn next_page(dataset: &str, rows: &[Value]) -> String {
    let mut out = format!("# next on {dataset}\n\n");
    if rows.is_empty() {
        out.push_str("Nothing is open.\n");
    }
    for row in rows {
        out.push_str(&format!(
            "**{}**, {} {} ({}): {}\n",
            field(row, "asset"),
            field(row, "level"),
            field(row, "kind"),
            field(row, "state"),
            field(row, "open")
        ));
        let views = field(row, "for_view");
        if !views.is_empty() {
            out.push_str(&format!("\nread by: {views}\n"));
        }
        let cause = field(row, "cause");
        if !cause.is_empty() {
            out.push_str(&format!("\ncause: {cause}\n"));
        }
        let statement = field(row, "statement");
        if !statement.is_empty() {
            out.push_str(&format!("\n```glossql\n{statement}\n```\n"));
        }
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::series_window;

    /// The window line is on a call that reads the series, and on no other.
    #[test]
    fn the_window_line_is_on_a_read_of_the_series_only() {
        let line = series_window("USE fin; SELECT * FROM metric_series(grain := 'month')");
        assert!(line.is_some_and(|l| l.starts_with("window: ")));
        assert!(series_window("USE fin; SELECT * FROM view_summary()").is_none());
    }
}
