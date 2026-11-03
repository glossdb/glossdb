//! The language's record parses on the engine, the grammar on: every
//! ```sql block of SPEC.md, which the door serves as `doc://SPEC.md`,
//! and the corpus beside it, where a ```glossql block must parse and a
//! ```glossql-gap block must not.

use std::path::{Path, PathBuf};

use crate::common;

struct Block {
    file: String,
    line: usize,
    text: String,
}

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("the crate sits two levels under the repo root")
}

/// The fenced blocks of `path` whose tag is one of `tags`.
fn fenced(path: &Path, tags: &[&str]) -> Vec<Block> {
    let text = std::fs::read_to_string(path).expect("a page of the record");
    let file = path.file_name().unwrap().to_string_lossy().to_string();
    let mut out = Vec::new();
    let mut open: Option<(usize, String)> = None;
    for (i, line) in text.lines().enumerate() {
        match &mut open {
            Some((start, body)) => {
                if line.trim_end() == "```" {
                    out.push(Block {
                        file: file.clone(),
                        line: *start + 1,
                        text: body.clone(),
                    });
                    open = None;
                } else {
                    body.push_str(line);
                    body.push('\n');
                }
            }
            None => {
                if let Some(tag) = line.trim_end().strip_prefix("```")
                    && tags.contains(&tag)
                {
                    open = Some((i, String::new()));
                }
            }
        }
    }
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn every_spec_sql_block_parses_on_the_engine() {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    let blocks = fenced(&repo().join("SPEC.md"), &["sql"]);
    assert!(
        blocks.len() > 10,
        "no ```sql blocks found in SPEC.md — path rot?"
    );
    let mut broken = Vec::new();
    for b in &blocks {
        if let Err(e) = session.parse(&b.text).await {
            broken.push(format!("{}:{} — {e}", b.file, b.line));
        }
    }
    assert!(
        broken.is_empty(),
        "SPEC.md blocks the engine does not parse:\n{}",
        broken.join("\n")
    );
}

/// The corpus is the acceptance record: a block tagged `glossql` is a
/// transcription the language admits, one tagged `glossql-gap` documents
/// what it does not, and the engine's parser is the judge of both.
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
    assert!(fixtures.len() > 20, "the corpus holds its fixtures");
    let mut admitted = 0;
    let mut gaps = 0;
    let mut wrong = Vec::new();
    for fixture in &fixtures {
        for b in fenced(fixture, &["glossql"]) {
            admitted += 1;
            if let Err(e) = session.parse(&b.text).await {
                wrong.push(format!("{}:{} must parse — {e}", b.file, b.line));
            }
        }
        for b in fenced(fixture, &["glossql-gap"]) {
            gaps += 1;
            if session.parse(&b.text).await.is_ok() {
                wrong.push(format!("{}:{} is a gap and parses", b.file, b.line));
            }
        }
    }
    assert!(
        admitted > 50 && gaps > 0,
        "{admitted} admitted blocks, {gaps} gaps"
    );
    assert!(
        wrong.is_empty(),
        "corpus blocks that do not behave as tagged:\n{}",
        wrong.join("\n")
    );
}
