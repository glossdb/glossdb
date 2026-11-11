//! The lines on every result: where the call left the agent, on its
//! last outcome (`status:`), and, where the call is on a dataset, what
//! is open on it (`next:`), a count per step, and the first open row
//! (`first:`) with a link into `next://` and the `next` read. A call
//! that reads `metric_series()` adds `window:`. The lines are context:
//! the skills say how, the catalog says what is open, and the agent
//! decides.

use serde_json::Value;

/// The `status:` line: refused, with the refusal's first line, or
/// loaded — and for a metric definition what its fact row said.
pub fn situation(refusal: Option<&str>, outcome: Option<&Value>) -> String {
    if let Some(text) = refusal {
        let first = text.lines().next().unwrap_or(text);
        return format!("status: refused — {first}");
    }
    // a definition's summary row, never another read that names a metric
    let Some(fact) = outcome.filter(|o| o.get("view").is_some() && o.get("applicable").is_some())
    else {
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
    let mut line = format!("status: done — {view}: ");
    // A re-record says first what it changed against the writing it
    // supersedes — the totals over their shared periods: the line is
    // read left to right, and a moved total unsays the axes after it.
    if let Some(drift) = fact
        .get("superseded_divergence")
        .and_then(Value::as_str)
        .filter(|d| !d.is_empty())
    {
        line.push_str(&format!("{drift}; "));
    }
    if fact.get("applicable") == Some(&Value::Bool(true)) {
        // The metric definition's word on its axes, where it spoke: what the
        // list closed and what a gloss would have
        // admitted, or that the empty list did not hold.
        let word = match fact.get("axes_basis").and_then(Value::as_str) {
            Some("authored") => {
                let closed = tagged(fact, &["closed", "closed over gloss"]);
                let by_gloss = tagged(fact, &["closed over gloss"]);
                let mut word = String::from(" (as the definition says");
                if !closed.is_empty() {
                    word.push_str(&format!(" — closes {}", closed.join(", ")));
                }
                if !by_gloss.is_empty() {
                    word.push_str(&format!("; an annotation admits {}", by_gloss.join(", ")));
                }
                word.push(')');
                word
            }
            Some("measured over authored") => format!(
                " (measured over the definition's empty list — a {} keeps its results; the empty \
                 list closes a distinct count or a ratio)",
                fact.get("additivity")
                    .and_then(Value::as_str)
                    .unwrap_or("additive")
            ),
            _ => String::new(),
        };
        // served, and by which columns it slices; then only what is
        // left to say: a served column with no role, a profile not run
        let dims = list("dims");
        line.push_str("served");
        if !dims.is_empty() {
            line.push_str(&format!(", sliced by {dims}"));
        }
        line.push_str(&word);
        let without_role = list("columns_without_role");
        if !without_role.is_empty() {
            line.push_str(&format!("; columns without a role: {without_role}"));
        }
        let to_run = list("measurements_to_run");
        if !to_run.is_empty() {
            line.push_str(&format!("; still to run: {to_run}"));
        }
    } else {
        let reason = fact.get("reason").and_then(Value::as_str).unwrap_or("");
        let first = reason.split(". ").next().unwrap_or(reason);
        // A table and a single value are served as they are, and their
        // row says how to read them; only a metric has a series to wait for.
        let kind = fact.get("kind").and_then(Value::as_str).unwrap_or("");
        if matches!(kind, "relation" | "scalar") {
            line.push_str(first);
        } else {
            line.push_str(&format!("no series yet — {first}"));
        }
    }
    line
}

/// The columns without a role of a summary row whose act is one of `tags`,
/// in the row's order.
fn tagged(fact: &Value, tags: &[&str]) -> Vec<String> {
    let columns = fact.get("columns_without_role").and_then(Value::as_array);
    let acts = fact.get("unadmitted_act").and_then(Value::as_array);
    let (Some(columns), Some(acts)) = (columns, acts) else {
        return Vec::new();
    };
    columns
        .iter()
        .zip(acts.iter())
        .filter(|(_, act)| act.as_str().is_some_and(|t| tags.contains(&t)))
        .filter_map(|(column, _)| column.as_str().map(str::to_string))
        .collect()
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

/// The steps of the work, in order.
const STEPS: [&str; 5] = ["connect", "describe", "test", "decide", "serve"];

/// The `next:` line: how many rows are open for the agent per step,
/// then the first row of the list (the view orders by priority), with
/// the link to its step's page. What waits for a person closes the
/// line and never counts as the agent's.
pub fn next_line(dataset: &str, rows: &[Value]) -> String {
    let mine: Vec<&Value> = rows
        .iter()
        .filter(|r| field(r, "who") != "person")
        .collect();
    let waiting = rows.len() - mine.len();
    let mut parts: Vec<String> = STEPS
        .iter()
        .filter_map(|step| {
            let n = mine.iter().filter(|r| field(r, "step") == *step).count();
            (n > 0).then(|| format!("{step} {n}"))
        })
        .collect();
    if parts.is_empty() {
        parts.push("nothing open".to_string());
    }
    if waiting > 0 {
        parts.push(format!("waiting for a person {waiting}"));
    }
    let mut line = format!("next: {}", parts.join(" · "));
    if let Some(first) = mine.first() {
        let step = field(first, "step");
        line.push_str(&format!(
            "\nfirst: {step} {} ({}): {} (next://{dataset}/{step})",
            field(first, "asset"),
            field(first, "state"),
            field(first, "open")
        ));
    }
    line
}

/// The `next://<dataset>[/<step>]` page: every open row with its
/// cause and the statement that opens the work.
pub fn next_page(dataset: &str, rows: &[Value]) -> String {
    let mut out = format!("# next on {dataset}\n\n");
    if rows.is_empty() {
        out.push_str("Nothing is open.\n");
    }
    for step in STEPS {
        let of_step: Vec<&Value> = rows.iter().filter(|r| field(r, "step") == step).collect();
        if of_step.is_empty() {
            continue;
        }
        out.push_str(&format!("## {step}\n\n"));
        for row in of_step {
            out.push_str(&format!(
                "**{}** ({}): {}\n",
                field(row, "asset"),
                field(row, "state"),
                field(row, "open")
            ));
            let metrics = field(row, "for_view");
            if !metrics.is_empty() {
                out.push_str(&format!("\nread by: {metrics}\n"));
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
