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

use crate::examples::{self, Block};

/// Every fenced glossql/sql block in the docs.
fn blocks() -> Vec<Block> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs")
        .canonicalize()
        .expect("the docs directory ships with the repo");
    examples::under(&root, &root)
}

#[tokio::test(flavor = "multi_thread")]
async fn every_doc_example_parses_and_every_read_binds() {
    let report = examples::check(&blocks()).await;
    assert!(
        report.unparsed.is_empty(),
        "doc examples that do not parse:\n{}",
        report.unparsed.join("\n")
    );
    assert!(
        report.broken_bodies.is_empty(),
        "doc function bodies that do not compile:\n{}",
        report.broken_bodies.join("\n")
    );
    assert!(
        report.unbound_reads.is_empty(),
        "doc examples naming something the reads do not serve:\n{}",
        report.unbound_reads.join("\n")
    );
}

/// The engine's SQL guide under `vendor/` is served as it holds on
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
    let mut on_disk: Vec<String> = Vec::new();
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
                on_disk.push(rel);
            }
        }
    }
    on_disk.sort();
    let mut served: Vec<String> = glossdb_serverd::skills::VENDORED
        .iter()
        .map(|p| p.path.to_string())
        .collect();
    served.sort();
    assert_eq!(
        served, on_disk,
        "the served guide is the files under vendor/"
    );
    let pages = glossdb_serverd::skills::served_pages()
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
