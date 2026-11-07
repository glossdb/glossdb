//! The docs, under the same standing invariant as the skills.
//!
//! Prose drifts from a moving surface because nothing checks it, so
//! doc examples are checked instead of proofread — the same two rules
//! `skills.rs` holds over the skills, here over every fenced
//! ` ```glossql ` and ` ```sql ` block in `docs/**/*.md`:
//!
//!   1. it parses;
//!   2. if it is a single read, it PLANS against a bootstrapped
//!      workspace — with the one exemption that a missing TABLE is
//!      fine, because an example may name a customer's data. A missing
//!      or misspelled COLUMN is not fine: those are ours.
//!
//! Nothing here executes a write; a block that declares or glosses is
//! held to rule 1 alone. Unlike `skills.rs` there is no floor on how
//! many blocks exist: the docs tree grows page by page, and a page
//! with no examples is legitimate. The skills file keeps the floors
//! that prove the harness still finds its subject.

use crate::common;

struct Block {
    page: String,
    line: usize,
    sql: String,
}

/// Every markdown file under `docs/`, recursively, in a stable order.
fn pages() -> Vec<std::path::PathBuf> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs")
        .canonicalize()
        .expect("the docs directory ships with the repo");
    let mut stack = vec![root];
    let mut out = Vec::new();
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md") {
                out.push(path);
            }
        }
    }
    out.sort();
    assert!(!out.is_empty(), "no markdown pages found under docs/");
    out
}

/// Every fenced glossql/sql block in the docs.
fn blocks() -> Vec<Block> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs")
        .canonicalize()
        .expect("the docs directory ships with the repo");
    let mut out = Vec::new();
    for path in pages() {
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let page = path
            .strip_prefix(&root)
            .unwrap_or(&path)
            .display()
            .to_string();
        let mut open: Option<(usize, String)> = None;
        for (i, line) in text.lines().enumerate() {
            match &mut open {
                None => {
                    if line.trim() == "```glossql" || line.trim() == "```sql" {
                        open = Some((i + 2, String::new()));
                    }
                }
                Some((start, body)) => {
                    if line.trim() == "```" {
                        out.push(Block {
                            page: page.clone(),
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
    }
    out
}

/// Every fenced example parses on the engine, the language's grammar
/// on: the extension's parser is the one the door runs.
#[tokio::test(flavor = "multi_thread")]
async fn every_doc_example_parses() {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let mut broken = Vec::new();
    for b in blocks() {
        if let Err(e) = session.parse(&b.sql).await {
            broken.push(format!("{}:{} — {e}", b.page, b.line));
        }
    }
    assert!(
        broken.is_empty(),
        "doc examples that do not parse:\n{}",
        broken.join("\n")
    );
}

/// Every `DECLARE FUNCTION … AS $$…$$` body in the docs is one SQL
/// query — the engine's parser cannot see inside a dollar-quoted body,
/// so a broken example would parse perfectly and ship as documentation.
#[tokio::test(flavor = "multi_thread")]
async fn every_doc_function_body_compiles() {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let mut broken = Vec::new();
    for b in blocks() {
        // Anchored on DECLARE FUNCTION, as in `skills.rs`: within a
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
            let body = &after[..close];
            // A body is SQL — a measurement over data, a detector over
            // `slots` (§6) — so the check is the session's shape rule.
            let one_query = session.parse(body).await.is_ok_and(|n| n == 1);
            if !one_query {
                broken.push(format!(
                    "{}:{} — a function body is one SQL query",
                    b.page, b.line
                ));
            }
        }
    }
    assert!(
        broken.is_empty(),
        "doc function bodies that do not compile:\n{}",
        broken.join("\n")
    );
}

/// A missing table is fine: an example may name a customer's data, or a
/// grounding a fresh workspace has none of. A missing column is not.
fn missing_table(error: &str) -> bool {
    error.contains("Table with name") && error.contains("does not exist")
}

/// A frame's read binds its parameters at the call: an example that
/// spells them bound up to the values it was not given.
fn unbound_parameters(error: &str) -> bool {
    error.contains("Values were not provided for the following parameters")
}

/// The examples' reads, bound on a fresh workspace: a read naming a
/// column, a relation or a function the engine and its kits do not
/// serve fails here. One channel for the run, with a dataset in use —
/// the names the examples spell — so a read reaches its columns
/// instead of stopping at the binding.
async fn bind_reads(blocks: &[Block], at: impl Fn(&Block) -> String) -> (usize, Vec<String>) {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    for name in ["ops", "fin", "orders", "erp_export"] {
        session
            .execute(&format!(
                "DECLARE DATASET {name} SET (purpose: 'the docs harness');"
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
        // One statement per block, or we cannot bound it.
        if trimmed.trim_end().trim_end_matches(';').contains(';') {
            continue;
        }
        bound += 1;
        let sql = format!("EXPLAIN {}", trimmed.trim().trim_end_matches(';'));
        if let Err(e) = session.batches(&sql, &[]).await {
            let text = e.to_string();
            if !missing_table(&text) && !unbound_parameters(&text) {
                broken.push(format!("{} — {text}", at(b)));
            }
        }
    }
    (bound, broken)
}

#[tokio::test(flavor = "multi_thread")]
async fn every_doc_read_names_columns_that_exist() {
    let blocks = blocks();
    let (_, broken) = bind_reads(&blocks, |b| format!("{}:{}", b.page, b.line)).await;
    assert!(
        broken.is_empty(),
        "doc examples naming something the reads do not serve:\n{}",
        broken.join("\n")
    );
}

/// The engine's SQL guide under `vendor/` is served as it stands on
/// disk, for the release the lock resolves: `vendor/duckdb/VERSION`
/// against Cargo.lock's `libduckdb-sys` package, whose version spells
/// the DuckDB release it downloads. A pin move that skips
/// `vendor/duckdb/refresh.sh` fails here instead of teaching a dialect
/// this build does not run.
#[test]
fn the_served_substrate_guide_is_the_vendor_directory_at_the_pin() {
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap();
    let mut on_disk: Vec<(String, String)> = Vec::new();
    let mut stack = vec![repo.join("vendor")];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).unwrap().filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md") {
                let rel = path
                    .strip_prefix(&repo)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned();
                on_disk.push((rel, std::fs::read_to_string(&path).unwrap()));
            }
        }
    }
    on_disk.sort();
    let mut served: Vec<(String, String)> = glossdb_serverd::skills::VENDORED
        .iter()
        .map(|p| (p.path.to_string(), p.body.to_string()))
        .collect();
    served.sort();
    assert_eq!(
        served.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(),
        on_disk.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(),
        "the served guide is the files under vendor/"
    );
    assert_eq!(served, on_disk, "a served page is the file as it stands");
    let pages = glossdb_serverd::skills::door_pages()
        .expect("the language's documents beside the extension's kits");
    for p in glossdb_serverd::skills::VENDORED {
        assert!(
            p.uri().starts_with("doc://vendor/") && p.title() != p.path,
            "{} needs a `# ` title line — the listing serves it as the description",
            p.path
        );
        assert!(
            pages.iter().any(|d| d.uri == p.uri() && d.body == p.body),
            "{} is not readable at its own URI",
            p.path
        );
    }
    let version = std::fs::read_to_string(repo.join("vendor/duckdb/VERSION")).unwrap();
    let vendored = version
        .lines()
        .next()
        .unwrap_or_default()
        .trim()
        .to_string();
    // libduckdb-sys 1.MMmmpp.n downloads DuckDB MM.mm.pp; the guide is
    // versioned by MM.mm.
    let lock = std::fs::read_to_string(repo.join("Cargo.lock")).unwrap();
    let locked = lock
        .lines()
        .skip_while(|l| *l != "name = \"libduckdb-sys\"")
        .nth(1)
        .and_then(|l| l.strip_prefix("version = \""))
        .and_then(|l| l.strip_suffix('"'))
        .and_then(|v| v.split('.').nth(1))
        .and_then(|n| n.parse::<u32>().ok())
        .map(|n| format!("{}.{}", n / 10000, (n / 100) % 100))
        .expect("Cargo.lock resolves libduckdb-sys");
    assert_eq!(
        vendored, locked,
        "vendor/duckdb/VERSION is not the lock's DuckDB — run vendor/duckdb/refresh.sh {locked} <duckdb-web commit>"
    );
}
