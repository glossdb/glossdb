//! Fenced examples in markdown, and the rules the suites hold them to:
//! an example parses; a `DECLARE FUNCTION` body in it is one SQL query;
//! a single read binds on a fresh workspace. Nothing here executes a
//! write: a block that declares or glosses is held to parsing alone.

use std::path::{Path, PathBuf};

use crate::common;

/// One fenced block: the page it is on, the line it starts on, its text.
pub struct Block {
    pub page: String,
    pub line: usize,
    pub sql: String,
}

impl Block {
    fn at(&self) -> String {
        format!("{}:{}", self.page, self.line)
    }
}

/// The fenced blocks of `text`, the page named `page`, whose tag is one
/// of `tags`.
pub fn fenced(page: &str, text: &str, tags: &[&str]) -> Vec<Block> {
    let mut out = Vec::new();
    let mut open: Option<(usize, String)> = None;
    for (i, line) in text.lines().enumerate() {
        match &mut open {
            None => {
                if let Some(tag) = line.trim().strip_prefix("```")
                    && tags.contains(&tag)
                {
                    open = Some((i + 2, String::new()));
                }
            }
            Some((start, body)) => {
                if line.trim() == "```" {
                    out.push(Block {
                        page: page.to_string(),
                        line: *start,
                        sql: std::mem::take(body),
                    });
                    open = None;
                } else {
                    body.push_str(line);
                    body.push('\n');
                }
            }
        }
    }
    out
}

/// Every ` ```glossql ` and ` ```sql ` block of every `.md` under
/// `root`, recursively, in a stable order; a page is named by its path
/// under `base`.
pub fn under(root: &Path, base: &Path) -> Vec<Block> {
    let mut pages: Vec<PathBuf> = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md") {
                pages.push(path);
            }
        }
    }
    pages.sort();
    let mut out = Vec::new();
    for path in pages {
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let page = path.strip_prefix(base).unwrap_or(&path).display();
        out.extend(fenced(&page.to_string(), &text, &["glossql", "sql"]));
    }
    out
}

/// The examples the engine does not parse, the language's grammar on:
/// the extension's parser is the one the interface runs.
pub async fn unparsed(blocks: &[Block]) -> Vec<String> {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let mut broken = Vec::new();
    for b in blocks {
        if let Err(e) = session.parse(&b.sql).await {
            broken.push(format!("{} — {e}", b.at()));
        }
    }
    broken
}

/// The `DECLARE FUNCTION … AS $$…$$` bodies that are not one SQL query,
/// and how many bodies were checked. The engine's parser cannot see
/// inside a dollar-quoted body, so a broken one parses perfectly as
/// part of its statement.
pub async fn broken_function_bodies(blocks: &[Block]) -> (usize, Vec<String>) {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let mut checked = 0;
    let mut broken = Vec::new();
    for b in blocks {
        // Anchored on DECLARE FUNCTION: PREVIEW, RECIPE and GLOSS bodies
        // ride the same dollar quoting and are SQL or JSON. Within a
        // function statement `AS $$` opens the body and the next `$$`
        // closes it — bodies cannot contain `$$`.
        for part in b.sql.split("DECLARE FUNCTION").skip(1) {
            let Some(open) = part.find("AS $$") else {
                continue;
            };
            let after = &part[open + 5..];
            let Some(close) = after.find("$$") else {
                continue;
            };
            checked += 1;
            match session.parse(&after[..close]).await {
                Ok(1) => {}
                Ok(_) => broken.push(format!("{} — a function body is one SQL query", b.at())),
                Err(e) => broken.push(format!("{} — {e}", b.at())),
            }
        }
    }
    (checked, broken)
}

/// The single reads that do not bind on a fresh workspace — a read
/// naming a column, a relation or a function the engine and its kits
/// do not serve — and how many reads were bound. A missing table is
/// fine: an example may name a customer's data. A missing column is
/// not. One channel for the run, with a dataset in use — the names the
/// examples spell — so a read reaches its columns.
pub async fn unbound_reads(blocks: &[Block]) -> (usize, Vec<String>) {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    for name in ["ops", "fin", "orders", "erp_export"] {
        session
            .execute(&format!(
                "DECLARE DATASET {name} SET (purpose: 'the examples harness');"
            ))
            .await
            .unwrap();
    }
    session.execute("USE ops;").await.unwrap();
    let mut bound = 0;
    let mut broken = Vec::new();
    for b in blocks {
        let trimmed: String = b
            .sql
            .lines()
            .filter(|l| !l.trim_start().starts_with("--"))
            .collect::<Vec<_>>()
            .join("\n");
        let head = trimmed.trim_start().to_lowercase();
        // Reads only: a write example is held to parsing alone, and a
        // read of the language's own — GLOSSARY(), TESTS(), a
        // measurement over a subject — binds in the extension, not in
        // a plan.
        if !(head.starts_with("select") || head.starts_with("with ") || head.starts_with("from "))
            || head.contains("glossary(")
            || head.contains("tests(")
            || head.starts_with("select temporal(")
        {
            continue;
        }
        // One statement per block, or it cannot be bound.
        if trimmed.trim_end().trim_end_matches(';').contains(';') {
            continue;
        }
        bound += 1;
        let sql = format!("EXPLAIN {}", trimmed.trim().trim_end_matches(';'));
        if let Err(e) = session.batches(&sql, &[]).await {
            let text = e.to_string();
            // A frame's read binds its parameters at the call.
            let missing_table = text.contains("Table with name") && text.contains("does not exist");
            let unbound_parameters =
                text.contains("Values were not provided for the following parameters");
            if !missing_table && !unbound_parameters {
                broken.push(format!("{} — {text}", b.at()));
            }
        }
    }
    (bound, broken)
}
