//! The corpus here — the two fixtures behind the server's kits — on the
//! engine: a ```glossql block must parse and a ```glossql-gap block must
//! not. SPEC.md and the language's own corpus are held to the grammar in
//! the extension's suite, which the pin inherits.

use std::path::{Path, PathBuf};

use crate::common;
use crate::examples::fenced;

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("the crate sits two levels under the repo root")
}

/// The corpus here is the kits' own: a block tagged `glossql` is a
/// transcription the language admits, one tagged `glossql-gap`
/// documents what it does not, and the engine's parser is the judge
/// of both.
#[tokio::test(flavor = "multi_thread")]
async fn every_corpus_block_behaves_as_tagged() {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let mut fixtures: Vec<PathBuf> = std::fs::read_dir(repo().join("corpus"))
        .expect("the corpus directory")
        .map(|e| e.expect("an entry").path())
        .filter(|p| p.extension().is_some_and(|x| x == "md") && !p.ends_with("README.md"))
        .collect();
    fixtures.sort();
    assert!(!fixtures.is_empty(), "the corpus holds the kits' fixtures");
    let mut admitted = 0;
    let mut gaps = 0;
    let mut wrong = Vec::new();
    for fixture in &fixtures {
        let text = std::fs::read_to_string(fixture).expect("a fixture");
        let file = fixture.file_name().unwrap().to_string_lossy();
        for b in fenced(&file, &text, &["glossql"]) {
            admitted += 1;
            if let Err(e) = session.parse(&b.sql).await {
                wrong.push(format!("{}:{} must parse — {e}", b.page, b.line));
            }
        }
        for b in fenced(&file, &text, &["glossql-gap"]) {
            gaps += 1;
            if session.parse(&b.sql).await.is_ok() {
                wrong.push(format!("{}:{} is a gap and parses", b.page, b.line));
            }
        }
    }
    assert!(admitted > 5, "{admitted} admitted blocks, {gaps} gaps");
    assert!(
        wrong.is_empty(),
        "corpus blocks that do not behave as tagged:\n{}",
        wrong.join("\n")
    );
}
