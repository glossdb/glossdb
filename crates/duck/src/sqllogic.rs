//! The kits' suites on the engine. A suite is DuckDB's sqllogictest
//! form in the four directives the kits' suites use: `statement ok`;
//! `statement error`, with the text the refusal carries after `----`;
//! `query <types>`, with its rows after `----` (one per line, cells
//! tab-separated, `NULL` and `(empty)` as DuckDB's own runner spells
//! them, an `R` cell equal within one percent); and `require
//! <extension>`, which holds for one the engine loads at open and
//! fails for any other, so nothing is skipped. The engine is the
//! server's own instance before the lake: a suite attaches its lake
//! and loads the kits it tests. In the text, `{TEST_DIR}` is a
//! directory of the suite's own, `{GLOSS_KITS}` the extension's kits
//! and `{KITS}` this repository's.

use std::path::Path;

use duckdb_neo::connection::Connection;

use crate::{Config, arrow_batches, engine_instance, pieces, rows_as_text, run};

/// The extensions the engine loads at open.
const LOADED: &[&str] = &["gloss", "json", "parquet", "ducklake"];

enum Record {
    Require(String),
    Statement {
        ok: bool,
        sql: String,
        carries: Option<String>,
    },
    Query {
        types: String,
        sql: String,
        rows: Vec<String>,
    },
}

/// Run one suite to its end or its first failure, which the error
/// names with the suite's path and line. Ok carries the records run.
pub fn run_suite(suite: &Path, test_dir: &Path) -> Result<usize, String> {
    let at = |why: String| format!("{}: {why}", suite.display());
    let pieces = pieces();
    let text = std::fs::read_to_string(suite)
        .map_err(|e| at(e.to_string()))?
        .replace("{TEST_DIR}", &test_dir.display().to_string())
        .replace("{GLOSS_KITS}", &pieces.gloss_kits.display().to_string())
        .replace("{KITS}", &pieces.kits.display().to_string());
    let records = parse(&text).map_err(at)?;
    let config = Config::laptop(test_dir);
    let (_environment, _instance, conn) =
        engine_instance(&config).map_err(|e| at(e.to_string()))?;
    run(&conn, "SET active_grammar_extensions = ['gloss']").map_err(|e| at(e.to_string()))?;
    for (line, record) in &records {
        check(&conn, record).map_err(|why| format!("{}:{line}: {why}", suite.display()))?;
    }
    Ok(records.len())
}

/// The records with the line each starts on. A record is a directive
/// line and the lines to the next blank one; `----` separates a
/// statement from what it answers.
fn parse(text: &str) -> Result<Vec<(usize, Record)>, String> {
    let lines: Vec<&str> = text.lines().collect();
    let mut records = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        let directive = lines[i].trim();
        i += 1;
        if directive.is_empty() || directive.starts_with('#') {
            continue;
        }
        let at = i;
        let (mut sql, mut answer, mut answering) = (Vec::new(), Vec::new(), false);
        while i < lines.len() && !lines[i].trim().is_empty() {
            match (lines[i], answering) {
                ("----", false) => answering = true,
                (line, true) => answer.push(line.to_string()),
                (line, false) => sql.push(line),
            }
            i += 1;
        }
        let sql = sql.join("\n");
        let record = if let Some(name) = directive.strip_prefix("require ") {
            Record::Require(name.trim().to_string())
        } else if directive == "statement ok" {
            Record::Statement {
                ok: true,
                sql,
                carries: None,
            }
        } else if directive == "statement error" {
            let carries = (!answer.is_empty()).then(|| answer.join("\n"));
            Record::Statement {
                ok: false,
                sql,
                carries,
            }
        } else if let Some(rest) = directive.strip_prefix("query ") {
            let mut words = rest.split_whitespace();
            let types = words.next().unwrap_or_default().to_string();
            if let Some(extra) = words.next() {
                return Err(format!(
                    "line {at}: query {types} {extra}: a sort mode or label this runner does not take"
                ));
            }
            Record::Query {
                types,
                sql,
                rows: answer,
            }
        } else {
            return Err(format!(
                "line {at}: {directive}: a directive this runner does not take"
            ));
        };
        records.push((at, record));
    }
    Ok(records)
}

fn check(conn: &Connection, record: &Record) -> Result<(), String> {
    match record {
        Record::Require(name) if LOADED.contains(&name.as_str()) => Ok(()),
        Record::Require(name) => Err(format!("require {name}: not an extension the engine loads")),
        Record::Statement { ok: true, sql, .. } => run(conn, sql).map_err(|e| e.to_string()),
        Record::Statement { sql, carries, .. } => match run(conn, sql) {
            Ok(()) => Err(format!("ran, a refusal expected: {}", first_line(sql))),
            Err(e) => match carries {
                Some(text) if !e.to_string().contains(text.as_str()) => {
                    Err(format!("the refusal does not carry {text:?}: {e}"))
                }
                _ => Ok(()),
            },
        },
        Record::Query { types, sql, rows } => compare(types, rows, &answer(conn, sql)?),
    }
}

fn first_line(sql: &str) -> &str {
    sql.lines().next().unwrap_or_default()
}

/// A query's rows as the engine spells them: every column cast to
/// VARCHAR by the engine itself, so a number, a date or a list reads
/// as DuckDB's runner would read it; a statement the cast cannot wrap
/// runs as it is and is spelled by Arrow.
fn answer(conn: &Connection, sql: &str) -> Result<Vec<Vec<String>>, String> {
    let inner = sql.trim().trim_end_matches(';');
    let wrapped = format!("SELECT COLUMNS(*)::VARCHAR FROM ({inner}) AS suite_");
    let batches = match arrow_batches(conn, &wrapped, &[]) {
        Ok((_, _, batches)) => batches,
        Err(_) => arrow_batches(conn, sql, &[]).map_err(|e| e.to_string())?.2,
    };
    Ok(rows_as_text(&batches)
        .into_iter()
        .map(|row| {
            row.into_iter()
                .map(|cell| match cell {
                    None => "NULL".to_string(),
                    Some(s) if s.is_empty() => "(empty)".to_string(),
                    Some(s) => s,
                })
                .collect()
        })
        .collect())
}

fn compare(types: &str, expected: &[String], served: &[Vec<String>]) -> Result<(), String> {
    let cols = types.len();
    let expected = expected_rows(expected, cols, served.len());
    if expected.len() != served.len() {
        return Err(format!(
            "{} rows expected, {} served:\n{}",
            expected.len(),
            served.len(),
            served
                .iter()
                .map(|r| r.join("\t"))
                .collect::<Vec<_>>()
                .join("\n")
        ));
    }
    for (n, (want, have)) in expected.iter().zip(served).enumerate() {
        if want.len() != cols || have.len() != cols {
            return Err(format!(
                "row {}: {cols} cells expected, the suite spells {} and the engine serves {}",
                n + 1,
                want.len(),
                have.len()
            ));
        }
        for ((kind, w), h) in types.chars().zip(want).zip(have) {
            if !cell_equal(kind, w, h) {
                return Err(format!("row {}: expected {want:?}, served {have:?}", n + 1));
            }
        }
    }
    Ok(())
}

/// The expected rows: one per line, cells tab-separated; or one cell
/// per line, when the lines count the served rows times the columns
/// and no line carries a tab.
fn expected_rows(lines: &[String], cols: usize, served: usize) -> Vec<Vec<String>> {
    if cols > 1 && lines.len() == served * cols && lines.iter().all(|l| !l.contains('\t')) {
        return lines.chunks(cols).map(<[String]>::to_vec).collect();
    }
    lines
        .iter()
        .map(|l| l.split('\t').map(str::to_string).collect())
        .collect()
}

fn cell_equal(kind: char, want: &str, have: &str) -> bool {
    if want == have {
        return true;
    }
    if kind == 'R'
        && let (Ok(w), Ok(h)) = (want.parse::<f64>(), have.parse::<f64>())
    {
        return (w - h).abs() <= w.abs() * 0.01;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_records_parse_with_their_lines() {
        let text = "# a comment\n\nrequire gloss\n\nstatement ok\nSELECT 1;\n\nstatement error\nSELECT nothing;\n----\nnothing\n\nquery TR\nSELECT 'a', 1.5\nUNION ALL SELECT 'b', 2;\n----\na\t1.5\nb\t2.0\n";
        let records = parse(text).unwrap();
        let lines: Vec<usize> = records.iter().map(|(l, _)| *l).collect();
        assert_eq!(lines, vec![3, 5, 8, 13]);
        match &records[2].1 {
            Record::Statement { ok, sql, carries } => {
                assert!(!ok);
                assert_eq!(sql, "SELECT nothing;");
                assert_eq!(carries.as_deref(), Some("nothing"));
            }
            _ => panic!("a statement"),
        }
        match &records[3].1 {
            Record::Query { types, sql, rows } => {
                assert_eq!(types, "TR");
                assert_eq!(sql, "SELECT 'a', 1.5\nUNION ALL SELECT 'b', 2;");
                assert_eq!(rows, &["a\t1.5".to_string(), "b\t2.0".to_string()]);
            }
            _ => panic!("a query"),
        }
        assert!(parse("query TT rowsort\nSELECT 1;\n").is_err());
        assert!(parse("loop i 0 10\n").is_err());
    }

    #[test]
    fn the_cells_compare_as_the_runner_does() {
        let served = vec![vec!["a".to_string(), "1.004".to_string()]];
        assert!(compare("TR", &["a\t1.0".to_string()], &served).is_ok());
        assert!(compare("TR", &["a\t1.5".to_string()], &served).is_err());
        assert!(compare("TT", &["a\t1.0".to_string()], &served).is_err());
        assert!(compare("TR", &[], &served).is_err());
        let cells = vec![vec!["x".to_string(), "y".to_string()]];
        assert!(compare("TT", &["x".to_string(), "y".to_string()], &cells).is_ok());
    }
}
